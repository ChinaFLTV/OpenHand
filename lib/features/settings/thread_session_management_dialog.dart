import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/export_config_dialog.dart';
import '../../shared/widgets/export_progress_dialog.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../ai/ai_session_controller.dart';
import '../ai/model/ai_session.dart';
import '../ai/service/ai_session_jsonl_exporter.dart';

/// Shows the Thread Session Management dialog. Honors the global dialog
/// animation settings (entrance/exit are picked from the nearest
/// `SettingsController` automatically by [showAnimatedDialog]).
Future<void> showThreadSessionManagementDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => const _ThreadSessionManagementDialog(),
  );
}

class _ThreadSessionManagementDialog extends StatefulWidget {
  const _ThreadSessionManagementDialog();

  @override
  State<_ThreadSessionManagementDialog> createState() =>
      _ThreadSessionManagementDialogState();
}

class _ThreadSessionManagementDialogState
    extends State<_ThreadSessionManagementDialog> {
  // Per-dialog overlay of the controller's `sessions` list. We mirror the
  // controller order on first build, then take ownership locally so drag
  // reordering feels instant — persistence happens on Save / on auto-flush
  // for safety (auto-save is debounced via [_scheduleReorderPersist]).
  List<AiSession>? _localOrder;
  Set<String> _selectedIds = <String>{};
  bool _isSelectionMode = false;
  Timer? _persistDebounce;

  // Precise on-disk byte footprint per session, refreshed asynchronously
  // after the dialog opens / sessions change. Falls back to the
  // statistics-based estimate while loading.
  Map<String, int> _diskBytes = const <String, int>{};
  bool _diskBytesLoading = false;

  // View controls.
  _SortMode _sortMode = _SortMode.manual;
  String _searchQuery = '';
  late final TextEditingController _searchController;
  final Set<String> _templateFilter = <String>{};
  bool _denseMode = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDiskBytes();
    });
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshDiskBytes() async {
    if (_diskBytesLoading) return;
    _diskBytesLoading = true;
    try {
      final controller = context.read<AiSessionController>();
      final bytes = await controller.store.computeAllSessionDiskBytes();
      if (!mounted) return;
      setState(() {
        _diskBytes = bytes;
      });
    } catch (error, stack) {
      silentLog(
        'thread_session_management_dialog',
        'computeAllSessionDiskBytes',
        error,
        stack,
      );
    } finally {
      _diskBytesLoading = false;
    }
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  String _localizedText(
    BuildContext context, {
    required String zh,
    required String en,
  }) {
    final code = Localizations.localeOf(context).languageCode;
    return code.startsWith('zh') ? zh : en;
  }

  String _formatDateTime(BuildContext context, DateTime dt) {
    final local = dt.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Approximate on-disk size based on the session statistics already
  /// loaded in memory. Avoids any file-system access so the dialog stays
  /// snappy even with thousands of sessions. We multiply character counts
  /// by 2 as a rough UTF-8 average for mixed CJK/Latin content.
  int _estimateBytes(AiSession session) {
    final stats = session.statistics;
    final chars = stats.totalInputCharacters + stats.totalOutputCharacters;
    return chars * 2;
  }

  void _scheduleReorderPersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      final order = _localOrder;
      if (order == null) return;
      final controller = context.read<AiSessionController>();
      try {
        await controller.reorderSessions(
          order.map((s) => s.id).toList(growable: false),
        );
      } catch (error, stack) {
        silentLog(
          'thread_session_management_dialog',
          'reorderSessions',
          error,
          stack,
        );
      }
    });
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  Future<void> _renameSession(AiSession session) async {
    final controller = context.read<AiSessionController>();
    final titleController = TextEditingController(text: session.title);
    final l10n = AppLocalizations.of(context)!;
    String? submitted;
    try {
      submitted = await showAnimatedDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(_localizedText(
              dialogContext,
              zh: '重命名线程',
              en: 'Rename Thread',
            )),
            content: TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: _localizedText(
                  dialogContext,
                  zh: '输入线程标题',
                  en: 'Enter a thread title',
                ),
              ),
              onSubmitted: (value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(dialogContext).pop(),
                label: l10n.commonCancel,
              ),
              OpenHandDialogActionButton.primary(
                onPressed: () => Navigator.of(dialogContext)
                    .pop(titleController.text.trim()),
                label: l10n.commonSave,
              ),
            ],
          );
        },
      );
    } finally {
      // Defer disposal one frame so the dialog's dismissal animation can
      // still read the controller (matches openhand_home_page pattern).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        titleController.dispose();
      });
    }
    if (!mounted || submitted == null || submitted.isEmpty) return;
    final ok = await controller.renameSession(session.id, submitted);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.lastErrorMessage ??
              _localizedText(context, zh: '重命名失败', en: 'Rename failed'),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSingle(AiSession session) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_localizedText(
          dialogContext,
          zh: '删除线程',
          en: 'Delete Thread',
        )),
        content: Text(session.title),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: l10n.commonCancel,
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: l10n.commonDelete,
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _deleteIds(<String>{session.id});
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final ids = Set<String>.from(_selectedIds);
    final l10n = AppLocalizations.of(context)!;
    final ok = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_localizedText(
          dialogContext,
          zh: '删除所选线程',
          en: 'Delete Selected Threads',
        )),
        content: Text(_localizedText(
          dialogContext,
          zh: '将永久删除 ${ids.length} 个线程及其消息。此操作无法撤销。',
          en: 'Will permanently delete ${ids.length} threads and their '
              'messages. This cannot be undone.',
        )),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: l10n.commonCancel,
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: l10n.commonDelete,
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _deleteIds(ids);
  }

  Future<void> _deleteIds(Set<String> ids) async {
    final controller = context.read<AiSessionController>();
    var failed = 0;
    for (final id in ids) {
      final ok = await controller.deleteSession(id);
      if (!ok) failed++;
    }
    if (!mounted) return;
    setState(() {
      _selectedIds.removeAll(ids);
      if (_selectedIds.isEmpty) _isSelectionMode = false;
      // Drop deleted rows from the local order overlay so the list
      // refreshes immediately without waiting for the controller listener.
      _localOrder?.removeWhere((s) => ids.contains(s.id));
    });
    if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizedText(
            context,
            zh: '$failed 个线程删除失败',
            en: '$failed thread(s) failed to delete',
          )),
        ),
      );
    }
    // Recompute disk footprint after the row count changes.
    unawaited(_refreshDiskBytes());
  }

  Future<void> _exportSession(AiSession headerOnly) async {
    final controller = context.read<AiSessionController>();
    final messenger = ScaffoldMessenger.of(context);
    AiSession? full;
    try {
      full = await controller.store.loadSession(headerOnly.id);
    } catch (error, stack) {
      silentLog(
        'thread_session_management_dialog',
        'export.loadSession',
        error,
        stack,
      );
    }
    if (full == null || !mounted) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(_localizedText(
            context,
            zh: '会话不存在或已被删除',
            en: 'Session is missing or deleted',
          )),
        ));
      }
      return;
    }
    final config = await showAiSessionExportConfigDialog(
      context: context,
      totalMessages: full.messages.length,
    );
    if (config == null || !mounted) return;
    const typeGroup = XTypeGroup(label: 'JSONL', extensions: <String>['jsonl']);
    final safeTitle = full.title
        .replaceAll(RegExp(r'[^A-Za-z0-9_\u4e00-\u9fa5]+'), '_')
        .trim();
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: '${safeTitle.isEmpty ? "session" : safeTitle}_'
            '${full.id}.jsonl',
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog(
        'thread_session_management_dialog',
        'export.getSaveLocation',
        error,
        stack,
      );
    }
    if (location == null || !mounted) return;
    final cancelToken = ExportCancelToken();
    final progressController =
        ExportProgressController(cancelToken: cancelToken);
    final dialogFuture = showExportProgressDialog(
      context: context,
      controller: progressController,
      title: _localizedText(context, zh: '导出会话数据', en: 'Export Session Data'),
      subtitle: _localizedText(
        context,
        zh: '正在导出 “${full.title}”…',
        en: 'Exporting "${full.title}"…',
      ),
      cancelLabel: _localizedText(context, zh: '取消', en: 'Cancel'),
    );
    ExportResult result;
    try {
      result = await exportAiSessionToJsonl(
        session: full,
        destinationPath: location.path,
        cancelToken: cancelToken,
        config: config,
        onProgress: progressController.updateProgress,
      );
    } catch (error, stack) {
      silentLog(
        'thread_session_management_dialog',
        'export.run',
        error,
        stack,
      );
      result = ExportResult(kind: ExportResultKind.failure, error: error);
    }
    progressController.markFinished();
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialogFuture;
    if (!mounted) return;
    final ok = result.kind == ExportResultKind.success;
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? _localizedText(context, zh: '导出完成', en: 'Export complete')
          : _localizedText(context, zh: '导出失败', en: 'Export failed')),
    ));
  }

  Future<void> _batchExportSelected() async {
    if (_selectedIds.isEmpty) return;
    final ids = List<String>.from(_selectedIds);
    final controller = context.read<AiSessionController>();
    final messenger = ScaffoldMessenger.of(context);
    // Pick a destination folder once, then write each session into it.
    String? folderPath;
    try {
      folderPath = await getDirectoryPath(
        confirmButtonText: _localizedText(
          context,
          zh: '选择导出目录',
          en: 'Choose Export Folder',
        ),
      );
    } catch (error, stack) {
      silentLog(
        'thread_session_management_dialog',
        'batchExport.getDirectoryPath',
        error,
        stack,
      );
    }
    if (folderPath == null || !mounted) return;
    final config = await showAiSessionExportConfigDialog(
      context: context,
      // Use a placeholder total — per-session totals vary; we rely on the
      // config's filter flags only.
      totalMessages: 0,
    );
    if (config == null || !mounted) return;
    final cancelToken = ExportCancelToken();
    final progressController =
        ExportProgressController(cancelToken: cancelToken);
    final dialogFuture = showExportProgressDialog(
      context: context,
      controller: progressController,
      title: _localizedText(context, zh: '批量导出', en: 'Batch Export'),
      subtitle: _localizedText(
        context,
        zh: '即将导出 ${ids.length} 个线程…',
        en: 'About to export ${ids.length} threads…',
      ),
      cancelLabel: _localizedText(context, zh: '取消', en: 'Cancel'),
    );
    var ok = 0;
    var failed = 0;
    for (var i = 0; i < ids.length; i++) {
      if (cancelToken.isCancelled) break;
      final id = ids[i];
      progressController.updateProgress(
        ExportProgress(processed: i, total: ids.length),
      );
      AiSession? full;
      try {
        full = await controller.store.loadSession(id);
      } catch (error, stack) {
        silentLog(
          'thread_session_management_dialog',
          'batchExport.loadSession',
          error,
          stack,
        );
      }
      if (full == null) {
        failed++;
        continue;
      }
      final safeTitle = full.title
          .replaceAll(RegExp(r'[^A-Za-z0-9_\u4e00-\u9fa5]+'), '_')
          .trim();
      final fileName =
          '${safeTitle.isEmpty ? "session" : safeTitle}_${full.id}.jsonl';
      final destPath = '$folderPath/$fileName';
      try {
        final result = await exportAiSessionToJsonl(
          session: full,
          destinationPath: destPath,
          cancelToken: cancelToken,
          config: config,
        );
        if (result.kind == ExportResultKind.success) {
          ok++;
        } else {
          failed++;
        }
      } catch (error, stack) {
        silentLog(
          'thread_session_management_dialog',
          'batchExport.run',
          error,
          stack,
        );
        failed++;
      }
    }
    progressController.markFinished();
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialogFuture;
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(_localizedText(
        context,
        zh: '批量导出完成：成功 $ok / 失败 $failed',
        en: 'Batch export done: $ok ok / $failed failed',
      )),
    ));
  }

  Future<void> _showSessionContextMenu(
    AiSession session,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = await showMenu<_SessionRowAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _SessionRowAction.rename,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: Text(
              _localizedText(context, zh: '重命名', en: 'Rename'),
            ),
          ),
        ),
        PopupMenuItem(
          value: _SessionRowAction.export,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(
              _localizedText(context, zh: '导出会话数据', en: 'Export Session'),
            ),
          ),
        ),
        PopupMenuItem(
          value: _SessionRowAction.delete,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: Text(
              _localizedText(context, zh: '删除', en: 'Delete'),
            ),
          ),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case _SessionRowAction.rename:
        await _renameSession(session);
      case _SessionRowAction.export:
        await _exportSession(session);
      case _SessionRowAction.delete:
        await _confirmDeleteSingle(session);
    }
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AiSessionController>();
    final upstream = controller.sessions;
    // Initialize / sync local overlay. We trust the controller's order on
    // first build and after additions/removals the user didn't perform.
    if (_localOrder == null) {
      _localOrder = List<AiSession>.from(upstream);
    } else {
      // Reconcile: keep our manual order for ids that still exist, append
      // new ids that appeared in upstream at the top (matches sidebar
      // behaviour where new threads surface at the top). This avoids
      // visual jumps mid-drag.
      final knownIds = _localOrder!.map((s) => s.id).toSet();
      final upstreamById = <String, AiSession>{
        for (final s in upstream) s.id: s,
      };
      // Refresh known sessions (so titles update after rename, etc.)
      final preserved = <AiSession>[];
      for (final s in _localOrder!) {
        final fresh = upstreamById[s.id];
        if (fresh != null) preserved.add(fresh);
      }
      // Prepend brand-new sessions that don't appear in our local order.
      final additions = upstream
          .where((s) => !knownIds.contains(s.id))
          .toList(growable: false);
      _localOrder = <AiSession>[...additions, ...preserved];
    }
    final sessions = _localOrder!;
    // Apply view-controls (search / template filter / sort) to derive
    // the visible list. Reorder mode operates against `sessions` (the
    // raw manual order) so drag indices map back to the underlying list.
    final templates = <String>{
      for (final s in sessions) s.templateName.trim(),
    }..removeWhere((t) => t.isEmpty);
    final query = _searchQuery.trim().toLowerCase();
    Iterable<AiSession> filtered = sessions;
    if (query.isNotEmpty) {
      filtered = filtered.where(
        (s) => s.title.toLowerCase().contains(query) || s.id.contains(query),
      );
    }
    if (_templateFilter.isNotEmpty) {
      filtered = filtered
          .where((s) => _templateFilter.contains(s.templateName.trim()));
    }
    final visible = filtered.toList();
    int sizeOf(AiSession s) => _diskBytes[s.id] ?? _estimateBytes(s);
    switch (_sortMode) {
      case _SortMode.manual:
        // Already in manual order — leave as-is.
        break;
      case _SortMode.updatedDesc:
        visible.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _SortMode.createdDesc:
        visible.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _SortMode.sizeDesc:
        visible.sort((a, b) => sizeOf(b).compareTo(sizeOf(a)));
      case _SortMode.messagesDesc:
        visible.sort((a, b) => b.statistics.totalMessageCount
            .compareTo(a.statistics.totalMessageCount));
      case _SortMode.tokenDesc:
        visible.sort((a, b) => (b.statistics.totalTokens ?? 0)
            .compareTo(a.statistics.totalTokens ?? 0));
    }
    final theme = Theme.of(context);
    final mediaWidth = MediaQuery.sizeOf(context).width;
    final mediaHeight = MediaQuery.sizeOf(context).height;
    final dialogWidth = mediaWidth.clamp(420.0, 920.0);
    final dialogHeight = (mediaHeight * 0.85).clamp(420.0, 880.0);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme, sessions),
            const Divider(height: 1),
            _buildToolbar(theme, templates),
            const Divider(height: 1),
            if (_isSelectionMode) _buildSelectionToolbar(theme, visible),
            Expanded(
              child: visible.isEmpty
                  ? _buildEmptyState()
                  : _buildList(visible),
            ),
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme, Set<String> templates) {
    final isManual = _sortMode == _SortMode.manual;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: _localizedText(
                        context,
                        zh: '按标题或 ID 搜索',
                        en: 'Search by title or ID',
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<_SortMode>(
                value: _sortMode,
                isDense: true,
                items: [
                  for (final mode in _SortMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(_sortModeLabel(mode)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _sortMode = value);
                },
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: _localizedText(
                  context,
                  zh: _denseMode ? '舒适密度' : '紧凑密度',
                  en: _denseMode ? 'Comfortable' : 'Compact',
                ),
                child: IconButton(
                  icon: Icon(
                    _denseMode
                        ? Icons.density_medium
                        : Icons.density_small,
                  ),
                  onPressed: () => setState(() => _denseMode = !_denseMode),
                ),
              ),
            ],
          ),
          if (templates.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: Text(
                    _localizedText(context, zh: '全部模板', en: 'All Templates'),
                  ),
                  selected: _templateFilter.isEmpty,
                  onSelected: (_) => setState(() => _templateFilter.clear()),
                ),
                for (final t in templates)
                  FilterChip(
                    label: Text(t),
                    selected: _templateFilter.contains(t),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _templateFilter.add(t);
                        } else {
                          _templateFilter.remove(t);
                        }
                      });
                    },
                  ),
              ],
            ),
          ],
          if (!isManual)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _localizedText(
                  context,
                  zh: '当前为「${_sortModeLabel(_sortMode)}」排序，'
                      '拖拽手柄已禁用，切回「手动顺序」可继续调整。',
                  en: 'Sorted by "${_sortModeLabel(_sortMode)}". Drag handles '
                      'are disabled; switch back to "Manual Order" to '
                      'reorder.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _sortModeLabel(_SortMode mode) {
    switch (mode) {
      case _SortMode.manual:
        return _localizedText(context, zh: '手动顺序', en: 'Manual Order');
      case _SortMode.updatedDesc:
        return _localizedText(context, zh: '最近更新', en: 'Recently Updated');
      case _SortMode.createdDesc:
        return _localizedText(context, zh: '最近创建', en: 'Recently Created');
      case _SortMode.sizeDesc:
        return _localizedText(context, zh: '占用大小', en: 'By Size');
      case _SortMode.messagesDesc:
        return _localizedText(context, zh: '消息数量', en: 'By Messages');
      case _SortMode.tokenDesc:
        return _localizedText(context, zh: 'Token 数', en: 'By Token');
    }
  }

  Widget _buildHeader(ThemeData theme, List<AiSession> sessions) {
    final totalCount = sessions.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localizedText(
                    context,
                    zh: '线程会话管理',
                    en: 'Thread Session Management',
                  ),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  _localizedText(
                    context,
                    zh: '共 $totalCount 个线程 · 长按或拖拽手柄可调整顺序，'
                        '双击/右键查看更多操作',
                    en: '$totalCount thread(s) · long-press / drag the handle '
                        'to reorder, double-click / right-click for more',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _isSelectionMode
                ? _localizedText(context, zh: '退出多选', en: 'Exit Selection')
                : _localizedText(context, zh: '多选', en: 'Multi-select'),
            icon: Icon(
              _isSelectionMode
                  ? Icons.check_box_outlined
                  : Icons.checklist_rtl_outlined,
            ),
            onPressed: () {
              setState(() {
                _isSelectionMode = !_isSelectionMode;
                if (!_isSelectionMode) _selectedIds.clear();
              });
            },
          ),
          IconButton(
            tooltip: _localizedText(context, zh: '关闭', en: 'Close'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar(ThemeData theme, List<AiSession> sessions) {
    final allSelected = sessions.isNotEmpty &&
        sessions.every((s) => _selectedIds.contains(s.id));
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            tristate: !allSelected && _selectedIds.isNotEmpty,
            onChanged: (_) {
              setState(() {
                if (allSelected) {
                  _selectedIds.clear();
                } else {
                  _selectedIds = sessions.map((s) => s.id).toSet();
                }
              });
            },
          ),
          Text(
            _localizedText(
              context,
              zh: '已选 ${_selectedIds.length}',
              en: '${_selectedIds.length} selected',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed:
                _selectedIds.isEmpty ? null : _batchExportSelected,
            icon: const Icon(Icons.download_outlined),
            label: Text(
              _localizedText(context, zh: '批量导出', en: 'Batch Export'),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed:
                _selectedIds.isEmpty ? null : _confirmDeleteSelected,
            icon: const Icon(Icons.delete_outline),
            label: Text(
              _localizedText(context, zh: '删除所选', en: 'Delete Selected'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _localizedText(
            context,
            zh: '暂无线程会话',
            en: 'No thread sessions yet',
          ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }

  Widget _buildList(List<AiSession> sessions) {
    final canReorder = _sortMode == _SortMode.manual &&
        _searchQuery.trim().isEmpty &&
        _templateFilter.isEmpty;

    Widget rowFor(int index) {
      final session = sessions[index];
      return _SessionRow(
        key: ValueKey<String>(session.id),
        index: index,
        session: session,
        isSelectionMode: _isSelectionMode,
        isSelected: _selectedIds.contains(session.id),
        denseMode: _denseMode,
        showDragHandle: canReorder,
        diskBytes: _diskBytes[session.id],
        formatDateTime: _formatDateTime,
        formatBytes: _formatBytes,
        estimateBytes: _estimateBytes,
        localizedText: _localizedText,
        onToggleSelect: (checked) {
          setState(() {
            if (checked == true) {
              _selectedIds.add(session.id);
            } else {
              _selectedIds.remove(session.id);
            }
          });
        },
        onDoubleTap: (pos) => _showSessionContextMenu(session, pos),
        onSecondaryTap: (pos) => _showSessionContextMenu(session, pos),
      );
    }

    if (!canReorder) {
      return ListView.builder(
        itemCount: sessions.length,
        cacheExtent: 600,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        itemBuilder: (context, index) => rowFor(index),
      );
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: sessions.length,
      cacheExtent: 600,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      itemBuilder: (context, index) => rowFor(index),
      onReorder: (oldIndex, newIndex) {
        setState(() {
          final list = _localOrder!;
          if (newIndex > oldIndex) newIndex -= 1;
          final moved = list.removeAt(oldIndex);
          list.insert(newIndex, moved);
        });
        _scheduleReorderPersist();
      },
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(context).pop(),
            label: _localizedText(context, zh: '关闭', en: 'Close'),
          ),
        ],
      ),
    );
  }
}

enum _SessionRowAction { rename, export, delete }

enum _SortMode {
  manual,
  updatedDesc,
  createdDesc,
  sizeDesc,
  messagesDesc,
  tokenDesc,
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    super.key,
    required this.index,
    required this.session,
    required this.isSelectionMode,
    required this.isSelected,
    required this.denseMode,
    required this.showDragHandle,
    required this.diskBytes,
    required this.formatDateTime,
    required this.formatBytes,
    required this.estimateBytes,
    required this.localizedText,
    required this.onToggleSelect,
    required this.onDoubleTap,
    required this.onSecondaryTap,
  });

  final int index;
  final AiSession session;
  final bool isSelectionMode;
  final bool isSelected;
  final bool denseMode;
  final bool showDragHandle;
  final int? diskBytes;
  final String Function(BuildContext, DateTime) formatDateTime;
  final String Function(int) formatBytes;
  final int Function(AiSession) estimateBytes;
  final String Function(BuildContext, {required String zh, required String en})
      localizedText;
  final ValueChanged<bool?> onToggleSelect;
  final void Function(Offset globalPosition) onDoubleTap;
  final void Function(Offset globalPosition) onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = session.statistics;
    final total = stats.totalMessageCount;
    String pct(int n) =>
        total == 0 ? '0%' : '${(100 * n / total).round()}%';
    final tokenSummary = stats.totalTokens != null
        ? '${stats.totalTokens} '
            '(in ${stats.totalPromptTokens ?? 0} / out '
            '${stats.totalCompletionTokens ?? 0})'
        : localizedText(context, zh: '未知', en: 'unknown');
    final bytes = diskBytes ?? estimateBytes(session);
    final isApproxBytes = diskBytes == null;

    final card = Card(
      margin: EdgeInsets.symmetric(
        vertical: denseMode ? 2 : 4,
        horizontal: 4,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTapDown: (details) => onDoubleTap(details.globalPosition),
        onSecondaryTapDown: (details) =>
            onSecondaryTap(details.globalPosition),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            denseMode ? 6 : 10,
            8,
            denseMode ? 6 : 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 4, top: 2),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: onToggleSelect,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.title.isEmpty
                                ? localizedText(
                                    context,
                                    zh: '(未命名线程)',
                                    en: '(Untitled Thread)',
                                  )
                                : session.title,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          session.templateName,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        _MetaChip(
                          icon: Icons.add_circle_outline,
                          label: localizedText(
                            context,
                            zh: '创建',
                            en: 'Created',
                          ),
                          value: formatDateTime(context, session.createdAt),
                        ),
                        _MetaChip(
                          icon: Icons.update,
                          label: localizedText(
                            context,
                            zh: '更新',
                            en: 'Updated',
                          ),
                          value: formatDateTime(context, session.updatedAt),
                        ),
                        _MetaChip(
                          icon: Icons.storage_outlined,
                          label: localizedText(
                            context,
                            zh: '占用',
                            en: 'Size',
                          ),
                          value: isApproxBytes
                              ? '~ ${formatBytes(bytes)}'
                              : formatBytes(bytes),
                        ),
                        _MetaChip(
                          icon: Icons.forum_outlined,
                          label: localizedText(
                            context,
                            zh: '消息',
                            en: 'Messages',
                          ),
                          value: '$total',
                        ),
                        _MetaChip(
                          icon: Icons.bolt_outlined,
                          label: localizedText(
                            context,
                            zh: 'Token',
                            en: 'Token',
                          ),
                          value: tokenSummary,
                        ),
                      ],
                    ),
                    if (total > 0 && !denseMode) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${localizedText(context, zh: '占比', en: 'By kind')}: '
                        'user ${pct(stats.userMessageCount)} · '
                        'assistant ${pct(stats.assistantMessageCount)} · '
                        'tool ${pct(stats.toolMessageCount)} · '
                        'mcp ${pct(stats.mcpMessageCount)} · '
                        'skill ${pct(stats.skillMessageCount)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showDragHandle)
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Icon(
                      Icons.drag_indicator,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return card;
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
