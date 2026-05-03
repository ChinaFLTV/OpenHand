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
    return Stack(
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
              ],
            ),
          ),
            ),
          ),
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.45),
          ),
          // Rows
          for (final v in views)
            _FileMutationCardRow(
              view: v,
              expanded: _expandedRecordIds.contains(v.record.recordId),
              busy: _busyRecordIds.contains(v.record.recordId),
              onToggleExpand: () => _toggleExpand(v.record.recordId),
              onUndo: () => _undo(v),
              onRedo: () => _redo(v),
              onOpenLegacyDialog: () => _showLegacyDiff(
                v.record.filePath,
                _fileMutationKind(widget.message),
              ),
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
      ],
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
  });

  final FileMutationView view;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggleExpand;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onOpenLegacyDialog;

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
          InkWell(
            onTap: onToggleExpand,
            onDoubleTap: onOpenLegacyDialog,
            // 阶段 ⑩c：row hover 背景轻微高亮，让指针落点更清晰。
            hoverColor: cs.primary.withValues(alpha: 0.05),
            splashColor: cs.primary.withValues(alpha: 0.10),
            highlightColor: cs.primary.withValues(alpha: 0.06),
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
                child: SelectableText.rich(
                  TextSpan(
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.5,
                      fontSize: 11.5,
                    ),
                    children: diff.map((l) {
                      Color? bg;
                      Color? fg;
                      if (l.startsWith('+')) {
                        bg = cs.primaryContainer.withValues(alpha: 0.32);
                        fg = cs.onPrimaryContainer;
                      } else if (l.startsWith('-')) {
                        bg = cs.errorContainer.withValues(alpha: 0.30);
                        fg = cs.onErrorContainer;
                      }
                      return TextSpan(
                        text: '$l\n',
                        style: TextStyle(backgroundColor: bg, color: fg),
                      );
                    }).toList(),
                  ),
                ),
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
