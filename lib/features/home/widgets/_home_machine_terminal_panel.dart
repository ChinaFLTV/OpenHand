part of '../openhand_home_page.dart';

class _MachineExpertTerminalPanel extends StatefulWidget {
  const _MachineExpertTerminalPanel({
    required this.sessionId,
    this.onPanelClose,
  });

  final String sessionId;
  final VoidCallback? onPanelClose;

  @override
  State<_MachineExpertTerminalPanel> createState() =>
      _MachineExpertTerminalPanelState();
}

class _MachineExpertTerminalPanelState
    extends State<_MachineExpertTerminalPanel> {
  static const EdgeInsets _terminalViewportPadding = EdgeInsets.fromLTRB(
    12,
    10,
    12,
    10,
  );

  final ScrollController _terminalScrollController = ScrollController();
  final FocusNode _terminalFocusNode = FocusNode(
    debugLabel: 'machine-terminal',
  );
  String? _initializedSessionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTerminal());
  }

  @override
  void didUpdateWidget(covariant _MachineExpertTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _initializedSessionId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTerminal());
    }
  }

  @override
  void dispose() {
    _terminalScrollController.dispose();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  void _ensureTerminal() {
    if (!mounted || _initializedSessionId == widget.sessionId) return;
    _initializedSessionId = widget.sessionId;
    final sessionController = context.read<AiSessionController>();
    AiSession? session;
    for (final candidate in sessionController.sessions) {
      if (candidate.id == widget.sessionId) {
        session = candidate;
        break;
      }
    }
    final terminalMetadata = session?.metadata[kMachineTerminalMetadataKey];
    final terminalService = context.read<MachineTerminalService>();
    terminalService.rememberSessionMetadata(
      sessionId: widget.sessionId,
      metadata: terminalMetadata,
    );
    terminalService.ensureWorkspace(
      sessionId: widget.sessionId,
      workingDirectory:
          MachineTerminalSessionMetadata.defaultWorkingDirectoryFrom(
            terminalMetadata,
          ),
    );
    unawaited(terminalService.startTerminal(sessionId: widget.sessionId));
  }

  void _followBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_terminalScrollController.hasClients) return;
      final position = _terminalScrollController.position;
      final target = position.maxScrollExtent;
      if ((position.pixels - target).abs() < 2) return;
      _terminalScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final terminalService = context.watch<MachineTerminalService>();
    final workspace = terminalService.snapshot(widget.sessionId);
    final activeSession = terminalService.activeTerminal(widget.sessionId);
    final activeSnapshot = workspace?.activeTerminal;
    _followBottom();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (workspace == null || activeSession == null || activeSnapshot == null) {
      return _MachineTerminalShell(
        child: Stack(
          children: [
            Center(
              child: Text(
                _localizedText(context, zh: '正在启动终端', en: 'Starting terminal'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (widget.onPanelClose != null)
              Positioned(
                top: 0,
                right: 0,
                child: _MachineTerminalIconButton(
                  icon: Icons.close_rounded,
                  tooltip: _localizedText(
                    context,
                    zh: '关闭面板',
                    en: 'Close Panel',
                  ),
                  onPressed: widget.onPanelClose,
                ),
              ),
          ],
        ),
      );
    }

    return _MachineTerminalShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MachineTerminalHeader(
            snapshot: activeSnapshot,
            onCopyId: () => _copyTerminalId(activeSnapshot.terminalId),
            onPanelClose: widget.onPanelClose,
            onStart: () => _control('start', activeSnapshot.terminalId),
            onStop: () => _control('stop', activeSnapshot.terminalId),
            onRestart: () => _control('restart', activeSnapshot.terminalId),
            onNew: () => _control('new', null),
            onDuplicate: () => _control('duplicate', activeSnapshot.terminalId),
            onClear: () => _control('clear', activeSnapshot.terminalId),
            onHistory: _showHistoryDialog,
          ),
          const SizedBox(height: 10),
          _MachineTerminalTabs(
            workspace: workspace,
            onSelected: (terminalId) => _control('select', terminalId),
            onClosed: (terminalId) => _control('close', terminalId),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0B0D10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.34),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _MachineTerminalViewport(
                  key: ValueKey<String>(
                    'machine-terminal-view-${activeSession.id}',
                  ),
                  session: activeSession,
                  scrollController: _terminalScrollController,
                  focusNode: _terminalFocusNode,
                  padding: _terminalViewportPadding,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _MachineTerminalMetadataBar(snapshot: activeSnapshot),
        ],
      ),
    );
  }

  Future<void> _control(String action, String? terminalId) async {
    final terminalService = context.read<MachineTerminalService>();
    try {
      await terminalService.control(
        sessionId: widget.sessionId,
        action: action,
        terminalId: terminalId,
      );
      if (mounted) {
        _terminalFocusNode.requestFocus();
      }
    } catch (error, stack) {
      silentLog('openhand_home', 'machine terminal control', error, stack);
      if (!mounted) return;
      showFriendlyErrorSnackBar(
        context,
        message: '$error',
        fallback: _localizedText(
          context,
          zh: '终端操作失败。',
          en: 'Terminal action failed.',
        ),
      );
    }
  }

  Future<void> _copyTerminalId(String terminalId) async {
    await Clipboard.setData(ClipboardData(text: terminalId));
    if (!mounted) return;
    showOpenHandSnackBar(
      context,
      SnackBar(
        content: Text(
          _localizedText(context, zh: '终端 ID 已复制。', en: 'Terminal ID copied.'),
        ),
      ),
    );
  }

  void _showHistoryDialog() {
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => _MachineTerminalHistoryDialog(
        sessionId: widget.sessionId,
        onReplay: _showReplayDialog,
      ),
    );
  }

  void _showReplayDialog(MachineTerminalSnapshot snapshot) {
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _MachineTerminalReplayDialog(snapshot: snapshot),
    );
  }
}

