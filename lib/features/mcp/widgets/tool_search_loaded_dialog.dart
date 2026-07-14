import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/bounded_xfile_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/lifecycle_cache.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../service/tool_search_history_export_prefs.dart';
import '../service/tool_search_history_serializer.dart';
import 'mcp_dialog_utils.dart';

const int _toolSearchHistoryImportMaxBytes = 8 * kBytesPerMiB;
const int _mcpGroupExpansionCacheMaxEntries = 128;

Future<void> showToolSearchLoadedDialog(
  BuildContext context, {
  required List<String> names,
  void Function()? onClear,
  List<AiToolSearchLoadHistoryEntry> history =
      const <AiToolSearchLoadHistoryEntry>[],
  Future<void> Function(List<String> names)? onReplayBatch,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => ToolSearchLoadedDialog(
      initialNames: names,
      onClear: onClear,
      initialHistory: history,
      onReplayBatch: onReplayBatch,
    ),
  );
}

/// 列出本会话已通过 `ToolSearch` 加载的工具名。
/// 工具名形如 `mcp__SERVER__tool` 时按 `SERVER` 分组、可折叠展示，便于在工具
/// 数量很多时快速扫读。每行右侧提供「复制 select:NAME」按钮；当 [onClear]
/// 非空时，标题栏显示「清空已加载列表」按钮。
class ToolSearchLoadedDialog extends StatefulWidget {
  const ToolSearchLoadedDialog({
    super.key,
    required this.initialNames,
    this.onClear,
    this.initialHistory = const <AiToolSearchLoadHistoryEntry>[],
    this.onReplayBatch,
  });

  final List<String> initialNames;
  final void Function()? onClear;
  final List<AiToolSearchLoadHistoryEntry> initialHistory;

  /// 当用户点击「加载历史」中的某一条目时被调用：调用方应直接重新发起
  /// 一次 `select:N1, select:N2,...` 的 ToolSearch 调用（一般做法是把
  /// 文本填入 composer 然后立刻 submit），从而省去用户手动复制粘贴。
  /// 为 `null` 时退化为复制到剪贴板的旧行为。
  final Future<void> Function(List<String> names)? onReplayBatch;

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

  String get persistKey => server ?? '_misc';
}

/// 进程级缓存，记录用户对每个分组的折叠/展开偏好。
/// 跨次打开 dialog 保留；进程重启后回到默认展开。
final LifecycleLruCache<bool> _mcpGroupExpansionCache = LifecycleLruCache<bool>(
  maxEntries: _mcpGroupExpansionCacheMaxEntries,
);

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
    groups.add(
      _ToolGroup(server: null, names: List<String>.unmodifiable(misc)),
    );
  }
  return groups;
}

