import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/service/mcp_loaded_tools_tracker.dart';

/// 弹出 [ToolSearchLoadedDialog] 的便捷入口。
/// 复用方：[OpenHandHomePage] 的 SnackBar action、MCP 设置页快捷入口、
/// 以及未来其它需要展示「本会话已加载 MCP 工具」的场景。
Future<void> showToolSearchLoadedDialog(
  BuildContext context, {
  required List<String> names,
  void Function()? onClear,
  List<AiToolSearchLoadHistoryEntry> history =
      const <AiToolSearchLoadHistoryEntry>[],
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ToolSearchLoadedDialog(
      initialNames: names,
      onClear: onClear,
      initialHistory: history,
    ),
  );
}

/// 列出本会话已通过 `ToolSearch` 加载的 MCP 工具完整名（含 `mcp__` 前缀）。
/// 工具名形如 `mcp__SERVER__tool` 时按 `SERVER` 分组、可折叠展示，便于在工具
/// 数量很多时快速扫读。每行右侧提供「复制 select:NAME」按钮；当 [onClear]
/// 非空时，标题栏显示「清空已加载列表」按钮。
class ToolSearchLoadedDialog extends StatefulWidget {
  const ToolSearchLoadedDialog({
    super.key,
    required this.initialNames,
    this.onClear,
    this.initialHistory = const <AiToolSearchLoadHistoryEntry>[],
  });

  final List<String> initialNames;
  final void Function()? onClear;
  final List<AiToolSearchLoadHistoryEntry> initialHistory;

  @override
  State<ToolSearchLoadedDialog> createState() => _ToolSearchLoadedDialogState();
}

/// 单个分组：server 名 + 该 server 下所有完整工具名（已排序）。
/// `server == null` 表示无法解析出 `mcp__SERVER__` 前缀的「其他」组。
@immutable
class _ToolGroup {
  const _ToolGroup({required this.server, required this.names});

  final String? server;
  final List<String> names;
}

/// 将完整工具名拆出 `SERVER` 段。
/// 形如 `mcp__SERVER__tool_name` 返回 `SERVER`；其它返回 `null`。
String? _serverOfMcpTool(String name) {
  if (!name.startsWith('mcp__')) return null;
  final rest = name.substring(5);
  final sepIdx = rest.indexOf('__');
  if (sepIdx <= 0) return null;
  return rest.substring(0, sepIdx);
}

List<_ToolGroup> _groupByServer(List<String> names) {
  final byServer = <String, List<String>>{};
  final misc = <String>[];
  for (final n in names) {
    final svr = _serverOfMcpTool(n);
    if (svr == null) {
      misc.add(n);
    } else {
      (byServer[svr] ??= <String>[]).add(n);
    }
  }
  final sortedServers = byServer.keys.toList()..sort();
  final groups = <_ToolGroup>[
    for (final s in sortedServers)
      _ToolGroup(
        server: s,
        names: List<String>.unmodifiable(byServer[s]!..sort()),
      ),
  ];
  if (misc.isNotEmpty) {
    misc.sort();
    groups.add(_ToolGroup(server: null, names: List<String>.unmodifiable(misc)));
  }
  return groups;
}