class _MachineTerminalViewport extends StatelessWidget {
  const _MachineTerminalViewport({
    super.key,
    required this.session,
    required this.scrollController,
    required this.focusNode,
    required this.padding,
  });

  final MachineTerminalSession session;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TerminalView(
        session.terminal,
        scrollController: scrollController,
        focusNode: focusNode,
        autofocus: true,
        padding: padding,
        theme: _machineTerminalTheme(),
        alwaysShowCursor: true,
      ),
    );
  }
}

class _MachineTerminalShell extends StatelessWidget {
  const _MachineTerminalShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.72)),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class _MachineTerminalHeader extends StatelessWidget {
  const _MachineTerminalHeader({
    required this.snapshot,
    required this.onCopyId,
    this.onPanelClose,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onNew,
    required this.onDuplicate,
    required this.onClear,
    required this.onHistory,
  });

  final MachineTerminalSnapshot snapshot;
  final VoidCallback onCopyId;
  final VoidCallback? onPanelClose;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onNew;
  final VoidCallback onDuplicate;
  final VoidCallback onClear;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canStart =
        snapshot.status != MachineTerminalStatus.running &&
        snapshot.status != MachineTerminalStatus.starting;
    final canStop =
        snapshot.status == MachineTerminalStatus.running ||
        snapshot.status == MachineTerminalStatus.starting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _terminalStatusColor(
                  cs,
                  snapshot.status,
                ).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _terminalStatusColor(
                    cs,
                    snapshot.status,
                  ).withValues(alpha: 0.32),
                ),
              ),
              child: Icon(
                Icons.terminal_rounded,
                color: _terminalStatusColor(cs, snapshot.status),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localizedText(context, zh: '机器终端', en: 'Machine Terminal'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${snapshot.identity} · ${snapshot.shell}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            _MachineTerminalIconButton(
              icon: Icons.copy_rounded,
              tooltip: _localizedText(context, zh: '复制 ID', en: 'Copy ID'),
              onPressed: onCopyId,
            ),
            if (onPanelClose != null) ...[
              const SizedBox(width: 7),
              _MachineTerminalIconButton(
                icon: Icons.close_rounded,
                tooltip: _localizedText(context, zh: '关闭面板', en: 'Close Panel'),
                onPressed: onPanelClose,
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _MachineTerminalChip(
              icon: Icons.circle_rounded,
              label: _statusLabel(context, snapshot.status),
              color: _terminalStatusColor(cs, snapshot.status),
            ),
            _MachineTerminalChip(
              icon: Icons.tag_rounded,
              label: snapshot.terminalId,
              color: cs.primary,
            ),
            _MachineTerminalChip(
              icon: Icons.memory_rounded,
              label: snapshot.pid == null ? 'PID -' : 'PID ${snapshot.pid}',
              color: cs.tertiary,
            ),
            _MachineTerminalChip(
              icon: Icons.fit_screen_rounded,
              label: '${snapshot.columns}x${snapshot.rows}',
              color: cs.secondary,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _MachineTerminalIconButton(
              icon: Icons.add_rounded,
              tooltip: _localizedText(context, zh: '新建终端', en: 'New Terminal'),
              onPressed: onNew,
            ),
            _MachineTerminalIconButton(
              icon: Icons.content_copy_rounded,
              tooltip: _localizedText(
                context,
                zh: '复制终端',
                en: 'Duplicate Terminal',
              ),
              onPressed: onDuplicate,
            ),
            _MachineTerminalIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: _localizedText(context, zh: '启动', en: 'Start'),
              onPressed: canStart ? onStart : null,
            ),
            _MachineTerminalIconButton(
              icon: Icons.stop_rounded,
              tooltip: _localizedText(context, zh: '关闭进程', en: 'Stop Process'),
              onPressed: canStop ? onStop : null,
            ),
            _MachineTerminalIconButton(
              icon: Icons.restart_alt_rounded,
              tooltip: _localizedText(context, zh: '重启', en: 'Restart'),
              onPressed: onRestart,
            ),
            _MachineTerminalIconButton(
              icon: Icons.cleaning_services_rounded,
              tooltip: _localizedText(context, zh: '清屏', en: 'Clear'),
              onPressed: onClear,
            ),
            _MachineTerminalIconButton(
              icon: Icons.history_rounded,
              tooltip: _localizedText(
                context,
                zh: '执行历史',
                en: 'Execution History',
              ),
              onPressed: onHistory,
            ),
          ],
        ),
      ],
    );
  }
}

