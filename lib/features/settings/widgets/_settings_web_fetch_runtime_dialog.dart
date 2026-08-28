part of 'settings_view.dart';

/// 触发「证书校验失败」补充诊断提示的错误特征（小写匹配）。
const String _certificateVerificationFailedMarker =
    'certificate verification failed';

/// 运行时控制台的固定前景色：始终渲染在深色控制台底色上，不随主题切换。
const Color _kConsoleCommandColor = Color(0xFFF1F5F9);
const Color _kConsoleStatusColor = Color(0xFF64B5F6);
const Color _kConsoleStdoutColor = Color(0xFFCDD9E5);

enum _ScraplingRuntimeAction { install, uninstall }

class _ScraplingRuntimeDialog extends StatefulWidget {
  const _ScraplingRuntimeDialog({required this.action, required this.settings});

  final _ScraplingRuntimeAction action;
  final AiWebFetchScraplingSettings settings;

  @override
  State<_ScraplingRuntimeDialog> createState() =>
      _ScraplingRuntimeDialogState();
}

class _ScraplingRuntimeDialogState extends State<_ScraplingRuntimeDialog> {
  static const int _maxLogEntries = 800;
  static const int _maxLogCharacters = 400000;
  static const int _maxLogLineCharacters = 4000;

  final List<_ScraplingRuntimeLogEntry> _entries =
      <_ScraplingRuntimeLogEntry>[];
  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  final ValueNotifier<int> _successPulse = ValueNotifier<int>(0);
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);
  StreamSubscription<WebFetchScraplingRuntimeEvent>? _runtimeSubscription;

  int _retainedLogCharacters = 0;
  bool _running = true;
  bool _success = false;
  String? _errorMessage;
  bool _pulsedOutcome = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    final runtimeSubscription = _runtimeSubscription;
    _runtimeSubscription = null;
    unawaited(
      cancelStreamSubscriptionBounded<WebFetchScraplingRuntimeEvent>(
        runtimeSubscription,
        onError: (error, stack) => silentLog(
          'settings_web_fetch_runtime_dialog',
          '取消 Scrapling 运行时事件订阅',
          error,
          stack,
        ),
      ),
    );
    _scrollController.dispose();
    _successPulse.dispose();
    _errorPulse.dispose();
    super.dispose();
  }

  _ScraplingRuntimeLogLevel _inferLevel(String line, {bool stderr = false}) {
    final normalized = line.trim().toLowerCase();
    if (normalized.isEmpty) {
      return stderr
          ? _ScraplingRuntimeLogLevel.stderr
          : _ScraplingRuntimeLogLevel.stdout;
    }
    if (normalized.startsWith('✓') ||
        normalized.contains(' success') ||
        normalized.contains('installed') ||
        normalized.contains('completed')) {
      return _ScraplingRuntimeLogLevel.success;
    }
    if (normalized.startsWith('!') ||
        normalized.contains('warn') ||
        normalized.contains('warning')) {
      return _ScraplingRuntimeLogLevel.warning;
    }
    if (normalized.startsWith('✗') ||
        normalized.contains('error') ||
        normalized.contains('failed') ||
        normalized.contains('traceback') ||
        normalized.contains('exception')) {
      return _ScraplingRuntimeLogLevel.error;
    }
    return stderr
        ? _ScraplingRuntimeLogLevel.stderr
        : _ScraplingRuntimeLogLevel.stdout;
  }

  void _append(
    String line, {
    _ScraplingRuntimeLogLevel level = _ScraplingRuntimeLogLevel.stdout,
  }) {
    if (!mounted) return;
    final retainedLine = clipTextWithEllipsis(line, _maxLogLineCharacters);
    setState(() {
      _entries.add(_ScraplingRuntimeLogEntry(line: retainedLine, level: level));
      _retainedLogCharacters += retainedLine.length;
      while (_entries.length > _maxLogEntries ||
          _retainedLogCharacters > _maxLogCharacters) {
        _retainedLogCharacters -= _entries.removeAt(0).line.length;
      }
    });
    _scrollGuard.scheduleFollowToBottom(
      _scrollController,
      animated: true,
      animationDuration: openHandMotionDuration(
        context,
        const Duration(milliseconds: 100),
      ),
      curve: Curves.easeOut,
    );
  }

  void _start() {
    if (!mounted) return;
    final runtime = context.read<AiSessionController>().toolRuntimeService;
    final l10n = AppLocalizations.of(context)!;
    final actionLabel = widget.action == _ScraplingRuntimeAction.install
        ? l10n.settingsScraplingRuntimeActionInstall
        : l10n.settingsScraplingRuntimeActionUninstall;
    _append(
      '> ${l10n.settingsScraplingRuntimeCommand(actionLabel)}',
      level: _ScraplingRuntimeLogLevel.command,
    );
    _append('');
    final stream = widget.action == _ScraplingRuntimeAction.install
        ? runtime.installWebFetchScraplingRuntimeStreaming(
            settings: widget.settings,
          )
        : runtime.uninstallWebFetchScraplingRuntimeStreaming(
            settings: widget.settings,
          );
    _runtimeSubscription = stream.listen(
      _handleRuntimeEvent,
      onError: _handleRuntimeError,
      onDone: _handleRuntimeDone,
      cancelOnError: true,
    );
  }

  void _handleRuntimeEvent(WebFetchScraplingRuntimeEvent event) {
    final level = switch (event.type) {
      WebFetchScraplingRuntimeEventType.command =>
        _ScraplingRuntimeLogLevel.command,
      WebFetchScraplingRuntimeEventType.stdout => _inferLevel(event.line),
      WebFetchScraplingRuntimeEventType.stderr => _inferLevel(
        event.line,
        stderr: true,
      ),
      WebFetchScraplingRuntimeEventType.status =>
        _ScraplingRuntimeLogLevel.status,
      WebFetchScraplingRuntimeEventType.success =>
        _ScraplingRuntimeLogLevel.success,
      WebFetchScraplingRuntimeEventType.warning =>
        _ScraplingRuntimeLogLevel.warning,
    };
    _append(event.line, level: level);
  }

  void _handleRuntimeError(Object error, StackTrace stack) {
    if (!mounted) return;
    silentLog(
      'settings_web_fetch_runtime_dialog',
      '执行 Scrapling 运行时操作',
      error,
      stack,
    );
    final message = userFailureMessage(
      error,
      fallback: openHandLocalizedText(
        context,
        zh: 'Scrapling 运行时操作失败。',
        en: 'The Scrapling runtime operation failed.',
      ),
    );
    _runtimeSubscription = null;
    setState(() {
      _running = false;
      _success = false;
      _errorMessage = message;
    });
    _append('✗ $message', level: _ScraplingRuntimeLogLevel.error);
    _scheduleOutcomePulse();
  }

  void _handleRuntimeDone() {
    if (!mounted || !_running) return;
    _runtimeSubscription = null;
    setState(() {
      _running = false;
      _success = true;
    });
    _scheduleOutcomePulse();
  }

  void _scheduleOutcomePulse() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pulsedOutcome) return;
      _pulsedOutcome = true;
      final signal = _success ? _successPulse : _errorPulse;
      signal.value += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final installing = widget.action == _ScraplingRuntimeAction.install;
    final title = installing
        ? l10n.settingsScraplingRuntimeInstallTitle
        : l10n.settingsScraplingRuntimeUninstallTitle;
    final statusColor = _running
        ? colorScheme.primary
        : _success
        ? OpenHandStatusColors.success
        : colorScheme.error;
    final statusLabel = _running
        ? (installing
              ? l10n.settingsScraplingRuntimeInstalling
              : l10n.settingsScraplingRuntimeUninstalling)
        : _success
        ? (installing
              ? l10n.settingsScraplingRuntimeInstalled
              : l10n.settingsScraplingRuntimeUninstalled)
        : l10n.settingsScraplingRuntimeFailed;

    final dialog = buildOpenHandAlertDialog(
      title: Row(
        children: [
          Icon(
            installing ? Icons.download_rounded : Icons.delete_outline_rounded,
            size: 22,
            color: colorScheme.primary,
          ),
          kOpenHandHGap8,
          Expanded(child: Text(title)),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 460,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    OpenHandBusyStatusIcon(
                      busy: _running,
                      icon: _success
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: statusColor,
                    ),
                    kOpenHandHGap8,
                    Expanded(
                      child: Text(
                        statusLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                OpenHandVerticalRevealSwitcher(
                  presentKey: ValueKey<String>(
                    'scrapling-runtime-error-${_errorMessage ?? ''}',
                  ),
                  child: _errorMessage == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.error,
                                ),
                              ),
                              if (_errorMessage!.toLowerCase().contains(
                                _certificateVerificationFailedMarker,
                              )) ...[
                                kOpenHandGap6,
                                Text(
                                  l10n.settingsScraplingRuntimeCertificateDiagnosis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
                kOpenHandGap10,
                Expanded(
                  child: OpenHandConsoleLogView(
                    controller: _scrollController,
                    onNotification: _scrollGuard.handleNotification,
                    itemCount: _entries.length,
                    itemBuilder: (_, index) =>
                        _ScraplingRuntimeLogLine(entry: _entries[index]),
                  ),
                ),
              ],
            ),
            FeedbackHighlightPulseOverlay(
              successSignal: _successPulse,
              errorSignal: _errorPulse,
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () async {
            await copyOpenHandTextToClipboard(
              logTag: 'settings',
              context: context,
              text: _entries.map((entry) => entry.line).join('\n').trimRight(),
              successMessage: l10n.settingsScraplingRuntimeCopiedAllLogs,
              logAction: '复制 Scrapling 运行日志',
              successDuration: const Duration(milliseconds: 1400),
            );
          },
          label: l10n.settingsScraplingRuntimeCopyLogs,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _running
              ? null
              : () => Navigator.of(context).pop(_success),
          label: l10n.commonClose,
        ),
      ],
    );
    return PopScope(canPop: !_running, child: dialog);
  }
}

