part of '../openhand_home_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// _FileMutationRow — shows file-change indicator for write/edit/multiedit tools
// ─────────────────────────────────────────────────────────────────────────────

String _fileMutationKind(AiSessionMessage message) =>
    '${message.metadata['file_mutation_kind'] ?? ''}'.trim();

const int _kFileMutationUndoConcurrency = 4;
const int _kFileMutationDiffReadMaxBytes = 16 * kBytesPerMiB;
const Color _kFileMutationAddedColor = Color(0xFF2E7D32);
const Color _kFileMutationAdditionAccent = Color(0xFF35D782);
const Color _kFileMutationDeletionAccent = Color(0xFFFF5C5C);
const double _kFileMutationLineDeltaGap = 4;
const Duration _kFileMutationOverlaySwitchDuration = kOpenHandMotion220;
const Duration _kFileMutationRowStateDuration = kOpenHandMotion220;
const Duration _kFileMutationRowSlideDuration = kOpenHandMotion320;
const Duration _kFileMutationRowChevronDuration = kOpenHandMotion180;

/// 需要用户读完再消失的提示（跳转降级、保存失败），比默认信息提示久一点。
const Duration _kFileMutationNoticeSnackDuration = Duration(milliseconds: 2800);

/// 按消息对象缓存的文件变动路径列表。消息不可变，一次解析终身有效。
final Expando<List<String>> _fileMutationPathsCache =
    Expando<List<String>>('_fileMutationPaths');

/// 聚合「单文件 (`file_mutation_path`)」与「多文件
/// (`file_mutation_paths`)」两路 metadata，去重后按出现顺序返回。
List<String> _fileMutationPaths(AiSessionMessage message) {
  final cached = _fileMutationPathsCache[message];
  if (cached != null) return cached;
  final out = <String>[];
  final seen = <String>{};
  void add(String? raw) {
    if (raw == null) return;
    final t = raw.trim();
    if (t.isEmpty) return;
    if (seen.add(t)) out.add(t);
  }

  add(message.metadata['file_mutation_path'] as String?);
  final multi = message.metadata['file_mutation_paths'];
  if (multi is List) {
    for (final p in multi) {
      if (p is String) add(p);
    }
  }
  _fileMutationPathsCache[message] = out;
  return out;
}

FileMutationLineDelta _sumFileMutationLineDeltas(
  Iterable<FileMutationView> views,
) {
  var added = 0;
  var removed = 0;
  var available = false;
  for (final view in views) {
    final delta = view.lineDelta;
    if (!delta.available) continue;
    available = true;
    added += delta.addedLines;
    removed += delta.removedLines;
  }
  return available
      ? FileMutationLineDelta(
          addedLines: added,
          removedLines: removed,
          available: true,
        )
      : const FileMutationLineDelta.unavailable();
}

/// Codex 风「文件变动」卡片：聚合本工具调用产生的全部 ledger 记录，
/// 提供多文件列表 + 内联 diff + 单条/全部撤销/重做按钮。
///
/// - 撤销 X 时同文件后续记录 (Y/Z) 自动级联失效 → 显示「已被级联撤销」。
/// - 单条「重做」仅恢复自身 after 内容；级联失效条目走「重做」按钮单独
///   恢复，行为与 ledger 语义对齐。
/// - 内联 diff 默认折叠，点击行展开；双击行回退到旧的 [_FileDiffDialog]
///   全屏对比 (兼容历史无 ledger 的会话)。
/// - 全程使用 M3 expressive 配色；动画走共享 motion preference 降级。
class _FileMutationCard extends StatefulWidget {
  const _FileMutationCard({super.key, required this.message});

  final AiSessionMessage message;

  @override
  State<_FileMutationCard> createState() => _FileMutationCardState();

  /// Shorten an absolute path to the last 3 segments for readability.
  static String _shortenFilePath(String filePath) {
    if (filePath.isEmpty) return filePath;
    final normalised = filePath.replaceAll('\\', '/');
    final parts = normalised.split('/');
    if (parts.length <= 3) return normalised;
    return '.../${parts.sublist(parts.length - 3).join('/')}';
  }
}

class _FileMutationCardState extends State<_FileMutationCard> {
  static const int _kExpansionStateCacheLimit = 500;
  static final Map<String, Set<String>> _expandedRecordIdsByScope =
      <String, Set<String>>{};

  Set<String> _expandedRecordIds = <String>{};
  final Set<String> _busyRecordIds = <String>{};
  final ValueNotifier<int> _pulseSignal = ValueNotifier<int>(0);
  Future<List<FileMutationView>>? _viewsFuture;
  String? _lastSessionId;
  String? _lastToolCallId;
  String? _expansionScopeKey;
  // 批量「全部撤销」并发执行 + 进度提示。
  int _bulkUndoTotal = 0;
  int _bulkUndoDone = 0;
  bool get _bulkUndoBusy => _bulkUndoTotal > 0;

  // view 超过 _kInitialReveal 条时先只渲染前 _kInitialReveal 条，后续点
  // 「展开剩余 N 条」再按 _kRevealStep 递增。避免一次构造上百个
  // _FileMutationCardRow（每个都含可能巨大的 _InlineDiffPanel build closure）。
  static const int _kInitialReveal = 10;
  static const int _kRevealStep = 30;
  int _revealedCount = _kInitialReveal;

  @override
  void dispose() {
    _rememberExpansionState();
    _pulseSignal.dispose();
    super.dispose();
  }

  String get _toolCallId =>
      '${widget.message.metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'.trim();

  AiSessionController _ctrl(BuildContext ctx) =>
      ctx.read<AiSessionController>();

  Future<List<FileMutationView>> _loadViews() async {
    final ctrl = _ctrl(context);
    final sessionId = ctrl.currentSession?.id ?? '';
    final toolCallId = _toolCallId;
    _lastSessionId = sessionId;
    _lastToolCallId = toolCallId;
    if (sessionId.isEmpty || toolCallId.isEmpty) {
      return const <FileMutationView>[];
    }
    return ctrl.toolRuntimeService.mutationLedger.viewsForToolCall(
      sessionId: sessionId,
      toolCallId: toolCallId,
    );
  }

  String _buildExpansionScopeKey({
    required String sessionId,
    required String toolCallId,
  }) {
    final scopedSessionId = sessionId.trim().isEmpty ? '_' : sessionId.trim();
    final scopedToolCallId = toolCallId.trim().isEmpty
        ? widget.message.id
        : toolCallId.trim();
    return '$scopedSessionId::$scopedToolCallId::${widget.message.id}';
  }

  void _bindExpansionScope({
    required String sessionId,
    required String toolCallId,
  }) {
    final nextKey = _buildExpansionScopeKey(
      sessionId: sessionId,
      toolCallId: toolCallId,
    );
    if (_expansionScopeKey == nextKey) return;
    _rememberExpansionState();
    _expansionScopeKey = nextKey;
    final cached = _expandedRecordIdsByScope[nextKey];
    _expandedRecordIds = cached == null ? <String>{} : Set<String>.from(cached);
  }

  void _rememberExpansionState() {
    final key = _expansionScopeKey;
    if (key == null || key.isEmpty) return;
    _expandedRecordIdsByScope.remove(key);
    if (_expandedRecordIds.isNotEmpty) {
      _expandedRecordIdsByScope[key] = Set<String>.unmodifiable(
        _expandedRecordIds,
      );
    }
    while (_expandedRecordIdsByScope.length > _kExpansionStateCacheLimit) {
      _expandedRecordIdsByScope.remove(_expandedRecordIdsByScope.keys.first);
    }
  }

  void _ensureFutureBound() {
    final ctrl = _ctrl(context);
    final sessionId = ctrl.currentSession?.id ?? '';
    final toolCallId = _toolCallId;
    _bindExpansionScope(sessionId: sessionId, toolCallId: toolCallId);
    if (_viewsFuture == null ||
        sessionId != _lastSessionId ||
        toolCallId != _lastToolCallId) {
      _viewsFuture = _loadViews();
    }
  }

  void _refresh() {
    setState(() {
      _viewsFuture = _loadViews();
    });
  }

  Future<void> _undo(FileMutationView view) async {
    if (_busyRecordIds.contains(view.record.recordId)) return;
    setState(() => _busyRecordIds.add(view.record.recordId));
    try {
      final ledger = _ctrl(context).toolRuntimeService.mutationLedger;
      final r = await ledger.undoRecord(
        sessionId: view.record.sessionId,
        recordId: view.record.recordId,
      );
      if (!mounted) return;
      if (!r.success) {
        showOpenHandErrorSnack(
          context,
          r.errorMessage.isNotEmpty
              ? r.errorMessage
              : AppLocalizations.of(context)!.fileMutationUndoFailed,
        );
      } else {
        _pulseSignal.value += 1;
      }
    } finally {
      if (mounted) {
        setState(() => _busyRecordIds.remove(view.record.recordId));
        _refresh();
      }
    }
  }

  Future<void> _redo(FileMutationView view) async {
    if (_busyRecordIds.contains(view.record.recordId)) return;
    setState(() => _busyRecordIds.add(view.record.recordId));
    try {
      final ledger = _ctrl(context).toolRuntimeService.mutationLedger;
      final r = await ledger.redoRecord(
        sessionId: view.record.sessionId,
        recordId: view.record.recordId,
      );
      if (!mounted) return;
      if (!r.success) {
        showOpenHandErrorSnack(
          context,
          r.errorMessage.isNotEmpty
              ? r.errorMessage
              : AppLocalizations.of(context)!.fileMutationRedoFailed,
        );
      } else {
        _pulseSignal.value += 1;
      }
    } finally {
      if (mounted) {
        setState(() => _busyRecordIds.remove(view.record.recordId));
        _refresh();
      }
    }
  }