class _MachineTerminalHistoryDialog extends StatefulWidget {
  const _MachineTerminalHistoryDialog({
    required this.sessionId,
    required this.onReplay,
  });

  final String sessionId;
  final ValueChanged<MachineTerminalSnapshot> onReplay;

  @override
  State<_MachineTerminalHistoryDialog> createState() =>
      _MachineTerminalHistoryDialogState();
}

class _MachineTerminalHistoryDialogState
    extends State<_MachineTerminalHistoryDialog> {
  static const double _dialogMaxWidth = 1060;
  static const double _dialogMaxHeight = 720;
  static const double _terminalColumnWidth = 150;
  static const double _statusColumnWidth = 98;
  static const double _pidColumnWidth = 98;
  static const double _sizeColumnWidth = 80;
  static const double _commandsColumnWidth = 86;
  static const double _outputColumnWidth = 110;
  static const double _timeColumnWidth = 145;
  static const double _actionsColumnWidth = 138;
  static const double _tableWidth =
      _terminalColumnWidth +
      _statusColumnWidth +
      _pidColumnWidth +
      _sizeColumnWidth +
      _commandsColumnWidth +
      _outputColumnWidth +
      _timeColumnWidth * 2 +
      _actionsColumnWidth;

  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  String? _deletingTerminalId;

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terminalService = context.watch<MachineTerminalService>();
    final workspace = terminalService.snapshot(widget.sessionId);
    final terminals = workspace?.terminals ?? const <MachineTerminalSnapshot>[];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(viewport.width * 0.94, _dialogMaxWidth);
    final dialogHeight = math.min(viewport.height * 0.86, _dialogMaxHeight);
    final activeTerminalId = workspace?.activeTerminalId ?? '';

    return buildOpenHandDialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.none,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.62)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.20),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          children: [
            _MachineTerminalDialogHeader(
              icon: Icons.history_rounded,
              title: _localizedText(
                context,
                zh: '终端执行历史',
                en: 'Terminal History',
              ),
              subtitle: _localizedText(
                context,
                zh: '当前线程关联 ${terminals.length} 个终端会话 · 当前 ${activeTerminalId.isEmpty ? '-' : activeTerminalId}',
                en: '${terminals.length} terminal sessions · active ${activeTerminalId.isEmpty ? '-' : activeTerminalId}',
              ),
              onClose: () => Navigator.of(context).pop(),
            ),
            _MachineTerminalHistoryMetrics(
              terminalCount: terminals.length,
              commandCount: _terminalCommandTotal(terminals),
              outputSize: formatByteSize(_terminalHistoryBytes(terminals)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: _buildHistoryTable(context, terminals, activeTerminalId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTable(
    BuildContext context,
    List<MachineTerminalSnapshot> terminals,
    String activeTerminalId,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (terminals.isEmpty) {
      return Center(
        child: Text(
          _localizedText(
            context,
            zh: '暂无终端会话历史。',
            en: 'No terminal history yet.',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.54)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: OpenHandSafeScrollbar(
          controller: _verticalScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalScrollController,
            physics: kOpenHandDialogScrollPhysics,
            child: OpenHandSafeScrollbar(
              controller: _horizontalScrollController,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                physics: kOpenHandDialogScrollPhysics,
                child: SizedBox(
                  width: _tableWidth,
                  child: Column(
                    children: [
                      _historyHeaderRow(context),
                      ...terminals.map(
                        (terminal) => _historyDataRow(
                          context,
                          terminal,
                          active: terminal.terminalId == activeTerminalId,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyHeaderRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      color: cs.surfaceContainerHigh.withValues(alpha: 0.92),
      child: Row(
        children: [
          _historyCell(
            context,
            _localizedText(context, zh: '终端', en: 'Terminal'),
            width: _terminalColumnWidth,
            header: true,
          ),
          _historyCell(
            context,
            _localizedText(context, zh: '状态', en: 'Status'),
            width: _statusColumnWidth,
            header: true,
          ),
          _historyCell(context, 'PID', width: _pidColumnWidth, header: true),
          _historyCell(
            context,
            _localizedText(context, zh: '尺寸', en: 'Size'),
            width: _sizeColumnWidth,
            header: true,
          ),
          _historyCell(
            context,
            _localizedText(context, zh: '命令', en: 'Commands'),
            width: _commandsColumnWidth,
            header: true,
          ),
          _historyCell(
            context,
            _localizedText(context, zh: '输出', en: 'Output'),
            width: _outputColumnWidth,
            header: true,
          ),
          _historyCell(
            context,
            _localizedText(context, zh: '启动时间', en: 'Started'),
            width: _timeColumnWidth,
            header: true,
          ),
          _historyCell(
            context,
            _localizedText(context, zh: '更新时间', en: 'Updated'),
            width: _timeColumnWidth,
            header: true,
          ),
          _historyCell(
            context,
            _localizedText(context, zh: '操作', en: 'Actions'),
            width: _actionsColumnWidth,
            header: true,
            alignEnd: true,
          ),
        ],
      ),
    );
  }

  Widget _historyDataRow(
    BuildContext context,
    MachineTerminalSnapshot terminal, {
    required bool active,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final deleting = _deletingTerminalId == terminal.terminalId;
    return AnimatedContainer(
      duration: openHandMotionDuration(
        context,
        const Duration(milliseconds: 160),
      ),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: active
            ? cs.primary.withValues(alpha: 0.075)
            : Colors.transparent,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.36)),
        ),
      ),
      child: Row(
        children: [
          _historyCell(
            context,
            terminal.terminalId,
            width: _terminalColumnWidth,
            leading: Icon(
              Icons.terminal_rounded,
              size: 16,
              color: _terminalStatusColor(cs, terminal.status),
            ),
            trailing: active
                ? _MachineTerminalTinyBadge(
                    label: _localizedText(context, zh: '当前', en: 'Active'),
                  )
                : null,
          ),
          SizedBox(
            width: _statusColumnWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _MachineTerminalStatusPill(status: terminal.status),
              ),
            ),
          ),
          _historyCell(
            context,
            terminal.pid == null ? '-' : '${terminal.pid}',
            width: _pidColumnWidth,
            mono: true,
          ),
          _historyCell(
            context,
            '${terminal.columns}x${terminal.rows}',
            width: _sizeColumnWidth,
            mono: true,
          ),
          _historyCell(
            context,
            '${terminal.commandCount}',
            width: _commandsColumnWidth,
            mono: true,
          ),
          _historyCell(
            context,
            formatByteSize(terminal.historyOutputCharacters),
            width: _outputColumnWidth,
          ),
          _historyCell(
            context,
            _formatTerminalHistoryTime(terminal.startedAt),
            width: _timeColumnWidth,
            mono: true,
          ),
          _historyCell(
            context,
            _formatTerminalHistoryTime(terminal.updatedAt),
            width: _timeColumnWidth,
            mono: true,
          ),
          SizedBox(
            width: _actionsColumnWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _MachineTerminalMiniActionButton(
                  icon: Icons.replay_rounded,
                  tooltip: _localizedText(context, zh: '回放', en: 'Replay'),
                  onPressed: deleting ? null : () => widget.onReplay(terminal),
                ),
                const SizedBox(width: 6),
                _MachineTerminalMiniActionButton(
                  icon: deleting
                      ? Icons.hourglass_top_rounded
                      : Icons.delete_outline_rounded,
                  tooltip: _localizedText(context, zh: '删除', en: 'Delete'),
                  destructive: true,
                  onPressed: deleting ? null : () => _deleteTerminal(terminal),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyCell(
    BuildContext context,
    String text, {
    required double width,
    Widget? leading,
    Widget? trailing,
    bool header = false,
    bool mono = false,
    bool alignEnd = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style =
        (header ? theme.textTheme.labelMedium : theme.textTheme.bodySmall)
            ?.copyWith(
              color: header ? cs.onSurface : cs.onSurfaceVariant,
              fontWeight: header ? FontWeight.w900 : FontWeight.w700,
              fontFeatures: mono
                  ? const <FontFeature>[FontFeature.tabularFigures()]
                  : null,
              fontFamily: mono ? 'Menlo' : null,
            );
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 7)],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 7), trailing],
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTerminal(MachineTerminalSnapshot terminal) async {
    if (_deletingTerminalId != null) return;
    setState(() => _deletingTerminalId = terminal.terminalId);
    try {
      await context.read<MachineTerminalService>().control(
        sessionId: widget.sessionId,
        action: 'delete',
        terminalId: terminal.terminalId,
      );
      if (!mounted) return;
      showOpenHandSnackBar(
        context,
        SnackBar(
          content: Text(
            _localizedText(context, zh: '终端会话已删除。', en: 'Terminal deleted.'),
          ),
        ),
      );
    } catch (error, stack) {
      silentLog(
        'openhand_home',
        'delete machine terminal history',
        error,
        stack,
      );
      if (!mounted) return;
      showFriendlyErrorSnackBar(
        context,
        message: '$error',
        fallback: _localizedText(
          context,
          zh: '删除终端会话失败。',
          en: 'Failed to delete terminal.',
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingTerminalId = null);
    }
  }
}

class _MachineTerminalHistoryMetrics extends StatelessWidget {
  const _MachineTerminalHistoryMetrics({
    required this.terminalCount,
    required this.commandCount,
    required this.outputSize,
  });

  final int terminalCount;
  final int commandCount;
  final String outputSize;

  @override
  Widget build(BuildContext context) {
    final metrics = <Widget>[
      _MachineTerminalHistoryMetric(
        icon: Icons.layers_rounded,
        label: _localizedText(context, zh: '终端数量', en: 'Terminals'),
        value: '$terminalCount',
      ),
      _MachineTerminalHistoryMetric(
        icon: Icons.code_rounded,
        label: _localizedText(context, zh: '命令记录', en: 'Commands'),
        value: '$commandCount',
      ),
      _MachineTerminalHistoryMetric(
        icon: Icons.storage_rounded,
        label: _localizedText(context, zh: '历史输出', en: 'Output'),
        value: outputSize,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(
              children: [
                for (var index = 0; index < metrics.length; index++) ...[
                  metrics[index],
                  if (index != metrics.length - 1) const SizedBox(height: 8),
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                Expanded(child: metrics[index]),
                if (index != metrics.length - 1) const SizedBox(width: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MachineTerminalReplayDialog extends StatefulWidget {
  const _MachineTerminalReplayDialog({required this.snapshot});

  final MachineTerminalSnapshot snapshot;

  @override
  State<_MachineTerminalReplayDialog> createState() =>
      _MachineTerminalReplayDialogState();
}

class _MachineTerminalReplayDialogState
    extends State<_MachineTerminalReplayDialog> {
  static const int _replayScrollbackLines = 10000;
  static const double _dialogMaxWidth = 980;
  static const double _dialogMaxHeight = 760;
  static const EdgeInsets _replayPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);

  late final Terminal _terminal;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'machine-terminal-replay');

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: _replayScrollbackLines,
      reflowEnabled: false,
    );
    _terminal.write(_replayAnsiOutput(widget.snapshot));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(viewport.width * 0.94, _dialogMaxWidth);
    final dialogHeight = math.min(viewport.height * 0.88, _dialogMaxHeight);

    return buildOpenHandDialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.none,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.62)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.22),
              blurRadius: 36,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          children: [
            _MachineTerminalDialogHeader(
              icon: Icons.replay_rounded,
              title: _localizedText(
                context,
                zh: '终端历史回放',
                en: 'Terminal Replay',
              ),
              subtitle:
                  '${widget.snapshot.terminalId} · ${formatByteSize(widget.snapshot.historyOutputCharacters)} · ${_localizedText(context, zh: '命令', en: 'commands')} ${widget.snapshot.commandCount}',
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MachineTerminalChip(
                    icon: Icons.circle_rounded,
                    label: _statusLabel(context, widget.snapshot.status),
                    color: _terminalStatusColor(cs, widget.snapshot.status),
                  ),
                  _MachineTerminalChip(
                    icon: Icons.fit_screen_rounded,
                    label: '${widget.snapshot.columns}x${widget.snapshot.rows}',
                    color: cs.secondary,
                  ),
                  _MachineTerminalChip(
                    icon: Icons.schedule_rounded,
                    label: _formatTerminalHistoryTime(
                      widget.snapshot.updatedAt,
                    ),
                    color: cs.tertiary,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0D10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.34),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 24,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: RepaintBoundary(
                      child: TerminalView(
                        _terminal,
                        scrollController: _scrollController,
                        focusNode: _focusNode,
                        padding: _replayPadding,
                        theme: _machineTerminalTheme(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineTerminalDialogHeader extends StatelessWidget {
  const _MachineTerminalDialogHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.primary.withValues(alpha: 0.26)),
            ),
            child: Icon(icon, color: cs.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _MachineTerminalIconButton(
            icon: Icons.close_rounded,
            tooltip: _localizedText(context, zh: '关闭', en: 'Close'),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _MachineTerminalHistoryMetric extends StatelessWidget {
  const _MachineTerminalHistoryMetric({
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
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.44)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineTerminalTinyBadge extends StatelessWidget {
  const _MachineTerminalTinyBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: cs.primary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _MachineTerminalStatusPill extends StatelessWidget {
  const _MachineTerminalStatusPill({required this.status});

  final MachineTerminalStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _terminalStatusColor(cs, status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          _statusLabel(context, status),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _MachineTerminalMiniActionButton extends StatelessWidget {
  const _MachineTerminalMiniActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? cs.error : cs.primary;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onPressed,
        child: AnimatedOpacity(
          duration: openHandMotionDuration(
            context,
            const Duration(milliseconds: 140),
          ),
          opacity: enabled ? 1 : 0.45,
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: destructive ? 0.10 : 0.12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: color.withValues(alpha: 0.24)),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

class _MachineTerminalTabs extends StatelessWidget {
  const _MachineTerminalTabs({
    required this.workspace,
    required this.onSelected,
    required this.onClosed,
  });

  final MachineTerminalWorkspaceSnapshot workspace;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onClosed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final duration = openHandMotionDuration(
      context,
      const Duration(milliseconds: 160),
    );
    final canCloseTabs = workspace.terminals.length > 1;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final terminal = workspace.terminals[index];
          final selected = terminal.terminalId == workspace.activeTerminalId;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: selected ? null : () => onSelected(terminal.terminalId),
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minWidth: 96, maxWidth: 172),
              padding: EdgeInsets.only(left: 10, right: canCloseTabs ? 5 : 10),
              decoration: BoxDecoration(
                color: selected
                    ? cs.primary.withValues(alpha: 0.15)
                    : cs.surface.withValues(alpha: 0.54),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? cs.primary.withValues(alpha: 0.42)
                      : cs.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.terminal_rounded,
                    size: 16,
                    color: _terminalStatusColor(cs, terminal.status),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      terminal.terminalId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w700,
                        color: selected ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (canCloseTabs) ...[
                    const SizedBox(width: 5),
                    _MachineTerminalTabCloseButton(
                      onPressed: () => onClosed(terminal.terminalId),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemCount: workspace.terminals.length,
      ),
    );
  }
}

class _MachineTerminalTabCloseButton extends StatelessWidget {
  const _MachineTerminalTabCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: _localizedText(context, zh: '关闭终端', en: 'Close Terminal'),
      child: InkResponse(
        onTap: onPressed,
        radius: 13,
        containedInkWell: true,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: cs.onSurfaceVariant.withValues(alpha: 0.82),
          ),
        ),
      ),
    );
  }
}

class _MachineTerminalMetadataBar extends StatelessWidget {
  const _MachineTerminalMetadataBar({required this.snapshot});

  final MachineTerminalSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.50)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MachineTerminalMetaLine(
              icon: Icons.folder_open_rounded,
              text: snapshot.workingDirectory,
            ),
            const SizedBox(height: 5),
            _MachineTerminalMetaLine(
              icon: Icons.schedule_rounded,
              text:
                  '${_localizedText(context, zh: '更新', en: 'Updated')} ${formatYearMonthDayHms(snapshot.updatedAt.toLocal())}',
            ),
            if (snapshot.errorMessage != null) ...[
              const SizedBox(height: 5),
              _MachineTerminalMetaLine(
                icon: Icons.error_outline_rounded,
                text: snapshot.errorMessage!,
                color: cs.error,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MachineTerminalMetaLine extends StatelessWidget {
  const _MachineTerminalMetaLine({
    required this.icon,
    required this.text,
    this.color,
  });

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final effectiveColor = color ?? cs.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 15, color: effectiveColor),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: effectiveColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _MachineTerminalChip extends StatelessWidget {
  const _MachineTerminalChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 188, minHeight: 28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
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

class _MachineTerminalIconButton extends StatelessWidget {
  const _MachineTerminalIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final duration = openHandMotionDuration(
      context,
      const Duration(milliseconds: 140),
    );
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: AnimatedOpacity(
          duration: duration,
          opacity: onPressed == null ? 0.42 : 1,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

TerminalTheme _machineTerminalTheme() {
  return const TerminalTheme(
    cursor: Color(0xFFE6F6C3),
    selection: Color(0x664D7CFF),
    foreground: Color(0xFFE7ECF3),
    background: Color(0xFF0B0D10),
    black: Color(0xFF101217),
    red: Color(0xFFFF6B6B),
    green: Color(0xFF5FE3A1),
    yellow: Color(0xFFE8D66B),
    blue: Color(0xFF75A7FF),
    magenta: Color(0xFFD98CFF),
    cyan: Color(0xFF62DCE8),
    white: Color(0xFFF4F7FB),
    brightBlack: Color(0xFF6E7681),
    brightRed: Color(0xFFFF8F86),
    brightGreen: Color(0xFF7CF3B6),
    brightYellow: Color(0xFFF4E58D),
    brightBlue: Color(0xFF9DBDFF),
    brightMagenta: Color(0xFFE7A8FF),
    brightCyan: Color(0xFF8FEAF2),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFE8D66B),
    searchHitBackgroundCurrent: Color(0xFF5FE3A1),
    searchHitForeground: Color(0xFF0B0D10),
  );
}

Color _terminalStatusColor(ColorScheme cs, MachineTerminalStatus status) {
  return switch (status) {
    MachineTerminalStatus.running => const Color(0xFF4C9A2A),
    MachineTerminalStatus.starting => cs.tertiary,
    MachineTerminalStatus.failed => cs.error,
    MachineTerminalStatus.stopped => cs.onSurfaceVariant,
    MachineTerminalStatus.idle => cs.secondary,
  };
}

String _statusLabel(BuildContext context, MachineTerminalStatus status) {
  return switch (status) {
    MachineTerminalStatus.running => _localizedText(
      context,
      zh: '运行中',
      en: 'Running',
    ),
    MachineTerminalStatus.starting => _localizedText(
      context,
      zh: '启动中',
      en: 'Starting',
    ),
    MachineTerminalStatus.stopped => _localizedText(
      context,
      zh: '已停止',
      en: 'Stopped',
    ),
    MachineTerminalStatus.failed => _localizedText(
      context,
      zh: '异常',
      en: 'Failed',
    ),
    MachineTerminalStatus.idle => _localizedText(context, zh: '待机', en: 'Idle'),
  };
}

int _terminalCommandTotal(List<MachineTerminalSnapshot> terminals) {
  return terminals.fold<int>(0, (total, item) => total + item.commandCount);
}

int _terminalHistoryBytes(List<MachineTerminalSnapshot> terminals) {
  return terminals.fold<int>(
    0,
    (total, item) => total + item.historyOutputCharacters,
  );
}

String _formatTerminalHistoryTime(DateTime value) {
  return formatYearMonthDayHms(value.toLocal());
}

String _replayAnsiOutput(MachineTerminalSnapshot snapshot) {
  final history = snapshot.historyAnsiOutput.trimRight();
  if (history.isNotEmpty) return history;
  final live = snapshot.ansiOutput.trimRight();
  if (live.isNotEmpty) return live;
  if (snapshot.commandHistory.isNotEmpty) {
    final buffer = StringBuffer()
      ..writeln('\x1b[38;5;108mOpenHand terminal command history\x1b[0m');
    for (final command in snapshot.commandHistory) {
      buffer
        ..writeln('\x1b[38;5;75m\$ ${command.command}\x1b[0m')
        ..write(command.output.trimRight())
        ..writeln()
        ..writeln(
          '\x1b[38;5;244mexit=${command.exitCode ?? '-'} timeout=${command.timedOut} duration=${command.durationMs}ms\x1b[0m',
        );
    }
    return buffer.toString();
  }
  return '\x1b[38;5;245mNo terminal history recorded.\x1b[0m\r\n';
}