enum _ScraplingRuntimeLogLevel {
  command,
  status,
  stdout,
  stderr,
  success,
  warning,
  error,
}

class _ScraplingRuntimeLogEntry {
  const _ScraplingRuntimeLogEntry({required this.line, required this.level});

  final String line;
  final _ScraplingRuntimeLogLevel level;
}

class _ScraplingRuntimeLogLine extends StatelessWidget {
  const _ScraplingRuntimeLogLine({required this.entry});

  final _ScraplingRuntimeLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: SelectableText(
        entry.line.isEmpty ? ' ' : entry.line,
        style: TextStyle(
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: 12,
          color: _colorForLevel(entry.level),
          height: 1.5,
        ),
      ),
    );
  }

  Color _colorForLevel(_ScraplingRuntimeLogLevel level) {
    return switch (level) {
      // 回显命令用高亮前景与普通输出区分；stderr 未被识别为错误时按告警呈现。
      _ScraplingRuntimeLogLevel.command => _kConsoleCommandColor,
      _ScraplingRuntimeLogLevel.status => _kConsoleStatusColor,
      _ScraplingRuntimeLogLevel.stdout => _kConsoleStdoutColor,
      _ScraplingRuntimeLogLevel.stderr => OpenHandStatusColors.warning,
      _ScraplingRuntimeLogLevel.success => OpenHandStatusColors.success,
      _ScraplingRuntimeLogLevel.warning => OpenHandStatusColors.warning,
      _ScraplingRuntimeLogLevel.error => OpenHandStatusColors.error,
    };
  }
}
