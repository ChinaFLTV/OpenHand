import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/export_config_dialog.dart';
import '../../../shared/ui/export_progress_dialog.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/hover_lift.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/timer_safety.dart';
import '../../ai/index.dart';

const Duration _kReorderPersistDebounceDelay = Duration(milliseconds: 400);

/// 打开线程会话管理弹窗，进退场动效由 [showAnimatedDialog] 统一读取全局设置。
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
  // 弹窗首次构建时复制控制器顺序，拖动阶段在本地即时重排并防抖持久化。
  List<AiSession>? _localOrder;
  Set<String> _selectedIds = <String>{};
  bool _isSelectionMode = false;
  final OpenHandDebouncer _persistDebounce = OpenHandDebouncer(
    delay: _kReorderPersistDebounceDelay,
  );

  // 异步加载会话实际磁盘占用，加载期间使用统计数据估算值。
  Map<String, int> _diskBytes = const <String, int>{};
  bool _diskBytesLoading = false;

  // 置顶与归档标记不属于 AiSession，单独从数据库加载并维护。
  Map<String, ({bool pinned, bool archived})> _flags =
      const <String, ({bool pinned, bool archived})>{};
  int _flagsRefreshGeneration = 0;

  // 侧栏默认排除归档会话，仅在用户开启显示时单独加载并合并。
  List<AiSession> _archivedSessions = const <AiSession>[];

  // 视图控制状态。
  _SortMode _sortMode = _SortMode.manual;
  String _searchQuery = '';
  late final TextEditingController _searchController;
  final Set<String> _templateFilter = <String>{};
  bool _denseMode = false;
  bool _showArchived = false;

  // 正在执行删除退场动画的会话编号。
  final Set<String> _animatingOutIds = <String>{};

  // 右侧抽屉按需加载完整消息，避免阻塞弹窗打开。
  AiSession? _previewSession;
  bool _previewLoading = false;
  int _previewGeneration = 0;

  // 导出、置顶、归档与删除结果对应的成功/失败脉冲信号。
  final ValueNotifier<int> _outcomeSuccessSignal = ValueNotifier<int>(0);
  final ValueNotifier<int> _outcomeErrorSignal = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDiskBytes();
      _refreshFlags();
    });
  }

  @override
  void dispose() {
    _persistDebounce.dispose();
    _searchController.dispose();
    _outcomeSuccessSignal.dispose();
    _outcomeErrorSignal.dispose();
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
      silentLog('thread_session_management_dialog', '统计全部会话磁盘占用', error, stack);
    } finally {
      _diskBytesLoading = false;
    }
  }

  Future<void> _refreshFlags() async {
    final generation = ++_flagsRefreshGeneration;
    final showArchived = _showArchived;
    try {
      final controller = context.read<AiSessionController>();
      final flags = await controller.store.loadSessionFlags();
      // If "show archived" is on, also pull the archived sessions so we
      // can merge them into the visible list.
      List<AiSession> archived = const <AiSession>[];
      if (showArchived) {
        final result = await controller.store.loadAllHeaders(
          includeArchived: true,
        );
        archived = result.sessions
            .where((s) => flags[s.id]?.archived == true)
            .toList(growable: false);
      }
      if (!mounted ||
          generation != _flagsRefreshGeneration ||
          showArchived != _showArchived) {
        return;
      }
      setState(() {
        _flags = flags;
        _archivedSessions = archived;
      });
    } catch (error, stack) {
      silentLog('thread_session_management_dialog', '刷新会话标记', error, stack);
    }
  }

  String _formatDateTime(DateTime dt) {
    return formatYearMonthDayHm(dt.toLocal());
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
    _persistDebounce.schedule(() async {
      if (!mounted) return;
      final order = _localOrder;
      if (order == null) return;
      final controller = context.read<AiSessionController>();
      try {
        await controller.reorderSessions(
          order.map((s) => s.id).toList(growable: false),
        );
      } catch (error, stack) {
        silentLog('thread_session_management_dialog', '调整会话顺序', error, stack);
      }
    });
  }

  // Actions
  Future<void> _renameSession(AiSession session) async {
    final controller = context.read<AiSessionController>();
    final l10n = AppLocalizations.of(context)!;
    final submitted = await showOpenHandTextInputDialog(
      context: context,
      title: l10n.tsmRenameThreadTitle,
      initialValue: session.title,
      hintText: l10n.tsmRenameHint,
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonSave,
    );
    if (!mounted || submitted == null || submitted.isEmpty) return;
    final ok = await controller.renameSession(session.id, submitted);
    if (!mounted || ok) return;
    flashOpenHandSnack(
      context,
      controller.lastErrorMessage ??
          AppLocalizations.of(context)!.tsmRenameFailed,
      kind: OpenHandSnackKind.error,
    );
    _outcomeErrorSignal.value++;
  }

  Future<void> _confirmDeleteSingle(AiSession session) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.tsmDeleteThreadTitle,
      message: session.title,
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _deleteIds(<String>{session.id});
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final ids = Set<String>.from(_selectedIds);
    final l10n = AppLocalizations.of(context)!;
    final ok = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.tsmDeleteSelectedTitle,
      message: l10n.tsmDeleteSelectedConfirm(ids.length),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _deleteIds(ids);
  }

  Future<void> _deleteIds(Set<String> ids) async {
    if (!mounted || ids.isEmpty) return;
    final collapseDuration = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.listItem,
    ).exitDuration;
    // 先播放行收起动画，再删除实际数据。
    setState(() {
      _animatingOutIds.addAll(ids);
      // 删除当前预览会话时同步关闭抽屉并使未完成加载失效。
      if (_previewSession != null && ids.contains(_previewSession!.id)) {
        _previewGeneration++;
        _previewSession = null;
        _previewLoading = false;
      }
    });
    if (collapseDuration > Duration.zero) {
      await Future<void>.delayed(collapseDuration);
    }
    if (!mounted) return;
    final controller = context.read<AiSessionController>();
    var failed = 0;
    for (final id in ids) {
      // 抛出与返回 false 一样按失败计：否则异常会带着 _animatingOutIds 一起
      // 逃出去，把没删掉的行永久留在收起态，选择模式也退不出来。
      try {
        if (!await controller.deleteSession(id)) failed++;
      } catch (error, stack) {
        failed++;
        silentLog('thread_session_management_dialog', '删除会话：$id', error, stack);
      }
    }
    if (!mounted) return;
    setState(() {
      _animatingOutIds.removeAll(ids);
      _selectedIds.removeAll(ids);
      if (_selectedIds.isEmpty) _isSelectionMode = false;
      // Drop deleted rows from the local order overlay so the list
      // refreshes immediately without waiting for the controller listener.
      _localOrder?.removeWhere((s) => ids.contains(s.id));
    });
    if (failed > 0) {
      flashOpenHandSnack(
        context,
        AppLocalizations.of(context)!.tsmDeleteFailedCount(failed),
        kind: OpenHandSnackKind.error,
      );
      _outcomeErrorSignal.value++;
    } else {
      _outcomeSuccessSignal.value++;
    }
    // Recompute disk footprint after the row count changes.
    unawaited(_refreshDiskBytes());
    unawaited(_refreshFlags());
  }

  Future<void> _exportSession(AiSession headerOnly) async {
    final controller = context.read<AiSessionController>();
    AiSession? full;
    try {
      full = await controller.store.loadSession(headerOnly.id);
    } catch (error, stack) {
      silentLog('thread_session_management_dialog', '导出：加载会话', error, stack);
    }
    if (full == null || !mounted) {
      if (mounted) {
        flashOpenHandSnack(
          context,
          AppLocalizations.of(context)!.tsmSessionMissing,
          kind: OpenHandSnackKind.error,
        );
        _outcomeErrorSignal.value++;
      }
      return;
    }
    final config = await showAiSessionExportConfigDialog(
      context: context,
      totalMessages: full.messages.length,
    );
    if (config == null || !mounted) return;
    const typeGroup = XTypeGroup(label: 'JSONL', extensions: <String>['jsonl']);
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: jsonlExportPickerSuggestedName(
          buildJsonlExportFilename(title: full.title, sessionId: full.id),
        ),
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog('thread_session_management_dialog', '导出：选择保存位置', error, stack);
    }
    if (location == null || !mounted) return;
    final cancelToken = ExportCancelToken();
    final progressController = ExportProgressController(
      cancelToken: cancelToken,
    );
    final dialogSession = showExportProgressDialog(
      context: context,
      controller: progressController,
      title: AppLocalizations.of(context)!.tsmExportSessionDataTitle,
      subtitle: AppLocalizations.of(context)!.tsmExportingSession(full.title),
      cancelLabel: AppLocalizations.of(context)!.tsmCancel,
    );
    ExportResult result;
    try {
      result = await exportAiSessionToJsonl(
        session: full,
        destinationPath: normalizeJsonlExportPath(location.path),
        cancelToken: cancelToken,
        config: config,
        onProgress: progressController.updateProgress,
      );
    } catch (error, stack) {
      silentLog('thread_session_management_dialog', '执行会话导出', error, stack);
      result = ExportResult(kind: ExportResultKind.failure, error: error);
    }
    progressController.markFinished();
    await dialogSession.dismiss(
      logTag: 'thread_session_management_dialog',
      logAction: '关闭导出进度弹窗',
    );
    if (!mounted) return;
    final ok = result.kind == ExportResultKind.success;
    final l10n = AppLocalizations.of(context)!;
    flashOpenHandSnack(
      context,
      ok ? l10n.tsmExportComplete : l10n.tsmExportFailed,
      kind: ok ? OpenHandSnackKind.success : OpenHandSnackKind.error,
    );
    if (ok) {
      _outcomeSuccessSignal.value++;
    } else {
      _outcomeErrorSignal.value++;
    }
  }

  Future<void> _batchExportSelected() async {
    if (_selectedIds.isEmpty) return;
    final ids = List<String>.from(_selectedIds);
    final controller = context.read<AiSessionController>();
    // Pick a destination folder once, then write each session into it.
    String? folderPath;
    try {
      folderPath = await getDirectoryPath(
        confirmButtonText: AppLocalizations.of(context)!.tsmChooseExportFolder,
      );
    } catch (error, stack) {
      silentLog('thread_session_management_dialog', '批量导出：选择目录', error, stack);
    }
    if (folderPath == null || !mounted) return;
    final config = await showAiSessionExportConfigDialog(
      context: context,
      // Use a placeholder total — per-session totals vary; we rely on the
      // config's filter flags only.
      totalMessages: 0,
      allowRange: false,
    );
    if (config == null || !mounted) return;
    final cancelToken = ExportCancelToken();
    final progressController = ExportProgressController(
      cancelToken: cancelToken,
    );
    final dialogSession = showExportProgressDialog(
      context: context,
      controller: progressController,
      title: AppLocalizations.of(context)!.tsmBatchExportTitle,
      subtitle: AppLocalizations.of(
        context,
      )!.tsmBatchExportSubtitle(ids.length),
      cancelLabel: AppLocalizations.of(context)!.tsmCancel,
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
          '批量导出：加载会话',
          error,
          stack,
        );
      }
      if (full == null) {
        failed++;
        continue;
      }
      final fileName = buildJsonlExportFilename(
        title: full.title,
        sessionId: full.id,
      );
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
        silentLog('thread_session_management_dialog', '执行批量导出', error, stack);
        failed++;
      }
    }
    progressController.markFinished();
    await dialogSession.dismiss(
      logTag: 'thread_session_management_dialog',
      logAction: '关闭批量导出进度弹窗',
    );
    if (!mounted) return;
    final batchMessage = AppLocalizations.of(
      context,
    )!.tsmBatchExportDone(ok, failed);
    flashOpenHandSnack(
      context,
      batchMessage,
      kind: failed == 0 ? OpenHandSnackKind.success : OpenHandSnackKind.error,
    );
    if (failed == 0) {
      _outcomeSuccessSignal.value++;
    } else {
      _outcomeErrorSignal.value++;
    }
  }

  Future<void> _showSessionContextMenu(
    AiSession session,
    Offset globalPosition,
  ) async {
    final flag = _flags[session.id];
    final isPinned = flag?.pinned ?? false;
    final isArchived = flag?.archived ?? false;
    final l10n = AppLocalizations.of(context)!;
    final selected = await showAnimatedPointerMenu<_SessionRowAction>(
      context: context,
      globalPosition: globalPosition,
      items: [
        PopupMenuItem(
          value: _SessionRowAction.preview,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.visibility_outlined),
            title: Text(l10n.tsmMenuPreview),
          ),
        ),
        PopupMenuItem(
          value: _SessionRowAction.rename,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.tsmMenuRename),
          ),
        ),
        PopupMenuItem(
          value: _SessionRowAction.pin,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(isPinned ? l10n.tsmMenuUnpin : l10n.tsmMenuPin),
          ),
        ),
        PopupMenuItem(
          value: _SessionRowAction.archive,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
            ),
            title: Text(
              isArchived ? l10n.tsmMenuUnarchive : l10n.tsmMenuArchive,
            ),
          ),
        ),
        PopupMenuItem(
          value: _SessionRowAction.export,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(l10n.tsmMenuExportSession),
          ),
        ),
        PopupMenuItem(
          value: _SessionRowAction.delete,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.tsmMenuDelete),
          ),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case _SessionRowAction.preview:
        await _openPreview(session);
      case _SessionRowAction.rename:
        await _renameSession(session);
      case _SessionRowAction.pin:
        await _togglePin(session);
      case _SessionRowAction.archive:
        await _toggleArchive(session);
      case _SessionRowAction.export:
        await _exportSession(session);
      case _SessionRowAction.delete:
        await _confirmDeleteSingle(session);
    }
  }

  Future<void> _togglePin(AiSession session) async {
    final controller = context.read<AiSessionController>();
    final wasPinned = _flags[session.id]?.pinned ?? false;
    final ok = await controller.setSessionPinned(session.id, !wasPinned);
    if (!mounted) return;
    if (ok) {
      // Manual ordering tracked by the dialog overlay must be invalidated
      // because the controller has just refreshed `sessions` with a new
      // pinned-first order. Drop the overlay so the next build re-mirrors
      // upstream.
      setState(() {
        _localOrder = null;
      });
      await _refreshFlags();
    } else {
      flashOpenHandSnack(
        context,
        AppLocalizations.of(context)!.tsmPinUpdateFailed,
        kind: OpenHandSnackKind.error,
      );
      _outcomeErrorSignal.value++;
    }
  }

  Future<void> _toggleArchive(AiSession session) async {
    final controller = context.read<AiSessionController>();
    final wasArchived = _flags[session.id]?.archived ?? false;
    final ok = await controller.setSessionArchived(session.id, !wasArchived);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _localOrder = null;
        // 隐藏归档会话时同步关闭当前预览抽屉。
        if (_previewSession?.id == session.id &&
            !wasArchived &&
            !_showArchived) {
          _previewGeneration++;
          _previewSession = null;
          _previewLoading = false;
        }
      });
      await _refreshFlags();
    } else {
      flashOpenHandSnack(
        context,
        AppLocalizations.of(context)!.tsmArchiveUpdateFailed,
        kind: OpenHandSnackKind.error,
      );
      _outcomeErrorSignal.value++;
    }
  }

  Future<void> _openPreview(AiSession session) async {
    final generation = ++_previewGeneration;
    setState(() {
      _previewLoading = true;
      _previewSession = session;
    });
    AiSession? full;
    try {
      final controller = context.read<AiSessionController>();
      full = await controller.store.loadSession(session.id);
    } catch (error, stack) {
      silentLog('thread_session_management_dialog', '打开预览：加载会话', error, stack);
    }
    if (!mounted || generation != _previewGeneration) return;
    setState(() {
      _previewLoading = false;
      // 加载失败时保留概要，成功后再替换为完整消息。
      if (full != null) _previewSession = full;
    });
  }

  void _closePreview() {
    _previewGeneration++;
    setState(() {
      _previewSession = null;
      _previewLoading = false;
    });
  }

  Widget _buildPreviewDrawer(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    final session = _previewSession!;
    final stats = session.statistics;
    // Take the last 6 visible messages so the drawer stays compact.
    final allMessages = session.messages;
    final tail = allMessages.length > 6
        ? allMessages.sublist(allMessages.length - 6)
        : allMessages;
    return Container(
      width: 340,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title.isEmpty
                            ? l10n.tsmUntitledThread
                            : session.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.tsmPreviewMessageCount(stats.totalMessageCount),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.tsmClosePreview,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _closePreview,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_previewLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: tail.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          l10n.tsmNoMessages,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: tail.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final m = tail[index];
                        final preview = m.content.length > 320
                            ? '${m.content.substring(0, 320)}…'
                            : m.content;
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${m.kind.name} · ${m.role.name}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                preview.isEmpty
                                    ? l10n.tsmEmptyMessage
                                    : preview,
                                style: theme.textTheme.bodySmall,
                                maxLines: 8,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  // Build
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AiSessionController>();
    final upstream = controller.sessions;
    // When the user opts in to view archived rows, fold them into the
    // upstream list. Archived sessions live outside `controller.sessions`
    // (which mirrors the sidebar — sidebar excludes archived) so we
    // augment locally only when the toggle is active.
    final List<AiSession> upstreamMerged = _showArchived
        ? <AiSession>[
            ...upstream,
            for (final s in _archivedSessions)
              if (!upstream.any((u) => u.id == s.id)) s,
          ]
        : upstream;
    // Initialize / sync local overlay. We trust the controller's order on
    // first build and after additions/removals the user didn't perform.
    if (_localOrder == null) {
      _localOrder = List<AiSession>.from(upstreamMerged);
    } else {
      // Reconcile: keep our manual order for ids that still exist, append
      // new ids that appeared in upstream at the top (matches sidebar
      // behaviour where new threads surface at the top). This avoids
      // visual jumps mid-drag.
      final knownIds = _localOrder!.map((s) => s.id).toSet();
      final upstreamById = <String, AiSession>{
        for (final s in upstreamMerged) s.id: s,
      };
      // Refresh known sessions (so titles update after rename, etc.)
      final preserved = <AiSession>[];
      for (final s in _localOrder!) {
        final fresh = upstreamById[s.id];
        if (fresh != null) preserved.add(fresh);
      }
      // Prepend brand-new sessions that don't appear in our local order.
      final additions = upstreamMerged
          .where((s) => !knownIds.contains(s.id))
          .toList(growable: false);
      _localOrder = <AiSession>[...additions, ...preserved];
    }
    final sessions = _localOrder!;
    // Apply view-controls (search / template filter / sort) to derive
    // the visible list. Reorder mode operates against `sessions` (the
    // raw manual order) so drag indices map back to the underlying list.
    final templates = <String>{for (final s in sessions) s.templateName.trim()}
      ..removeWhere((t) => t.isEmpty);
    final query = _searchQuery.trim().toLowerCase();
    Iterable<AiSession> filtered = sessions;
    if (query.isNotEmpty) {
      filtered = filtered.where(
        (s) => s.title.toLowerCase().contains(query) || s.id.contains(query),
      );
    }
    if (_templateFilter.isNotEmpty) {
      filtered = filtered.where(
        (s) => _templateFilter.contains(s.templateName.trim()),
      );
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
        visible.sort(
          (a, b) => b.statistics.totalMessageCount.compareTo(
            a.statistics.totalMessageCount,
          ),
        );
      case _SortMode.tokenDesc:
        visible.sort(
          (a, b) => (b.statistics.totalTokens ?? 0).compareTo(
            a.statistics.totalTokens ?? 0,
          ),
        );
    }
    final theme = Theme.of(context);
    final panelMotion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.panel,
    );

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: 920,
      maxHeight: 880,
      maxHeightFraction: 0.85,
      minAvailableWidth: 420,
      minAvailableHeight: 420,
      horizontalMargin: 48,
      verticalMargin: 48,
      safeAreaMinimum: const EdgeInsets.all(24),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(theme, sessions),
              const Divider(height: 1),
              _buildToolbar(theme, templates),
              const Divider(height: 1),
              if (_isSelectionMode) _buildSelectionToolbar(theme, visible),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: visible.isEmpty
                          ? _buildEmptyState()
                          : _buildList(visible),
                    ),
                    AnimatedSize(
                      duration: panelMotion.entranceDuration,
                      reverseDuration: panelMotion.exitDuration,
                      curve: panelMotion.curve.curve,
                      alignment: Alignment.centerLeft,
                      child: _previewSession == null
                          ? const SizedBox(width: 0)
                          : _buildPreviewDrawer(theme),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              _buildFooter(),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: HighlightPulse(
                signal: _outcomeSuccessSignal,
                color: OpenHandStatusColors.success,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: HighlightPulse(
                signal: _outcomeErrorSignal,
                color: OpenHandStatusColors.error,
              ),
            ),
          ),
        ],
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
                      hintText: AppLocalizations.of(context)!.tsmSearchHint,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AnimatedDropdownButton<_SortMode>(
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
                message: _denseMode
                    ? AppLocalizations.of(context)!.tsmDensityComfortable
                    : AppLocalizations.of(context)!.tsmDensityCompact,
                child: IconButton(
                  icon: Icon(
                    _denseMode ? Icons.density_medium : Icons.density_small,
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
                  label: Text(AppLocalizations.of(context)!.tsmAllTemplates),
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
                AppLocalizations.of(
                  context,
                )!.tsmSortDisabledHint(_sortModeLabel(_sortMode)),
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
    final l10n = AppLocalizations.of(context)!;
    switch (mode) {
      case _SortMode.manual:
        return l10n.tsmSortManual;
      case _SortMode.updatedDesc:
        return l10n.tsmSortUpdated;
      case _SortMode.createdDesc:
        return l10n.tsmSortCreated;
      case _SortMode.sizeDesc:
        return l10n.tsmSortSize;
      case _SortMode.messagesDesc:
        return l10n.tsmSortMessages;
      case _SortMode.tokenDesc:
        return l10n.tsmSortToken;
    }
  }

  Widget _buildHeader(ThemeData theme, List<AiSession> sessions) {
    final l10n = AppLocalizations.of(context)!;
    final totalCount = sessions.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.tsmTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  l10n.tsmHeaderSubtitle(totalCount),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _showArchived
                ? l10n.tsmHideArchived
                : l10n.tsmShowArchived,
            icon: Icon(
              _showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
            ),
            onPressed: () {
              final showArchived = !_showArchived;
              setState(() {
                _showArchived = showArchived;
                if (!showArchived) {
                  final archivedIds = _flags.entries
                      .where((entry) => entry.value.archived)
                      .map((entry) => entry.key)
                      .toSet();
                  _selectedIds.removeAll(archivedIds);
                  if (_previewSession != null &&
                      archivedIds.contains(_previewSession!.id)) {
                    _previewGeneration++;
                    _previewSession = null;
                    _previewLoading = false;
                  }
                }
              });
              unawaited(_refreshFlags());
            },
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: _isSelectionMode
                ? l10n.tsmExitSelection
                : l10n.tsmEnterSelection,
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
          const SizedBox(width: 6),
          IconButton(
            tooltip: l10n.tsmClose,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar(ThemeData theme, List<AiSession> sessions) {
    final allSelected =
        sessions.isNotEmpty &&
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
            AppLocalizations.of(context)!.tsmSelectedCount(_selectedIds.length),
            style: theme.textTheme.bodyMedium,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _selectedIds.isEmpty ? null : _batchExportSelected,
            icon: const Icon(Icons.download_outlined),
            label: Text(AppLocalizations.of(context)!.tsmBatchExportButton),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _selectedIds.isEmpty ? null : _confirmDeleteSelected,
            icon: const Icon(Icons.delete_outline),
            label: Text(AppLocalizations.of(context)!.tsmDeleteSelectedButton),
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
          AppLocalizations.of(context)!.tsmEmptyState,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<AiSession> sessions) {
    final canReorder =
        _sortMode == _SortMode.manual &&
        _searchQuery.trim().isEmpty &&
        _templateFilter.isEmpty;
    final exitMotion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.listItem,
    );

    Widget rowFor(int index) {
      final session = sessions[index];
      final flag = _flags[session.id];
      final isAnimatingOut = _animatingOutIds.contains(session.id);
      final row = _SessionRow(
        key: ValueKey<String>(session.id),
        index: index,
        session: session,
        isSelectionMode: _isSelectionMode,
        isSelected: _selectedIds.contains(session.id),
        isPinned: flag?.pinned ?? false,
        isArchived: flag?.archived ?? false,
        isPreviewing: _previewSession?.id == session.id,
        denseMode: _denseMode,
        showDragHandle: canReorder,
        diskBytes: _diskBytes[session.id],
        formatDateTime: _formatDateTime,
        formatBytes: formatByteSize,
        estimateBytes: _estimateBytes,
        onTap: _isSelectionMode ? null : () => _openPreview(session),
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
      // Wrap each row so deletion plays a smooth collapse + fade before
      // the controller's notifyListeners actually removes the entry from
      // the list. The wrapper itself keeps a stable key so its state
      // survives upstream rebuilds.
      return KeyedSubtree(
        key: ValueKey<String>('row-wrapper-${session.id}'),
        child: AnimatedSize(
          duration: exitMotion.exitDuration,
          curve: exitMotion.curve.reverseCurve,
          alignment: Alignment.topCenter,
          child: AnimatedOpacity(
            duration: exitMotion.exitDuration,
            curve: exitMotion.curve.reverseCurve,
            opacity: isAnimatingOut ? 0.0 : 1.0,
            child: isAnimatingOut
                ? const SizedBox(width: double.infinity, height: 0)
                : row,
          ),
        ),
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
      proxyDecorator: (child, index, animation) {
        // The default proxy wraps the row in a square Material whose
        // bounds extend past our rounded Card border, leaving an ugly
        // rectangular halo while dragging. Override with a transparent
        // Material so only the Card's own rounded shape is visible.
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final lerp = Curves.easeInOut.transform(animation.value);
            return Material(
              type: MaterialType.transparency,
              child: Transform.scale(scale: 1 + 0.02 * lerp, child: child),
            );
          },
          child: child,
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(context).pop(),
            label: AppLocalizations.of(context)!.tsmClose,
          ),
        ],
      ),
    );
  }
}

enum _SessionRowAction { preview, rename, pin, archive, export, delete }

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
    required this.onToggleSelect,
    required this.onDoubleTap,
    required this.onSecondaryTap,
    this.isPinned = false,
    this.isArchived = false,
    this.isPreviewing = false,
    this.onTap,
  });

  final int index;
  final AiSession session;
  final bool isSelectionMode;
  final bool isSelected;
  final bool denseMode;
  final bool showDragHandle;
  final int? diskBytes;
  final String Function(DateTime) formatDateTime;
  final String Function(int) formatBytes;
  final int Function(AiSession) estimateBytes;
  final ValueChanged<bool?> onToggleSelect;
  final void Function(Offset globalPosition) onDoubleTap;
  final void Function(Offset globalPosition) onSecondaryTap;
  final bool isPinned;
  final bool isArchived;
  final bool isPreviewing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final stats = session.statistics;
    final total = stats.totalMessageCount;
    String pct(int n) => total == 0 ? '0%' : '${(100 * n / total).round()}%';
    final tokenSummary = stats.totalTokens != null
        ? '${stats.totalTokens} '
              '(in ${stats.totalPromptTokens ?? 0} / out '
              '${stats.totalCompletionTokens ?? 0})'
        : l10n.tsmRowUnknown;
    final bytes = diskBytes ?? estimateBytes(session);
    final isApproxBytes = diskBytes == null;

    final card = Card(
      margin: EdgeInsets.symmetric(vertical: denseMode ? 2 : 4, horizontal: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isPreviewing
              ? theme.colorScheme.primary
              : (isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant),
          width: isPreviewing ? 1.4 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Opacity(
        opacity: isArchived ? 0.62 : 1.0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
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
                          if (isPinned) ...[
                            Icon(
                              Icons.push_pin,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (isArchived) ...[
                            Icon(
                              Icons.archive,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              session.title.isEmpty
                                  ? l10n.tsmUntitledThread
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
                            label: l10n.tsmRowCreated,
                            value: formatDateTime(session.createdAt),
                          ),
                          _MetaChip(
                            icon: Icons.update,
                            label: l10n.tsmRowUpdated,
                            value: formatDateTime(session.updatedAt),
                          ),
                          _MetaChip(
                            icon: Icons.storage_outlined,
                            label: l10n.tsmRowSize,
                            value: isApproxBytes
                                ? '~ ${formatBytes(bytes)}'
                                : formatBytes(bytes),
                          ),
                          _MetaChip(
                            icon: Icons.forum_outlined,
                            label: l10n.tsmRowMessages,
                            value: '$total',
                          ),
                          _MetaChip(
                            icon: Icons.bolt_outlined,
                            label: l10n.tsmRowToken,
                            value: tokenSummary,
                          ),
                        ],
                      ),
                      if (total > 0 && !denseMode) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${l10n.tsmRowByKind}: '
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
      ),
    );
    return HoverLift(child: card);
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
        Text(value, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