class _ToolSearchLoadedDialogState extends State<ToolSearchLoadedDialog>
    with SingleTickerProviderStateMixin {
  late List<String> _names = List<String>.unmodifiable(widget.initialNames);
  late List<AiToolSearchLoadHistoryEntry> _history =
      List<AiToolSearchLoadHistoryEntry>.unmodifiable(widget.initialHistory);
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';
  final TextEditingController _historyFilterController =
      TextEditingController();
  final ScrollController _groupsScrollController = ScrollController();
  final ScrollController _historyScrollController = ScrollController();
  String _historyFilterQuery = '';
  // null = 全部；其余值代表只看该来源。
  AiToolSearchLoadSource? _historySourceFilter;

  @override
  void dispose() {
    _filterController.dispose();
    _historyFilterController.dispose();
    _groupsScrollController.dispose();
    _historyScrollController.dispose();
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
    flashOpenHandSnack(context, l10n.snackToolSearchLoadedClearedToast);
  }

  Future<void> _handleCopy(String name) async {
    final l10n = AppLocalizations.of(context);
    await copyMcpTextToClipboard(
      context: context,
      text: 'select:$name',
      successMessage: l10n?.snackToolSearchLoadedCopiedToast,
      logAction: 'copy tool search selection',
    );
  }

  Future<void> _handleCopyGroup(_ToolGroup group) async {
    if (group.names.isEmpty) return;
    final payload = group.names.map((n) => 'select:$n').join(', ');
    final l10n = AppLocalizations.of(context);
    await copyMcpTextToClipboard(
      context: context,
      text: payload,
      successMessage: l10n?.snackToolSearchLoadedCopiedToast,
      logAction: 'copy tool search group',
    );
  }

  Future<void> _handleReplayHistoryEntry(
    AiToolSearchLoadHistoryEntry entry,
  ) async {
    if (entry.addedNames.isEmpty) return;
    final cb = widget.onReplayBatch;
    if (cb != null) {
      // 直接重新调用 ToolSearch：先关闭 dialog 再交给上游执行（一般是
      // 把 select: 文本填入 composer 并触发 submit）。
      Navigator.of(context).pop();
      await cb(entry.addedNames);
      return;
    }
    // 退化路径：未提供 onReplayBatch 时，回退为复制到剪贴板。
    final payload = entry.addedNames.map((n) => 'select:$n').join(', ');
    final l10n = AppLocalizations.of(context);
    await copyMcpTextToClipboard(
      context: context,
      text: payload,
      successMessage: l10n?.snackToolSearchLoadedCopiedToast,
      logAction: 'copy tool search history replay',
    );
  }

  void _handleClearHistory() {
    if (_history.isEmpty) return;
    setState(() {
      _history = const <AiToolSearchLoadHistoryEntry>[];
    });
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    flashOpenHandSnack(context, l10n.snackToolSearchLoadedHistoryClearedToast);
  }

  /// 把当前 [_history]（应用 [_historyFilterQuery]、[_historyFilterSource] 之后）
  /// 序列化为 CSV 或 Markdown，并按 [action] 选择目的地：
  ///   - copy: 写入系统剪贴板，Toast 行数；
  ///   - save: 调 file_selector 让用户挑文件，写盘后 Toast 路径。
  /// 任一步骤失败均仅吐 SnackBar，不抛出。
  Future<void> _handleExportHistory(_HistoryExportAction action) async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    final entries = _filterHistory(_history);
    if (entries.isEmpty) {
      flashOpenHandSnack(
        context,
        l10n.snackToolSearchLoadedHistoryExportEmptyToast,
      );
      return;
    }
    final isCsv = action.format == _HistoryExportFormat.csv;
    final isJson = action.format == _HistoryExportFormat.json;
    final payload = isCsv
        ? ToolSearchHistorySerializer.toCsv(entries)
        : isJson
        ? ToolSearchHistorySerializer.toJson(entries)
        : ToolSearchHistorySerializer.toMarkdown(entries);
    if (action.destination == _HistoryExportDestination.clipboard) {
      await copyMcpTextToClipboard(
        context: context,
        text: payload,
        successMessage: l10n.snackToolSearchLoadedHistoryExportedToast(
          entries.length,
        ),
        logAction: 'copy tool search history export',
      );
      return;
    }
    // Save-to-file branch.
    final ext = isCsv ? 'csv' : (isJson ? 'json' : 'md');
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final suggested = 'tool_search_history_$stamp.$ext';
    final typeGroup = XTypeGroup(
      label: isCsv ? 'CSV' : (isJson ? 'JSON' : 'Markdown'),
      extensions: <String>[ext],
    );
    FileSaveLocation? location;
    final lastDir = await ToolSearchHistoryExportPrefs.readLastDir();
    if (!mounted) return;
    try {
      location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
        initialDirectory: lastDir,
      );
    } catch (error, stack) {
      silentLog(
        'tool_search_loaded_dialog',
        '_handleExportHistory.getSaveLocation',
        error,
        stack,
      );
      if (!mounted) return;
      flashOpenHandSnack(
        context,
        l10n.snackToolSearchLoadedHistoryExportSaveFailedToast('$error'),
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    if (location == null) return;
    try {
      await File(location.path).writeAsString(payload, flush: true);
    } catch (error, stack) {
      silentLog(
        'tool_search_loaded_dialog',
        '_handleExportHistory.writeAsString',
        error,
        stack,
      );
      if (!mounted) return;
      flashOpenHandSnack(
        context,
        l10n.snackToolSearchLoadedHistoryExportSaveFailedToast('$error'),
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    if (!mounted) return;
    final savedPath = location.path;
    // Remember the directory for next export.
    unawaited(ToolSearchHistoryExportPrefs.writeLastDir(p.dirname(savedPath)));
    flashOpenHandSnack(
      context,
      l10n.snackToolSearchLoadedHistoryExportSavedToast(
        entries.length,
        savedPath,
      ),
      kind: OpenHandSnackKind.success,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: l10n.snackToolSearchLoadedHistoryExportRevealAction,
        onPressed: () => _revealInFileManager(savedPath),
      ),
    );
  }

  /// 在系统文件管理器里高亮显示刚保存的文件：macOS 用 `open -R`，
  /// Windows 用 `explorer.exe /select,`，Linux 退化到打开父目录。失败静默 log。
  Future<void> _revealInFileManager(String filePath) async {
    try {
      await revealLocalPathInSystemFileManager(
        filePath,
        tag: 'tool_search_loaded_dialog.reveal',
      );
    } catch (error, stack) {
      silentLog(
        'tool_search_loaded_dialog',
        '_revealInFileManager',
        error,
        stack,
      );
    }
  }

  /// 让用户挑一个由 [ToolSearchHistorySerializer.toJson] 生成的 JSON 文件，
  /// 解析失败时 SnackBar 提示，成功时弹一个只读 preview dialog 列出条目。
  Future<void> _handleImportHistoryFromJson() async {
    XFile? picked;
    try {
      picked = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'JSON', extensions: <String>['json']),
        ],
        initialDirectory: await ToolSearchHistoryExportPrefs.readLastDir(),
      );
    } catch (error, stack) {
      silentLog(
        'tool_search_loaded_dialog',
        '_handleImportHistoryFromJson.openFile',
        error,
        stack,
      );
      return;
    }
    if (picked == null || !mounted) return;
    String raw;
    try {
      final bytes = await readBoundedXFileBytes(
        picked,
        maxBytes: _toolSearchHistoryImportMaxBytes,
      );
      raw = utf8.decode(bytes);
    } catch (error, stack) {
      silentLog(
        'tool_search_loaded_dialog',
        '_handleImportHistoryFromJson.read',
        error,
        stack,
      );
      _showHistoryImportFailure();
      return;
    }
    List<AiToolSearchLoadHistoryEntry> entries;
    try {
      entries = ToolSearchHistorySerializer.fromJson(raw);
    } catch (error, stack) {
      silentLog(
        'tool_search_loaded_dialog',
        '_handleImportHistoryFromJson.parse',
        error,
        stack,
      );
      _showHistoryImportFailure();
      return;
    }
    if (!mounted) return;
    await showAnimatedDialog<void>(
      context: context,
      builder: (ctx) => _ToolSearchHistoryImportPreviewDialog(entries: entries),
    );
  }

  void _showHistoryImportFailure() {
    if (!mounted) return;
    final maxSize = formatByteSize(_toolSearchHistoryImportMaxBytes);
    flashOpenHandSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '无法导入历史记录，请确认 JSON 文件有效且未超过 $maxSize。',
        zhHant: '無法匯入歷史記錄，請確認 JSON 檔案有效且未超過 $maxSize。',
        en: 'Could not import history. Check that the JSON file is valid and no larger than $maxSize.',
        fr: 'Import impossible. Vérifiez que le fichier JSON est valide et ne dépasse pas $maxSize.',
        de: 'Verlauf konnte nicht importiert werden. Die JSON-Datei muss gültig und höchstens $maxSize groß sein.',
        ja: '履歴をインポートできません。JSON ファイルが有効で $maxSize 以下か確認してください。',
      ),
      kind: OpenHandSnackKind.error,
    );
  }

  /// 把 [_groupByServer] 的结果按 [_filterQuery] 做大小写不敏感子串过滤，
  /// 仅保留至少有一项命中的分组；分组内只保留命中条目。
  List<_ToolGroup> _filterGroups(List<_ToolGroup> groups) {
    final q = _filterQuery.trim().toLowerCase();
    if (q.isEmpty) return groups;
    final filtered = <_ToolGroup>[];
    for (final g in groups) {
      final hit = g.names.where((n) => n.toLowerCase().contains(q)).toList();
      if (hit.isEmpty) continue;
      filtered.add(
        _ToolGroup(server: g.server, names: List<String>.unmodifiable(hit)),
      );
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final groups = _groupByServer(_names);
    return buildOpenHandAlertDialog(
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
        height: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSummaryStrip(context, l10n),
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
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.snackToolSearchLoadedDialogClose,
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
    final filtered = _filterGroups(groups);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _filterController,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            hintText: l10n.snackToolSearchLoadedFilterHint,
            suffixIcon: _filterQuery.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _filterController.clear();
                      setState(() => _filterQuery = '');
                    },
                  ),
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _filterQuery = v),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    '—',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : PrimaryScrollController.none(
                  child: OpenHandSafeScrollbar(
                    controller: _groupsScrollController,
                    child: ListView.builder(
                      controller: _groupsScrollController,
                      primary: false,
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, index) =>
                          _buildGroup(context, filtered[index], l10n),
                    ),
                  ),
                ),
        ),
      ],
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
    final filtered = _filterHistory(reversed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _historyFilterController,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  hintText: l10n.snackToolSearchLoadedHistoryFilterHint,
                  suffixIcon: _historyFilterQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _historyFilterController.clear();
                            setState(() => _historyFilterQuery = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _historyFilterQuery = v),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedPopupMenuButton<_HistoryExportAction>(
              tooltip: l10n.snackToolSearchLoadedHistoryExportTooltip,
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              padding: EdgeInsets.zero,
              onSelected: _handleExportHistory,
              itemBuilder: (context) => <PopupMenuEntry<_HistoryExportAction>>[
                PopupMenuItem<_HistoryExportAction>(
                  value: _HistoryExportAction.copyCsv,
                  child: Tooltip(
                    message: l10n.snackToolSearchLoadedHistoryExportCsvHint,
                    child: Text(l10n.snackToolSearchLoadedHistoryExportCsv),
                  ),
                ),
                PopupMenuItem<_HistoryExportAction>(
                  value: _HistoryExportAction.copyMarkdown,
                  child: Tooltip(
                    message:
                        l10n.snackToolSearchLoadedHistoryExportMarkdownHint,
                    child: Text(
                      l10n.snackToolSearchLoadedHistoryExportMarkdown,
                    ),
                  ),
                ),
                PopupMenuItem<_HistoryExportAction>(
                  value: _HistoryExportAction.copyJson,
                  child: Tooltip(
                    message: l10n.snackToolSearchLoadedHistoryExportJsonHint,
                    child: Text(l10n.snackToolSearchLoadedHistoryExportJson),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<_HistoryExportAction>(
                  value: _HistoryExportAction.saveCsv,
                  child: Tooltip(
                    message: l10n.snackToolSearchLoadedHistoryExportCsvHint,
                    child: Text(l10n.snackToolSearchLoadedHistoryExportSaveCsv),
                  ),
                ),
                PopupMenuItem<_HistoryExportAction>(
                  value: _HistoryExportAction.saveMarkdown,
                  child: Tooltip(
                    message:
                        l10n.snackToolSearchLoadedHistoryExportMarkdownHint,
                    child: Text(
                      l10n.snackToolSearchLoadedHistoryExportSaveMarkdown,
                    ),
                  ),
                ),
                PopupMenuItem<_HistoryExportAction>(
                  value: _HistoryExportAction.saveJson,
                  child: Tooltip(
                    message: l10n.snackToolSearchLoadedHistoryExportJsonHint,
                    child: Text(
                      l10n.snackToolSearchLoadedHistoryExportSaveJson,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: l10n.toolSearchLoadedHistoryImportTooltip,
              icon: const Icon(Icons.file_open_rounded, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _handleImportHistoryFromJson,
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _handleClearHistory,
              icon: const Icon(Icons.delete_sweep_rounded, size: 16),
              label: Text(l10n.snackToolSearchLoadedHistoryClearAction),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<AiToolSearchLoadSource?>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: <ButtonSegment<AiToolSearchLoadSource?>>[
              ButtonSegment(
                value: null,
                label: Text(l10n.snackToolSearchLoadedSourceFilterAll),
              ),
              ButtonSegment(
                value: AiToolSearchLoadSource.aiSession,
                label: Text(l10n.snackToolSearchLoadedSourceFilterAi),
              ),
              ButtonSegment(
                value: AiToolSearchLoadSource.harnessPhase,
                label: Text(l10n.snackToolSearchLoadedSourceFilterHarness),
              ),
            ],
            selected: <AiToolSearchLoadSource?>{_historySourceFilter},
            onSelectionChanged: (selection) {
              setState(() => _historySourceFilter = selection.first);
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    l10n.snackToolSearchLoadedHistoryEmpty,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : PrimaryScrollController.none(
                  child: OpenHandSafeScrollbar(
                    controller: _historyScrollController,
                    child: ListView.separated(
                      controller: _historyScrollController,
                      primary: false,
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) =>
                          _buildHistoryEntry(context, l10n, filtered[index]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// 按 [_historyFilterQuery] 同时匹配 entry.query 与 entry.addedNames，
  /// 大小写不敏感子串匹配；空查询返回原列表。再按 [_historySourceFilter]
  /// 进行来源筛选（null 表示「全部」）。
  List<AiToolSearchLoadHistoryEntry> _filterHistory(
    List<AiToolSearchLoadHistoryEntry> entries,
  ) {
    final q = _historyFilterQuery.trim().toLowerCase();
    final source = _historySourceFilter;
    return entries
        .where(
          (e) =>
              (q.isEmpty ||
                  e.query.toLowerCase().contains(q) ||
                  e.addedNames.any((n) => n.toLowerCase().contains(q))) &&
              (source == null || e.source == source),
        )
        .toList(growable: false);
  }

  Widget _buildHistoryEntry(
    BuildContext context,
    AppLocalizations l10n,
    AiToolSearchLoadHistoryEntry entry,
  ) {
    final theme = Theme.of(context);
    final localTime = entry.timestamp.toLocal();
    final timestampLabel = formatYearMonthDayHms(localTime);
    final queryLabel = entry.query.isEmpty ? '—' : entry.query;
    return InkWell(
      onTap: entry.addedNames.isEmpty
          ? null
          : () => _handleReplayHistoryEntry(entry),
      child: Padding(
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
                const SizedBox(width: 8),
                _buildSourceChip(theme, l10n, entry.source),
                const Spacer(),
                IconButton(
                  tooltip: l10n.snackToolSearchLoadedHistoryReplayAction,
                  icon: const Icon(Icons.copy_all_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: entry.addedNames.isEmpty
                      ? null
                      : () => _handleReplayHistoryEntry(entry),
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
        key: PageStorageKey<String>('mcpToolGroup:${group.persistKey}'),
        initiallyExpanded:
            _mcpGroupExpansionCache.get(group.persistKey) ?? true,
        onExpansionChanged: (expanded) {
          _mcpGroupExpansionCache.put(group.persistKey, expanded);
        },
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

  /// 弹窗顶部 sticky 概要：当前 dialog 内可见的 MCP 工具数 + 历史里
  /// 累计的查询条数，让用户在不切到 history tab 的情况下即可掌握总量。
  Widget _buildSummaryStrip(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.summarize_rounded,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.snackToolSearchLoadedSummary(
                  _history.length,
                  _names.length,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 渲染来源标签 Chip：区分 AI 会话 / Harness 阶段，方便用户快速辨识
  /// 同一历史时间线中的来源。
  Widget _buildSourceChip(
    ThemeData theme,
    AppLocalizations l10n,
    AiToolSearchLoadSource source,
  ) {
    final isHarness = source == AiToolSearchLoadSource.harnessPhase;
    final label = isHarness
        ? l10n.snackToolSearchLoadedSourceHarness
        : l10n.snackToolSearchLoadedSourceAi;
    final color = isHarness
        ? theme.colorScheme.tertiary
        : theme.colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 历史导出格式：CSV（电子表格）或 Markdown 表（README/issue 粘贴）。
enum _HistoryExportFormat { csv, markdown, json }

/// 历史导出目的地：剪贴板（快速）或文件（持久化）。
enum _HistoryExportDestination { clipboard, file }

/// PopupMenu 单项一对一对应「目的地 × 格式」组合。
enum _HistoryExportAction {
  copyCsv(_HistoryExportFormat.csv, _HistoryExportDestination.clipboard),
  copyMarkdown(
    _HistoryExportFormat.markdown,
    _HistoryExportDestination.clipboard,
  ),
  copyJson(_HistoryExportFormat.json, _HistoryExportDestination.clipboard),
  saveCsv(_HistoryExportFormat.csv, _HistoryExportDestination.file),
  saveMarkdown(_HistoryExportFormat.markdown, _HistoryExportDestination.file),
  saveJson(_HistoryExportFormat.json, _HistoryExportDestination.file);

  const _HistoryExportAction(this.format, this.destination);
  final _HistoryExportFormat format;
  final _HistoryExportDestination destination;
}

/// 只读 preview dialog：把 [ToolSearchHistorySerializer.fromJson] 反解出的
/// 一组 entry 以列表形式展示，方便用户检查 JSON 转储是否符合预期。
/// 不写回任何 tracker；纯检视用途。
class _ToolSearchHistoryImportPreviewDialog extends StatelessWidget {
  const _ToolSearchHistoryImportPreviewDialog({required this.entries});

  final List<AiToolSearchLoadHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return buildOpenHandAlertDialog(
      title: Text(l10n.toolSearchLoadedHistoryImportDialogTitle),
      content: SizedBox(
        width: 520,
        height: 420,
        child: entries.isEmpty
            ? Center(child: Text(l10n.toolSearchLoadedHistoryImportDialogEmpty))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l10n.toolSearchLoadedHistoryImportDialogCount(
                        entries.length,
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            e.query.isEmpty ? '(no query)' : e.query,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${e.timestamp.toIso8601String()} · '
                            '${e.source.name} · +${e.addedCount} / '
                            '${e.totalDeferred}',
                            style: theme.textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: <Widget>[
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.toolSearchLoadedHistoryImportDialogClose,
        ),
      ],
    );
  }
}
