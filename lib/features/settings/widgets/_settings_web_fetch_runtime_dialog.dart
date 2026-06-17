part of 'settings_view.dart';

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
  final List<_ScraplingRuntimeLogEntry> _entries =
      <_ScraplingRuntimeLogEntry>[];
  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  final ValueNotifier<int> _successPulse = ValueNotifier<int>(0);
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);

  bool _running = true;
  bool _success = false;
  final bool _cancelled = false;
  String? _errorMessage;
  bool _pulsedOutcome = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
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
    setState(() {
      _entries.add(_ScraplingRuntimeLogEntry(line: line, level: level));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollGuard.followToBottom(
        _scrollController,
        animated: true,
        animationDuration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _start() async {
    final runtime = context.read<AiSessionController>().toolRuntimeService;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final actionLabel = widget.action == _ScraplingRuntimeAction.install
        ? (isZh ? '安装' : 'Install')
        : (isZh ? '卸载' : 'Uninstall');
    _append(
      '> $actionLabel Scrapling runtime',
      level: _ScraplingRuntimeLogLevel.command,
    );
    _append('');
    try {
      final stream = widget.action == _ScraplingRuntimeAction.install
          ? runtime.installWebFetchScraplingRuntimeStreaming(
              settings: widget.settings,
            )
          : runtime.uninstallWebFetchScraplingRuntimeStreaming(
              settings: widget.settings,
            );
      await for (final event in stream) {
        switch (event.type) {
          case WebFetchScraplingRuntimeEventType.command:
            _append(event.line, level: _ScraplingRuntimeLogLevel.command);
            break;
          case WebFetchScraplingRuntimeEventType.stdout:
            _append(event.line, level: _inferLevel(event.line));
            break;
          case WebFetchScraplingRuntimeEventType.stderr:
            _append(event.line, level: _inferLevel(event.line, stderr: true));
            break;
          case WebFetchScraplingRuntimeEventType.status:
            _append(event.line, level: _ScraplingRuntimeLogLevel.status);
            break;
          case WebFetchScraplingRuntimeEventType.success:
            _append(event.line, level: _ScraplingRuntimeLogLevel.success);
            break;
          case WebFetchScraplingRuntimeEventType.warning:
            _append(event.line, level: _ScraplingRuntimeLogLevel.warning);
            break;
        }
      }
      if (!mounted) return;
      setState(() {
        _running = false;
        _success = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _success = false;
        _errorMessage = '$e';
      });
      _append('✗ $e', level: _ScraplingRuntimeLogLevel.error);
    }
    if (!_running) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pulsedOutcome) return;
        _pulsedOutcome = true;
        if (_success) {
          _successPulse.value = _successPulse.value + 1;
        } else if (!_cancelled) {
          _errorPulse.value = _errorPulse.value + 1;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final installing = widget.action == _ScraplingRuntimeAction.install;
    final title = installing
        ? (isZh ? '安装 Scrapling 运行时' : 'Install Scrapling Runtime')
        : (isZh ? '卸载 Scrapling 运行时' : 'Uninstall Scrapling Runtime');
    final statusColor = _running
        ? colorScheme.primary
        : _success
        ? const Color(0xFF4CAF50)
        : colorScheme.error;
    final statusLabel = _running
        ? (installing
              ? (isZh ? '安装中...' : 'Installing...')
              : (isZh ? '卸载中...' : 'Uninstalling...'))
        : _success
        ? (installing
              ? (isZh ? '安装完成' : 'Installed')
              : (isZh ? '卸载完成' : 'Uninstalled'))
        : (isZh ? '执行失败' : 'Failed');

    return buildOpenHandAlertDialog(
      title: Row(
        children: [
          Icon(
            installing ? Icons.download_rounded : Icons.delete_outline_rounded,
            size: 22,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
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
                    if (_running)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: statusColor,
                        ),
                      )
                    else
                      Icon(
                        _success
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        size: 18,
                        color: statusColor,
                      ),
                    const SizedBox(width: 8),
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
                if (_errorMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                  if (_errorMessage!.toLowerCase().contains(
                    'certificate verification failed',
                  )) ...[
                    const SizedBox(height: 6),
                    Text(
                      isZh
                          ? '诊断：当前环境的 Python / pip 无法验证 PyPI 证书链。请检查系统 CA 证书、代理拦截证书，或为 Python 配置可用的证书文件。'
                          : 'Diagnosis: Python / pip in the current environment cannot validate the PyPI certificate chain. Check system CA certificates, proxy interception certificates, or configure a valid certificate file for Python.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                    child: OpenHandSafeScrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _scrollGuard.handleNotification,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _entries.length,
                          itemBuilder: (context, index) =>
                              _ScraplingRuntimeLogLine(entry: _entries[index]),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: HighlightPulse(
                  signal: _successPulse,
                  color: OpenHandStatusColors.success,
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: HighlightPulse(
                  signal: _errorPulse,
                  color: OpenHandStatusColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text: _entries
                    .map((entry) => entry.line)
                    .join('\n')
                    .trimRight(),
              ),
            );
            if (!context.mounted) return;
            OpenHandSnackBar.showSuccess(
              context,
              isZh ? '已复制全部日志' : 'Copied all logs',
              duration: const Duration(milliseconds: 1400),
            );
          },
          label: isZh ? '复制日志' : 'Copy Logs',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _running
              ? null
              : () => Navigator.of(context).pop(_success),
          label: isZh ? '关闭' : 'Close',
        ),
      ],
    );
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
          fontFamily: 'monospace',
          fontSize: 12,
          color: _colorForLevel(entry.level),
          height: 1.5,
        ),
      ),
    );
  }

  Color _colorForLevel(_ScraplingRuntimeLogLevel level) {
    return switch (level) {
      _ScraplingRuntimeLogLevel.command => const Color(0xFF4CAF50),
      _ScraplingRuntimeLogLevel.status => const Color(0xFF64B5F6),
      _ScraplingRuntimeLogLevel.stdout => const Color(0xFFCDD9E5),
      _ScraplingRuntimeLogLevel.stderr => const Color(0xFFFFA726),
      _ScraplingRuntimeLogLevel.success => const Color(0xFF4CAF50),
      _ScraplingRuntimeLogLevel.warning => const Color(0xFFFFA726),
      _ScraplingRuntimeLogLevel.error => const Color(0xFFEF5350),
    };
  }
}
