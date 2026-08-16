import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_inline_empty_state.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/bounded_xfile_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/lifecycle_cache.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../mcp_errors.dart';
import '../service/tool_search_history_export_prefs.dart';
import '../service/tool_search_history_serializer.dart';

const int _toolSearchHistoryImportMaxBytes = 8 * kBytesPerMiB;
const int _mcpGroupExpansionCacheMaxEntries = 128;
const double _toolSearchDialogMaxWidth = 720;
const double _toolSearchCardActionExtent = 36;
const double _toolSearchActionSpacing = 6;
const double _toolSearchToolbarBreakpoint = 520;

ButtonStyle _toolSearchCircularActionStyle(ColorScheme colorScheme) {
  return IconButton.styleFrom(
    backgroundColor: colorScheme.surfaceContainerHigh,
    foregroundColor: colorScheme.onSurfaceVariant,
    minimumSize: const Size.square(_toolSearchCardActionExtent),
    fixedSize: const Size.square(_toolSearchCardActionExtent),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const CircleBorder(),
  );
}

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

  String get persistKey => server == null ? 'misc' : 'server:$server';
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

List<String> _normalizeToolNames(Iterable<String> names) {
  final normalized = <String>{};
  for (final name in names) {
    final value = name.trim();
    if (value.isNotEmpty) normalized.add(value);
  }
  final result = normalized.toList(growable: false)..sort();
  return List<String>.unmodifiable(result);
}

