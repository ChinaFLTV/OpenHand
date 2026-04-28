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

  @override
  void dispose() {
    _persistDebounce?.cancel();
    super.dispose();
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
            if (_isSelectionMode) _buildSelectionToolbar(theme, sessions),
            Expanded(
              child: sessions.isEmpty
                  ? _buildEmptyState()
                  : _buildList(sessions),
            ),
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
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
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: sessions.length,
      cacheExtent: 600,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _SessionRow(
          key: ValueKey<String>(session.id),
          index: index,
          session: session,
          isSelectionMode: _isSelectionMode,
          isSelected: _selectedIds.contains(session.id),
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
      },
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

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    super.key,
    required this.index,
    required this.session,
    required this.isSelectionMode,
    required this.isSelected,
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
    final bytes = estimateBytes(session);

    final card = Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
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
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
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
                          value: formatBytes(bytes),
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
                    if (total > 0) ...[
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