  /// 「全部撤销」并发执行 + 进度提示。
  /// - 按 `record.filePath` 分组，**同一文件内严格串行**（避免互相
  ///   覆盖 / 竞争同一份磁盘内容）；
  /// - **跨文件最多 4 路并行**；
  /// - header 实时显示「N/M」进度环；
  /// - 完成后单次 `_refresh()` + 一次 highlight pulse；
  /// - 任意失败 SnackBar 摘要最后一个 error。
  Future<void> _undoAll(List<FileMutationView> views) async {
    if (_bulkUndoBusy) return;
    final candidates = views.where((v) => v.canUndo).toList(growable: false);
    if (candidates.isEmpty) return;
    // 同一文件按时间倒序撤销，避免先撤旧记录导致后续记录失效。
    final groups = <String, List<FileMutationView>>{};
    for (final v in candidates) {
      groups.putIfAbsent(v.record.filePath, () => <FileMutationView>[]).add(v);
    }
    for (final group in groups.values) {
      group.sort(
        (left, right) =>
            right.record.createdAt.compareTo(left.record.createdAt),
      );
    }
    setState(() {
      _bulkUndoTotal = candidates.length;
      _bulkUndoDone = 0;
    });
    final ledger = _ctrl(context).toolRuntimeService.mutationLedger;
    final paths = groups.keys.toList();
    int success = 0;
    int failure = 0;
    String? lastError;

    await forEachIndexWithConcurrencyLimit(
      itemCount: paths.length,
      maxConcurrency: _kFileMutationUndoConcurrency,
      shouldContinue: () => mounted,
      task: (index) async {
        final groupViews = groups[paths[index]]!;
        // 同文件内：串行撤销，避免并发覆写。
        for (final v in groupViews) {
          if (!mounted) return;
          try {
            final r = await ledger.undoRecord(
              sessionId: v.record.sessionId,
              recordId: v.record.recordId,
            );
            if (r.success) {
              success++;
            } else {
              failure++;
              if (r.errorMessage.isNotEmpty) lastError = r.errorMessage;
            }
          } catch (e, stack) {
            failure++;
            lastError = e.toString();
            // 统一走 silentLog：snackbar 只显示最后一条 message，原始 stack 不能丢。
            silentLog('file_mutation_card', '批量撤销文件变更', e, stack);
          } finally {
            if (mounted) setState(() => _bulkUndoDone++);
          }
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _bulkUndoTotal = 0;
      _bulkUndoDone = 0;
    });
    if (success > 0) _pulseSignal.value += 1;
    _refresh();
    if (failure > 0) {
      final l10n = AppLocalizations.of(context)!;
      showOpenHandErrorSnack(
        context,
        lastError != null && lastError!.isNotEmpty
            ? '${l10n.fileMutationUndoFailed} ($failure): $lastError'
            : '${l10n.fileMutationUndoFailed} ($failure)',
      );
    }
  }

  /// 聚合当前 toolCall 涉及的所有 view 的 before/after 内容，
  /// 拼成 `# <path>\n```diff\n<unified diff>\n```` 的合并 markdown 写入剪贴板。
  /// 任意 blob 读取失败的条目以 `<missing>` 占位，保持其它项可用。
  Future<void> _copyAllDiff(List<FileMutationView> views) async {
    if (views.isEmpty) return;
    final ledger = _ctrl(context).toolRuntimeService.mutationLedger;
    // 尊重 LedgerConfig.miniDiffMaxBytes——超过阈值时
    // 复制出去的合并 diff 也走 mini-diff（仅 +/- 行），避免大文件
    // 把剪贴板/聊天上下文撑爆。
    final config = await ledger.loadConfig();
    final buf = StringBuffer();
    for (final v in views) {
      final r = v.record;
      buf.writeln('# ${r.filePath}');
      buf.writeln('```diff');
      final snapshots = await ledger.readSnapshots(r);
      if (_mutationSnapshotsIncomplete(r, snapshots)) {
        buf.writeln('<snapshot unavailable>');
      } else {
        buf.writeln(
          unifiedDiffLineSummary(
            snapshots.before ?? '',
            snapshots.after ?? '',
            beforeSha: r.beforeSha,
            afterSha: r.afterSha,
            miniDiffMaxBytes: config.miniDiffMaxBytes,
          ),
        );
      }
      buf.writeln('```');
      buf.writeln();
    }
    if (!mounted) return;
    await copyOpenHandTextToClipboard(
      logTag: 'home',
      context: context,
      text: buf.toString(),
      logAction: '复制全部文件变更差异',
      successMessage: AppLocalizations.of(context)!.fileMutationCopyAllDiffDone,
    );
  }

  /// 把当前会话的 `sessions/<id>/ledger.jsonl` 在系统文件管理器
  /// 里高亮（macOS `open -R` / Windows `explorer.exe /select,` /
  /// Linux 退化到打开父目录）。文件不存在时退化到打开 ledger 根目录。
  Future<void> _revealLedgerFile() async {
    final ctrl = _ctrl(context);
    final sessionId = ctrl.currentSession?.id ?? '';
    if (sessionId.isEmpty) return;
    final ledger = ctrl.toolRuntimeService.mutationLedger;
    final file = ledger.ledgerFileFor(sessionId);
    final target = await isRegularFilePath(file.path, followLinks: true)
        ? file.path
        : file.parent.path;
    try {
      await revealLocalPathInSystemFileManager(
        target,
        tag: 'file_mutation_card.reveal',
      );
    } catch (error, stack) {
      silentLog('file_mutation_card', '定位变更账本文件', error, stack);
    }
  }

  /// 当前会话维度的 History Inspector dialog。展示该 session
  /// 下 ledger.jsonl 的全部记录（不局限于当前 toolCall），按 filePath 分
  /// 组并按 createdAt 倒序展示。复用现有 row 视觉，但不带 undo/redo 按钮
  /// （只读概览，避免误操作）。
  Future<void> _openHistoryInspector() async {
    final ctrl = _ctrl(context);
    final sessionId = ctrl.currentSession?.id ?? '';
    if (sessionId.isEmpty) return;
    final ledger = ctrl.toolRuntimeService.mutationLedger;
    if (!mounted) return;
    showAnimatedDialog(
      context: context,
      builder: (ctx) => _FileMutationHistoryInspectorDialog(
        sessionId: sessionId,
        ledger: ledger,
      ),
    );
  }

  void _toggleExpand(String recordId) {
    _markToolCardInteractiveTap(context);
    setState(() {
      if (!_expandedRecordIds.add(recordId)) {
        _expandedRecordIds.remove(recordId);
      }
    });
    _rememberExpansionState();
  }

  @override
  Widget build(BuildContext context) {
    _ensureFutureBound();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fallbackPaths = _fileMutationPaths(widget.message);

    return FutureBuilder<List<FileMutationView>>(
      future: _viewsFuture,
      builder: (ctx, snap) {
        final views = snap.data ?? const <FileMutationView>[];
        // 退化路径：ledger 还没 ready 或会话外的历史记录 → 用 metadata 路径
        // 渲染只读多文件行（保留点击查看 diff 对话框的能力）。
        if (views.isEmpty) {
          if (fallbackPaths.isEmpty) return const SizedBox.shrink();
          // FileMutationCard 走 AppearOnce 入场（fade + 12px 上滑）。
          // AppearOnce 自身在 reduceMotion 时退化为零时长，无需额外 gate。
          return AppearOnce(
            child: _buildLegacyMultiPath(theme, cs, fallbackPaths),
          );
        }
        return AppearOnce(child: _buildLedgerCard(theme, cs, views));
      },
    );
  }

  Widget _buildLegacyMultiPath(
    ThemeData theme,
    ColorScheme cs,
    List<String> paths,
  ) {
    final mutKind = _fileMutationKind(widget.message);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.78),
        borderRadius: kOpenHandBorderRadius16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.difference_rounded,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
              kOpenHandHGap6,
              Text(
                AppLocalizations.of(
                  context,
                )!.fileMutationFilesChanged(paths.length),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          for (final p in paths)
            InkWell(
              borderRadius: kOpenHandBorderRadius12,
              onTap: () => _showLegacyDiff(p, mutKind),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.insert_drive_file_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    kOpenHandHGap6,
                    Expanded(
                      child: Text(
                        _FileMutationCard._shortenFilePath(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLedgerCard(
    ThemeData theme,
    ColorScheme cs,
    List<FileMutationView> views,
  ) {
    final totalLineDelta = _sumFileMutationLineDeltas(views);
    final anyUndoable = views.any((v) => v.canUndo);
    final anyRedoable = views.any((v) => v.canRedo);
    // 卡内 Cmd/Ctrl+Z 撤销最近一条、Shift+Cmd/Ctrl+Z 重做。
    // 仅当卡片或其子节点持有焦点时生效，避免与全局快捷键冲突。
    FileMutationView? lastUndoable;
    FileMutationView? lastRedoable;
    for (final v in views) {
      if (v.canUndo) lastUndoable = v;
      if (v.canRedo) lastRedoable = v;
    }
    return FocusableActionDetector(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            const _UndoLastIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            const _UndoLastIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            const _RedoLastIntent(),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): const _RedoLastIntent(),
      },
      actions: <Type, Action<Intent>>{
        _UndoLastIntent: CallbackAction<_UndoLastIntent>(
          onInvoke: (_) {
            final v = lastUndoable;
            if (v != null) _undo(v);
            return null;
          },
        ),
        _RedoLastIntent: CallbackAction<_RedoLastIntent>(
          onInvoke: (_) {
            final v = lastRedoable;
            if (v != null) _redo(v);
            return null;
          },
        ),
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow.withValues(alpha: 0.85),
              borderRadius: kOpenHandBorderRadius16,
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.55),
                width: 0.6,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Tooltip(
                  message: AppLocalizations.of(
                    context,
                  )!.fileMutationRevealLedger,
                  waitDuration: kOpenHandTooltipWait,
                  child: InkWell(
                    onTap: () {
                      _markToolCardInteractiveTap(context);
                      unawaited(_revealLedgerFile());
                    },
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(kOpenHandRadius16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.difference_rounded,
                            size: 16,
                            color: cs.primary,
                          ),
                          kOpenHandHGap8,
                          Text(
                            AppLocalizations.of(context)!.fileMutationSection,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          kOpenHandHGap8,
                          _StatPill(
                            label: AppLocalizations.of(
                              context,
                            )!.fileMutationFilesCount(views.length),
                            color: cs.onSurfaceVariant,
                            bg: cs.surfaceContainerHighest.withValues(
                              alpha: 0.65,
                            ),
                          ),
                          if (totalLineDelta.available &&
                              totalLineDelta.hasChanges) ...[
                            kOpenHandHGap6,
                            _FileMutationLineDeltaBadge(delta: totalLineDelta),
                          ],
                          // 批量撤销进度 chip：宽度随动效增减，否则忙碌一
                          // 翻转，这一行右侧的按钮会整体平移一次。
                          OpenHandInlineRevealSwitcher(
                            presentKey: const ValueKey<String>('bulk-undo'),
                            child: _bulkUndoBusy
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      kOpenHandHGap8,
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.6,
                                          value: _bulkUndoTotal == 0
                                              ? null
                                              : unitRatio(
                                                  _bulkUndoDone,
                                                  _bulkUndoTotal,
                                                ),
                                        ),
                                      ),
                                      kOpenHandHGap6,
                                      Text(
                                        '$_bulkUndoDone/$_bulkUndoTotal',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                          const Spacer(),
                          if (anyUndoable && !_bulkUndoBusy)
                            _IconActionButton(
                              icon: Icons.undo_rounded,
                              tooltip: AppLocalizations.of(
                                context,
                              )!.fileMutationUndoAll,
                              onTap: () => _undoAll(views),
                            ),
                          if (anyRedoable)
                            _IconActionButton(
                              icon: Icons.refresh_rounded,
                              tooltip: AppLocalizations.of(
                                context,
                              )!.fileMutationRefresh,
                              onTap: _refresh,
                            ),
                          _IconActionButton(
                            icon: Icons.copy_all_rounded,
                            tooltip: AppLocalizations.of(
                              context,
                            )!.fileMutationCopyAllDiff,
                            onTap: () => _copyAllDiff(views),
                          ),
                          // 把当前会话所有 ledger 记录（含其他卡未展示的）
                          // 在 dialog 里按文件分组俯瞰，便于跨 toolCall 排查。
                          _IconActionButton(
                            icon: Icons.history_rounded,
                            tooltip: AppLocalizations.of(
                              context,
                            )!.fileMutationHistoryInspector,
                            onTap: () => _openHistoryInspector(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
                // 渐进式展开。views 多时只构造前 _revealedCount 条，
                // 余下用一行「展开剩余 N 条」按钮兜底，按需 +30 / 全展开。
                // 文件条目不做独立入场；跟随消息卡片一次性出现。
                for (int i = 0; i < views.length && i < _revealedCount; i++)
                  _FileMutationCardRow(
                    view: views[i],
                    expanded: _expandedRecordIds.contains(
                      views[i].record.recordId,
                    ),
                    busy: _busyRecordIds.contains(views[i].record.recordId),
                    onToggleExpand: () =>
                        _toggleExpand(views[i].record.recordId),
                    onUndo: () => _undo(views[i]),
                    onRedo: () => _redo(views[i]),
                    onOpenLegacyDialog: () => _showLegacyDiff(
                      views[i].record.filePath,
                      _fileMutationKind(widget.message),
                    ),
                    onCopyDiff: () => _copyAllDiff([views[i]]),
                    onOpenInspector: _openHistoryInspector,
                  ),
                if (views.length > _revealedCount)
                  _RevealMoreRow(
                    remaining: views.length - _revealedCount,
                    onRevealStep: () => setState(() {
                      _revealedCount = (_revealedCount + _kRevealStep).clamp(
                        0,
                        views.length,
                      );
                    }),
                    onRevealAll: () =>
                        setState(() => _revealedCount = views.length),
                  ),
              ],
            ),
          ),
          // 每次 undo/redo 成功在卡顶发一次温和的 highlight pulse；
          // HighlightPulse 自带 reduceMotion 守门，不需要我们再 gate。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(child: HighlightPulse(signal: _pulseSignal)),
          ),
          // 批量 undo 进行中——卡片整体覆 BackdropFilter blur 6px
          // + primary 色 tinted glow，进度环居中。AnimatedSwitcher 220ms 淡入
          // 淡出，reduceMotion 时退化为 0ms。
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_bulkUndoBusy,
              child: AnimatedSwitcher(
                duration: openHandMotionDuration(
                  context,
                  _kFileMutationOverlaySwitchDuration,
                ),
                child: _bulkUndoBusy
                    ? _BulkUndoOverlay(
                        key: const ValueKey('bulk-undo-overlay'),
                        done: _bulkUndoDone,
                        total: _bulkUndoTotal,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('bulk-undo-overlay-hidden'),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLegacyDiff(String path, String kind) {
    showAnimatedDialog(
      context: context,
      builder: (ctx) => _FileDiffDialog(filePath: path, changeKind: kind),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.color, required this.bg});
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: kOpenHandPillBorderRadius,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

enum _FileMutationLineDeltaStyle { pill, text }

class _FileMutationLineDeltaBadge extends StatelessWidget {
  const _FileMutationLineDeltaBadge({
    required this.delta,
    this.style = _FileMutationLineDeltaStyle.pill,
  });

  final FileMutationLineDelta delta;
  final _FileMutationLineDeltaStyle style;

  @override
  Widget build(BuildContext context) {
    if (!delta.available || !delta.hasChanges) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final children = <Widget>[
      if (delta.addedLines > 0)
        _piece(
          theme: theme,
          label: '+${delta.addedLines}',
          color: _kFileMutationAddedColor,
          background: _kFileMutationAddedColor.withValues(alpha: 0.12),
        ),
      if (delta.addedLines > 0 && delta.removedLines > 0)
        const SizedBox(width: _kFileMutationLineDeltaGap),
      if (delta.removedLines > 0)
        _piece(
          theme: theme,
          label: '-${delta.removedLines}',
          color: cs.error,
          background: cs.error.withValues(alpha: 0.12),
        ),
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _piece({
    required ThemeData theme,
    required String label,
    required Color color,
    required Color background,
  }) {
    final text = Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w600,
      ),
    );
    if (style == _FileMutationLineDeltaStyle.text) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: kOpenHandBorderRadius8,
      ),
      child: text,
    );
  }
}

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: kOpenHandPillBorderRadius,
        onTap: () {
          _markToolCardInteractiveTap(context);
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _FileMutationRevealPathButton extends StatelessWidget {
  const _FileMutationRevealPathButton({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: _fileMutationRevealPathLabel(context),
      waitDuration: kOpenHandTooltipWait,
      child: MicroPressFeedback(
        child: InkResponse(
          onTap: () {
            _markToolCardInteractiveTap(context);
            unawaited(_revealFileMutationPath(context, filePath));
          },
          radius: 18,
          containedInkWell: true,
          borderRadius: kOpenHandPillBorderRadius,
          child: SizedBox.square(
            dimension: 28,
            child: Icon(
              Icons.folder_open_outlined,
              size: 15,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _FileMutationCardRow extends StatelessWidget {
  const _FileMutationCardRow({
    required this.view,
    required this.expanded,
    required this.busy,
    required this.onToggleExpand,
    required this.onUndo,
    required this.onRedo,
    required this.onOpenLegacyDialog,
    required this.onCopyDiff,
    required this.onOpenInspector,
  });

  final FileMutationView view;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggleExpand;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onOpenLegacyDialog;
  final VoidCallback onCopyDiff;
  final VoidCallback onOpenInspector;

  IconData get _kindIcon {
    switch (view.record.kind) {
      case FileMutationKind.create:
        return Icons.add_circle_outline_rounded;
      case FileMutationKind.modify:
        return Icons.edit_outlined;
      case FileMutationKind.delete:
        return Icons.delete_outline_rounded;
    }
  }

  Color _kindColor(ColorScheme cs) {
    switch (view.record.kind) {
      case FileMutationKind.create:
        return _kFileMutationAddedColor;
      case FileMutationKind.modify:
        return cs.primary;
      case FileMutationKind.delete:
        return cs.error;
    }
  }

  /// 长按 / 右键弹出 ContextMenu，便利动作集中暴露：
  /// reveal in OS / copy path / copy diff / open inspector / jump-to-toolcall。
  Future<void> _showRowContextMenu(
    BuildContext context, {
    Offset? position,
  }) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = position ?? box?.localToGlobal(box.size.center(Offset.zero));
    final l10n = AppLocalizations.of(context)!;
    final selected = await showAnimatedPointerMenu<String>(
      context: context,
      globalPosition: origin,
      items: [
        PopupMenuItem<String>(
          value: 'reveal',
          child: Row(
            children: [
              const Icon(Icons.folder_open_outlined, size: 16),
              kOpenHandHGap8,
              Text(_fileMutationRevealPathLabel(context)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copyPath',
          child: Row(
            children: [
              const Icon(Icons.content_copy_rounded, size: 16),
              kOpenHandHGap8,
              Text(l10n.fileMutationCopyPath),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copyDiff',
          child: Row(
            children: [
              const Icon(Icons.difference_rounded, size: 16),
              kOpenHandHGap8,
              Text(l10n.fileMutationCopyAllDiff),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'inspector',
          child: Row(
            children: [
              const Icon(Icons.history_rounded, size: 16),
              kOpenHandHGap8,
              Text(l10n.fileMutationHistoryInspector),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'diff',
          child: Row(
            children: [
              const Icon(Icons.open_in_new_rounded, size: 16),
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '打开 diff 对话框',
                  en: 'Open diff dialog',
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (selected == null || !context.mounted) return;
    switch (selected) {
      case 'reveal':
        if (context.mounted) {
          unawaited(_revealFileMutationPath(context, view.record.filePath));
        }
      case 'copyPath':
        if (context.mounted) {
          _copyPathToClipboard(context, view.record.filePath);
        }
      case 'copyDiff':
        onCopyDiff();
      case 'inspector':
        onOpenInspector();
      case 'diff':
        onOpenLegacyDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final greyOut = view.isEffectivelyUndone;
    final rowStateDuration = openHandMotionDuration(
      context,
      _kFileMutationRowStateDuration,
    );
    final rowSlideDuration = openHandMotionDuration(
      context,
      _kFileMutationRowSlideDuration,
    );
    final chevronDuration = openHandMotionDuration(
      context,
      _kFileMutationRowChevronDuration,
    );
    return AnimatedContainer(
      duration: rowStateDuration,
      curve: kOpenHandSwitchInCurve,
      decoration: BoxDecoration(
        color: greyOut
            ? cs.surfaceContainerHighest.withValues(alpha: 0.32)
            : Colors.transparent,
      ),
      child: AnimatedSlide(
        duration: rowSlideDuration,
        curve: kOpenHandEntranceCurve,
        offset: Offset(view.cascadeUndone ? 0.025 : 0.0, 0.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 键盘导航——
            // - Up/Down 在 row 间走 Directional focus；
            // - Space 切换 expand；
            // - Enter 打开 legacy diff dialog。
            FocusableActionDetector(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.enter):
                    _OpenLegacyDialogIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter):
                    _OpenLegacyDialogIntent(),
                SingleActivator(LogicalKeyboardKey.arrowUp):
                    DirectionalFocusIntent(TraversalDirection.up),
                SingleActivator(LogicalKeyboardKey.arrowDown):
                    DirectionalFocusIntent(TraversalDirection.down),
              },
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    onToggleExpand();
                    return null;
                  },
                ),
                _OpenLegacyDialogIntent:
                    CallbackAction<_OpenLegacyDialogIntent>(
                      onInvoke: (_) {
                        onOpenLegacyDialog();
                        return null;
                      },
                    ),
              },
              child: InkWell(
                onTap: onToggleExpand,
                onDoubleTap: () {
                  _markToolCardInteractiveTap(context);
                  onOpenLegacyDialog();
                },
                onLongPress: () {
                  _markToolCardInteractiveTap(context);
                  unawaited(_showRowContextMenu(context));
                },
                onSecondaryTapDown: (d) {
                  _markToolCardInteractiveTap(context);
                  unawaited(
                    _showRowContextMenu(context, position: d.globalPosition),
                  );
                },
                // row hover 背景轻微高亮，让指针落点更清晰。
                hoverColor: cs.primary.withValues(alpha: 0.05),
                splashColor: cs.primary.withValues(alpha: 0.10),
                highlightColor: cs.primary.withValues(alpha: 0.06),
                focusColor: cs.primary.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Opacity(
                    opacity: greyOut ? 0.55 : 1.0,
                    child: Row(
                      children: [
                        AnimatedRotation(
                          duration: chevronDuration,
                          turns: expanded ? 0.25 : 0,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        kOpenHandHGap6,
                        Icon(_kindIcon, size: 14, color: _kindColor(cs)),
                        kOpenHandHGap6,
                        Expanded(
                          // hover 显示完整路径，右键 / Ctrl-长按复制路径。
                          child: Tooltip(
                            message: view.record.filePath,
                            waitDuration: kOpenHandTooltipWait,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onSecondaryTap: () {
                                _markToolCardInteractiveTap(context);
                                unawaited(
                                  _copyPathToClipboard(
                                    context,
                                    view.record.filePath,
                                  ),
                                );
                              },
                              onLongPress: () {
                                _markToolCardInteractiveTap(context);
                                unawaited(
                                  _copyPathToClipboard(
                                    context,
                                    view.record.filePath,
                                  ),
                                );
                              },
                              child: Text(
                                _FileMutationCard._shortenFilePath(
                                  view.record.filePath,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  color: cs.onSurface,
                                  decoration: greyOut
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                  decorationColor: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (view.directlyUndone && !view.cascadeUndone) ...[
                          kOpenHandHGap6,
                          _StatPill(
                            label: AppLocalizations.of(
                              context,
                            )!.fileMutationUndone,
                            color: cs.onSurfaceVariant,
                            bg: cs.surfaceContainerHighest.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ],
                        if (view.cascadeUndone) ...[
                          kOpenHandHGap6,
                          _StatPill(
                            label: AppLocalizations.of(
                              context,
                            )!.fileMutationCascadeUndone,
                            color: cs.tertiary,
                            bg: cs.tertiaryContainer.withValues(alpha: 0.55),
                          ),
                        ],
                        kOpenHandHGap8,
                        if (busy)
                          const OpenHandBusyStatusIcon(
                            busy: true,
                            icon: null,
                            size: 14,
                            strokeWidth: 1.6,
                          )
                        else if (view.canUndo)
                          _IconActionButton(
                            icon: Icons.undo_rounded,
                            tooltip: AppLocalizations.of(
                              context,
                            )!.fileMutationUndoThis,
                            onTap: onUndo,
                          )
                        else if (view.canRedo)
                          _IconActionButton(
                            icon: Icons.redo_rounded,
                            tooltip: AppLocalizations.of(
                              context,
                            )!.fileMutationRedo,
                            onTap: onRedo,
                          ),
                        kOpenHandHGap4,
                        _FileMutationRevealPathButton(
                          filePath: view.record.filePath,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: rowStateDuration,
              curve: kOpenHandSwitchInCurve,
              alignment: Alignment.topCenter,
              child: expanded
                  ? _InlineDiffPanel(view: view)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineDiffPanel extends StatefulWidget {
  const _InlineDiffPanel({required this.view});
  final FileMutationView view;

  @override
  State<_InlineDiffPanel> createState() => _InlineDiffPanelState();
}

class _InlineDiffPanelState extends State<_InlineDiffPanel> {
  Future<({String? before, String? after})>? _future;
  String? _key;

  String _keyOf(FileMutationView v) =>
      '${v.record.recordId}|${v.record.beforeSha ?? ''}|${v.record.afterSha ?? ''}';

  @override
  Widget build(BuildContext context) {
    final newKey = _keyOf(widget.view);
    if (_key != newKey) {
      _key = newKey;
      _future = _load(widget.view);
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: FutureBuilder<({String? before, String? after})>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            );
          }
          final snapshots = snap.data;
          if (snapshots == null ||
              _mutationSnapshotsIncomplete(widget.view.record, snapshots)) {
            return Text(
              AppLocalizations.of(context)!.fileMutationSnapshotUnavailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            );
          }
          final before = snapshots.before ?? '';
          final after = snapshots.after ?? '';
          if (before.isEmpty && after.isEmpty) {
            return Text(
              AppLocalizations.of(context)!.fileMutationSnapshotUnavailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            );
          }
          return _CodexDiffViewer(
            record: widget.view.record,
            before: before,
            after: after,
            previewLineLimit: 28,
          );
        },
      ),
    );
  }

  Future<({String? before, String? after})> _load(FileMutationView v) async {
    return _loadMutationDiffSnapshots(context, v.record);
  }
}

Future<({String? before, String? after})> _loadMutationDiffSnapshots(
  BuildContext context,
  FileMutationRecord record,
) async {
  final ledger = context
      .read<AiSessionController>()
      .toolRuntimeService
      .mutationLedger;
  return ledger.readSnapshots(record);
}

bool _mutationSnapshotsIncomplete(
  FileMutationRecord record,
  ({String? before, String? after}) snapshots,
) {
  return (record.beforeSha != null && snapshots.before == null) ||
      (record.afterSha != null && snapshots.after == null);
}

enum _CodexDiffLineKind { context, addition, deletion, folded }

class _CodexDiffPalette {
  const _CodexDiffPalette({
    required this.surface,
    required this.border,
    required this.separator,
    required this.text,
    required this.mutedText,
    required this.contextLineNumber,
    required this.additionBackground,
    required this.deletionBackground,
    required this.foldedBackground,
    required this.additionLineNumber,
    required this.deletionLineNumber,
    required this.foldedLineNumber,
    required this.additionFallbackText,
    required this.deletionFallbackText,
    required this.additionAccent,
    required this.deletionAccent,
    required this.footerSurface,
    required this.footerBorder,
    required this.footerForeground,
  });

  final Color surface;
  final Color border;
  final Color separator;
  final Color text;
  final Color mutedText;
  final Color contextLineNumber;
  final Color additionBackground;
  final Color deletionBackground;
  final Color foldedBackground;
  final Color additionLineNumber;
  final Color deletionLineNumber;
  final Color foldedLineNumber;
  final Color additionFallbackText;
  final Color deletionFallbackText;
  final Color additionAccent;
  final Color deletionAccent;
  final Color footerSurface;
  final Color footerBorder;
  final Color footerForeground;

  int get signature => Object.hash(
    surface,
    border,
    separator,
    text,
    mutedText,
    contextLineNumber,
    additionBackground,
    deletionBackground,
    foldedBackground,
    additionLineNumber,
    deletionLineNumber,
    foldedLineNumber,
    additionFallbackText,
    deletionFallbackText,
    additionAccent,
    deletionAccent,
    footerSurface,
    footerForeground,
  );

  static _CodexDiffPalette resolve(ThemeData theme) {
    final cs = theme.colorScheme;
    if (theme.brightness == Brightness.dark) {
      return const _CodexDiffPalette(
        surface: Color(0xFF151515),
        border: Color(0x14FFFFFF),
        separator: Color(0x0FFFFFFF),
        text: Color(0xFFE8E8E8),
        mutedText: Color(0xFFB9B9B9),
        contextLineNumber: Color(0xFF8E8F94),
        additionBackground: Color(0xFF183622),
        deletionBackground: Color(0xFF461D1D),
        foldedBackground: Color(0xFF202020),
        additionLineNumber: _kFileMutationAdditionAccent,
        deletionLineNumber: _kFileMutationDeletionAccent,
        foldedLineNumber: Color(0xFF9EA0A6),
        additionFallbackText: Color(0xFFE9F8ED),
        deletionFallbackText: Color(0xFFFFDEDE),
        additionAccent: _kFileMutationAdditionAccent,
        deletionAccent: _kFileMutationDeletionAccent,
        footerSurface: OpenHandConsolePalette.terminalSurfaceAlt,
        footerBorder: Color(0x12FFFFFF),
        footerForeground: Color(0xFFD7D7D7),
      );
    }
    const addition = Color(0xFF00A341);
    final deletion = cs.error;
    return _CodexDiffPalette(
      surface: cs.surface,
      border: cs.outlineVariant.withValues(alpha: 0.52),
      separator: cs.outlineVariant.withValues(alpha: 0.78),
      text: cs.onSurface,
      mutedText: cs.onSurfaceVariant,
      contextLineNumber: cs.onSurfaceVariant.withValues(alpha: 0.86),
      additionBackground: Color.alphaBlend(
        addition.withValues(alpha: 0.11),
        cs.surface,
      ),
      deletionBackground: Color.alphaBlend(
        deletion.withValues(alpha: 0.12),
        cs.surface,
      ),
      foldedBackground: Color.alphaBlend(
        cs.onSurface.withValues(alpha: 0.045),
        cs.surface,
      ),
      additionLineNumber: addition,
      deletionLineNumber: deletion,
      foldedLineNumber: cs.onSurfaceVariant,
      additionFallbackText: cs.onSurface,
      deletionFallbackText: cs.onSurface,
      additionAccent: addition,
      deletionAccent: deletion,
      footerSurface: Color.alphaBlend(
        cs.onSurface.withValues(alpha: 0.025),
        cs.surface,
      ),
      footerBorder: cs.outlineVariant.withValues(alpha: 0.58),
      footerForeground: cs.primary,
    );
  }
}

class _CodexDiffLine {
  const _CodexDiffLine({
    required this.kind,
    this.lineNumber,
    this.text = '',
    this.foldedCount = 0,
    this.foldedOldStart,
    this.foldedNewStart,
  });

  final _CodexDiffLineKind kind;
  final int? lineNumber;
  final String text;
  final int foldedCount;
  final int? foldedOldStart;
  final int? foldedNewStart;
}

class _CodexDiffViewer extends StatefulWidget {
  const _CodexDiffViewer({
    required this.record,
    required this.before,
    required this.after,
    this.previewLineLimit = 24,
  });

  final FileMutationRecord record;
  final String before;
  final String after;
  final int previewLineLimit;

  @override
  State<_CodexDiffViewer> createState() => _CodexDiffViewerState();
}

class _CodexDiffViewerState extends State<_CodexDiffViewer> {
  static const int _kExpandedStateCacheLimit = 500;
  static final Map<String, bool> _expandedByDiffKey = <String, bool>{};
  static final Map<String, Set<String>> _expandedFoldKeysByDiffKey =
      <String, Set<String>>{};

  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  String? _diffKey;
  List<_CodexDiffLine> _lines = const <_CodexDiffLine>[];
  Set<String> _expandedFoldKeys = <String>{};
  late bool _showFull;

  @override
  void initState() {
    super.initState();
    _rebuildDiffIfNeeded(force: true);
  }

  @override
  void didUpdateWidget(covariant _CodexDiffViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildDiffIfNeeded();
  }

  @override
  void dispose() {
    _rememberExpandedState();
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  String _buildDiffKey() {
    return [
      widget.record.recordId,
      widget.record.beforeSha ?? '_',
      widget.record.afterSha ?? '_',
      widget.before.length,
      widget.after.length,
      boundedTextFingerprint(widget.before),
      boundedTextFingerprint(widget.after),
    ].join('|');
  }

  void _rebuildDiffIfNeeded({bool force = false}) {
    final nextKey = _buildDiffKey();
    if (!force && _diffKey == nextKey) return;
    _rememberExpandedState();
    _diffKey = nextKey;
    _showFull = _expandedByDiffKey[nextKey] ?? false;
    _expandedFoldKeys = Set<String>.of(
      _expandedFoldKeysByDiffKey[nextKey] ?? const <String>{},
    );
    _lines = _codexDiffLinesFromUnifiedLines(
      unifiedDiffLinesFromText(widget.before, widget.after),
    );
  }

  void _rememberExpandedState() {
    final key = _diffKey;
    if (key == null || key.isEmpty) return;
    _expandedByDiffKey.remove(key);
    if (_showFull) {
      _expandedByDiffKey[key] = true;
    }
    _expandedFoldKeysByDiffKey.remove(key);
    if (_expandedFoldKeys.isNotEmpty) {
      _expandedFoldKeysByDiffKey[key] = Set<String>.unmodifiable(
        _expandedFoldKeys,
      );
    }
    while (_expandedByDiffKey.length > _kExpandedStateCacheLimit) {
      _expandedByDiffKey.remove(_expandedByDiffKey.keys.first);
    }
    while (_expandedFoldKeysByDiffKey.length > _kExpandedStateCacheLimit) {
      _expandedFoldKeysByDiffKey.remove(_expandedFoldKeysByDiffKey.keys.first);
    }
  }

  void _setShowFull(bool value) {
    if (_showFull == value) return;
    _markToolCardInteractiveTap(context);
    setState(() => _showFull = value);
    _rememberExpandedState();
  }

  void _toggleFold(_CodexDiffLine line) {
    final key = _foldKey(line);
    if (key == null) return;
    _markToolCardInteractiveTap(context);
    setState(() {
      if (!_expandedFoldKeys.remove(key)) {
        _expandedFoldKeys.add(key);
      }
    });
    _rememberExpandedState();
  }

  String? _foldKey(_CodexDiffLine line) {
    final oldStart = line.foldedOldStart;
    final newStart = line.foldedNewStart;
    if (oldStart == null || newStart == null || line.foldedCount <= 0) {
      return null;
    }
    return '$oldStart:$newStart:${line.foldedCount}';
  }

  List<_CodexDiffLine> _materializeFoldedLines() {
    if (_expandedFoldKeys.isEmpty) return _lines;
    final out = <_CodexDiffLine>[];
    final beforeLines = widget.before.isEmpty
        ? const <String>[]
        : const LineSplitter().convert(widget.before);
    final afterLines = widget.after.isEmpty
        ? const <String>[]
        : const LineSplitter().convert(widget.after);
    for (final line in _lines) {
      out.add(line);
      final key = _foldKey(line);
      if (key == null || !_expandedFoldKeys.contains(key)) continue;
      out.addAll(_expandedContextLines(line, beforeLines, afterLines));
    }
    return out;
  }

  Iterable<_CodexDiffLine> _expandedContextLines(
    _CodexDiffLine folded,
    List<String> beforeLines,
    List<String> afterLines,
  ) sync* {
    final lineNumberStart = folded.foldedNewStart ?? folded.foldedOldStart;
    if (lineNumberStart == null || folded.foldedCount <= 0) return;
    for (var offset = 0; offset < folded.foldedCount; offset++) {
      final afterIndex = folded.foldedNewStart == null
          ? -1
          : folded.foldedNewStart! - 1 + offset;
      final beforeIndex = folded.foldedOldStart == null
          ? -1
          : folded.foldedOldStart! - 1 + offset;
      final text = afterIndex >= 0 && afterIndex < afterLines.length
          ? afterLines[afterIndex]
          : (beforeIndex >= 0 && beforeIndex < beforeLines.length
                ? beforeLines[beforeIndex]
                : '');
      yield _CodexDiffLine(
        kind: _CodexDiffLineKind.context,
        lineNumber: lineNumberStart + offset,
        text: text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _CodexDiffPalette.resolve(theme);
    final visibleLimit = math.max(1, widget.previewLineLimit);
    final materializedLines = _materializeFoldedLines();
    final clipped =
        !_showFull &&
        _expandedFoldKeys.isEmpty &&
        materializedLines.length > visibleLimit;
    final visibleLines = clipped
        ? materializedLines.take(visibleLimit).toList()
        : materializedLines;
    final hiddenCount = materializedLines.length - visibleLines.length;
    final maxTextLength = visibleLines.fold<int>(
      0,
      (max, line) => math.max(max, line.text.length),
    );
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final maxBodyHeight = _showFull
        ? math.min(viewportHeight * 0.64, 720.0)
        : 320.0;
    final bodyHeight = codeBodyHeight(
      maxBodyHeight: maxBodyHeight,
      lineCount: visibleLines.length,
    );
    // 只订阅代码主题这一项：整体 watch 会让任意一条设置变更都重建每张差异卡。
    final codeTheme = context.select<SettingsController, EditorCodeTheme>(
      (controller) => controller.editorCodeTheme,
    );
    final brightness = theme.brightness;
    final paletteSignature = palette.signature;
    final diffDecoration = BoxDecoration(
      color: palette.surface,
      borderRadius: kOpenHandBorderRadius12,
      border: Border.all(color: palette.border, width: 0.8),
    );
    final baseStyle = openHandCodeBodyTextStyle(theme, color: palette.text);
    final highlighter = _CodeSyntaxHighlighter(
      baseStyle: baseStyle,
      darkSurface: brightness == Brightness.dark,
      codeTheme: codeTheme,
    );
    if (_lines.isEmpty) {
      return DecoratedBox(
        decoration: diffDecoration,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            _homeNoTextualDiffAvailableLabel(context),
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.mutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: kOpenHandBorderRadius12,
      child: DecoratedBox(
        decoration: diffDecoration,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 640.0;
            final contentWidth = codeBodyContentWidth(
              viewportWidth: viewportWidth,
              maxTextLength: maxTextLength,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSize(
                  duration: openHandMotionDuration(context, kOpenHandMotion180),
                  curve: kOpenHandSwitchInCurve,
                  alignment: Alignment.topCenter,
                  child: _CodeLineViewport(
                    height: bodyHeight,
                    contentWidth: contentWidth,
                    itemCount: visibleLines.length,
                    verticalController: _verticalController,
                    horizontalController: _horizontalController,
                    itemBuilder: (context, index) {
                      final line = visibleLines[index];
                      final foldKey = _foldKey(line);
                      return _CodexDiffLineRow(
                        line: line,
                        minWidth: viewportWidth,
                        highlighter: highlighter,
                        language: _languageFromFilePath(widget.record.filePath),
                        baseStyle: baseStyle,
                        palette: palette,
                        cacheKey:
                            '${_diffKey ?? widget.record.recordId}|'
                            '${brightness.name}|${codeTheme.name}|'
                            '$paletteSignature|$index',
                        foldedExpanded:
                            foldKey != null &&
                            _expandedFoldKeys.contains(foldKey),
                        onToggleFold: foldKey == null
                            ? null
                            : () => _toggleFold(line),
                      );
                    },
                  ),
                ),
                if (clipped ||
                    (_showFull && materializedLines.length > visibleLimit))
                  _CodexDiffFooter(
                    hiddenCount: hiddenCount,
                    showFull: _showFull,
                    palette: palette,
                    onToggle: () => _setShowFull(!_showFull),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 代码 / 差异正文的排版尺寸。
///
/// 内联差异卡与文件改动卡此前各写一遍同一套算式与魔数——行高 25、单字符估宽
/// 7.6、内容宽上限 3600……调一个数就得同步两处，漏一处两张卡的换行位置就会
/// 分叉，同一份 diff 在两处看起来不一样。
const double kCodeBodyRowExtent = 25;
const double _kCodeBodyContentWidthMax = 3600;
const double _kCodeBodyContentWidthPadding = 96;
const double _kCodeBodyApproxCharWidth = 7.6;

/// 正文高度：不超过 [maxBodyHeight]，也不小于一行。
double codeBodyHeight({required double maxBodyHeight, required int lineCount}) {
  return math.min(
    maxBodyHeight,
    math.max(kCodeBodyRowExtent, lineCount * kCodeBodyRowExtent),
  );
}

/// 横向内容宽度：按最长行估宽，不窄于视口、不超过上限。
double codeBodyContentWidth({
  required double viewportWidth,
  required int maxTextLength,
}) {
  return math.max(
    viewportWidth,
    math.min(
      _kCodeBodyContentWidthMax,
      _kCodeBodyContentWidthPadding + maxTextLength * _kCodeBodyApproxCharWidth,
    ),
  );
}

/// 代码 / diff 行视图的双向滚动外壳。
///
/// 纵向由 [verticalController] 驱动列表本体，横向由 [horizontalController]
/// 承载超宽内容；[PrimaryScrollController.none] 用来切断与页面主滚动的耦合，
/// 否则代码块内的滚轮事件会一路冒泡到会话列表。内联 diff 面板与文件改动卡片
/// 此前各写了一份完全相同的六层嵌套。
class _CodeLineViewport extends StatelessWidget {
  const _CodeLineViewport({
    required this.height,
    required this.contentWidth,
    required this.itemCount,
    required this.itemBuilder,
    required this.verticalController,
    required this.horizontalController,
  });

  final double height;
  final double contentWidth;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController verticalController;
  final ScrollController horizontalController;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: PrimaryScrollController.none(
        child: OpenHandSafeScrollbar(
          controller: verticalController,
          child: SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            primary: false,
            child: SizedBox(
              width: contentWidth,
              child: SelectionArea(
                child: ListView.builder(
                  controller: verticalController,
                  primary: false,
                  padding: EdgeInsets.zero,
                  itemExtent: kCodeBodyRowExtent,
                  itemCount: itemCount,
                  itemBuilder: itemBuilder,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodexDiffLineRow extends StatelessWidget {
  const _CodexDiffLineRow({
    required this.line,
    required this.minWidth,
    required this.highlighter,
    required this.language,
    required this.baseStyle,
    required this.palette,
    required this.cacheKey,
    this.foldedExpanded = false,
    this.onToggleFold,
  });

  final _CodexDiffLine line;
  final double minWidth;
  final _CodeSyntaxHighlighter highlighter;
  final String? language;
  final TextStyle baseStyle;
  final _CodexDiffPalette palette;
  final String cacheKey;
  final bool foldedExpanded;
  final VoidCallback? onToggleFold;

  Color get _background {
    return switch (line.kind) {
      _CodexDiffLineKind.addition => palette.additionBackground,
      _CodexDiffLineKind.deletion => palette.deletionBackground,
      _CodexDiffLineKind.folded => palette.foldedBackground,
      _CodexDiffLineKind.context => Colors.transparent,
    };
  }

  Color get _lineNumberColor {
    return switch (line.kind) {
      _CodexDiffLineKind.addition => palette.additionLineNumber,
      _CodexDiffLineKind.deletion => palette.deletionLineNumber,
      _CodexDiffLineKind.folded => palette.foldedLineNumber,
      _CodexDiffLineKind.context => palette.contextLineNumber,
    };
  }

  Color get _accentColor {
    return switch (line.kind) {
      _CodexDiffLineKind.addition => palette.additionAccent,
      _CodexDiffLineKind.deletion => palette.deletionAccent,
      _CodexDiffLineKind.context ||
      _CodexDiffLineKind.folded => Colors.transparent,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (line.kind == _CodexDiffLineKind.folded) {
      return _CodexDiffFoldRow(
        count: line.foldedCount,
        minWidth: minWidth,
        palette: palette,
        expanded: foldedExpanded,
        onToggle: onToggleFold,
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(color: _background),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(color: _accentColor, child: kOpenHandHGap4),
            SizedBox(
              width: 58,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    '${line.lineNumber ?? ''}',
                    style: baseStyle.copyWith(
                      color: _lineNumberColor,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ),
            Container(width: 1, color: palette.separator),
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  _highlightedCodeSpan(),
                  softWrap: false,
                  overflow: TextOverflow.visible,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _highlightedCodeSpan() {
    final text = line.text.isEmpty ? ' ' : line.text;
    final spanKey = Object.hash(
      cacheKey,
      line.kind.name,
      line.lineNumber ?? 0,
      boundedTextFingerprint(text),
    );
    var span = _highlightSpanCache.get(spanKey);
    if (span == null) {
      span = highlighter.build(text, language: language);
      _highlightSpanCache.put(spanKey, span, text.length);
    }
    if (line.kind == _CodexDiffLineKind.context) return span;
    final fallbackColor = line.kind == _CodexDiffLineKind.addition
        ? palette.additionFallbackText
        : palette.deletionFallbackText;
    return TextSpan(
      style: baseStyle.copyWith(color: fallbackColor),
      children:
          span.children ??
          <InlineSpan>[TextSpan(text: span.text ?? text, style: span.style)],
    );
  }
}

class _CodexDiffFoldRow extends StatelessWidget {
  const _CodexDiffFoldRow({
    required this.count,
    required this.minWidth,
    required this.palette,
    required this.expanded,
    this.onToggle,
  });

  final int count;
  final double minWidth;
  final _CodexDiffPalette palette;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final label = openHandLocalizedText(
      context,
      zh: expanded ? '收起 $count 行未修改' : '$count 行未修改',
      en: expanded
          ? 'Collapse $count unmodified lines'
          : '$count unmodified lines',
    );
    final row = ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(color: palette.foldedBackground),
        child: Row(
          children: [
            const ColoredBox(
              color: Colors.transparent,
              child: kOpenHandWidth4,
            ),
            SizedBox(
              width: 58,
              child: Center(
                child: Icon(
                  expanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 16,
                  color: palette.foldedLineNumber,
                ),
              ),
            ),
            Container(width: 1, color: palette.separator),
            kOpenHandHGap14,
            Text(
              label,
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFamily: kOpenHandMonospaceFontFamily,
              ),
            ),
          ],
        ),
      ),
    );
    if (onToggle == null) return row;
    return MicroPressFeedback(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          child: Tooltip(
            message: openHandLocalizedText(
              context,
              zh: expanded ? '折叠未修改内容' : '展开未修改内容',
              en: expanded
                  ? 'Collapse unchanged content'
                  : 'Expand unchanged content',
            ),
            waitDuration: kOpenHandTooltipWait,
            child: row,
          ),
        ),
      ),
    );
  }
}

class _CodexDiffFooter extends StatelessWidget {
  const _CodexDiffFooter({
    required this.hiddenCount,
    required this.showFull,
    required this.palette,
    required this.onToggle,
  });

  final int hiddenCount;
  final bool showFull;
  final _CodexDiffPalette palette;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = showFull
        ? openHandLocalizedText(context, zh: '收起 Diff 预览', en: 'Collapse diff')
        : openHandLocalizedText(
            context,
            zh: '展开全部 Diff（还有 $hiddenCount 行）',
            en: 'Show full diff ($hiddenCount more lines)',
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.footerSurface,
        border: Border(top: BorderSide(color: palette.footerBorder)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: palette.footerForeground,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: onToggle,
          icon: Icon(
            showFull ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
            size: 16,
          ),
          label: Text(label),
        ),
      ),
    );
  }
}

/// 从文件路径推断 highlight.dart 用的语言名（小写）。无后缀
/// 或 unknown 后缀返回 null，由 `_CodeSyntaxHighlighter` 退化成纯文本。
String? _languageFromFilePath(String path) {
  final i = path.lastIndexOf('.');
  if (i < 0 || i == path.length - 1) return null;
  final ext = path.substring(i + 1).toLowerCase();
  return switch (ext) {
    'js' || 'mjs' || 'cjs' => 'javascript',
    'ts' => 'typescript',
    'tsx' => 'typescript',
    'jsx' => 'javascript',
    'py' || 'pyi' => 'python',
    'rb' => 'ruby',
    'kt' || 'kts' => 'kotlin',
    'rs' => 'rust',
    'go' => 'go',
    'cpp' || 'cxx' || 'cc' || 'hpp' || 'hxx' || 'hh' => 'cpp',
    'c' || 'h' => 'c',
    'cs' => 'csharp',
    'php' => 'php',
    'swift' => 'swift',
    'm' || 'mm' => 'objectivec',
    'scala' => 'scala',
    'sh' || 'bash' || 'zsh' => 'bash',
    'ps1' => 'powershell',
    'sql' => 'sql',
    'yaml' || 'yml' => 'yaml',
    'json' || 'jsonc' => 'json',
    'xml' || 'plist' => 'xml',
    'html' || 'htm' => 'xml',
    'css' => 'css',
    'scss' => 'scss',
    'less' => 'less',
    'md' || 'markdown' => 'markdown',
    'toml' => 'ini',
    'ini' || 'cfg' || 'conf' => 'ini',
    'lua' => 'lua',
    'dart' => 'dart',
    'arb' => 'json',
    'gradle' => 'groovy',
    'groovy' => 'groovy',
    'r' => 'r',
    'pl' || 'pm' => 'perl',
    'erl' => 'erlang',
    'ex' || 'exs' => 'elixir',
    'hs' => 'haskell',
    'fs' || 'fsx' => 'fsharp',
    'clj' || 'cljs' => 'clojure',
    'jl' => 'julia',
    'proto' => 'protobuf',
    'graphql' || 'gql' => 'graphql',
    'vue' => 'xml',
    'dockerfile' => 'dockerfile',
    'cmake' => 'cmake',
    _ => null,
  };
}

/// 把 `filePath` 写入剪贴板并 SnackBar 提示。统一从 Row 的右键
/// / 长按手势调用，因此抽到顶层而非 row state。
Future<void> _copyPathToClipboard(BuildContext context, String filePath) async {
  await copyOpenHandTextToClipboard(
    logTag: 'home',
    context: context,
    text: filePath,
    logAction: '复制文件变更路径',
    successMessage: AppLocalizations.of(context)!.fileMutationPathCopied,
  );
}

String _fileMutationRevealPathLabel(BuildContext context) =>
    openHandLocalizedText(
      context,
      zh: '在系统文件浏览器中打开',
      en: 'Reveal file in file manager',
    );

String _fileMutationRevealPathFailedLabel(BuildContext context) =>
    openHandLocalizedText(
      context,
      zh: '无法在系统文件浏览器中打开该路径',
      en: 'Could not reveal this path in the file manager.',
    );

Future<void> _revealFileMutationPath(
  BuildContext context,
  String filePath,
) async {
  final rawPath = filePath.trim();
  if (rawPath.isEmpty) {
    showOpenHandErrorSnack(
      context,
      _fileMutationRevealPathFailedLabel(context),
      duration: kOpenHandSnackBarBriefDuration,
    );
    return;
  }

  var target = rawPath;
  try {
    final type = await FileSystemEntity.type(
      target,
      followLinks: false,
    ).timeout(defaultBoundedFileReadIdleTimeout);
    if (type == FileSystemEntityType.notFound) {
      final parent = File(target).parent.path.trim();
      if (parent.isNotEmpty && parent != '.') {
        target = parent;
      }
    }
  } catch (error, stack) {
    silentLog('file_mutation_entry', '解析展示目标', error, stack);
  }

  try {
    final ok = await revealLocalPathInSystemFileManager(
      target,
      tag: 'file_mutation_entry.reveal',
    );
    if (!context.mounted) return;
    if (!ok) {
      showOpenHandErrorSnack(
        context,
        _fileMutationRevealPathFailedLabel(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  } catch (error, stack) {
    silentLog('file_mutation_entry', '展示路径', error, stack);
    if (!context.mounted) return;
    showOpenHandErrorSnack(
      context,
      _fileMutationRevealPathFailedLabel(context),
      duration: kOpenHandSnackBarBriefDuration,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FileDiffDialog — displays file content diff when file change card is tapped
// ─────────────────────────────────────────────────────────────────────────────

class _FileDiffDialog extends StatefulWidget {
  const _FileDiffDialog({required this.filePath, required this.changeKind});

  final String filePath;
  final String changeKind;

  @override
  State<_FileDiffDialog> createState() => _FileDiffDialogState();
}

class _FileDiffDialogState extends State<_FileDiffDialog> {
  bool _loading = true;
  String? _beforeContent;
  String? _afterContent;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDiff();
  }

  Future<void> _loadDiff() async {
    try {
      // Create a new instance since AiFileHistoryService is not a singleton.
      final historyService = AiFileHistoryService();
      final versions = await historyService.getVersionHistory(widget.filePath);

      if (versions.isEmpty) {
        // No history, try to read current file content as 'after'.
        final file = File(widget.filePath);
        if (await isRegularFilePath(file.path, followLinks: true)) {
          final content = await readBoundedFileString(
            file,
            maxBytes: _kFileMutationDiffReadMaxBytes,
          );
          if (!mounted) return;
          setState(() {
            _beforeContent = null;
            _afterContent = content;
            _loading = false;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _error = openHandLocalizedText(
              context,
              zh: '没有保存的版本历史',
              zhHant: '沒有儲存的版本歷史',
              en: 'No saved version history',
              fr: 'Aucun historique de versions enregistré',
              de: 'Kein gespeicherter Versionsverlauf',
              ja: '保存済みのバージョン履歴はありません',
            );
            _loading = false;
          });
        }
        return;
      }

      // Get oldest version as "before" and read current file as "after".
      // This shows what changed from the saved snapshot to current state.
      final oldest = versions.last;

      final (beforeContent, _) = await historyService.readVersionContent(
        filePath: widget.filePath,
        versionId: oldest.versionId,
      );

      // Read current file content as "after"
      String? afterContent;
      final currentFile = File(widget.filePath);
      if (await isRegularFilePath(currentFile.path, followLinks: true)) {
        afterContent = await readBoundedFileString(
          currentFile,
          maxBytes: _kFileMutationDiffReadMaxBytes,
        );
      }

      if (!mounted) return;
      setState(() {
        _beforeContent = beforeContent;
        _afterContent = afterContent;
        _loading = false;
      });
    } catch (e, stack) {
      // _friendlyFileDiffError 只把异常翻译成用户文案；原始 error/stack
      // 必须走 silentLog 才能在 debug 期被 console 看到。
      silentLog('file_diff_dialog', '加载文件差异', e, stack);
      if (!mounted) return;
      setState(() {
        _error = _friendlyFileDiffError(context, e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: kOpenHandDialogHeightStandard,
      safeAreaMinimum: kOpenHandDialogDefaultInsetPadding,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: kOpenHandBorderRadius24,
      ),
      child: ClipRRect(
        borderRadius: kOpenHandBorderRadius24,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              color: colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  Icon(
                    Icons.difference_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                  kOpenHandHGap12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          openHandLocalizedText(
                            context,
                            zh: '文件变更对比',
                            zhHant: '檔案變更對比',
                            en: 'File Diff',
                            fr: 'Diff de fichier',
                            de: 'Dateivergleich',
                            ja: 'ファイル差分',
                          ),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        kOpenHandGap4,
                        Text(
                          _FileMutationCard._shortenFilePath(widget.filePath),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: kOpenHandMonospaceFontFamily,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: openHandCloseLabel(context),
                  ),
                ],
              ),
            ),

            // Diff content
            Expanded(
              child: OpenHandContentStateSwitcher(
                // 外层 Expanded 已定高，这里只做淡入淡出。
                animateSize: false,
                stateKey: _loading
                    ? 'loading'
                    : _error != null
                    ? 'error'
                    : 'diff',
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                      )
                    : _buildDiffView(theme, colorScheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffView(ThemeData theme, ColorScheme colorScheme) {
    final diff = unifiedDiffLinesFromText(
      _beforeContent ?? '',
      _afterContent ?? '',
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText.rich(
        TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: kOpenHandMonospaceFontFamily,
            height: 1.6,
          ),
          children: diff.map((line) {
            Color? bgColor;
            Color? textColor;
            if (line.startsWith('+')) {
              bgColor = colorScheme.primaryContainer.withValues(alpha: 0.35);
              textColor = colorScheme.onPrimaryContainer;
            } else if (line.startsWith('-')) {
              bgColor = colorScheme.errorContainer.withValues(alpha: 0.35);
              textColor = colorScheme.onErrorContainer;
            } else if (line.startsWith('@@')) {
              textColor = colorScheme.primary;
            }
            return TextSpan(
              text: '$line\n',
              style: TextStyle(backgroundColor: bgColor, color: textColor),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// FileMutationCard 渐进式展开尾部按钮。
/// - 文案 / 图标走当前 ColorScheme，与 row 视觉对齐；
/// - 提供「展开 +30」与「全部展开」两个动作；
/// - 触发的是父 setState，无内部状态，纯展示组件。
class _RevealMoreRow extends StatelessWidget {
  const _RevealMoreRow({
    required this.remaining,
    required this.onRevealStep,
    required this.onRevealAll,
  });

  final int remaining;
  final VoidCallback onRevealStep;
  final VoidCallback onRevealAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onRevealStep,
      hoverColor: cs.primary.withValues(alpha: 0.05),
      splashColor: cs.primary.withValues(alpha: 0.10),
      highlightColor: cs.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.unfold_more_rounded, size: 16, color: cs.primary),
            kOpenHandHGap8,
            Expanded(
              child: Text(
                l10n.fileMutationRevealMore(remaining),
                style: TextStyle(
                  fontSize: 12.5,
                  color: cs.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: onRevealAll,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 28),
              ),
              child: Text(l10n.fileMutationRevealAll),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// File Mutation History Inspector dialog
// 当前会话级别的全 ledger 俯瞰：跨 toolCall 聚合，按 filePath 分组，每组
// 内按 createdAt 倒序展示。只读：仅展示 + 复用既有 _FileMutationCardRow
// 视觉层（但不带 undo/redo callback——传 null/空 op）。

class _FileMutationHistoryInspectorDialog extends StatefulWidget {
  const _FileMutationHistoryInspectorDialog({
    required this.sessionId,
    required this.ledger,
  });

  final String sessionId;
  final AiFileMutationLedger ledger;

  @override
  State<_FileMutationHistoryInspectorDialog> createState() =>
      _FileMutationHistoryInspectorDialogState();
}

class _FileMutationHistoryInspectorDialogState
    extends State<_FileMutationHistoryInspectorDialog> {
  late Future<List<FileMutationView>> _future;
  String _filter = '';
  late final TextEditingController _filterCtrl;
  // 单路径 zoom 模式。group header 双击进入，仅展示该 path
  // 下的所有版本；空字符串表示常规多路径模式。
  String? _zoomedPath;

  @override
  void initState() {
    super.initState();
    _filterCtrl = TextEditingController();
    _future = widget.ledger.viewsForSession(widget.sessionId);
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthStandard,
      maxHeight: kOpenHandDialogHeightStandard,
      safeAreaMinimum: kOpenHandDialogDefaultInsetPadding,
      shape: const RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 18, color: cs.primary),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
                    l10n.fileMutationHistoryInspectorTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _filterCtrl,
              onChanged: (s) => setState(() => _filter = s.trim()),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: l10n.fileMutationHistoryInspectorFilterHint,
                border: const OutlineInputBorder(borderRadius: kOpenHandBorderRadius10),
              ),
            ),
          ),
          // zoom 模式提示条 + 退出按钮
          if (_zoomedPath != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: InputChip(
                avatar: Icon(
                  Icons.center_focus_strong_rounded,
                  size: 14,
                  color: cs.primary,
                ),
                label: Text(
                  _zoomedPath!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
                deleteIcon: const Icon(Icons.close_rounded, size: 14),
                onDeleted: () => setState(() => _zoomedPath = null),
              ),
            ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.45)),
          Expanded(
            child: FutureBuilder<List<FileMutationView>>(
              future: _future,
              builder: (ctx, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final all = snap.data!;
                final filtered = _filter.isEmpty
                    ? all
                    : all
                          .where(
                            (v) => v.record.filePath.toLowerCase().contains(
                              _filter.toLowerCase(),
                            ),
                          )
                          .toList(growable: false);
                // zoom 模式 → 只保留该路径
                final visible = _zoomedPath == null
                    ? filtered
                    : filtered
                          .where((v) => v.record.filePath == _zoomedPath)
                          .toList(growable: false);
                if (visible.isEmpty) {
                  return OpenHandInlineEmptyState(
                    message: l10n.fileMutationHistoryInspectorEmpty,
                    dense: true,
                  );
                }
                // 按文件路径分组（保持原 createdAt 倒序）
                final groups = <String, List<FileMutationView>>{};
                for (final v in visible) {
                  groups
                      .putIfAbsent(
                        v.record.filePath,
                        () => <FileMutationView>[],
                      )
                      .add(v);
                }
                final paths = groups.keys.toList()..sort();
                // 分组 staggered AppearOnce——
                // 80ms/张，封顶 1.2s（reduceMotion 跳过）。
                final reduceMotion = !openHandTickerMotionEnabled(context);
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: paths.length,
                  itemBuilder: (_, i) {
                    final path = paths[i];
                    final entries = groups[path]!
                      ..sort(
                        (a, b) =>
                            b.record.createdAt.compareTo(a.record.createdAt),
                      );
                    final group = _HistoryInspectorGroup(
                      filePath: path,
                      entries: entries,
                      zoomed: _zoomedPath == path,
                      onZoomToggle: () => setState(() {
                        _zoomedPath = _zoomedPath == path ? null : path;
                      }),
                    );
                    if (reduceMotion) return group;
                    final delayMs = (i * 80).clamp(0, 1200);
                    return _DelayedAppear(
                      delay: Duration(milliseconds: delayMs),
                      child: group,
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.primary(
                  onPressed: () => Navigator.of(context).maybePop(),
                  label: MaterialLocalizations.of(context).closeButtonLabel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryInspectorGroup extends StatelessWidget {
  const _HistoryInspectorGroup({
    required this.filePath,
    required this.entries,
    required this.zoomed,
    required this.onZoomToggle,
  });

  final String filePath;
  final List<FileMutationView> entries;
  final bool zoomed;
  final VoidCallback onZoomToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final lineDelta = _sumFileMutationLineDeltas(entries);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: _HoverElevateBox(
        radius: 12,
        baseColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        baseBorder: cs.outlineVariant.withValues(alpha: 0.45),
        hoverBorder: cs.primary.withValues(alpha: 0.45),
        hoverShadow: cs.primary.withValues(alpha: 0.15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // group header
            InkWell(
              onTap: () => _copyPathToClipboard(context, filePath),
              onDoubleTap: onZoomToggle,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(kOpenHandRadius12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.insert_drive_file_outlined,
                      size: 14,
                      color: cs.primary,
                    ),
                    kOpenHandHGap6,
                    Expanded(
                      child: Tooltip(
                        message: filePath,
                        waitDuration: kOpenHandTooltipWait,
                        child: Text(
                          filePath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontFamily: kOpenHandMonospaceFontFamily,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        zoomed
                            ? Icons.center_focus_strong_rounded
                            : Icons.center_focus_weak_outlined,
                        size: 14,
                      ),
                      tooltip: zoomed
                          ? l10n.fileMutationHistoryInspectorZoomOut
                          : l10n.fileMutationHistoryInspectorZoomIn,
                      onPressed: onZoomToggle,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                    kOpenHandHGap4,
                    if (lineDelta.available && lineDelta.hasChanges) ...[
                      _FileMutationLineDeltaBadge(delta: lineDelta),
                      kOpenHandHGap6,
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.10),
                        borderRadius: kOpenHandBorderRadius10,
                      ),
                      child: Text(
                        l10n.fileMutationFilesCount(entries.length),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
            for (final v in entries) _InspectorEntryRow(view: v),
          ],
        ),
      ),
    );
  }
}

/// 检查器单条记录，长按或右键可复制记录 JSON。
class _InspectorEntryRow extends StatelessWidget {
  const _InspectorEntryRow({required this.view});
  final FileMutationView view;

  Future<void> _showRecordMenu(BuildContext context, Offset globalPos) async {
    final selected = await showAnimatedPointerMenu<String>(
      context: context,
      globalPosition: globalPos,
      rootOverlay: true,
      useRootNavigator: true,
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'copy_json',
          child: Row(
            children: [
              const Icon(Icons.data_object_rounded, size: 16),
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '复制此条记录 JSON',
                  zhHant: '複製此筆記錄 JSON',
                  en: 'Copy record JSON',
                  fr: 'Copier le JSON de l’entrée',
                  de: 'Eintrag-JSON kopieren',
                  ja: 'このレコードの JSON をコピー',
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy_id',
          child: Row(
            children: [
              const Icon(Icons.tag_rounded, size: 16),
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '复制 record ID',
                  zhHant: '複製 record ID',
                  en: 'Copy record ID',
                  fr: 'Copier le record ID',
                  de: 'Record-ID kopieren',
                  ja: 'record ID をコピー',
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (!context.mounted) return;
    if (selected == 'copy_json') {
      final json = jsonEncode(view.record.toJson());
      await copyOpenHandTextToClipboard(
        logTag: 'home',
        context: context,
        text: json,
        logAction: '复制文件变更记录 JSON',
        successMessage: openHandLocalizedText(
          context,
          zh: '已复制 record JSON',
          zhHant: '已複製 record JSON',
          en: 'Copied record JSON',
          fr: 'JSON de l’entrée copié',
          de: 'Record-JSON kopiert',
          ja: 'record JSON をコピーしました',
        ),
      );
    } else if (selected == 'copy_id') {
      await copyOpenHandTextToClipboard(
        logTag: 'home',
        context: context,
        text: view.record.recordId,
        logAction: '复制文件变更记录 ID',
        successMessage: openHandLocalizedText(
          context,
          zh: '已复制 record ID',
          zhHant: '已複製 record ID',
          en: 'Copied record ID',
          fr: 'Record ID copié',
          de: 'Record-ID kopiert',
          ja: 'record ID をコピーしました',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox?;
        final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
        _showRecordMenu(context, pos + const Offset(20, 20));
      },
      onSecondaryTapDown: (d) => _showRecordMenu(context, d.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            _RecordKindBadge(kind: view.record.kind),
            kOpenHandHGap8,
            Expanded(
              child: Text(
                view.record.toolName,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              formatYearMonthDayHmsLocal(view.record.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            kOpenHandHGap8,
            if (view.directlyUndone)
              Tooltip(
                message: l10n.fileMutationUndone,
                child: Icon(
                  Icons.undo_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
              )
            else if (view.cascadeUndone)
              Tooltip(
                message: l10n.fileMutationCascadeUndone,
                child: Icon(
                  Icons.link_off_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecordKindBadge extends StatelessWidget {
  const _RecordKindBadge({required this.kind});
  final FileMutationKind kind;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (kind) {
      FileMutationKind.create => (
        Icons.add_circle_outline_rounded,
        cs.primary,
        'create',
      ),
      FileMutationKind.modify => (Icons.edit_outlined, cs.tertiary, 'modify'),
      FileMutationKind.delete => (
        Icons.delete_outline_rounded,
        cs.error,
        'delete',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(kOpenHandRadius6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          kOpenHandHGap4,
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: color,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// FileMutationCard row 键盘 Enter 触发的 Intent。
class _OpenLegacyDialogIntent extends Intent {
  const _OpenLegacyDialogIntent();
}

/// 卡内 Cmd/Ctrl+Z 撤销最近一条记录。
class _UndoLastIntent extends Intent {
  const _UndoLastIntent();
}

/// 卡内 Shift+Cmd/Ctrl+Z 重做最近一条记录。
class _RedoLastIntent extends Intent {
  const _RedoLastIntent();
}

/// inspector 分组卡 hover 微抬升——
/// 200ms easeOutCubic 边框 / 阴影 fade，reduceMotion 下退化为零时长。
class _HoverElevateBox extends StatefulWidget {
  const _HoverElevateBox({
    required this.child,
    required this.radius,
    required this.baseColor,
    required this.baseBorder,
    required this.hoverBorder,
    required this.hoverShadow,
  });
  final Widget child;
  final double radius;
  final Color baseColor;
  final Color baseBorder;
  final Color hoverBorder;
  final Color hoverShadow;

  @override
  State<_HoverElevateBox> createState() => _HoverElevateBoxState();
}

class _HoverElevateBoxState extends State<_HoverElevateBox>
    with OpenHandHoverState {
  @override
  Widget build(BuildContext context) {
    final dur = openHandMotionDuration(context, kOpenHandMotion200,
    );
    return MouseRegion(
      onEnter: (_) => setOpenHandHovered(true),
      onExit: (_) => setOpenHandHovered(false),
      cursor: SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: dur,
        curve: kOpenHandSwitchInCurve,
        decoration: BoxDecoration(
          color: widget.baseColor,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: openHandHovered ? widget.hoverBorder : widget.baseBorder,
            width: openHandHovered ? 0.8 : 0.5,
          ),
          boxShadow: openHandHovered
              ? [
                  BoxShadow(
                    color: widget.hoverShadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

/// 在 [delay] 之前显示透明占位（保持高度通过 child build），
/// 之后再用 AppearOnce 包裹 child 实现错峰入场。
class _DelayedAppear extends StatefulWidget {
  const _DelayedAppear({required this.delay, required this.child});
  final Duration delay;
  final Widget child;

  @override
  State<_DelayedAppear> createState() => _DelayedAppearState();
}

class _DelayedAppearState extends State<_DelayedAppear> {
  bool _show = false;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _scheduleShow();
  }

  @override
  void didUpdateWidget(covariant _DelayedAppear oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_show && oldWidget.delay != widget.delay) _scheduleShow();
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    super.dispose();
  }

  void _scheduleShow() {
    _delayTimer?.cancel();
    _delayTimer = null;
    if (widget.delay <= Duration.zero) {
      _show = true;
      return;
    }
    _delayTimer = startSafeTimer(widget.delay, () {
      _delayTimer = null;
      if (!mounted) return;
      setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return Opacity(opacity: 0, child: widget.child);
    return AppearOnce(child: widget.child);
  }
}

/// 批量 undo overlay。BackdropFilter blur 6px + primary 色
/// tinted glow 渐变背景 + 圆形进度环 + 「N/M」百分比文案。淡入淡出由
/// 外层 AnimatedSwitcher 控制。
class _BulkUndoOverlay extends StatelessWidget {
  const _BulkUndoOverlay({super.key, required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 批量撤销过程中 done 可能短暂超过 total（并发回执），除法结果越界会让
    // 进度指示器断言失败，这里统一夹到 0..1。
    final ratio = total == 0 ? null : unitRatio(done, total);
    return ClipRRect(
      borderRadius: kOpenHandBorderRadius16,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primary.withValues(alpha: 0.10),
                cs.primary.withValues(alpha: 0.04),
              ],
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  value: ratio,
                  color: cs.primary,
                  backgroundColor: cs.primary.withValues(alpha: 0.15),
                ),
              ),
              kOpenHandGap8,
              Text(
                '$done/$total',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 本轮文件变动汇总卡（_RoundFileMutationSummaryCard）
// 当 AssistantTurn 末尾 (`result.toolCalls.isEmpty`) 触发时，controller 已
// 写入一条 metadata 含 `round_file_mutation_summary == true` 的 status
// 消息。这里把该消息渲染为一张「Codex 风总览卡」：
// - 仅展示本轮真正产生 ledger 记录的 toolCallId（controller 已预筛）。
// - 行级 dedup 单元 = (filePath × toolCallId)；同一文件被多次 Edit/Write
//   会出现多行，每行带独立「跳转到来源消息」按钮，跳转通过
//   `_TranscriptBubbleRegistry` 反查 BuildContext + `Scrollable
//   .ensureVisible(alignment:0.18)` 实现 Q 弹丝滑滚动；目标早于当前窗口时
//   由 dispatcher 先 reveal-older，再精确定位。
// - 文件条目跟随消息卡片一次性出现，不再做行级 drip-in 入场。
// - 不支持 undo/redo（信息聚合卡，避免与每个工具调用卡的 ledger 操作
//   重复 / 并发竞态）。
// ─────────────────────────────────────────────────────────────────────────────

class _RoundFileMutationSummaryCard extends StatefulWidget {
  const _RoundFileMutationSummaryCard({required this.message});

  final AiSessionMessage message;

  @override
  State<_RoundFileMutationSummaryCard> createState() =>
      _RoundFileMutationSummaryCardState();
}

class _RoundFileMutationSummaryCardState
    extends State<_RoundFileMutationSummaryCard> {
  Future<List<_RoundSummaryRow>>? _rowsFuture;
  String? _lastSessionId;
  String? _lastMessageId;
  int _bulkUndoTotal = 0;
  int _bulkUndoDone = 0;
  bool get _bulkUndoBusy => _bulkUndoTotal > 0;
  final ValueNotifier<int> _pulseSignal = ValueNotifier<int>(0);
  // 跨重建保留折叠状态，并限制缓存规模。
  static final Set<String> _collapsedGroups = <String>{};
  static final Set<String> _expandedDiffRows = <String>{};
  static final Set<String> _collapsedPathGroups = <String>{};
  static final Set<String> _expandedFullList = <String>{};
  static const int _summaryStateCacheLimit = 500;
  static const int _virtualRowCap = 30;
  static const int _pathSubgroupThreshold = 8;

  String _groupKey(String toolName) => '${widget.message.id}::$toolName';
  String _diffKey(String recordId) => '${widget.message.id}#$recordId';
  String _pathGroupKey(String toolName, String dir) =>
      '${widget.message.id}::$toolName::$dir';

  static void _rememberSummaryState(Set<String> cache, String key) {
    cache.remove(key);
    cache.add(key);
    while (cache.length > _summaryStateCacheLimit) {
      cache.remove(cache.first);
    }
  }

  /// 取 path 的目录前缀（去掉最后一段文件名）。空目录返回 `<root>`。
  static String _topDir(String filePath) {
    final p = filePath.replaceAll(r'\\', '/');
    final idx = p.lastIndexOf('/');
    if (idx <= 0) return '<root>';
    return p.substring(0, idx);
  }

  @override
  void dispose() {
    _pulseSignal.dispose();
    super.dispose();
  }

  List<String> get _toolCallIds {
    final raw = widget.message.metadata['round_summary_tool_call_ids'];
    if (raw is List) {
      return raw.whereType<String>().where((e) => e.isNotEmpty).toList();
    }
    return const <String>[];
  }

  Map<String, String> get _sourceMessageIdsByToolCallId {
    final raw = widget.message.metadata['round_summary_source_message_ids'];
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in raw.entries)
        if ('${entry.key}'.trim().isNotEmpty &&
            '${entry.value}'.trim().isNotEmpty)
          '${entry.key}'.trim(): '${entry.value}'.trim(),
    };
  }

  Future<List<_RoundSummaryRow>> _load(BuildContext ctx) async {
    if (kDebugMode) {
      developer.Timeline.startSync(
        'openhand.round_summary.load',
        arguments: <String, Object?>{'tool_calls': _toolCallIds.length},
      );
    }
    try {
      final ctrl = ctx.read<AiSessionController>();
      final sessionId = ctrl.currentSession?.id ?? '';
      if (sessionId.isEmpty) return const <_RoundSummaryRow>[];
      final ledger = ctrl.toolRuntimeService.mutationLedger;
      // 反向索引 toolCallId → 对应 toolCall message.id（用于跳转）。
      final session = ctrl.currentSession;
      final toolCallMessageIdByCallId = <String, String>{
        ..._sourceMessageIdsByToolCallId,
      };
      if (session != null) {
        for (final m in session.messages) {
          if (m.kind != AiSessionMessageKind.toolCall) continue;
          final id = '${m.metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'.trim();
          if (id.isNotEmpty) {
            toolCallMessageIdByCallId.putIfAbsent(id, () => m.id);
          }
        }
      }
      final ids = _toolCallIds;
      final rows = <_RoundSummaryRow>[];
      final seen = <String>{}; // (filePath|toolCallId) dedup
      Map<String, List<FileMutationView>> viewsByToolCall;
      try {
        viewsByToolCall = await ledger.viewsForToolCalls(
          sessionId: sessionId,
          toolCallIds: ids,
        );
      } catch (error, stack) {
        silentLog('round_summary_card', '构建工具调用视图', error, stack);
        return const <_RoundSummaryRow>[];
      }
      for (final entry in viewsByToolCall.entries) {
        final tcId = entry.key;
        final views = entry.value;
        // 同 toolCall + 同文件 多次 ⇒ 取最后一条（最终态）。
        final byPath = <String, FileMutationView>{};
        for (final v in views) {
          byPath[v.record.filePath] = v;
        }
        for (final entry in byPath.entries) {
          final key = '${entry.key}|$tcId';
          if (!seen.add(key)) continue;
          rows.add(
            _RoundSummaryRow(
              view: entry.value,
              toolCallId: tcId,
              sourceMessageId: toolCallMessageIdByCallId[tcId],
            ),
          );
        }
      }
      // 时间升序排列：早→晚，符合执行轨迹直觉。
      rows.sort(
        (a, b) => a.view.record.createdAt.compareTo(b.view.record.createdAt),
      );
      return rows;
    } finally {
      if (kDebugMode) developer.Timeline.finishSync();
    }
  }

  void _ensureFutureBound() {
    final ctrl = context.read<AiSessionController>();
    final sessionId = ctrl.currentSession?.id ?? '';
    final messageId = widget.message.id;
    if (_rowsFuture == null ||
        sessionId != _lastSessionId ||
        messageId != _lastMessageId) {
      _lastSessionId = sessionId;
      _lastMessageId = messageId;
      _rowsFuture = _load(context);
    }
  }

  Future<void> _jumpToSourceMessage(String? messageId) async {
    if (messageId == null || messageId.isEmpty) return;
    if (_jumpingToSourceId == messageId) return;
    _jumpingToSourceId = messageId;
    try {
      await _runJumpToSourceMessage(messageId);
    } finally {
      if (_jumpingToSourceId == messageId) {
        _jumpingToSourceId = null;
      }
    }
  }

  Future<void> _runJumpToSourceMessage(String messageId) async {
    final ctrl = context.read<AiSessionController>();
    final sessionId = ctrl.currentSession?.id ?? '';
    if (sessionId.isEmpty) return;

    // 先尝试直接跳转
    final ok = await _TranscriptScrollDispatcher.instance.scrollToMessage(
      sessionId,
      messageId,
      highlight: true,
    );
    if (ok) return;

    // 如果跳转失败，尝试在全部消息中查找该消息附近的可见消息作为替代目标
    final session = ctrl.currentSession;
    if (session != null) {
      final allMessages = session.messages;
      final targetIdx = allMessages.indexWhere((m) => m.id == messageId);
      if (targetIdx >= 0) {
        // 目标消息存在于 session.messages 但不在 displayMessages 中
        // （可能被压缩点截断）。尝试跳转到压缩点之后最近的消息。
        final displayMessages = session.displayMessages;
        if (displayMessages.isNotEmpty) {
          // 找到 displayMessages 中第一条消息作为替代
          final fallbackOk = await _TranscriptScrollDispatcher.instance
              .scrollToMessage(
                sessionId,
                displayMessages.first.id,
                highlight: true,
              );
          if (fallbackOk && mounted) {
            showOpenHandInfoSnack(
              context,
              openHandLocalizedText(
                context,
                zh: '目标消息位于上下文压缩点之前，已跳转到最早可见消息。',
                en: 'Target message is before compression point. Jumped to earliest visible message.',
              ),
              duration: _kFileMutationNoticeSnackDuration,
            );
            return;
          }
        }
      }
    }

    if (!mounted) return;
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '未能定位来源消息（可能已被删除）。',
        en: 'Could not locate source message (may have been deleted).',
      ),
      duration: kOpenHandMotion2200,
    );
  }

  String? _jumpingToSourceId;

  /// 「全部撤销本轮」批量入口。
  /// 按 filePath 聚合 → 同文件严格串行（避免互相覆盖磁盘内容），
  /// 跨文件 4 路并行；进度打到 header chip 与中央 overlay；完成后
  /// 单次 reload + highlight pulse；任意失败 SnackBar 报最后一次错误。
  Future<void> _undoAllRound(List<_RoundSummaryRow> rows) async {
    if (_bulkUndoBusy) return;
    final candidates = rows
        .where((r) => r.view.canUndo)
        .toList(growable: false);
    if (candidates.isEmpty) return;
    final groups = <String, List<_RoundSummaryRow>>{};
    for (final r in candidates) {
      groups
          .putIfAbsent(r.view.record.filePath, () => <_RoundSummaryRow>[])
          .add(r);
    }
    for (final group in groups.values) {
      group.sort(
        (left, right) =>
            right.view.record.createdAt.compareTo(left.view.record.createdAt),
      );
    }
    setState(() {
      _bulkUndoTotal = candidates.length;
      _bulkUndoDone = 0;
    });
    final ledger = context
        .read<AiSessionController>()
        .toolRuntimeService
        .mutationLedger;
    String? lastError;
    final paths = groups.keys.toList();
    await forEachIndexWithConcurrencyLimit(
      itemCount: paths.length,
      maxConcurrency: _kFileMutationUndoConcurrency,
      shouldContinue: () => mounted,
      task: (index) async {
        for (final r in groups[paths[index]]!) {
          if (!mounted) return;
          try {
            final res = await ledger.undoRecord(
              sessionId: r.view.record.sessionId,
              recordId: r.view.record.recordId,
            );
            if (!res.success && res.errorMessage.isNotEmpty) {
              lastError = res.errorMessage;
            }
          } catch (error, stack) {
            silentLog('round_summary_card', '撤销整轮变更', error, stack);
            lastError = '$error';
          }
          if (!mounted) return;
          setState(() => _bulkUndoDone += 1);
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _bulkUndoTotal = 0;
      _bulkUndoDone = 0;
      _rowsFuture = _load(context);
    });
    _pulseSignal.value += 1;
    if (lastError != null) {
      showOpenHandErrorSnack(context, lastError!);
    }
  }

  /// 把本轮全部 ledger 记录序列化为 JSON。
  /// 弹出系统文件选择器让用户挑选保存位置 / 文件名；保存成功 / 失败均弹
  /// SnackBar 提示。字段直接调 FileMutationRecord.toJson()，再附 toolCallId
  /// / sourceMessageId 让外部审计/对账能完整反查。
  Future<void> _exportRoundJson(List<_RoundSummaryRow> rows) async {
    final payload = <String, Object?>{
      'session_id':
          widget.message.metadata['session_id'] ??
          context.read<AiSessionController>().currentSession?.id,
      'round_summary_message_id': widget.message.id,
      'anchor_user_message_id':
          widget.message.metadata['round_summary_anchor_user_id'],
      'created_at': widget.message.createdAt.toIso8601String(),
      'rows': [
        for (final r in rows)
          <String, Object?>{
            'record': r.view.record.toJson(),
            'effectively_undone': r.view.isEffectivelyUndone,
            aiSessionMessageToolCallIdMetadataKey: r.toolCallId,
            'source_message_id': r.sourceMessageId,
          },
      ],
    };
    final encoded = prettyPrintJson(payload);

    final timestamp = widget.message.createdAt
        .toLocal()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final suggested = 'openhand-round-mutations-$timestamp.json';
    const typeGroup = XTypeGroup(label: 'JSON', extensions: <String>['json']);

    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog('round_summary_card', '选择轮次变更导出位置', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '导出取消（无法打开文件选择器）：$error',
          en: 'Export aborted (file picker unavailable): $error',
        ),
        duration: kOpenHandMotion2400,
      );
      return;
    }
    if (location == null) {
      if (!mounted) return;
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(context, zh: '已取消导出。', en: 'Export cancelled.'),
        duration: kOpenHandMotion1600,
      );
      return;
    }
    try {
      await writeFileAtomically(File(location.path), encoded);
    } catch (error, stack) {
      silentLog('round_summary_card', '导出轮次变更', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '保存失败：$error',
          en: 'Save failed: $error',
        ),
        duration: _kFileMutationNoticeSnackDuration,
      );
      return;
    }
    if (!mounted) return;
    _pulseSignal.value += 1;
    showOpenHandSuccessSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '已保存到 ${location.path}',
        en: 'Saved to ${location.path}',
      ),
      duration: kOpenHandMotion2400,
      maxLines: 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureFutureBound();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = !openHandTickerMotionEnabled(context);
    return AppearOnce(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer.withValues(alpha: 0.92),
              borderRadius: kOpenHandBorderRadius18,
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.28),
                width: 0.8,
              ),
            ),
            child: ClipRRect(
              borderRadius: kOpenHandBorderRadius18,
              child: FutureBuilder<List<_RoundSummaryRow>>(
                future: _rowsFuture,
                builder: (context, snap) {
                  final rows = snap.data ?? const <_RoundSummaryRow>[];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(theme, cs, rows),
                      if (rows.isEmpty &&
                          snap.connectionState != ConnectionState.done)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: cs.primary,
                                ),
                              ),
                              kOpenHandHGap8,
                              Text(
                                openHandLocalizedText(
                                  context,
                                  zh: '正在汇总本轮文件变动…',
                                  en: 'Aggregating round mutations…',
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                          child: Text(
                            openHandLocalizedText(
                              context,
                              zh: '本轮无文件变动。',
                              en: 'No file mutations this round.',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          child: _buildGroupedBody(
                            theme,
                            cs,
                            rows,
                            reduceMotion,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          // HighlightPulse: undo / export 成功后温和高亮顶边。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(child: HighlightPulse(signal: _pulseSignal)),
          ),
          // Bulk-undo overlay：blur + 进度环。
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_bulkUndoBusy,
              child: AnimatedSwitcher(
                duration: openHandMotionDuration(
                  context,
                  _kFileMutationOverlaySwitchDuration,
                ),
                child: _bulkUndoBusy
                    ? _BulkUndoOverlay(
                        key: const ValueKey('round-bulk-undo-overlay'),
                        done: _bulkUndoDone,
                        total: _bulkUndoTotal,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('round-bulk-undo-overlay-hidden'),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    ColorScheme cs,
    List<_RoundSummaryRow> rows,
  ) {
    int created = 0, modified = 0, deleted = 0;
    for (final r in rows) {
      switch (r.view.record.kind) {
        case FileMutationKind.create:
          created += 1;
        case FileMutationKind.modify:
          modified += 1;
        case FileMutationKind.delete:
          deleted += 1;
      }
    }
    final totalLineDelta = _sumFileMutationLineDeltas(
      rows.map((row) => row.view),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.14),
            cs.primary.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_motion_rounded, size: 18, color: cs.primary),
          kOpenHandHGap8,
          Text(
            openHandLocalizedText(
              context,
              zh: '本轮文件变动汇总',
              en: 'Round File Mutations',
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          kOpenHandHGap10,
          if (rows.isNotEmpty)
            _StatPill(
              label: AppLocalizations.of(
                context,
              )!.fileMutationFilesCount(rows.length),
              color: cs.onSurfaceVariant,
              bg: cs.surfaceContainerHighest.withValues(alpha: 0.65),
            ),
          if (created > 0) ...[
            kOpenHandHGap6,
            _StatPill(
              label: 'C $created',
              color: _kFileMutationAddedColor,
              bg: _kFileMutationAddedColor.withValues(alpha: 0.12),
            ),
          ],
          if (modified > 0) ...[
            kOpenHandHGap6,
            _StatPill(
              label: 'M $modified',
              color: cs.primary,
              bg: cs.primary.withValues(alpha: 0.12),
            ),
          ],
          if (deleted > 0) ...[
            kOpenHandHGap6,
            _StatPill(
              label: 'D $deleted',
              color: cs.error,
              bg: cs.errorContainer.withValues(alpha: 0.55),
            ),
          ],
          const Spacer(),
          if (totalLineDelta.available && totalLineDelta.hasChanges)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: openHandLocalizedText(
                  context,
                  zh: '行级增删统计',
                  en: 'Line additions/deletions',
                ),
                child: _FileMutationLineDeltaBadge(
                  delta: totalLineDelta,
                  style: _FileMutationLineDeltaStyle.text,
                ),
              ),
            ),
          // 进度 chip — 全部撤销中显示 N/M；宽度随动效增减，避免翻转时
          // 把右侧动作组整体推走。
          OpenHandInlineRevealSwitcher(
            presentKey: const ValueKey<String>('bulk-undo'),
            child: _bulkUndoBusy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          value: _bulkUndoTotal == 0
                              ? null
                              : unitRatio(_bulkUndoDone, _bulkUndoTotal),
                        ),
                      ),
                      kOpenHandHGap6,
                      Text(
                        '$_bulkUndoDone/$_bulkUndoTotal',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      kOpenHandHGap6,
                    ],
                  )
                : null,
          ),
          // 右侧动作组（按 reduceMotion 透明度逐个淡入由
          // 上层 HighlightPulse 提供反馈，无需在此再加入场动画）。
          if (rows.isNotEmpty &&
              rows.any((r) => r.view.canUndo) &&
              !_bulkUndoBusy)
            _IconActionButton(
              icon: Icons.undo_rounded,
              tooltip: openHandLocalizedText(
                context,
                zh: '撤销本轮全部变动',
                en: 'Undo all round mutations',
              ),
              onTap: () => _undoAllRound(rows),
            ),
          if (rows.isNotEmpty)
            _IconActionButton(
              icon: Icons.data_object_rounded,
              tooltip: openHandLocalizedText(
                context,
                zh: '导出本轮 JSON',
                en: 'Export round as JSON',
              ),
              onTap: () => _exportRoundJson(rows),
            ),
          _IconActionButton(
            icon: Icons.refresh_rounded,
            tooltip: openHandLocalizedText(
              context,
              zh: '刷新汇总',
              en: 'Refresh summary',
            ),
            // 注意：_load 返回 Future，箭头函数 `() => x = _load(...)` 会把
            // 这个 Future 作为 closure 的返回值传给 setState，被框架 assert 拦截
            // （setState callback must not return Future）。这里要用 block，
            // 让赋值表达式被 statement 吞掉，closure 返回 void。
            onTap: () => setState(() {
              _rowsFuture = _load(context);
            }),
          ),
        ],
      ),
    );
  }

  /// 按 `record.toolName` 分组渲染；每组一个可折叠 header。
  /// 组内行数超过 [_pathSubgroupThreshold] 时再按目录前缀做二级分组；
  /// 整体可视行数超过 [_virtualRowCap] 时显示"展开全部 N 行"按钮。
  Widget _buildGroupedBody(
    ThemeData theme,
    ColorScheme cs,
    List<_RoundSummaryRow> rows,
    bool reduceMotion,
  ) {
    // 保留首次出现顺序 — LinkedHashMap 默认行为。
    final groups = <String, List<_RoundSummaryRow>>{};
    for (final r in rows) {
      final key = r.view.record.toolName.isEmpty ? '_' : r.view.record.toolName;
      groups.putIfAbsent(key, () => <_RoundSummaryRow>[]).add(r);
    }
    final msgKey = widget.message.id;
    final showAll = _expandedFullList.contains(msgKey);
    final children = <Widget>[];
    var rendered = 0;
    var truncated = false;

    Widget buildTile(_RoundSummaryRow r) {
      return _RoundSummaryRowTile(
        row: r,
        onJump: () => _jumpToSourceMessage(r.sourceMessageId),
        isDiffExpanded: _expandedDiffRows.contains(
          _diffKey(r.view.record.recordId),
        ),
        onToggleDiff: () => _toggleDiffExpanded(r),
      );
    }

    bool capReached() => !showAll && rendered >= _virtualRowCap;

    // 单组：扁平输出（仍受路径子分组与 cap 影响）。
    if (groups.length <= 1) {
      final only = groups.values.isEmpty
          ? const <_RoundSummaryRow>[]
          : groups.values.first;
      final toolName = groups.keys.isEmpty ? '_' : groups.keys.first;
      _emitRowsWithOptionalPathSubgroups(
        theme: theme,
        cs: cs,
        toolName: toolName,
        groupRows: only,
        showAll: showAll,
        reduceMotion: reduceMotion,
        children: children,
        renderedAdd: (n) {
          rendered += n;
          if (capReached()) truncated = true;
        },
        capReached: capReached,
        buildTile: buildTile,
      );
    } else {
      for (final entry in groups.entries) {
        if (capReached()) {
          truncated = true;
          break;
        }
        final groupKey = _groupKey(entry.key);
        final collapsed = _collapsedGroups.contains(groupKey);
        children.add(
          _GroupHeader(
            toolName: entry.key,
            count: entry.value.length,
            collapsed: collapsed,
            onToggle: () {
              setState(() {
                if (collapsed) {
                  _collapsedGroups.remove(groupKey);
                } else {
                  _rememberSummaryState(_collapsedGroups, groupKey);
                }
              });
            },
          ),
        );
        if (collapsed) {
          continue;
        }
        _emitRowsWithOptionalPathSubgroups(
          theme: theme,
          cs: cs,
          toolName: entry.key,
          groupRows: entry.value,
          showAll: showAll,
          reduceMotion: reduceMotion,
          children: children,
          renderedAdd: (n) {
            rendered += n;
            if (capReached()) truncated = true;
          },
          capReached: capReached,
          buildTile: buildTile,
        );
      }
    }

    if (truncated) {
      final remaining = rows.length - rendered;
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                foregroundColor: cs.primary,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.unfold_more_rounded, size: 16),
              label: Text(
                openHandLocalizedText(
                  context,
                  zh: '展开剩余 $remaining 行',
                  en: 'Show $remaining more',
                ),
                style: theme.textTheme.labelMedium,
              ),
              onPressed: () {
                setState(() {
                  _rememberSummaryState(_expandedFullList, msgKey);
                });
              },
            ),
          ),
        ),
      );
    } else if (showAll && rows.length > _virtualRowCap) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                foregroundColor: cs.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.unfold_less_rounded, size: 16),
              label: Text(
                openHandCollapseLabel(context),
                style: theme.textTheme.labelMedium,
              ),
              onPressed: () {
                setState(() => _expandedFullList.remove(msgKey));
              },
            ),
          ),
        ),
      );
    }

    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : kOpenHandMotion220,
      curve: kOpenHandSwitchInCurve,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// 组内若超阈值 → 按 `_topDir` 二级分桶；否则平铺。
  void _emitRowsWithOptionalPathSubgroups({
    required ThemeData theme,
    required ColorScheme cs,
    required String toolName,
    required List<_RoundSummaryRow> groupRows,
    required bool showAll,
    required bool reduceMotion,
    required List<Widget> children,
    required void Function(int n) renderedAdd,
    required bool Function() capReached,
    required Widget Function(_RoundSummaryRow) buildTile,
  }) {
    if (groupRows.length < _pathSubgroupThreshold) {
      for (final r in groupRows) {
        if (capReached()) return;
        children.add(buildTile(r));
        renderedAdd(1);
      }
      return;
    }
    final dirBuckets = <String, List<_RoundSummaryRow>>{};
    for (final r in groupRows) {
      final dir = _topDir(r.view.record.filePath);
      dirBuckets.putIfAbsent(dir, () => <_RoundSummaryRow>[]).add(r);
    }
    // 单一目录就别套二级 header。
    if (dirBuckets.length <= 1) {
      for (final r in groupRows) {
        if (capReached()) return;
        children.add(buildTile(r));
        renderedAdd(1);
      }
      return;
    }
    for (final entry in dirBuckets.entries) {
      if (capReached()) return;
      final pathKey = _pathGroupKey(toolName, entry.key);
      final pathCollapsed = _collapsedPathGroups.contains(pathKey);
      children.add(
        _PathSubGroupHeader(
          dir: entry.key,
          count: entry.value.length,
          collapsed: pathCollapsed,
          onToggle: () {
            setState(() {
              if (pathCollapsed) {
                _collapsedPathGroups.remove(pathKey);
              } else {
                _rememberSummaryState(_collapsedPathGroups, pathKey);
              }
            });
          },
        ),
      );
      if (pathCollapsed) continue;
      for (final r in entry.value) {
        if (capReached()) return;
        children.add(buildTile(r));
        renderedAdd(1);
      }
    }
  }

  void _toggleDiffExpanded(_RoundSummaryRow row) {
    final key = _diffKey(row.view.record.recordId);
    setState(() {
      if (_expandedDiffRows.contains(key)) {
        _expandedDiffRows.remove(key);
      } else {
        _rememberSummaryState(_expandedDiffRows, key);
      }
    });
  }
}

class _RoundSummaryRow {
  const _RoundSummaryRow({
    required this.view,
    required this.toolCallId,
    required this.sourceMessageId,
  });
  final FileMutationView view;
  final String toolCallId;
  final String? sourceMessageId;
}

class _RoundSummaryRowTile extends StatelessWidget {
  const _RoundSummaryRowTile({
    required this.row,
    required this.onJump,
    required this.isDiffExpanded,
    required this.onToggleDiff,
  });

  final _RoundSummaryRow row;
  final VoidCallback onJump;
  final bool isDiffExpanded;
  final VoidCallback onToggleDiff;

  IconData _kindIcon() {
    switch (row.view.record.kind) {
      case FileMutationKind.create:
        return Icons.add_circle_outline_rounded;
      case FileMutationKind.modify:
        return Icons.edit_outlined;
      case FileMutationKind.delete:
        return Icons.delete_outline_rounded;
    }
  }

  Color _kindColor(ColorScheme cs) {
    switch (row.view.record.kind) {
      case FileMutationKind.create:
        return _kFileMutationAddedColor;
      case FileMutationKind.modify:
        return cs.primary;
      case FileMutationKind.delete:
        return cs.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final greyOut = row.view.isEffectivelyUndone;
    final tile = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: greyOut
            ? cs.surfaceContainerHighest.withValues(alpha: 0.32)
            : cs.surface.withValues(alpha: 0.55),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(_kindIcon(), size: 15, color: _kindColor(cs)),
          kOpenHandHGap8,
          Expanded(
            child: Tooltip(
              message: row.view.record.filePath,
              waitDuration: kOpenHandTooltipWait,
              child: Text(
                _FileMutationCard._shortenFilePath(row.view.record.filePath),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  color: greyOut
                      ? cs.onSurfaceVariant.withValues(alpha: 0.6)
                      : cs.onSurface,
                  decoration: greyOut ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
          if (row.view.lineDelta.available &&
              row.view.lineDelta.hasChanges) ...[
            kOpenHandHGap8,
            _FileMutationLineDeltaBadge(
              delta: row.view.lineDelta,
              style: _FileMutationLineDeltaStyle.text,
            ),
          ],
          kOpenHandHGap6,
          if (row.sourceMessageId != null)
            _RoundSummarySourceJumpButton(onTap: onJump),
          kOpenHandHGap4,
          _FileMutationRevealPathButton(filePath: row.view.record.filePath),
          // 任意有快照的记录都支持 inline Diff 预览；create/delete
          // 分别以空 before/after 参与 diff，与单个工具调用卡片保持一致。
          if (row.view.record.beforeSha != null ||
              row.view.record.afterSha != null) ...[
            kOpenHandHGap4,
            Tooltip(
              message: openHandLocalizedText(
                context,
                zh: '展开 / 收起 Diff 预览',
                en: 'Expand / collapse diff preview',
              ),
              child: MicroPressFeedback(
                child: InkWell(
                  onTap: onToggleDiff,
                  borderRadius: kOpenHandPillBorderRadius,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: AnimatedRotation(
                      turns: isDiffExpanded ? 0.5 : 0.0,
                      duration: openHandMotionDuration(
                        context,
                        kOpenHandMotion200,
                      ),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final wrapped = RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile,
          AnimatedSize(
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            curve: kOpenHandSwitchInCurve,
            alignment: Alignment.topCenter,
            child: isDiffExpanded
                ? _DiffPreviewBox(
                    key: ValueKey('diff-${row.view.record.recordId}'),
                    record: row.view.record,
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
    return wrapped;
  }
}

class _RoundSummarySourceJumpButton extends StatelessWidget {
  const _RoundSummarySourceJumpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: openHandLocalizedText(
        context,
        zh: '跳转到产生该变动的工具调用',
        en: 'Jump to source tool-call message',
      ),
      child: MicroPressFeedback(
        child: InkResponse(
          onTap: onTap,
          radius: 18,
          containedInkWell: true,
          borderRadius: kOpenHandPillBorderRadius,
          child: SizedBox.square(
            dimension: 28,
            child: Icon(Icons.my_location_rounded, size: 15, color: cs.primary),
          ),
        ),
      ),
    );
  }
}

/// 分组 header — 显示工具名 + 计数 + 折叠箭头。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.toolName,
    required this.count,
    required this.collapsed,
    required this.onToggle,
  });

  final String toolName;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return MicroPressFeedback(
      child: InkWell(
        onTap: onToggle,
        borderRadius: kOpenHandBorderRadius10,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
          child: Row(
            children: [
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0.0,
                duration: openHandMotionDuration(context, kOpenHandMotion200),
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ),
              kOpenHandHGap4,
              Text(
                toolName.isEmpty ? '·' : toolName,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              kOpenHandHGap8,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: kOpenHandPillBorderRadius,
                ),
                child: Text(
                  '$count',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 路径子分组 header — 比 [_GroupHeader] 更轻盈、左侧缩进。
class _PathSubGroupHeader extends StatelessWidget {
  const _PathSubGroupHeader({
    required this.dir,
    required this.count,
    required this.collapsed,
    required this.onToggle,
  });

  final String dir;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return MicroPressFeedback(
      child: InkWell(
        onTap: onToggle,
        borderRadius: kOpenHandBorderRadius8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 6, 2),
          child: Row(
            children: [
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0.0,
                duration: openHandMotionDuration(context, kOpenHandMotion200),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              kOpenHandHGap2,
              Icon(
                Icons.folder_rounded,
                size: 12,
                color: cs.onSurfaceVariant.withValues(alpha: 0.55),
              ),
              kOpenHandHGap4,
              Flexible(
                child: Text(
                  dir,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              kOpenHandHGap6,
              Text(
                '($count)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 行内 Diff 预览 — lazy 加载 before/after blob，交给 Codex 风 viewer
/// 统一渲染行号、增删底色、未修改行折叠条和完整展开。
class _DiffPreviewBox extends StatefulWidget {
  const _DiffPreviewBox({super.key, required this.record});

  final FileMutationRecord record;

  @override
  State<_DiffPreviewBox> createState() => _DiffPreviewBoxState();
}

class _DiffPreviewBoxState extends State<_DiffPreviewBox> {
  Future<({String? before, String? after})>? _diffFuture;
  String? _diffKey;

  @override
  void initState() {
    super.initState();
    _bindFuture();
  }

  @override
  void didUpdateWidget(covariant _DiffPreviewBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindFuture();
  }

  String _keyOf(FileMutationRecord record) =>
      '${record.recordId}|${record.beforeSha ?? ''}|${record.afterSha ?? ''}';

  void _bindFuture() {
    final nextKey = _keyOf(widget.record);
    if (_diffKey == nextKey && _diffFuture != null) return;
    _diffKey = nextKey;
    _diffFuture = _loadMutationDiffSnapshots(context, widget.record);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
      child: FutureBuilder<({String? before, String? after})>(
        future: _diffFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _DiffLoadingPlaceholder(theme: theme, colorScheme: cs);
          }
          final snapshots = snap.data;
          if (snapshots == null ||
              _mutationSnapshotsIncomplete(widget.record, snapshots)) {
            return _DiffEmptyPlaceholder(
              theme: theme,
              colorScheme: cs,
              message: AppLocalizations.of(
                context,
              )!.fileMutationSnapshotUnavailable,
            );
          }
          final before = snapshots.before ?? '';
          final after = snapshots.after ?? '';
          if (before.isEmpty && after.isEmpty) {
            return _DiffEmptyPlaceholder(theme: theme, colorScheme: cs);
          }
          return _CodexDiffViewer(
            record: widget.record,
            before: before,
            after: after,
            previewLineLimit: 18,
          );
        },
      ),
    );
  }
}

class _DiffLoadingPlaceholder extends StatelessWidget {
  const _DiffLoadingPlaceholder({
    required this.theme,
    required this.colorScheme,
  });

  final ThemeData theme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.45),
        borderRadius: kOpenHandBorderRadius10,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.4,
                color: colorScheme.primary,
              ),
            ),
            kOpenHandHGap8,
            Text(
              openHandLocalizedText(
                context,
                zh: '加载 Diff…',
                en: 'Loading diff…',
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffEmptyPlaceholder extends StatelessWidget {
  const _DiffEmptyPlaceholder({
    required this.theme,
    required this.colorScheme,
    this.message,
  });

  final ThemeData theme;
  final ColorScheme colorScheme;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.45),
        borderRadius: kOpenHandBorderRadius10,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          message ?? _homeNoTextualDiffAvailableLabel(context),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
