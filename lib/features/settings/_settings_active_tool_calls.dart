// 运行中工具调用观测面板：订阅 [AiToolExecutionRegistry]，按行展示
// 每个正在执行的工具调用——名称、类别图标、所属会话、PID、已运行时长，
// 并提供单点 Stop 按钮（仅终止该 toolCallId，不影响兄弟工具或全局响应）。
//
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
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _registry.activeRecords.isNotEmpty) {
          setState(() {});
        } else {
          _ticker?.cancel();
          _ticker = null;
        }
      });
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

  String _kindLabel(AiToolExecutionKind kind) {
    switch (kind) {
      case AiToolExecutionKind.builtin:
        return '内建';
      case AiToolExecutionKind.mcp:
        return 'MCP';
      case AiToolExecutionKind.skill:
        return 'Skill';
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
                                _kindLabel(record.kind),
                                if (record.pid != null) 'PID ${record.pid}',
                                _formatElapsed(record.elapsed),
                                'session ${record.sessionId.length > 8 ? record.sessionId.substring(0, 8) : record.sessionId}',
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
                          await _registry.cancelToolCall(record.toolCallId);
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
