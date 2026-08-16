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
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_inline_empty_state.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/reorder_proxy_decorator.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/text_clip.dart';
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
  bool _diskBytesRefreshPending = false;
  Future<void>? _diskBytesRefreshTask;

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
    _diskBytesRefreshPending = false;
    _persistDebounce.dispose();
    _searchController.dispose();
    _outcomeSuccessSignal.dispose();
    _outcomeErrorSignal.dispose();
    super.dispose();
  }

  Future<void> _refreshDiskBytes() {
    if (!mounted) return Future<void>.value();
    _diskBytesRefreshPending = true;
    final activeTask = _diskBytesRefreshTask;
    if (activeTask != null) return activeTask;
    late final Future<void> task;
    task = _drainDiskBytesRefreshRequests().whenComplete(() {
      if (identical(_diskBytesRefreshTask, task)) {
        _diskBytesRefreshTask = null;
      }
    });
    _diskBytesRefreshTask = task;
    return task;
  }

  Future<void> _drainDiskBytesRefreshRequests() async {
    while (mounted && _diskBytesRefreshPending) {
      _diskBytesRefreshPending = false;
      try {
        final controller = context.read<AiSessionController>();
        final bytes = await controller.store.computeAllSessionDiskBytes();
        if (!mounted) return;
        if (_diskBytesRefreshPending) continue;
        setState(() => _diskBytes = bytes);
      } catch (error, stack) {
        silentLog(
          'thread_session_management_dialog',
          '统计全部会话磁盘占用',
          error,
          stack,
        );
      }
    }
  }

  Future<void> _refreshFlags() async {
    final generation = ++_flagsRefreshGeneration;
    final showArchived = _showArchived;
    try {
      final controller = context.read<AiSessionController>();
      final flags = await controller.store.loadSessionFlags();
      // 开启“显示已归档”时额外加载归档会话，并合入可见列表。
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


  /// 根据内存中的会话统计估算磁盘占用，避免大量会话时同步访问文件系统。
  /// 中英文混合内容按每字符约 2 字节估算。
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

  // 会话操作。
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
    await awaitOpenHandListRemoval(context);
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
      // 从本地排序层立即移除已删除行，不等待控制器监听回调。
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
    // 行数变化后重新统计磁盘占用。
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
    // 绑定为 final：可空局部变量的类型提升不会延续到下面的闭包里。
    final session = full;
    final config = await showAiSessionExportConfigDialog(
      context: context,
      totalMessages: session.messages.length,
    );
    if (config == null || !mounted) return;
    const typeGroup = XTypeGroup(label: 'JSONL', extensions: <String>['jsonl']);
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: jsonlExportPickerSuggestedName(
          buildJsonlExportFilename(title: session.title, sessionId: session.id),
        ),
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog('thread_session_management_dialog', '导出：选择保存位置', error, stack);
    }
    if (location == null || !mounted) return;
    final destinationPath = normalizeJsonlExportPath(location.path);
    final result = await runWithExportProgressDialog(
      context: context,
      title: AppLocalizations.of(context)!.tsmExportSessionDataTitle,
      subtitle: AppLocalizations.of(
        context,
      )!.tsmExportingSession(session.title),
      cancelLabel: AppLocalizations.of(context)!.tsmCancel,
      logTag: 'thread_session_management_dialog',
      logAction: '关闭导出进度弹窗',
      run: (cancelToken, progressController) => _runBoundedExport(
        logAction: '执行会话导出',
        cancelToken: cancelToken,
        export: () => exportAiSessionToJsonl(
          session: session,
          destinationPath: destinationPath,
          cancelToken: cancelToken,
          config: config,
          onProgress: progressController.updateProgress,
        ),
      ),
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

  /// 导出统一走超时与失败兜底：此前批量循环里每一项都是无限等待，一次卡住
  /// 的写入会把整批钉死，用户只剩强退这一条路。
  Future<ExportResult> _runBoundedExport({
    required String logAction,
    required ExportCancelToken cancelToken,
    required Future<ExportResult> Function() export,
  }) async {
    try {
      return await export().timeout(
        kOpenHandExportTimeout,
        onTimeout: () {
          cancelToken.cancel();
          return const ExportResult(kind: ExportResultKind.failure);
        },
      );
    } catch (error, stack) {
      silentLog('thread_session_management_dialog', logAction, error, stack);
      return ExportResult(kind: ExportResultKind.failure, error: error);
    }
  }

  Future<void> _batchExportSelected() async {
    if (_selectedIds.isEmpty) return;
    final ids = List<String>.from(_selectedIds);
    final controller = context.read<AiSessionController>();
    // 只选择一次目标目录，再逐个写入会话。
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
      // 各会话消息数不同，此处仅使用配置中的筛选选项。
      totalMessages: 0,
      allowRange: false,
    );
    if (config == null || !mounted) return;
    var ok = 0;
    var failed = 0;
    await runWithExportProgressDialog<void>(
      context: context,
      title: AppLocalizations.of(context)!.tsmBatchExportTitle,
      subtitle: AppLocalizations.of(
        context,
      )!.tsmBatchExportSubtitle(ids.length),
      cancelLabel: AppLocalizations.of(context)!.tsmCancel,
      logTag: 'thread_session_management_dialog',
      logAction: '关闭批量导出进度弹窗',
      run: (cancelToken, progressController) async {
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
          // 绑定为 final：可空局部变量的类型提升不会延续到下面的闭包里。
          final session = full;
          final fileName = buildJsonlExportFilename(
            title: session.title,
            sessionId: session.id,
          );
          final destPath = '$folderPath/$fileName';
          final result = await _runBoundedExport(
            logAction: '执行批量导出',
            cancelToken: cancelToken,
            export: () => exportAiSessionToJsonl(
              session: session,
              destinationPath: destPath,
              cancelToken: cancelToken,
              config: config,
            ),
          );
          if (result.kind == ExportResultKind.success) {
            ok++;
          } else {
            failed++;
          }
        }
      },
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
      // 置顶会刷新控制器顺序，清除本地排序层以便下次构建同步最新顺序。
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
    // 仅展示最后 6 条消息，保持抽屉紧凑。
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
                      kOpenHandGap4,
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
                  ? OpenHandInlineEmptyState(message: l10n.tsmNoMessages)
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: tail.length,
                      separatorBuilder: (_, _) => kOpenHandGap8,
                      itemBuilder: (context, index) {
                        final m = tail[index];
                        final preview = clipTextByCodeUnits(
                          m.content,
                          320,
                          suffix: '…',
                        );
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(kOpenHandRadius8),
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
                              kOpenHandGap4,
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

  // 构建界面。
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AiSessionController>();
    final upstream = controller.sessions;
    // 控制器列表与侧栏一致，不含归档会话；仅在开启显示时本地合并归档项。
    final List<AiSession> upstreamMerged = _showArchived
        ? <AiSession>[
            ...upstream,
            for (final s in _archivedSessions)
              if (!upstream.any((u) => u.id == s.id)) s,
          ]
        : upstream;
    // 首次构建或外部增删后，以控制器顺序初始化并同步本地排序层。
    if (_localOrder == null) {
      _localOrder = List<AiSession>.from(upstreamMerged);
    } else {
      // 保留仍存在会话的手动顺序，并将新会话置顶，避免拖拽期间跳动。
      final knownIds = _localOrder!.map((s) => s.id).toSet();
      final upstreamById = <String, AiSession>{
        for (final s in upstreamMerged) s.id: s,
      };
      // 刷新已知会话，及时同步重命名等变更。
      final preserved = <AiSession>[];
      for (final s in _localOrder!) {
        final fresh = upstreamById[s.id];
        if (fresh != null) preserved.add(fresh);
      }
      // 将本地顺序中尚不存在的新会话置顶。
      final additions = upstreamMerged
          .where((s) => !knownIds.contains(s.id))
          .toList(growable: false);
      _localOrder = <AiSession>[...additions, ...preserved];
    }
    final sessions = _localOrder!;
    // 应用搜索、模板筛选和排序；拖拽仍基于原始手动顺序计算下标。
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
        // 手动顺序无需额外排序。
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
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightFull,
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
                          ? const SizedBox.shrink()
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
              kOpenHandHGap12,
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
              kOpenHandHGap8,
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
            kOpenHandGap6,
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
                kOpenHandGap4,
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
          kOpenHandHGap6,
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
          kOpenHandHGap6,
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
          kOpenHandHGap8,
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
    return OpenHandInlineEmptyState(
      message: AppLocalizations.of(context)!.tsmEmptyState,
    );
  }

  Widget _buildList(List<AiSession> sessions) {
    final canReorder =
        _sortMode == _SortMode.manual &&
        _searchQuery.trim().isEmpty &&
        _templateFilter.isEmpty;

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
        formatDateTime: (dt) => formatYearMonthDayHmLocal(dt),
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
      // 数据删除前先播放收起与淡出动画，稳定键确保重建时保留行状态。
      return KeyedSubtree(
        key: ValueKey<String>('row-wrapper-${session.id}'),
        child: OpenHandListRemovalTransition(
          collapsed: isAnimatingOut,
          child: row,
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
      proxyDecorator: (child, index, animation) =>
          buildOpenHandReorderProxy(context, child, animation),
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
        borderRadius: BorderRadius.circular(kOpenHandRadius10),
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
                            kOpenHandHGap4,
                          ],
                          if (isArchived) ...[
                            Icon(
                              Icons.archive,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            kOpenHandHGap4,
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
                          kOpenHandHGap8,
                          Text(
                            session.templateName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      kOpenHandGap6,
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
                        kOpenHandGap4,
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
        kOpenHandHGap4,
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
