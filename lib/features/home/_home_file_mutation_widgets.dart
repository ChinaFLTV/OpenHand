part of 'openhand_home_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// _FileMutationRow — shows file-change indicator for write/edit/multiedit tools
// ─────────────────────────────────────────────────────────────────────────────

String _fileMutationKind(AiSessionMessage message) =>
    '${message.metadata['file_mutation_kind'] ?? ''}'.trim();

/// 2026-05-03：聚合「单文件 (`file_mutation_path`)」与「多文件
/// (`file_mutation_paths`)」两路 metadata，去重后按出现顺序返回。
List<String> _fileMutationPaths(AiSessionMessage message) {
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
  return out;
}

/// Codex 风「文件变动」卡片：聚合本工具调用产生的全部 ledger 记录，
/// 提供多文件列表 + 内联 diff + 单条/全部撤销/重做按钮。
///
/// - 撤销 X 时同文件后续记录 (Y/Z) 自动级联失效 → 显示「已被级联撤销」。
/// - 单条「重做」仅恢复自身 after 内容；级联失效条目走「重做」按钮单独
///   恢复，行为与 ledger 语义对齐。
/// - 内联 diff 默认折叠，点击行展开；双击行回退到旧的 [_FileDiffDialog]
///   全屏对比 (兼容历史无 ledger 的会话)。
/// - 全程使用 M3 expressive 配色；动画走 `MediaQuery.disableAnimationsOf`
///   降级。
class _FileMutationCard extends StatefulWidget {
  const _FileMutationCard({required this.message});

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
  final Set<String> _expandedRecordIds = <String>{};
  final Set<String> _busyRecordIds = <String>{};
  final ValueNotifier<int> _pulseSignal = ValueNotifier<int>(0);
  Future<List<FileMutationView>>? _viewsFuture;
  String? _lastSessionId;
  String? _lastToolCallId;
  // 阶段 ⑨b：批量「全部撤销」并发执行 + 进度提示。
  int _bulkUndoTotal = 0;
  int _bulkUndoDone = 0;
  bool get _bulkUndoBusy => _bulkUndoTotal > 0;

  // 阶段 ⑪e：超过 12 条 view 时，先只展开前 _kInitialReveal 条，
  // 后续点「展开剩余 N 条」按需渲染。避免构造 200+ 个 _FileMutationCardRow
  // （每个含可能巨大的 _InlineDiffPanel build closure）。
  static const int _kInitialReveal = 10;
  static const int _kRevealStep = 30;
  int _revealedCount = _kInitialReveal;

  @override
  void dispose() {
    _pulseSignal.dispose();
    super.dispose();
  }

  String get _toolCallId =>
      '${widget.message.metadata['tool_call_id'] ?? ''}'.trim();

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