class _ToolSearchLoadedDialogState extends State<ToolSearchLoadedDialog>
    with SingleTickerProviderStateMixin {
  late List<String> _names = List<String>.unmodifiable(widget.initialNames);
  late final List<AiToolSearchLoadHistoryEntry> _history =
      List<AiToolSearchLoadHistoryEntry>.unmodifiable(widget.initialHistory);
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleClear() {
    final onClear = widget.onClear;
    if (onClear == null) return;
    onClear();
    setState(() {
      _names = const <String>[];
    });
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(l10n.snackToolSearchLoadedClearedToast),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleCopy(String name) async {
    await Clipboard.setData(ClipboardData(text: 'select:$name'));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(l10n.snackToolSearchLoadedCopiedToast),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleCopyGroup(_ToolGroup group) async {
    if (group.names.isEmpty) return;
    final payload = group.names.map((n) => 'select:$n').join(', ');
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(l10n.snackToolSearchLoadedCopiedToast),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final groups = _groupByServer(_names);
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(l10n.snackToolSearchLoadedDialogTitle)),
          if (widget.onClear != null && _names.isNotEmpty)
            TextButton.icon(
              onPressed: _handleClear,
              icon: const Icon(Icons.delete_sweep_rounded, size: 16),
              label: Text(l10n.snackToolSearchLoadedClearAction),
            ),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(
                  icon: const Icon(Icons.checklist_rounded, size: 18),
                  text:
                      '${l10n.snackToolSearchLoadedTabLoaded} (${_names.length})',
                ),
                Tab(
                  icon: const Icon(Icons.history_rounded, size: 18),
                  text:
                      '${l10n.snackToolSearchLoadedTabHistory} (${_history.length})',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLoadedTab(context, l10n, groups),
                  _buildHistoryTab(context, l10n),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.snackToolSearchLoadedDialogClose),
        ),
      ],
    );
  }

  Widget _buildLoadedTab(
    BuildContext context,
    AppLocalizations l10n,
    List<_ToolGroup> groups,
  ) {
    if (_names.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text('—', style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return Scrollbar(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: groups.length,
        itemBuilder: (_, index) => _buildGroup(context, groups[index], l10n),
      ),
    );
  }

  Widget _buildHistoryTab(BuildContext context, AppLocalizations l10n) {
    if (_history.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          l10n.snackToolSearchLoadedHistoryEmpty,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    // Show newest first.
    final reversed = _history.reversed.toList(growable: false);
    return Scrollbar(
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: reversed.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) =>
            _buildHistoryEntry(context, l10n, reversed[index]),
      ),
    );
  }

  Widget _buildHistoryEntry(
    BuildContext context,
    AppLocalizations l10n,
    AiToolSearchLoadHistoryEntry entry,
  ) {
    final theme = Theme.of(context);
    final localTime = entry.timestamp.toLocal();
    final hh = localTime.hour.toString().padLeft(2, '0');
    final mm = localTime.minute.toString().padLeft(2, '0');
    final ss = localTime.second.toString().padLeft(2, '0');
    final mo = localTime.month.toString().padLeft(2, '0');
    final dd = localTime.day.toString().padLeft(2, '0');
    final timestampLabel = '${localTime.year}-$mo-$dd $hh:$mm:$ss';
    final queryLabel = entry.query.isEmpty ? '—' : entry.query;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                timestampLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '+${entry.addedCount} / ${entry.totalDeferred}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: l10n.snackToolSearchLoadedHistoryQueryPrefix,
                  style: theme.textTheme.bodySmall,
                ),
                TextSpan(
                  text: queryLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final name in entry.addedNames)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    name,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroup(
    BuildContext context,
    _ToolGroup group,
    AppLocalizations l10n,
  ) {
    final headerLabel = group.server == null
        ? l10n.snackToolSearchLoadedGroupOther
        : group.server!;
    final countSuffix = ' (${group.names.length})';
    final theme = Theme.of(context);
    return Theme(
      // 隐藏 ExpansionTile 默认上下分割线，让组与组之间更紧凑。
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('mcpToolGroup:${group.server ?? '_misc'}'),
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.only(left: 8, bottom: 4),
        leading: Icon(
          group.server == null
              ? Icons.extension_off_outlined
              : Icons.dns_rounded,
          size: 18,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                '$headerLabel$countSuffix',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: l10n.snackToolSearchLoadedCopyGroupAction,
              icon: const Icon(Icons.copy_all_rounded, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: () => _handleCopyGroup(group),
            ),
          ],
        ),
        children: [
          for (final name in group.names)
            ListTile(
              dense: true,
              leading: const Icon(Icons.extension_rounded, size: 18),
              title: SelectableText(
                name,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              trailing: IconButton(
                tooltip: '${l10n.snackToolSearchLoadedCopyAction}$name',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () => _handleCopy(name),
              ),
            ),
        ],
      ),
    );
  }
}
