// 运行中工具调用观测面板：订阅 [AiToolExecutionRegistry]，按行展示
// 每个正在执行的工具调用——名称、类别图标、所属会话、PID、已运行时长，
// 并提供单点 Stop 按钮（仅终止该 toolCallId，不影响兄弟工具或全局响应）。
// 重要约束：
//  - 列表本身依赖 ChangeNotifier 通知；运行时长是衍生数据，需要再叠加
//    一个 1s 周期 timer 让 UI 平滑前进，但 timer 仅在 records 非空时开启，
//    避免空列表时空跑。
//  - 没有任何写持久化的逻辑，纯只读视图 + 取消动作。
part of 'settings_view.dart';

class _ActiveToolCallsPanel extends StatefulWidget {
  const _ActiveToolCallsPanel();

  @override
  State<_ActiveToolCallsPanel> createState() => _ActiveToolCallsPanelState();
}

class _ActiveToolCallsPanelState extends State<_ActiveToolCallsPanel> {
  late final AiToolExecutionRegistry _registry;
  Timer? _ticker;
  int _activeCount = 0;

  @override
  void initState() {
    super.initState();
    _registry = AiToolExecutionRegistry.instance;
    _registry.addListener(_handleChange);
    _activeCount = _registry.activeRecords.length;
    _maybeStartTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _registry.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() {
    if (!mounted) return;
    final next = _registry.activeRecords.length;
    setState(() {
      _activeCount = next;
    });
    _maybeStartTicker();
  }

  void _maybeStartTicker() {
    if (_activeCount > 0 && _ticker == null) {
      _ticker = startSafePeriodicTimer(
        const Duration(seconds: 1),
        (_) {
          if (mounted && _registry.activeRecords.isNotEmpty) {
            setState(() {});
          } else {
            _ticker?.cancel();
            _ticker = null;
          }
        },
        onError: (error, stack) =>
            silentLog('settings', '活动工具调用计时器', error, stack),
      );
    } else if (_activeCount == 0 && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  String _formatElapsed(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final rem = s % 60;
    if (m < 60) return '${m}m${rem.toString().padLeft(2, '0')}s';
    final h = m ~/ 60;
    final mm = m % 60;
    return '${h}h${mm.toString().padLeft(2, '0')}m';
  }

  IconData _kindIcon(AiToolExecutionKind kind) {
    switch (kind) {
      case AiToolExecutionKind.builtin:
        return Icons.terminal_outlined;
      case AiToolExecutionKind.mcp:
        return Icons.hub_outlined;
      case AiToolExecutionKind.skill:
        return Icons.auto_awesome_outlined;
    }
  }

  String _kindLabel(AiToolExecutionKind kind, AppLocalizations l10n) {
    switch (kind) {
      case AiToolExecutionKind.builtin:
        return l10n.settingsActiveToolKindBuiltin;
      case AiToolExecutionKind.mcp:
        return l10n.settingsActiveToolKindMcp;
      case AiToolExecutionKind.skill:
        return l10n.settingsActiveToolKindSkill;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final records = _registry.activeRecords;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _SettingsGroupCard(
      title: l10n.settingsActiveToolCallsTitle,
      description: l10n.settingsActiveToolCallsBody,
      children: [
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              l10n.settingsActiveToolCallsEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          )
        else
          Column(
            children: [
              for (final record in records)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _kindIcon(record.kind),
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.displayName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                _kindLabel(record.kind, l10n),
                                if (record.pid != null) 'PID ${record.pid}',
                                _formatElapsed(record.elapsed),
                                '${l10n.settingsActiveToolSessionLabel} ${record.sessionId.length > 8 ? record.sessionId.substring(0, 8) : record.sessionId}',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: colors.error,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                        onPressed: () async {
                          await _registry.cancelToolCall(
                            sessionId: record.sessionId,
                            toolCallId: record.toolCallId,
                          );
                        },
                        icon: const Icon(Icons.stop_circle_outlined, size: 16),
                        label: Text(l10n.settingsActiveToolCallsCancel),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// 三项工具加固参数：subprocessGracefulShutdownMs / bashOutputMaxBytes /
/// maxConcurrentTools。每个独立行用 TextField 和保存按钮提交，输入超出
/// 范围时显示红色提示文案，保存成功靠 SettingsController.saveSuccessSignal
/// 的全局 HighlightPulse 反馈。
class _ToolHardeningParamsPanel extends StatefulWidget {
  const _ToolHardeningParamsPanel();

  @override
  State<_ToolHardeningParamsPanel> createState() =>
      _ToolHardeningParamsPanelState();
}

class _ToolHardeningParamsPanelState extends State<_ToolHardeningParamsPanel> {
  late final TextEditingController _gracefulCtrl;
  late final TextEditingController _bashOutCtrl;
  late final TextEditingController _maxConcurCtrl;
  final FocusNode _gracefulFocus = FocusNode();
  final FocusNode _bashOutFocus = FocusNode();
  final FocusNode _maxConcurFocus = FocusNode();
  String? _gracefulError;
  String? _bashOutError;
  String? _maxConcurError;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsController>();
    _gracefulCtrl = TextEditingController(
      text: '${settings.subprocessGracefulShutdownMs}',
    );
    _bashOutCtrl = TextEditingController(
      text: '${settings.bashOutputMaxBytes}',
    );
    _maxConcurCtrl = TextEditingController(
      text: '${settings.maxConcurrentTools}',
    );
  }

  @override
  void dispose() {
    _gracefulCtrl.dispose();
    _bashOutCtrl.dispose();
    _maxConcurCtrl.dispose();
    _gracefulFocus.dispose();
    _bashOutFocus.dispose();
    _maxConcurFocus.dispose();
    super.dispose();
  }

  Future<void> _save({
    required TextEditingController controller,
    required int min,
    required int max,
    required Future<bool> Function(int) update,
    required void Function(String?) setError,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final raw = optionalIntFromText(controller.text);
    if (raw == null || raw < min || raw > max) {
      setState(() => setError(l10n.settingsToolHardeningInvalid));
      return;
    }
    setState(() => setError(null));
    await update(raw);
  }

  Widget _row({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String? errorText,
    required VoidCallback onSave,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return _ResponsiveSettingRow(
      title: title,
      subtitle: subtitle,
      controlMaxWidth: 360,
      control: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                errorText: errorText,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => onSave(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: onSave, child: Text(l10n.commonSave)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsController>();
    // 当外部（如重置）改了快照、或其它路径触发更新时，把控制器同步到最新值，
    // 但不抢用户正在编辑的字段焦点。
    if (!_gracefulFocus.hasFocus &&
        _gracefulCtrl.text != '${settings.subprocessGracefulShutdownMs}') {
      _gracefulCtrl.text = '${settings.subprocessGracefulShutdownMs}';
    }
    if (!_bashOutFocus.hasFocus &&
        _bashOutCtrl.text != '${settings.bashOutputMaxBytes}') {
      _bashOutCtrl.text = '${settings.bashOutputMaxBytes}';
    }
    if (!_maxConcurFocus.hasFocus &&
        _maxConcurCtrl.text != '${settings.maxConcurrentTools}') {
      _maxConcurCtrl.text = '${settings.maxConcurrentTools}';
    }
    return _SettingsGroupCard(
      title: l10n.settingsToolHardeningTitle,
      description: l10n.settingsToolHardeningBody,
      children: [
        _row(
          title: l10n.settingsSubprocessGracefulShutdownLabel,
          subtitle: l10n.settingsSubprocessGracefulShutdownBody,
          controller: _gracefulCtrl,
          focusNode: _gracefulFocus,
          errorText: _gracefulError,
          onSave: () => _save(
            controller: _gracefulCtrl,
            min: AppSettingsSnapshot.minSubprocessGracefulShutdownMs,
            max: AppSettingsSnapshot.maxSubprocessGracefulShutdownMs,
            update: settings.updateSubprocessGracefulShutdownMs,
            setError: (e) => _gracefulError = e,
          ),
        ),
        _row(
          title: l10n.settingsBashOutputMaxBytesLabel,
          subtitle: l10n.settingsBashOutputMaxBytesBody,
          controller: _bashOutCtrl,
          focusNode: _bashOutFocus,
          errorText: _bashOutError,
          onSave: () => _save(
            controller: _bashOutCtrl,
            min: AppSettingsSnapshot.minBashOutputMaxBytes,
            max: AppSettingsSnapshot.maxBashOutputMaxBytes,
            update: settings.updateBashOutputMaxBytes,
            setError: (e) => _bashOutError = e,
          ),
        ),
        _row(
          title: l10n.settingsMaxConcurrentToolsLabel,
          subtitle: l10n.settingsMaxConcurrentToolsBody,
          controller: _maxConcurCtrl,
          focusNode: _maxConcurFocus,
          errorText: _maxConcurError,
          onSave: () => _save(
            controller: _maxConcurCtrl,
            min: AppSettingsSnapshot.minMaxConcurrentTools,
            max: AppSettingsSnapshot.maxMaxConcurrentTools,
            update: settings.updateMaxConcurrentTools,
            setError: (e) => _maxConcurError = e,
          ),
        ),
      ],
    );
  }
}