  void _ensureFutureBound() {
    final ctrl = _ctrl(context);
    final sessionId = ctrl.currentSession?.id ?? '';
    final toolCallId = _toolCallId;
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
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(r.errorMessage.isNotEmpty
              ? r.errorMessage
              : AppLocalizations.of(context)!.fileMutationUndoFailed)),
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
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(r.errorMessage.isNotEmpty
              ? r.errorMessage
              : AppLocalizations.of(context)!.fileMutationRedoFailed)),
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

  /// 阶段 ⑨b / ⑩e：「全部撤销」并发执行 + 进度提示。
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
    // 按文件路径聚合（保留每条原始顺序——遵循 ledger 时间倒序撤销最佳实践）。
    final groups = <String, List<FileMutationView>>{};
    for (final v in candidates) {
      groups.putIfAbsent(v.record.filePath, () => <FileMutationView>[]).add(v);
    }
    setState(() {
      _bulkUndoTotal = candidates.length;
      _bulkUndoDone = 0;
    });
    final ledger = _ctrl(context).toolRuntimeService.mutationLedger;
    const concurrency = 4;
    final paths = groups.keys.toList();
    int nextPath = 0;
    int success = 0;
    int failure = 0;
    String? lastError;

    Future<void> worker() async {
      while (true) {
        final i = nextPath++;
        if (i >= paths.length) return;
        final groupViews = groups[paths[i]]!;
        // 同文件内：串行撤销，避免并发覆写。
        for (final v in groupViews) {
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
          } catch (e) {
            failure++;
            lastError = e.toString();
          } finally {
            if (mounted) setState(() => _bulkUndoDone++);
          }
        }
      }
    }

    final workerCount =
        paths.length < concurrency ? paths.length : concurrency;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    if (!mounted) return;
    setState(() {
      _bulkUndoTotal = 0;
      _bulkUndoDone = 0;
    });
    if (success > 0) _pulseSignal.value += 1;
    _refresh();
    if (failure > 0) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            lastError != null && lastError!.isNotEmpty
                ? '${l10n.fileMutationUndoFailed} ($failure): $lastError'
                : '${l10n.fileMutationUndoFailed} ($failure)',
          ),
        ),
      );
    }
  }

  /// 阶段 ⑦c：聚合当前 toolCall 涉及的所有 view 的 before/after 内容，
  /// 拼成 `# <path>\n```diff\n<unified diff>\n```` 的合并 markdown 写入剪贴板。
  /// 任意 blob 读取失败的条目以 `<missing>` 占位，保持其它项可用。
  Future<void> _copyAllDiff(List<FileMutationView> views) async {
    if (views.isEmpty) return;
    final ledger = _ctrl(context).toolRuntimeService.mutationLedger;
    // 阶段 ⑬c：尊重 LedgerConfig.miniDiffMaxBytes——超过阈值时
    // 复制出去的合并 diff 也走 mini-diff（仅 +/- 行），避免大文件
    // 把剪贴板/聊天上下文撑爆。
    final config = await ledger.loadConfig();
    final buf = StringBuffer();
    for (final v in views) {
      final r = v.record;
      buf.writeln('# ${r.filePath}');
      final before = r.beforeSha == null
          ? ''
          : (await ledger.readBlob(r.beforeSha!) ?? '<missing>');
      final after = r.afterSha == null
          ? ''
          : (await ledger.readBlob(r.afterSha!) ?? '<missing>');
      buf.writeln('```diff');
      buf.writeln(
        unifiedDiffLineSummary(
          before,
          after,
          beforeSha: r.beforeSha,
          afterSha: r.afterSha,
          miniDiffMaxBytes: config.miniDiffMaxBytes,
        ),
      );
      buf.writeln('```');
      buf.writeln();
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.fileMutationCopyAllDiffDone,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 阶段 ⑩a：把当前会话的 `sessions/<id>/ledger.jsonl` 在系统文件管理器
  /// 里高亮（macOS `open -R` / Windows `explorer.exe /select,` /
  /// Linux 退化到打开父目录）。文件不存在时退化到打开 ledger 根目录。
  Future<void> _revealLedgerFile() async {
    final ctrl = _ctrl(context);
    final sessionId = ctrl.currentSession?.id ?? '';
    if (sessionId.isEmpty) return;
    final ledger = ctrl.toolRuntimeService.mutationLedger;
    final file = ledger.ledgerFileFor(sessionId);
    final target = await file.exists() ? file.path : file.parent.path;
    try {
      if (Platform.isMacOS) {
        await runProcessWithTimeout('open', <String>['-R', target],
            tag: 'file_mutation_card.reveal');
      } else if (Platform.isWindows) {
        await runProcessWithTimeout(
            'explorer.exe', <String>['/select,$target'],
            tag: 'file_mutation_card.reveal');
      } else {
        final dir = await file.exists() ? file.parent.path : target;
        await runProcessWithTimeout('xdg-open', <String>[dir],
            tag: 'file_mutation_card.reveal');
      }
    } catch (error, stack) {
      silentLog('file_mutation_card', '_revealLedgerFile', error, stack);
    }
  }

  /// 阶段 ⑪a：当前会话维度的 History Inspector dialog。展示该 session
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
    setState(() {
      if (!_expandedRecordIds.add(recordId)) {
        _expandedRecordIds.remove(recordId);
      }
    });
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
          // 阶段 ⑩d：FileMutationCard 走 AppearOnce 入场（fade + 12px 上滑）。
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
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.difference_rounded,
                  size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!
                    .fileMutationFilesChanged(paths.length),
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final p in paths)
            InkWell(
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              onTap: () => _showLegacyDiff(p, mutKind),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file_outlined,
                        size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _FileMutationCard._shortenFilePath(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.45)),
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
    int totalAdded = 0;
    int totalRemoved = 0;
    for (final v in views) {
      // approx：用 size 差近似（精确 +/- 行数等展开时算）。
      final delta = v.record.afterSize - v.record.beforeSize;
      if (delta > 0) {
        totalAdded += 1;
      } else if (delta < 0) {
        totalRemoved += 1;
      }
    }
    final anyUndoable = views.any((v) => v.canUndo);
    final anyRedoable = views.any((v) => v.canRedo);
    // 阶段 ⑮c：卡内 Cmd/Ctrl+Z 撤销最近一条、Shift+Cmd/Ctrl+Z 重做。
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
        const SingleActivator(LogicalKeyboardKey.keyZ,
            meta: true, shift: true): const _RedoLastIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): const _RedoLastIntent(),
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
        borderRadius: const BorderRadius.all(Radius.circular(16)),
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
            message: AppLocalizations.of(context)!.fileMutationRevealLedger,
            waitDuration: const Duration(milliseconds: 600),
            child: InkWell(
              onTap: _revealLedgerFile,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Icon(Icons.difference_rounded,
                    size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.fileMutationSection,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                _StatPill(
                  label: AppLocalizations.of(context)!
                      .fileMutationFilesCount(views.length),
                  color: cs.onSurfaceVariant,
                  bg: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                ),
                if (totalAdded > 0) ...[
                  const SizedBox(width: 6),
                  _StatPill(
                    label: '+$totalAdded',
                    color: const Color(0xFF2E7D32),
                    bg: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                  ),
                ],
                if (totalRemoved > 0) ...[
                  const SizedBox(width: 6),
                  _StatPill(
                    label: '-$totalRemoved',
                    color: cs.error,
                    bg: cs.errorContainer.withValues(alpha: 0.55),
                  ),
                ],
                // 阶段 ⑨b：批量撤销进度 chip。
                if (_bulkUndoBusy) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      value: _bulkUndoTotal == 0
                          ? null
                          : _bulkUndoDone / _bulkUndoTotal,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$_bulkUndoDone/$_bulkUndoTotal',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                const Spacer(),
                if (anyUndoable && !_bulkUndoBusy)
                  _IconActionButton(
                    icon: Icons.undo_rounded,
                    tooltip: AppLocalizations.of(context)!.fileMutationUndoAll,
                    onTap: () => _undoAll(views),
                  ),
                if (anyRedoable)
                  _IconActionButton(
                    icon: Icons.refresh_rounded,
                    tooltip: AppLocalizations.of(context)!.fileMutationRefresh,
                    onTap: _refresh,
                  ),
                _IconActionButton(
                  icon: Icons.copy_all_rounded,
                  tooltip:
                      AppLocalizations.of(context)!.fileMutationCopyAllDiff,
                  onTap: () => _copyAllDiff(views),
                ),
                // 阶段 ⑪a：把当前会话所有 ledger 记录（含其他卡未展示的）
                // 在 dialog 里按文件分组俯瞰，便于跨 toolCall 排查。
                _IconActionButton(
                  icon: Icons.history_rounded,
                  tooltip: AppLocalizations.of(context)!
                      .fileMutationHistoryInspector,
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
          // 阶段 ⑪e：渐进式展开。views 多时只构造前 _revealedCount 条，
          // 余下用一行「展开剩余 N 条」按钮兜底，按需 +30 / 全展开。
          // 阶段 ⑮b：≥6 行时给主卡首批行加一次 60ms 步进的 drip-in
          // 入场，与 inspector 同源 _DelayedAppear；reduceMotion 下退化。
          for (int i = 0; i < views.length && i < _revealedCount; i++)
            Builder(builder: (rowCtx) {
              final reduceMotion =
                  MediaQuery.maybeDisableAnimationsOf(rowCtx) ?? false;
              final shouldDrip = !reduceMotion && views.length >= 6;
              final row = _FileMutationCardRow(
                view: views[i],
                expanded:
                    _expandedRecordIds.contains(views[i].record.recordId),
                busy: _busyRecordIds.contains(views[i].record.recordId),
                onToggleExpand: () => _toggleExpand(views[i].record.recordId),
                onUndo: () => _undo(views[i]),
                onRedo: () => _redo(views[i]),
                onOpenLegacyDialog: () => _showLegacyDiff(
                  views[i].record.filePath,
                  _fileMutationKind(widget.message),
                ),
                onRevealLedger: _revealLedgerFile,
                onCopyDiff: () => _copyAllDiff([views[i]]),
                onOpenInspector: _openHistoryInspector,
              );
              if (!shouldDrip) return row;
              return _DelayedAppear(
                delay: Duration(milliseconds: (i * 60).clamp(0, 720)),
                child: row,
              );
            }),
          if (views.length > _revealedCount)
            _RevealMoreRow(
              remaining: views.length - _revealedCount,
              onRevealStep: () => setState(() {
                _revealedCount = (_revealedCount + _kRevealStep)
                    .clamp(0, views.length);
              }),
              onRevealAll: () =>
                  setState(() => _revealedCount = views.length),
            ),
        ],
      ),
    ),
        // 阶段 ⑦e：每次 undo/redo 成功在卡顶发一次温和的 highlight pulse；
        // HighlightPulse 自带 reduceMotion 守门，不需要我们再 gate。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(child: HighlightPulse(signal: _pulseSignal)),
        ),
        // 阶段 ⑬b：批量 undo 进行中——卡片整体覆 BackdropFilter blur 6px
        // + primary 色 tinted glow，进度环居中。AnimatedSwitcher 220ms 淡入
        // 淡出，reduceMotion 时退化为 0ms。
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_bulkUndoBusy,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
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
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    showAnimatedDialog(
      context: context,
      builder: (ctx) =>
          _FileDiffDialog(filePath: path, changeKind: kind, isZh: isZh),
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
      decoration: BoxDecoration(color: bg, borderRadius: _borderRadius999),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
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
        borderRadius: _borderRadius999,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
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
    required this.onRevealLedger,
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
  final VoidCallback onRevealLedger;
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
        return const Color(0xFF2E7D32);
      case FileMutationKind.modify:
        return cs.primary;
      case FileMutationKind.delete:
        return cs.error;
    }
  }

  /// 阶段 ⑬d：长按 / 右键弹出 ContextMenu，便利动作集中暴露：
  /// reveal in OS / copy path / copy diff / open inspector / jump-to-toolcall。
  Future<void> _showRowContextMenu(
    BuildContext context, {
    Offset? position,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox?;
    final origin = position ??
        (box?.localToGlobal(box.size.center(Offset.zero)) ?? Offset.zero);
    final l10n = AppLocalizations.of(context)!;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(origin.dx, origin.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'reveal',
          child: Row(children: [
            const Icon(Icons.folder_open_outlined, size: 16),
            const SizedBox(width: 8),
            Text(l10n.fileMutationRevealLedger),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'copyPath',
          child: Row(children: [
            const Icon(Icons.content_copy_rounded, size: 16),
            const SizedBox(width: 8),
            Text(l10n.fileMutationCopyPath),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'copyDiff',
          child: Row(children: [
            const Icon(Icons.difference_rounded, size: 16),
            const SizedBox(width: 8),
            Text(l10n.fileMutationCopyAllDiff),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'inspector',
          child: Row(children: [
            const Icon(Icons.history_rounded, size: 16),
            const SizedBox(width: 8),
            Text(l10n.fileMutationHistoryInspector),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'diff',
          child: Row(children: [
            const Icon(Icons.open_in_new_rounded, size: 16),
            const SizedBox(width: 8),
            Text(_localizedTextStatic(context,
                zh: '打开 diff 对话框', en: 'Open diff dialog')),
          ]),
        ),
      ],
    );
    if (selected == null) return;
    switch (selected) {
      case 'reveal':
        onRevealLedger();
        break;
      case 'copyPath':
        if (context.mounted) {
          _copyPathToClipboard(context, view.record.filePath);
        }
        break;
      case 'copyDiff':
        onCopyDiff();
        break;
      case 'inspector':
        onOpenInspector();
        break;
      case 'diff':
        onOpenLegacyDialog();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final greyOut = view.isEffectivelyUndone;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: greyOut
            ? cs.surfaceContainerHighest.withValues(alpha: 0.32)
            : Colors.transparent,
      ),
      child: AnimatedSlide(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        offset: Offset(view.cascadeUndone ? 0.025 : 0.0, 0.0),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 阶段 ⑫a：键盘导航——
          // - Up/Down 在 row 间走 Directional focus；
          // - Space 切换 expand；
          // - Enter 打开 legacy diff dialog。
          FocusableActionDetector(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.space):
                  ActivateIntent(),
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
              onDoubleTap: onOpenLegacyDialog,
              onLongPress: () => _showRowContextMenu(context),
              onSecondaryTapDown: (d) =>
                  _showRowContextMenu(context, position: d.globalPosition),
              // 阶段 ⑩c：row hover 背景轻微高亮，让指针落点更清晰。
              hoverColor: cs.primary.withValues(alpha: 0.05),
              splashColor: cs.primary.withValues(alpha: 0.10),
              highlightColor: cs.primary.withValues(alpha: 0.06),
              focusColor: cs.primary.withValues(alpha: 0.12),
              child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Opacity(
                opacity: greyOut ? 0.55 : 1.0,
                child: Row(
                  children: [
                    AnimatedRotation(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      turns: expanded ? 0.25 : 0,
                      child: Icon(Icons.chevron_right_rounded,
                          size: 18, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 6),
                    Icon(_kindIcon, size: 14, color: _kindColor(cs)),
                    const SizedBox(width: 6),
                    Expanded(
                      // 阶段 ⑩b：hover 显示完整路径，右键 / Ctrl-长按复制路径。
                      child: Tooltip(
                        message: view.record.filePath,
                        waitDuration: const Duration(milliseconds: 500),
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onSecondaryTap: () => _copyPathToClipboard(
                              context, view.record.filePath),
                          onLongPress: () => _copyPathToClipboard(
                              context, view.record.filePath),
                          child: Text(
                            _FileMutationCard
                                ._shortenFilePath(view.record.filePath),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
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
                      const SizedBox(width: 6),
                      _StatPill(
                        label: AppLocalizations.of(context)!.fileMutationUndone,
                        color: cs.onSurfaceVariant,
                        bg: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      ),
                    ],
                    if (view.cascadeUndone) ...[
                      const SizedBox(width: 6),
                      _StatPill(
                        label: AppLocalizations.of(context)!
                            .fileMutationCascadeUndone,
                        color: cs.tertiary,
                        bg: cs.tertiaryContainer.withValues(alpha: 0.55),
                      ),
                    ],
                    const SizedBox(width: 8),
                    if (busy)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    else if (view.canUndo)
                      _IconActionButton(
                        icon: Icons.undo_rounded,
                        tooltip:
                            AppLocalizations.of(context)!.fileMutationUndoThis,
                        onTap: onUndo,
                      )
                    else if (view.canRedo)
                      _IconActionButton(
                        icon: Icons.redo_rounded,
                        tooltip: AppLocalizations.of(context)!.fileMutationRedo,
                        onTap: onRedo,
                      ),
                  ],
                ),
              ),
            ),
          ),
          ),
          AnimatedSize(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
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
      padding: const EdgeInsets.fromLTRB(40, 4, 12, 12),
      child: FutureBuilder<({String? before, String? after})>(
        future: _future,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            );
          }
          final before = snap.data!.before ?? '';
          final after = snap.data!.after ?? '';
          if (before.isEmpty && after.isEmpty) {
            return Text(
              AppLocalizations.of(context)!.fileMutationSnapshotUnavailable,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            );
          }
          final diff = _computeUnifiedDiffLines(before, after);
          // 阶段 ⑪b：复用 _CodeSyntaxHighlighter 给 diff 行加 token 着色。
          // 缓存命中：相同 record（即 sha pair）在同一 brightness 下复用整段
          // TextSpan，rebuild（hover/expand/收起）不再重新 tokenize。
          final brightness = theme.brightness;
          final isDark = brightness == Brightness.dark;
          final lang = _languageFromFilePath(widget.view.record.filePath);
          final baseStyle = theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.5,
                fontSize: 11.5,
              ) ??
              const TextStyle(fontFamily: 'monospace', fontSize: 11.5);
          final cacheKey =
              ('diff::${widget.view.record.recordId}::${brightness.name}::'
                      '${widget.view.record.beforeSha ?? "_"}::${widget.view.record.afterSha ?? "_"}::'
                      '${lang ?? "_"}')
                  .hashCode;
          var rootSpan = _highlightSpanCache.get(cacheKey);
          if (rootSpan == null) {
            final highlighter = _CodeSyntaxHighlighter(
              baseStyle: baseStyle,
              darkSurface: isDark,
            );
            final children = <InlineSpan>[];
            for (final l in diff) {
              Color? bg;
              Color? fg;
              String prefix = '';
              String code = l;
              if (l.startsWith('+')) {
                bg = cs.primaryContainer.withValues(alpha: 0.32);
                fg = cs.onPrimaryContainer;
                prefix = '+';
                code = l.length > 2 ? l.substring(2) : '';
              } else if (l.startsWith('-')) {
                bg = cs.errorContainer.withValues(alpha: 0.30);
                fg = cs.onErrorContainer;
                prefix = '-';
                code = l.length > 2 ? l.substring(2) : '';
              } else if (l.startsWith('  ')) {
                code = l.substring(2);
                prefix = '  ';
              }
              final lineStyle = TextStyle(backgroundColor: bg, color: fg);
              final lineChildren = <InlineSpan>[
                if (prefix.isNotEmpty)
                  TextSpan(text: prefix.length == 1 ? '$prefix ' : prefix),
              ];
              if (code.isEmpty) {
                lineChildren.add(const TextSpan(text: ''));
              } else {
                // tokenize 单行；文件巨大时 _CodeSyntaxHighlighter 内部已防 nullable
                lineChildren.add(highlighter.build(code, language: lang));
              }
              lineChildren.add(const TextSpan(text: '\n'));
              children.add(TextSpan(style: lineStyle, children: lineChildren));
            }
            rootSpan = TextSpan(style: baseStyle, children: children);
            _highlightSpanCache.put(cacheKey, rootSpan);
          }
          return Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.6),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.45),
                width: 0.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: SelectableText.rich(rootSpan),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<({String? before, String? after})> _load(
      FileMutationView v) async {
    final ledger = context.read<AiSessionController>().toolRuntimeService.mutationLedger;
    final before = v.record.beforeSha == null
        ? null
        : await ledger.readBlob(v.record.beforeSha!);
    final after = v.record.afterSha == null
        ? null
        : await ledger.readBlob(v.record.afterSha!);
    return (before: before, after: after);
  }
}

/// 阶段 ⑪b：从文件路径推断 highlight.dart 用的语言名（小写）。无后缀
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

/// 阶段 ⑩b：把 `filePath` 写入剪贴板并 SnackBar 提示。统一从 Row 的右键
/// / 长按手势调用，因此抽到顶层而非 row state。
Future<void> _copyPathToClipboard(BuildContext context, String filePath) async {
  await Clipboard.setData(ClipboardData(text: filePath));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(AppLocalizations.of(context)!.fileMutationPathCopied),
      duration: const Duration(seconds: 2),
    ),
  );
}

/// 简易 LCS-based unified diff（与 [_FileDiffDialogState._computeSimpleDiff]
/// 同语义，复制以避免跨私有 State 调用）。
List<String> _computeUnifiedDiffLines(String before, String after) {
  final beforeLines = const LineSplitter().convert(before);
  final afterLines = const LineSplitter().convert(after);
  final lcs = _lcs(beforeLines, afterLines);
  final out = <String>[];
  int bi = 0, ai = 0, li = 0;
  while (bi < beforeLines.length || ai < afterLines.length) {
    if (li < lcs.length &&
        bi < beforeLines.length &&
        ai < afterLines.length &&
        beforeLines[bi] == lcs[li] &&
        afterLines[ai] == lcs[li]) {
      out.add('  ${lcs[li]}');
      bi++;
      ai++;
      li++;
    } else {
      while (bi < beforeLines.length &&
          (li >= lcs.length || beforeLines[bi] != lcs[li])) {
        out.add('- ${beforeLines[bi]}');
        bi++;
      }
      while (ai < afterLines.length &&
          (li >= lcs.length || afterLines[ai] != lcs[li])) {
        out.add('+ ${afterLines[ai]}');
        ai++;
      }
    }
  }
  return out;
}

List<String> _lcs(List<String> a, List<String> b) {
  final m = a.length, n = b.length;
  final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
  for (int i = 1; i <= m; i++) {
    for (int j = 1; j <= n; j++) {
      if (a[i - 1] == b[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }
  final lcs = <String>[];
  int i = m, j = n;
  while (i > 0 && j > 0) {
    if (a[i - 1] == b[j - 1]) {
      lcs.insert(0, a[i - 1]);
      i--;
      j--;
    } else if (dp[i - 1][j] > dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  return lcs;
}

// ─────────────────────────────────────────────────────────────────────────────
// _FileDiffDialog — displays file content diff when file change card is tapped
// ─────────────────────────────────────────────────────────────────────────────

class _FileDiffDialog extends StatefulWidget {
  const _FileDiffDialog({
    required this.filePath,
    required this.changeKind,
    required this.isZh,
  });

  final String filePath;
  final String changeKind;
  final bool isZh;

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
        if (await file.exists()) {
          final content = await file.readAsString();
          if (!mounted) return;
          setState(() {
            _beforeContent = null;
            _afterContent = content;
            _loading = false;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _error = widget.isZh ? '没有保存的版本历史' : 'No saved version history';
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
      if (await currentFile.exists()) {
        afterContent = await currentFile.readAsString();
      }

      if (!mounted) return;
      setState(() {
        _beforeContent = beforeContent;
        _afterContent = afterContent;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyFileDiffError(e, isZh: widget.isZh);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 640),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isZh ? '文件变更对比' : 'File Diff',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _FileMutationCard._shortenFilePath(widget.filePath),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
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
                      tooltip: widget.isZh ? '关闭' : 'Close',
                    ),
                  ],
                ),
              ),

              // Diff content
              Expanded(
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiffView(ThemeData theme, ColorScheme colorScheme) {
    // Compute line-by-line diff.
    final diff = _computeSimpleDiff(_beforeContent ?? '', _afterContent ?? '');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText.rich(
        TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
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

  /// Compute a simple unified diff from before/after content.
  List<String> _computeSimpleDiff(String before, String after) {
    final beforeLines = const LineSplitter().convert(before);
    final afterLines = const LineSplitter().convert(after);
    final result = <String>[];

    // Simple LCS-based diff (good enough for small files).
    final lcs = _longestCommonSubsequence(beforeLines, afterLines);

    int bi = 0, ai = 0, li = 0;
    while (bi < beforeLines.length || ai < afterLines.length) {
      if (li < lcs.length &&
          bi < beforeLines.length &&
          ai < afterLines.length &&
          beforeLines[bi] == lcs[li] &&
          afterLines[ai] == lcs[li]) {
        result.add('  ${lcs[li]}');
        bi++;
        ai++;
        li++;
      } else {
        // Removed lines from before
        while (bi < beforeLines.length &&
            (li >= lcs.length || beforeLines[bi] != lcs[li])) {
          result.add('- ${beforeLines[bi]}');
          bi++;
        }
        // Added lines in after
        while (ai < afterLines.length &&
            (li >= lcs.length || afterLines[ai] != lcs[li])) {
          result.add('+ ${afterLines[ai]}');
          ai++;
        }
      }
    }

    return result;
  }

  /// Compute LCS for line-by-line comparison.
  List<String> _longestCommonSubsequence(List<String> a, List<String> b) {
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    // Backtrack to find LCS
    final lcs = <String>[];
    int i = m, j = n;
    while (i > 0 && j > 0) {
      if (a[i - 1] == b[j - 1]) {
        lcs.insert(0, a[i - 1]);
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }
    return lcs;
  }
}

/// 阶段 ⑪e：FileMutationCard 渐进式展开尾部按钮。
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
            const SizedBox(width: 8),
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
// 阶段 ⑪a：File Mutation History Inspector dialog
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
  // 阶段 ⑫b：单路径 zoom 模式。group header 双击进入，仅展示该 path
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
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
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
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            // 阶段 ⑫b：zoom 模式提示条 + 退出按钮
            if (_zoomedPath != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: InputChip(
                  avatar: Icon(Icons.center_focus_strong_rounded,
                      size: 14, color: cs.primary),
                  label: Text(
                    _zoomedPath!,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                  onDeleted: () => setState(() => _zoomedPath = null),
                ),
              ),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.45),
            ),
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
                          .where((v) => v.record.filePath
                              .toLowerCase()
                              .contains(_filter.toLowerCase()))
                          .toList(growable: false);
                  // 阶段 ⑫b：zoom 模式 → 只保留该路径
                  final visible = _zoomedPath == null
                      ? filtered
                      : filtered
                          .where((v) => v.record.filePath == _zoomedPath)
                          .toList(growable: false);
                  if (visible.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.fileMutationHistoryInspectorEmpty,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ),
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
                  // 阶段 ⑬a：分组 staggered AppearOnce——
                  // 80ms/张，封顶 1.2s（reduceMotion 跳过）。
                  final reduceMotion =
                      MediaQuery.disableAnimationsOf(context);
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
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(MaterialLocalizations.of(context)
                        .closeButtonLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                top: Radius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file_outlined,
                        size: 14, color: cs.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Tooltip(
                        message: filePath,
                        waitDuration: const Duration(milliseconds: 500),
                        child: Text(
                          filePath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontFamily: 'monospace',
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
                    const SizedBox(width: 4),
                    // 阶段 ⑬e：聚合 +X / -Y 字节增减徽章。
                    () {
                      var added = 0;
                      var removed = 0;
                      for (final v in entries) {
                        final d = v.record.afterSize - v.record.beforeSize;
                        if (d > 0) added += d;
                        if (d < 0) removed += -d;
                      }
                      final pieces = <Widget>[];
                      if (added > 0) {
                        pieces.add(Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+${_compactBytes(added)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF2E7D32),
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ));
                      }
                      if (removed > 0) {
                        if (pieces.isNotEmpty) {
                          pieces.add(const SizedBox(width: 4));
                        }
                        pieces.add(Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '-${_compactBytes(removed)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.error,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ));
                      }
                      if (pieces.isEmpty) return const SizedBox.shrink();
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...pieces,
                          const SizedBox(width: 6),
                        ],
                      );
                    }(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        l10n.fileMutationFilesCount(entries.length),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.primary),
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
            for (final v in entries)
              _InspectorEntryRow(view: v),
          ],
        ),
      ),
    );
  }

  static String _formatTimestamp(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }
}

/// 阶段 ⑮d：inspector 单条记录行——长按 / 右键弹「复制 record JSON」。
class _InspectorEntryRow extends StatelessWidget {
  const _InspectorEntryRow({required this.view});
  final FileMutationView view;

  Future<void> _showRecordMenu(BuildContext context, Offset globalPos) async {
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    if (overlay == null) return;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'copy_json',
          child: Row(
            children: [
              const Icon(Icons.data_object_rounded, size: 16),
              const SizedBox(width: 8),
              Text(isZh ? '复制此条记录 JSON' : 'Copy record JSON'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy_id',
          child: Row(
            children: [
              const Icon(Icons.tag_rounded, size: 16),
              const SizedBox(width: 8),
              Text(isZh ? '复制 record ID' : 'Copy record ID'),
            ],
          ),
        ),
      ],
    );
    if (!context.mounted) return;
    if (selected == 'copy_json') {
      final json = jsonEncode(view.record.toJson());
      await Clipboard.setData(ClipboardData(text: json));
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(isZh ? '已复制 record JSON' : 'Copied record JSON'),
          ),
        );
      }
    } else if (selected == 'copy_id') {
      await Clipboard.setData(
        ClipboardData(text: view.record.recordId),
      );
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(isZh ? '已复制 record ID' : 'Copied record ID'),
          ),
        );
      }
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
      onSecondaryTapDown: (d) =>
          _showRecordMenu(context, d.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            _RecordKindBadge(kind: view.record.kind),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                view.record.toolName,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _HistoryInspectorGroup._formatTimestamp(view.record.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            if (view.directlyUndone)
              Tooltip(
                message: l10n.fileMutationUndone,
                child: Icon(Icons.undo_rounded,
                    size: 14, color: cs.onSurfaceVariant),
              )
            else if (view.cascadeUndone)
              Tooltip(
                message: l10n.fileMutationCascadeUndone,
                child: Icon(Icons.link_off_rounded,
                    size: 14, color: cs.onSurfaceVariant),
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
      FileMutationKind.modify => (
        Icons.edit_outlined,
        cs.tertiary,
        'modify',
      ),
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
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
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

/// 阶段 ⑫a：FileMutationCard row 键盘 Enter 触发的 Intent。
class _OpenLegacyDialogIntent extends Intent {
  const _OpenLegacyDialogIntent();
}

/// 阶段 ⑮c：卡内 Cmd/Ctrl+Z 撤销最近一条记录。
class _UndoLastIntent extends Intent {
  const _UndoLastIntent();
}

/// 阶段 ⑮c：卡内 Shift+Cmd/Ctrl+Z 重做最近一条记录。
class _RedoLastIntent extends Intent {
  const _RedoLastIntent();
}

/// 阶段 ⑮e：inspector 分组卡 hover 微抬升——
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

class _HoverElevateBoxState extends State<_HoverElevateBox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dur = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: dur,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: widget.baseColor,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: _hover ? widget.hoverBorder : widget.baseBorder,
            width: _hover ? 0.8 : 0.5,
          ),
          boxShadow: _hover
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

/// 阶段 ⑬a：在 [delay] 之前显示透明占位（保持高度通过 child build），
/// 之后再用 AppearOnce 包裹 child 实现 staggered fade-in。这里通过
/// FutureBuilder + KeyedSubtree 让每个分组卡的 enter 动画错峰。
class _DelayedAppear extends StatefulWidget {
  const _DelayedAppear({required this.delay, required this.child});
  final Duration delay;
  final Widget child;

  @override
  State<_DelayedAppear> createState() => _DelayedAppearState();
}

class _DelayedAppearState extends State<_DelayedAppear> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay <= Duration.zero) {
      _show = true;
    } else {
      Future<void>.delayed(widget.delay, () {
        if (!mounted) return;
        setState(() => _show = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return Opacity(opacity: 0, child: widget.child);
    return AppearOnce(child: widget.child);
  }
}

/// 阶段 ⑬b：批量 undo overlay。BackdropFilter blur 6px + primary 色
/// tinted glow 渐变背景 + 圆形进度环 + 「N/M」百分比文案。淡入淡出由
/// 外层 AnimatedSwitcher 控制。
class _BulkUndoOverlay extends StatelessWidget {
  const _BulkUndoOverlay({
    super.key,
    required this.done,
    required this.total,
  });
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = total == 0 ? null : done / total;
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
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
                  backgroundColor:
                      cs.primary.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 8),
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

/// 阶段 ⑬d：part 文件内简易 zh/en 文案选择器（避免给 5 个 ⑬d 文案
/// 单独跑一轮 ARB → gen_l10n）。
String _localizedTextStatic(BuildContext context,
    {required String zh, required String en}) {
  final lang = Localizations.localeOf(context).languageCode;
  return lang == 'zh' ? zh : en;
}

/// 阶段 ⑬e：徽章用紧凑字节格式（B / KiB / MiB），保持单字符精度。
String _compactBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) {
    final kb = bytes / 1024;
    return kb >= 100 ? '${kb.round()}KiB' : '${kb.toStringAsFixed(1)}KiB';
  }
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(1)}MiB';
}

// ─────────────────────────────────────────────────────────────────────────────
// 阶段⑰ —— 本轮文件变动汇总卡（_RoundFileMutationSummaryCard）
//
// 当 AssistantTurn 末尾 (`result.toolCalls.isEmpty`) 触发时，controller 已
// 写入一条 metadata 含 `round_file_mutation_summary == true` 的 status
// 消息。这里把该消息渲染为一张「Codex 风总览卡」：
//
// - 仅展示本轮真正产生 ledger 记录的 toolCallId（controller 已预筛）。
// - 行级 dedup 单元 = (filePath × toolCallId)；同一文件被多次 Edit/Write
//   会出现多行，每行带独立「跳转到来源消息」按钮，跳转通过
//   `_MessageBubbleObjectKey(messageId).currentContext` + `Scrollable
//   .ensureVisible(alignment:0.18, duration:520ms, easeOutCubic)` 实现 Q
//   弹丝滑滚动；目标在大会话里被 ListView 释放时回退到滚轨估算。
// - reduceMotion 下所有过渡退化为瞬时；Drip-in 入场不超过 6 行的延迟。
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
  // 阶段⑰c：批量「撤销本轮」并发执行进度。
  int _bulkUndoTotal = 0;
  int _bulkUndoDone = 0;
  bool get _bulkUndoBusy => _bulkUndoTotal > 0;
  final ValueNotifier<int> _pulseSignal = ValueNotifier<int>(0);
  // 阶段⑰d：折叠记忆 — 跨重建保留每张卡的「哪些组被收起 / 哪些 Diff 被展开」。
  // key = '${messageId}::${toolName}'，进程级缓存即可，无需持久化到磁盘。
  static final Set<String> _collapsedGroups = <String>{};
  static final Set<String> _expandedDiffRows = <String>{};
  // 阶段⑱a：按路径前缀的二级分组折叠记忆。key = `${msgId}::${toolName}::${dir}`。
  static final Set<String> _collapsedPathGroups = <String>{};
  // 阶段⑱a：超过 _virtualRowCap 时仅展示前 N 行；记忆"已展开"消息。
  static final Set<String> _expandedFullList = <String>{};
  static const int _virtualRowCap = 30;
  static const int _pathSubgroupThreshold = 8;

  String _groupKey(String toolName) => '${widget.message.id}::$toolName';
  String _diffKey(String recordId) => '${widget.message.id}#$recordId';
  String _pathGroupKey(String toolName, String dir) =>
      '${widget.message.id}::$toolName::$dir';

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

  Future<List<_RoundSummaryRow>> _load(BuildContext ctx) async {
    final ctrl = ctx.read<AiSessionController>();
    final sessionId = ctrl.currentSession?.id ?? '';
    if (sessionId.isEmpty) return const <_RoundSummaryRow>[];
    final ledger = ctrl.toolRuntimeService.mutationLedger;
    // 反向索引 toolCallId → 对应 toolCall message.id（用于跳转）。
    final session = ctrl.currentSession;
    final toolCallMessageIdByCallId = <String, String>{};
    if (session != null) {
      for (final m in session.messages) {
        if (m.kind != AiSessionMessageKind.toolCall) continue;
        final id = '${m.metadata['tool_call_id'] ?? ''}'.trim();
        if (id.isNotEmpty) toolCallMessageIdByCallId[id] = m.id;
      }
    }
    final ids = _toolCallIds;
    final rows = <_RoundSummaryRow>[];
    final seen = <String>{}; // (filePath|toolCallId) dedup
    for (final tcId in ids) {
      List<FileMutationView> views;
      try {
        views = await ledger.viewsForToolCall(
          sessionId: sessionId,
          toolCallId: tcId,
        );
      } catch (error, stack) {
        silentLog('round_summary_card', 'viewsForToolCall', error, stack);
        continue;
      }
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
    rows.sort((a, b) =>
        a.view.record.createdAt.compareTo(b.view.record.createdAt));
    return rows;
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
    final ctrl = context.read<AiSessionController>();
    final sessionId = ctrl.currentSession?.id ?? '';
    if (sessionId.isEmpty) return;
    final ok = await _TranscriptScrollDispatcher.instance.scrollToMessage(
      sessionId,
      messageId,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2200),
          content: Text(
            _localizedTextStatic(context,
                zh: '未能定位来源消息（可能已被删除）。',
                en: 'Could not locate source message (may have been deleted).'),
          ),
        ),
      );
    }
  }

  /// 阶段⑰c：「全部撤销本轮」批量入口。
  /// 按 filePath 聚合 → 同文件严格串行（避免互相覆盖磁盘内容），
  /// 跨文件 4 路并行；进度打到 header chip 与中央 overlay；完成后
  /// 单次 reload + highlight pulse；任意失败 SnackBar 报最后一次错误。
  Future<void> _undoAllRound(List<_RoundSummaryRow> rows) async {
    if (_bulkUndoBusy) return;
    final candidates = rows.where((r) => r.view.canUndo).toList(growable: false);
    if (candidates.isEmpty) return;
    final groups = <String, List<_RoundSummaryRow>>{};
    for (final r in candidates) {
      groups.putIfAbsent(r.view.record.filePath, () => <_RoundSummaryRow>[])
          .add(r);
    }
    setState(() {
      _bulkUndoTotal = candidates.length;
      _bulkUndoDone = 0;
    });
    final ledger = context.read<AiSessionController>().toolRuntimeService
        .mutationLedger;
    String? lastError;
    const concurrency = 4;
    final paths = groups.keys.toList();
    int nextPath = 0;
    Future<void> worker() async {
      while (true) {
        if (!mounted) return;
        if (nextPath >= paths.length) return;
        final p = paths[nextPath];
        nextPath += 1;
        for (final r in groups[p]!) {
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
            silentLog('round_summary_card', '_undoAllRound', error, stack);
            lastError = '$error';
          }
          if (!mounted) return;
          setState(() => _bulkUndoDone += 1);
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(concurrency, (_) => worker()),
    );
    if (!mounted) return;
    setState(() {
      _bulkUndoTotal = 0;
      _bulkUndoDone = 0;
      _rowsFuture = _load(context);
    });
    _pulseSignal.value += 1;
    if (lastError != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(lastError!)),
      );
    }
  }

  /// 阶段⑰d：把本轮全部 ledger 记录序列化为 JSON 写入剪贴板。
  /// 字段直接调 FileMutationRecord.toJson()，再附 toolCallId /
  /// sourceMessageId 让外部审计/对账能完整反查。
  Future<void> _exportRoundJson(List<_RoundSummaryRow> rows) async {
    final payload = <String, Object?>{
      'session_id': widget.message.metadata['session_id'] ??
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
            'tool_call_id': r.toolCallId,
            'source_message_id': r.sourceMessageId,
          },
      ],
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    await Clipboard.setData(ClipboardData(text: encoded));
    if (!mounted) return;
    _pulseSignal.value += 1;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1800),
        content: Text(
          _localizedTextStatic(context,
              zh: '本轮文件变动 JSON 已复制到剪贴板',
              en: 'Round mutations JSON copied to clipboard'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureFutureBound();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AppearOnce(
      child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.28),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        child: FutureBuilder<List<_RoundSummaryRow>>(
          future: _rowsFuture,
          builder: (context, snap) {
            final rows = snap.data ?? const <_RoundSummaryRow>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(theme, cs, rows),
                if (rows.isEmpty && snap.connectionState != ConnectionState.done)
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
                        const SizedBox(width: 8),
                        Text(
                          _localizedTextStatic(context,
                              zh: '正在汇总本轮文件变动…',
                              en: 'Aggregating round mutations…'),
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
                      _localizedTextStatic(context,
                          zh: '本轮无文件变动。',
                          en: 'No file mutations this round.'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: _buildGroupedBody(theme, cs, rows, reduceMotion),
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
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
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
    int totalAdded = 0, totalRemoved = 0;
    for (final r in rows) {
      switch (r.view.record.kind) {
        case FileMutationKind.create:
          created += 1;
          break;
        case FileMutationKind.modify:
          modified += 1;
          break;
        case FileMutationKind.delete:
          deleted += 1;
          break;
      }
      final delta = r.view.record.afterSize - r.view.record.beforeSize;
      if (delta > 0) {
        totalAdded += delta;
      } else if (delta < 0) {
        totalRemoved += -delta;
      }
    }
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
          Icon(Icons.auto_awesome_motion_rounded,
              size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            _localizedTextStatic(context,
                zh: '本轮文件变动汇总',
                en: 'Round File Mutations'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 10),
          if (rows.isNotEmpty)
            _StatPill(
              label: AppLocalizations.of(context)!
                  .fileMutationFilesCount(rows.length),
              color: cs.onSurfaceVariant,
              bg: cs.surfaceContainerHighest.withValues(alpha: 0.65),
            ),
          if (created > 0) ...[
            const SizedBox(width: 6),
            _StatPill(
              label: 'C $created',
              color: const Color(0xFF2E7D32),
              bg: const Color(0xFF2E7D32).withValues(alpha: 0.12),
            ),
          ],
          if (modified > 0) ...[
            const SizedBox(width: 6),
            _StatPill(
              label: 'M $modified',
              color: cs.primary,
              bg: cs.primary.withValues(alpha: 0.12),
            ),
          ],
          if (deleted > 0) ...[
            const SizedBox(width: 6),
            _StatPill(
              label: 'D $deleted',
              color: cs.error,
              bg: cs.errorContainer.withValues(alpha: 0.55),
            ),
          ],
          const Spacer(),
          if (totalAdded > 0 || totalRemoved > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: _localizedTextStatic(context,
                    zh: '字节增减估算（基于文件大小）',
                    en: 'Byte delta (file-size estimate)'),
                child: Text(
                  '${totalAdded > 0 ? '+${_compactBytes(totalAdded)}' : ''}'
                  '${totalAdded > 0 && totalRemoved > 0 ? ' ' : ''}'
                  '${totalRemoved > 0 ? '-${_compactBytes(totalRemoved)}' : ''}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          // 阶段⑰c：进度 chip — 全部撤销中显示 N/M。
          if (_bulkUndoBusy) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                value:
                    _bulkUndoTotal == 0 ? null : _bulkUndoDone / _bulkUndoTotal,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$_bulkUndoDone/$_bulkUndoTotal',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
          ],
          // 阶段⑰c/⑰d：右侧动作组（按 reduceMotion 透明度逐个淡入由
          // 上层 HighlightPulse 提供反馈，无需在此再加入场动画）。
          if (rows.isNotEmpty && rows.any((r) => r.view.canUndo) &&
              !_bulkUndoBusy)
            _IconActionButton(
              icon: Icons.undo_rounded,
              tooltip: _localizedTextStatic(context,
                  zh: '撤销本轮全部变动', en: 'Undo all round mutations'),
              onTap: () => _undoAllRound(rows),
            ),
          if (rows.isNotEmpty)
            _IconActionButton(
              icon: Icons.data_object_rounded,
              tooltip: _localizedTextStatic(context,
                  zh: '导出本轮 JSON', en: 'Export round as JSON'),
              onTap: () => _exportRoundJson(rows),
            ),
          _IconActionButton(
            icon: Icons.refresh_rounded,
            tooltip: _localizedTextStatic(context,
                zh: '刷新汇总', en: 'Refresh summary'),
            onTap: () => setState(() => _rowsFuture = _load(context)),
          ),
        ],
      ),
    );
  }

  /// 阶段⑰d：按 `record.toolName` 分组渲染；每组一个可折叠 header。
  /// 阶段⑱a：组内行数超过 [_pathSubgroupThreshold] 时再按目录前缀做二级分组；
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
      final key = r.view.record.toolName.isEmpty
          ? '_'
          : r.view.record.toolName;
      groups.putIfAbsent(key, () => <_RoundSummaryRow>[]).add(r);
    }
    final msgKey = widget.message.id;
    final showAll = _expandedFullList.contains(msgKey);
    final children = <Widget>[];
    var globalIndex = 0;
    var rendered = 0;
    var truncated = false;

    Widget buildTile(_RoundSummaryRow r, int idx) {
      return _RoundSummaryRowTile(
        row: r,
        entranceDelay: (!reduceMotion && rows.length >= 6)
            ? Duration(milliseconds: (idx * 55).clamp(0, 660).toInt())
            : Duration.zero,
        onJump: () => _jumpToSourceMessage(r.sourceMessageId),
        isDiffExpanded:
            _expandedDiffRows.contains(_diffKey(r.view.record.recordId)),
        onToggleDiff: () => _toggleDiffExpanded(r),
      );
    }

    bool capReached() => !showAll && rendered >= _virtualRowCap;

    // 单组：扁平输出（仍受路径子分组与 cap 影响）。
    if (groups.length <= 1) {
      final only = groups.values.isEmpty ? const <_RoundSummaryRow>[] : groups.values.first;
      final toolName = groups.keys.isEmpty ? '_' : groups.keys.first;
      _emitRowsWithOptionalPathSubgroups(
        theme: theme,
        cs: cs,
        toolName: toolName,
        groupRows: only,
        showAll: showAll,
        reduceMotion: reduceMotion,
        children: children,
        globalIndex: () => globalIndex,
        bumpIndex: () => globalIndex += 1,
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
        children.add(_GroupHeader(
          toolName: entry.key,
          count: entry.value.length,
          collapsed: collapsed,
          onToggle: () {
            setState(() {
              if (collapsed) {
                _collapsedGroups.remove(groupKey);
              } else {
                _collapsedGroups.add(groupKey);
              }
            });
          },
        ));
        if (collapsed) {
          globalIndex += entry.value.length;
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
          globalIndex: () => globalIndex,
          bumpIndex: () => globalIndex += 1,
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
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              foregroundColor: cs.primary,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.unfold_more_rounded, size: 16),
            label: Text(
              _localizedTextStatic(context,
                  zh: '展开剩余 $remaining 行',
                  en: 'Show $remaining more'),
              style: theme.textTheme.labelMedium,
            ),
            onPressed: () {
              setState(() => _expandedFullList.add(msgKey));
            },
          ),
        ),
      ));
    } else if (showAll && rows.length > _virtualRowCap) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              foregroundColor: cs.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.unfold_less_rounded, size: 16),
            label: Text(
              _localizedTextStatic(context, zh: '收起', en: 'Collapse'),
              style: theme.textTheme.labelMedium,
            ),
            onPressed: () {
              setState(() => _expandedFullList.remove(msgKey));
            },
          ),
        ),
      ));
    }

    return AnimatedSize(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// 阶段⑱a：组内若超阈值 → 按 `_topDir` 二级分桶；否则平铺。
  void _emitRowsWithOptionalPathSubgroups({
    required ThemeData theme,
    required ColorScheme cs,
    required String toolName,
    required List<_RoundSummaryRow> groupRows,
    required bool showAll,
    required bool reduceMotion,
    required List<Widget> children,
    required int Function() globalIndex,
    required VoidCallback bumpIndex,
    required void Function(int n) renderedAdd,
    required bool Function() capReached,
    required Widget Function(_RoundSummaryRow, int) buildTile,
  }) {
    if (groupRows.length < _pathSubgroupThreshold) {
      for (final r in groupRows) {
        if (capReached()) return;
        children.add(buildTile(r, globalIndex()));
        bumpIndex();
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
        children.add(buildTile(r, globalIndex()));
        bumpIndex();
        renderedAdd(1);
      }
      return;
    }
    for (final entry in dirBuckets.entries) {
      if (capReached()) return;
      final pathKey = _pathGroupKey(toolName, entry.key);
      final pathCollapsed = _collapsedPathGroups.contains(pathKey);
      children.add(_PathSubGroupHeader(
        dir: entry.key,
        count: entry.value.length,
        collapsed: pathCollapsed,
        onToggle: () {
          setState(() {
            if (pathCollapsed) {
              _collapsedPathGroups.remove(pathKey);
            } else {
              _collapsedPathGroups.add(pathKey);
            }
          });
        },
      ));
      if (pathCollapsed) continue;
      for (final r in entry.value) {
        if (capReached()) return;
        children.add(buildTile(r, globalIndex()));
        bumpIndex();
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
        _expandedDiffRows.add(key);
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
    required this.entranceDelay,
    required this.onJump,
    required this.isDiffExpanded,
    required this.onToggleDiff,
  });

  final _RoundSummaryRow row;
  final Duration entranceDelay;
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
        return const Color(0xFF2E7D32);
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
    final delta = row.view.record.afterSize - row.view.record.beforeSize;
    final tile = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: greyOut
            ? cs.surfaceContainerHighest.withValues(alpha: 0.32)
            : cs.surface.withValues(alpha: 0.55),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(_kindIcon(), size: 15, color: _kindColor(cs)),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: row.view.record.filePath,
              waitDuration: const Duration(milliseconds: 600),
              child: Text(
                _FileMutationCard._shortenFilePath(row.view.record.filePath),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: greyOut
                      ? cs.onSurfaceVariant.withValues(alpha: 0.6)
                      : cs.onSurface,
                  decoration: greyOut ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
          if (delta != 0) ...[
            const SizedBox(width: 8),
            Text(
              delta > 0
                  ? '+${_compactBytes(delta)}'
                  : '-${_compactBytes(-delta)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: delta > 0 ? const Color(0xFF2E7D32) : cs.error,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(width: 6),
          if (row.sourceMessageId != null)
            Tooltip(
              message: _localizedTextStatic(context,
                  zh: '跳转到产生该变动的工具调用',
                  en: 'Jump to source tool-call message'),
              child: MicroPressFeedback(
                child: InkWell(
                  onTap: onJump,
                  borderRadius:
                      const BorderRadius.all(Radius.circular(999)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius:
                          const BorderRadius.all(Radius.circular(999)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.my_location_rounded,
                            size: 12, color: cs.primary),
                        const SizedBox(width: 4),
                        Text(
                          _localizedTextStatic(context,
                              zh: '跳转', en: 'Jump'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // 阶段⑰d：modify 类记录支持 inline Diff 预览（前后均有 blob 才显示）。
          if (row.view.record.kind == FileMutationKind.modify &&
              row.view.record.beforeSha != null &&
              row.view.record.afterSha != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: _localizedTextStatic(context,
                  zh: '展开 / 收起 Diff 预览',
                  en: 'Expand / collapse diff preview'),
              child: MicroPressFeedback(
                child: InkWell(
                  onTap: onToggleDiff,
                  borderRadius:
                      const BorderRadius.all(Radius.circular(999)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    child: AnimatedRotation(
                      turns: isDiffExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
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
    final wrapped = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isDiffExpanded
              ? _DiffPreviewBox(
                  key: ValueKey('diff-${row.view.record.recordId}'),
                  record: row.view.record,
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
    if (entranceDelay == Duration.zero) return wrapped;
    return _DelayedAppear(delay: entranceDelay, child: wrapped);
  }
}

/// 阶段⑰d：分组 header — 显示工具名 + 计数 + 折叠箭头。
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
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
          child: Row(
            children: [
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                toolName.isEmpty ? '·' : toolName,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
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

/// 阶段⑱a：路径子分组 header — 比 [_GroupHeader] 更轻盈、左侧缩进。
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
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 6, 2),
          child: Row(
            children: [
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.folder_rounded,
                size: 12,
                color: cs.onSurfaceVariant.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 4),
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
              const SizedBox(width: 6),
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

/// 阶段⑰d：行内 Diff 预览 — lazy 加载 before/after blob，渲染压缩的统一
/// diff 视图（≤ 10 行，超过截断 + 省略提示）。
class _DiffPreviewBox extends StatefulWidget {
  const _DiffPreviewBox({super.key, required this.record});

  final FileMutationRecord record;

  @override
  State<_DiffPreviewBox> createState() => _DiffPreviewBoxState();
}

class _DiffPreviewBoxState extends State<_DiffPreviewBox> {
  Future<String>? _diffFuture;

  @override
  void initState() {
    super.initState();
    _diffFuture = _loadDiff();
  }

  Future<String> _loadDiff() async {
    final ledger = context
        .read<AiSessionController>()
        .toolRuntimeService
        .mutationLedger;
    final config = await ledger.loadConfig();
    final r = widget.record;
    final before = r.beforeSha == null
        ? ''
        : (await ledger.readBlob(r.beforeSha!) ?? '');
    final after = r.afterSha == null
        ? ''
        : (await ledger.readBlob(r.afterSha!) ?? '');
    return unifiedDiffLineSummary(
      before,
      after,
      beforeSha: r.beforeSha,
      afterSha: r.afterSha,
      miniDiffMaxBytes: config.miniDiffMaxBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 8, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.45),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
        child: FutureBuilder<String>(
          future: _diffFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Row(
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _localizedTextStatic(context,
                        zh: '加载 Diff…', en: 'Loading diff…'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            }
            final raw = (snap.data ?? '').trim();
            if (raw.isEmpty) {
              return Text(
                _localizedTextStatic(context,
                    zh: '内容相同或不可对比。',
                    en: 'No textual diff available.'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              );
            }
            final lines = raw.split('\n');
            const maxLines = 10;
            final shown = lines.length > maxLines
                ? lines.take(maxLines).toList()
                : lines;
            final clipped = lines.length > maxLines;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in shown) _diffLine(theme, cs, line),
                if (clipped)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _localizedTextStatic(context,
                          zh: '… 还有 ${lines.length - maxLines} 行，复制全部 Diff 查看完整内容。',
                          en: '… ${lines.length - maxLines} more lines; copy full diff to inspect.'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _diffLine(ThemeData theme, ColorScheme cs, String line) {
    Color? bg;
    Color fg = cs.onSurface;
    if (line.startsWith('+')) {
      bg = const Color(0xFF2E7D32).withValues(alpha: 0.10);
      fg = const Color(0xFF1B5E20);
    } else if (line.startsWith('-')) {
      bg = cs.error.withValues(alpha: 0.10);
      fg = cs.error;
    } else {
      fg = cs.onSurfaceVariant;
    }
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(
        line.isEmpty ? ' ' : line,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontFamily: 'monospace',
          fontFeatures: const [FontFeature.tabularFigures()],
          height: 1.3,
        ),
      ),
    );
  }
}