class _ToolSearchLoadedDialogState extends State<ToolSearchLoadedDialog>
    with SingleTickerProviderStateMixin {
  late List<String> _names = _normalizeToolNames(widget.initialNames);
  late List<_ToolGroup> _groups = _groupByServer(_names);
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
      _groups = const <_ToolGroup>[];
    });
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    flashOpenHandSnack(context, l10n.snackToolSearchLoadedClearedToast);
  }

  Future<void> _handleCopy(String name) async {
    final l10n = AppLocalizations.of(context);
    await copyOpenHandTextToClipboard(
      logTag: 'mcp',
      context: context,
      text: 'select:$name',
      successMessage: l10n?.snackToolSearchLoadedCopiedToast,
      logAction: '复制 ToolSearch 工具选择',
    );
  }

  Future<void> _handleCopyGroup(_ToolGroup group) async {
    if (group.names.isEmpty) return;
    final payload = group.names.map((n) => 'select:$n').join(', ');
    final l10n = AppLocalizations.of(context);
    await copyOpenHandTextToClipboard(
      logTag: 'mcp',
      context: context,
      text: payload,
      successMessage: l10n?.snackToolSearchLoadedCopiedToast,
      logAction: '复制 ToolSearch 工具组',
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
    await copyOpenHandTextToClipboard(
      logTag: 'mcp',
      context: context,
      text: payload,
      successMessage: l10n?.snackToolSearchLoadedCopiedToast,
      logAction: '复制 ToolSearch 历史选择',
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

  /// 把当前 [_history]（应用 [_historyFilterQuery]、[_historySourceFilter] 之后）
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
      await copyOpenHandTextToClipboard(
        logTag: 'mcp',
        context: context,
        text: payload,
        successMessage: l10n.snackToolSearchLoadedHistoryExportedToast(
          entries.length,
        ),
        logAction: '复制 ToolSearch 历史导出内容',
      );
      return;
    }
    // 保存到文件。
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
      silentLog('tool_search_loaded_dialog', '选择工具历史导出位置', error, stack);
      if (!mounted) return;
      flashOpenHandSnack(
        context,
        l10n.snackToolSearchLoadedHistoryExportSaveFailedToast(
          mcpFailureMessage(
            error,
            fallback: openHandLocalizedText(
              context,
              zh: '无法选择导出位置。',
              en: 'Could not choose an export location.',
            ),
          ),
        ),
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    if (location == null) return;
    try {
      await writeFileAtomically(File(location.path), payload);
    } catch (error, stack) {
      silentLog('tool_search_loaded_dialog', '导出工具历史记录', error, stack);
      if (!mounted) return;
      flashOpenHandSnack(
        context,
        l10n.snackToolSearchLoadedHistoryExportSaveFailedToast(
          mcpFailureMessage(
            error,
            fallback: openHandLocalizedText(
              context,
              zh: '无法写入导出文件。',
              en: 'Could not write the export file.',
            ),
          ),
        ),
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    if (!mounted) return;
    final savedPath = location.path;
    // 记录目录，供下次导出使用。
    unawaited(ToolSearchHistoryExportPrefs.writeLastDir(p.dirname(savedPath)));
    flashOpenHandSnack(
      context,
      l10n.snackToolSearchLoadedHistoryExportSavedToast(
        entries.length,
        savedPath,
      ),
      kind: OpenHandSnackKind.success,
      duration: kOpenHandSnackBarLongReadDuration,
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
      silentLog('tool_search_loaded_dialog', '在文件管理器中定位', error, stack);
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
      silentLog('tool_search_loaded_dialog', '选择工具历史导入文件', error, stack);
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
      silentLog('tool_search_loaded_dialog', '读取工具历史导入文件', error, stack);
      _showHistoryImportFailure();
      return;
    }
    List<AiToolSearchLoadHistoryEntry> entries;
    try {
      entries = ToolSearchHistorySerializer.fromJson(raw);
    } catch (error, stack) {
      silentLog('tool_search_loaded_dialog', '解析工具历史导入文件', error, stack);
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: _toolSearchDialogMaxWidth,
      maxWidthFraction: 0.94,
      maxHeightFraction: 0.9,
      minAvailableWidth: 320,
      minAvailableHeight: 420,
      horizontalMargin: 24,
      verticalMargin: 40,
      safeAreaMinimum: const EdgeInsets.all(12),
      backgroundColor: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandRadius20)),
      expandToMax: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.extension_rounded,
            iconSize: 22,
            title: l10n.snackToolSearchLoadedDialogTitle,
            subtitle: l10n.snackToolSearchLoadedSummary(
              _history.length,
              _names.length,
            ),
            actions: [
              if (widget.onClear != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: IconButton(
                    key: const ValueKey<String>('toolSearchClearAction'),
                    tooltip: l10n.snackToolSearchLoadedClearAction,
                    onPressed: _names.isEmpty ? null : _handleClear,
                    icon: const Icon(Icons.delete_sweep_rounded, size: 19),
                  ),
                ),
            ],
            closeTooltip: l10n.snackToolSearchLoadedDialogClose,
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _buildTabBar(context, l10n),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLoadedTab(context, l10n, _groups),
                  _buildHistoryTab(context, l10n),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorAnimation: TabIndicatorAnimation.linear,
        indicator: ShapeDecoration(
          color: colorScheme.primaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kOpenHandRadius12),
            side: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.24),
            ),
          ),
        ),
        splashFactory: NoSplash.splashFactory,
        splashBorderRadius: BorderRadius.circular(kOpenHandRadius12),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        labelColor: colorScheme.onPrimaryContainer,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        tabs: [
          Tab(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.checklist_rounded, size: 18),
                kOpenHandHGap7,
                Flexible(
                  child: Text(
                    '${l10n.snackToolSearchLoadedTabLoaded} · ${_names.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Tab(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history_rounded, size: 18),
                kOpenHandHGap7,
                Flexible(
                  child: Text(
                    '${l10n.snackToolSearchLoadedTabHistory} · ${_history.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedTab(
    BuildContext context,
    AppLocalizations l10n,
    List<_ToolGroup> groups,
  ) {
    if (_names.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.extension_off_rounded,
        title: openHandLocalizedText(
          context,
          zh: '尚未加载 MCP 工具',
          zhHant: '尚未載入 MCP 工具',
          en: 'No MCP tools loaded',
          fr: 'Aucun outil MCP chargé',
          de: 'Keine MCP-Tools geladen',
          ja: 'MCP ツールはまだロードされていません',
        ),
      );
    }
    final filtered = _filterGroups(groups);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchField(
          controller: _filterController,
          query: _filterQuery,
          hintText: l10n.snackToolSearchLoadedFilterHint,
          onChanged: (v) => setState(() => _filterQuery = v),
          onClear: () {
            _filterController.clear();
            setState(() => _filterQuery = '');
          },
        ),
        kOpenHandGap12,
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState(
                  context,
                  icon: Icons.search_off_rounded,
                  title: openHandLocalizedText(
                    context,
                    zh: '没有匹配的工具',
                    zhHant: '沒有符合的工具',
                    en: 'No matching tools',
                    fr: 'Aucun outil correspondant',
                    de: 'Keine passenden Tools',
                    ja: '一致するツールはありません',
                  ),
                  description: l10n.snackToolSearchLoadedFilterHint,
                )
              : PrimaryScrollController.none(
                  child: OpenHandSafeScrollbar(
                    controller: _groupsScrollController,
                    child: ListView.builder(
                      controller: _groupsScrollController,
                      primary: false,
                      padding: const EdgeInsets.only(bottom: 4),
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

  Widget _buildSearchField({
    required TextEditingController controller,
    required String query,
    required String hintText,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
  }) {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded, size: 19),
          prefixIconConstraints: const BoxConstraints(minWidth: 44),
          hintText: hintText,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 42),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(kOpenHandRadius14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kOpenHandRadius14),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kOpenHandRadius14),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 1.5,
            ),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? description,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: kOpenHandContentMaxWidth360,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(kOpenHandRadius18),
                ),
                child: Icon(icon, color: colorScheme.onPrimaryContainer),
              ),
              kOpenHandGap14,
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (description != null && description.isNotEmpty) ...[
                kOpenHandGap5,
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab(BuildContext context, AppLocalizations l10n) {
    if (_history.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.history_toggle_off_rounded,
        title: l10n.snackToolSearchLoadedHistoryEmpty,
      );
    }
    // 最新记录优先，减少用户查找刚完成操作的成本。
    final reversed = _history.reversed.toList(growable: false);
    final filtered = _filterHistory(reversed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchField(
          controller: _historyFilterController,
          query: _historyFilterQuery,
          hintText: l10n.snackToolSearchLoadedHistoryFilterHint,
          onChanged: (v) => setState(() => _historyFilterQuery = v),
          onClear: () {
            _historyFilterController.clear();
            setState(() => _historyFilterQuery = '');
          },
        ),
        kOpenHandGap10,
        _buildHistoryToolbar(context, l10n),
        kOpenHandGap12,
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState(
                  context,
                  icon: Icons.search_off_rounded,
                  title: openHandLocalizedText(
                    context,
                    zh: '没有匹配的历史记录',
                    zhHant: '沒有符合的歷史紀錄',
                    en: 'No matching history',
                    fr: 'Aucun historique correspondant',
                    de: 'Kein passender Verlauf',
                    ja: '一致する履歴はありません',
                  ),
                  description: l10n.snackToolSearchLoadedHistoryFilterHint,
                )
              : PrimaryScrollController.none(
                  child: OpenHandSafeScrollbar(
                    controller: _historyScrollController,
                    child: ListView.separated(
                      controller: _historyScrollController,
                      primary: false,
                      padding: const EdgeInsets.only(bottom: 4),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => kOpenHandGap10,
                      itemBuilder: (_, index) =>
                          _buildHistoryEntry(context, l10n, filtered[index]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHistoryToolbar(BuildContext context, AppLocalizations l10n) {
    final sourceFilter = SegmentedButton<AiToolSearchLoadSource?>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, 38)),
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
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedPopupMenuButton<_HistoryExportAction>(
          tooltip: l10n.snackToolSearchLoadedHistoryExportTooltip,
          icon: const Icon(Icons.ios_share_rounded, size: 18),
          padding: EdgeInsets.zero,
          buttonConstraints: const BoxConstraints.tightFor(
            width: 38,
            height: 38,
          ),
          onSelected: _handleExportHistory,
          itemBuilder: (context) => _buildHistoryExportItems(l10n),
        ),
        const SizedBox(width: _toolSearchActionSpacing),
        IconButton(
          tooltip: l10n.toolSearchLoadedHistoryImportTooltip,
          icon: const Icon(Icons.file_open_rounded, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          onPressed: _handleImportHistoryFromJson,
        ),
        const SizedBox(width: _toolSearchActionSpacing),
        IconButton(
          tooltip: l10n.snackToolSearchLoadedHistoryClearAction,
          icon: const Icon(Icons.delete_sweep_rounded, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          onPressed: _handleClearHistory,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _toolSearchToolbarBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: sourceFilter),
              kOpenHandGap8,
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        }
        return Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: sourceFilter,
            ),
            const Spacer(),
            actions,
          ],
        );
      },
    );
  }

  List<PopupMenuEntry<_HistoryExportAction>> _buildHistoryExportItems(
    AppLocalizations l10n,
  ) {
    return <PopupMenuEntry<_HistoryExportAction>>[
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
          message: l10n.snackToolSearchLoadedHistoryExportMarkdownHint,
          child: Text(l10n.snackToolSearchLoadedHistoryExportMarkdown),
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
          message: l10n.snackToolSearchLoadedHistoryExportMarkdownHint,
          child: Text(l10n.snackToolSearchLoadedHistoryExportSaveMarkdown),
        ),
      ),
      PopupMenuItem<_HistoryExportAction>(
        value: _HistoryExportAction.saveJson,
        child: Tooltip(
          message: l10n.snackToolSearchLoadedHistoryExportJsonHint,
          child: Text(l10n.snackToolSearchLoadedHistoryExportSaveJson),
        ),
      ),
    ];
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
    final colorScheme = theme.colorScheme;
    final localTime = entry.timestamp.toLocal();
    final timestampLabel = formatYearMonthDayHms(localTime);
    final queryLabel = entry.query.isEmpty ? '—' : entry.query;
    final canReplay = entry.addedNames.isNotEmpty;
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canReplay ? () => _handleReplayHistoryEntry(entry) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 15,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            kOpenHandHGap5,
                            Text(
                              timestampLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: kOpenHandPillBorderRadius,
                          ),
                          child: Text(
                            '+${entry.addedCount} / ${entry.totalDeferred}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        _buildSourceChip(theme, l10n, entry.source),
                      ],
                    ),
                  ),
                  kOpenHandHGap8,
                  IconButton(
                    tooltip: l10n.snackToolSearchLoadedHistoryReplayAction,
                    icon: Icon(
                      widget.onReplayBatch == null
                          ? Icons.copy_all_rounded
                          : Icons.replay_rounded,
                      size: 18,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: _toolSearchCardActionExtent,
                      height: _toolSearchCardActionExtent,
                    ),
                    onPressed: canReplay
                        ? () => _handleReplayHistoryEntry(entry)
                        : null,
                  ),
                ],
              ),
              kOpenHandGap10,
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.68,
                  ),
                  borderRadius: BorderRadius.circular(kOpenHandRadius11),
                ),
                child: SelectableText.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: l10n.snackToolSearchLoadedHistoryQueryPrefix,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextSpan(
                        text: queryLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (entry.addedNames.isNotEmpty) ...[
                kOpenHandGap9,
                for (final name in entry.addedNames)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Tooltip(
                      message: name,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.extension_rounded,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                          ),
                          kOpenHandHGap8,
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final expanded = _mcpGroupExpansionCache.get(group.persistKey) ?? true;
    final actionColor = colorScheme.surfaceContainerHigh;
    final actionStyle = _toolSearchCircularActionStyle(colorScheme);
    final expansionTooltip = openHandLocalizedText(
      context,
      zh: expanded ? '收起工具组' : '展开工具组',
      zhHant: expanded ? '收合工具組' : '展開工具組',
      en: expanded ? 'Collapse tool group' : 'Expand tool group',
      fr: expanded ? 'Réduire le groupe' : 'Développer le groupe',
      de: expanded ? 'Tool-Gruppe einklappen' : 'Tool-Gruppe ausklappen',
      ja: expanded ? 'ツールグループを折りたたむ' : 'ツールグループを展開',
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // 折叠状态由有界缓存维护，避免与可选文本的内部滚动状态串槽。
          key: ValueKey<String>('mcpToolGroup:${group.persistKey}'),
          initiallyExpanded: expanded,
          onExpansionChanged: (nextExpanded) {
            setState(() {
              _mcpGroupExpansionCache.put(group.persistKey, nextExpanded);
            });
          },
          tilePadding: const EdgeInsets.fromLTRB(12, 4, 10, 4),
          childrenPadding: EdgeInsets.zero,
          minTileHeight: 58,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(kOpenHandRadius11),
            ),
            child: Icon(
              group.server == null
                  ? Icons.extension_off_outlined
                  : Icons.dns_rounded,
              size: 18,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  headerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              kOpenHandHGap7,
              Container(
                key: ValueKey<String>('mcpToolGroupCount:${group.persistKey}'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: actionColor,
                  borderRadius: kOpenHandPillBorderRadius,
                ),
                child: Text(
                  '${group.names.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          trailing: Builder(
            builder: (trailingContext) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: ValueKey<String>('mcpToolGroupCopy:${group.persistKey}'),
                  tooltip: l10n.snackToolSearchLoadedCopyGroupAction,
                  icon: const Icon(Icons.copy_all_rounded, size: 17),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: _toolSearchCardActionExtent,
                    height: _toolSearchCardActionExtent,
                  ),
                  style: actionStyle,
                  onPressed: () => _handleCopyGroup(group),
                ),
                const SizedBox(width: _toolSearchActionSpacing),
                IconButton(
                  key: ValueKey<String>(
                    'mcpToolGroupExpand:${group.persistKey}',
                  ),
                  tooltip: expansionTooltip,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: _toolSearchCardActionExtent,
                    height: _toolSearchCardActionExtent,
                  ),
                  style: actionStyle,
                  onPressed: () {
                    final controller = ExpansibleController.of(trailingContext);
                    if (expanded) {
                      controller.collapse();
                    } else {
                      controller.expand();
                    }
                  },
                  icon: AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: openHandMotionDuration(context, kOpenHandMotion180,
                    ),
                    curve: kOpenHandSwitchInCurve,
                    child: const Icon(Icons.expand_more_rounded, size: 19),
                  ),
                ),
              ],
            ),
          ),
          children: [
            Divider(
              height: 1,
              indent: 12,
              endIndent: 12,
              color: colorScheme.outlineVariant,
            ),
            for (var index = 0; index < group.names.length; index++) ...[
              _buildToolRow(context, group.names[index], l10n),
              if (index < group.names.length - 1)
                Divider(
                  height: 1,
                  indent: 54,
                  endIndent: 12,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToolRow(
    BuildContext context,
    String name,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Tooltip(
      message: name,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(kOpenHandRadius9),
              ),
              child: Icon(
                Icons.extension_rounded,
                size: 15,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            kOpenHandHGap11,
            Expanded(
              child: SelectableText(
                name,
                maxLines: 2,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
            kOpenHandHGap8,
            IconButton(
              key: ValueKey<String>('mcpToolCopy:$name'),
              tooltip: '${l10n.snackToolSearchLoadedCopyAction}$name',
              icon: const Icon(Icons.copy_rounded, size: 17),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: _toolSearchCardActionExtent,
                height: _toolSearchCardActionExtent,
              ),
              style: _toolSearchCircularActionStyle(colorScheme),
              onPressed: () => _handleCopy(name),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: kOpenHandPillBorderRadius,
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

/// 只读预览弹窗：把 [ToolSearchHistorySerializer.fromJson] 反解出的
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
            ? OpenHandInlineEmptyState(
                message: l10n.toolSearchLoadedHistoryImportDialogEmpty,
              )
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
                        final sourceLabel =
                            e.source == AiToolSearchLoadSource.harnessPhase
                            ? l10n.snackToolSearchLoadedSourceHarness
                            : l10n.snackToolSearchLoadedSourceAi;
                        return ListTile(
                          dense: true,
                          title: Text(
                            e.query.isEmpty ? '—' : e.query,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${formatYearMonthDayHmsLocal(e.timestamp)} · '
                            '$sourceLabel · +${e.addedCount} / '
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
