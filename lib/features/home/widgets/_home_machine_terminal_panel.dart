part of '../openhand_home_page.dart';

/// 终端画布底色：不随主题变化，始终保持深色以贴合终端配色。
const Color _machineTerminalBackground = Color(0xFF0B0D10);
const Color _machineTerminalGreen = Color(0xFF5FE3A1);
const Color _machineTerminalYellow = Color(0xFFE8D66B);
const Color _machineTerminalRunningColor = Color(0xFF4C9A2A);

/// 终端画布表面：深色底 + 细描边 + 一层托起阴影，圆角由调用方决定。
BoxDecoration _machineTerminalSurfaceDecoration(
  ColorScheme cs, {
  required double radius,
}) => BoxDecoration(
  color: _machineTerminalBackground,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.34)),
  boxShadow: <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.20),
      blurRadius: 24,
      offset: const Offset(0, 14),
    ),
  ],
);

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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_ensureTerminal()),
    );
  }

  @override
  void didUpdateWidget(covariant _MachineExpertTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _initializedSessionId = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_ensureTerminal()),
      );
    }
  }

  @override
  void dispose() {
    _terminalScrollController.dispose();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  Future<void> _ensureTerminal() async {
    if (!mounted || _initializedSessionId == widget.sessionId) return;
    final sessionId = widget.sessionId;
    _initializedSessionId = sessionId;
    final sessionController = context.read<AiSessionController>();
    AiSession? session;
    for (final candidate in sessionController.sessions) {
      if (candidate.id == sessionId) {
        session = candidate;
        break;
      }
    }
    final terminalMetadata = session?.metadata[kMachineTerminalMetadataKey];
    final terminalService = context.read<MachineTerminalService>();
    try {
      terminalService.rememberSessionMetadata(
        sessionId: sessionId,
        metadata: terminalMetadata,
      );
      await terminalService.ensureWorkspace(
        sessionId: sessionId,
        workingDirectory:
            MachineTerminalSessionMetadata.defaultWorkingDirectoryFrom(
              terminalMetadata,
            ),
        start: false,
      );
      if (!mounted || widget.sessionId != sessionId) return;
      await terminalService.startTerminal(sessionId: sessionId);
    } catch (error, stack) {
      silentLog('home_machine_terminal_panel', '初始化机器终端', error, stack);
      if (!mounted || widget.sessionId != sessionId) return;
      _initializedSessionId = null;
      showFriendlyErrorSnackBar(
        context,
        message: '$error',
        fallback: openHandLocalizedText(
          context,
          zh: '终端初始化失败。',
          en: 'Terminal initialization failed.',
        ),
      );
    }
  }

  void _followBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_terminalScrollController.hasClients) return;
      final position = _terminalScrollController.position;
      final target = position.maxScrollExtent;
      if ((position.pixels - target).abs() < 2) return;
      _terminalScrollController.animateTo(
        target,
        duration: kOpenHandMotion140,
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
                openHandLocalizedText(
                  context,
                  zh: '正在启动终端',
                  en: 'Starting terminal',
                ),
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
                  tooltip: _homeMachineTerClosePanelLabel(context),
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
          kOpenHandGap10,
          _MachineTerminalTabs(
            workspace: workspace,
            onSelected: (terminalId) => _control('select', terminalId),
            onClosed: (terminalId) => _control('close', terminalId),
          ),
          kOpenHandGap10,
          Expanded(
            child: DecoratedBox(
              decoration: _machineTerminalSurfaceDecoration(cs, radius: 8),
              child: ClipRRect(
                borderRadius: kOpenHandBorderRadius8,
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
          kOpenHandGap10,
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
      silentLog('home_machine_terminal_panel', '控制机器终端', error, stack);
      if (!mounted) return;
      showFriendlyErrorSnackBar(
        context,
        message: '$error',
        fallback: openHandLocalizedText(
          context,
          zh: '终端操作失败。',
          en: 'Terminal action failed.',
        ),
      );
    }
  }

  Future<void> _copyTerminalId(String terminalId) async {
    await copyOpenHandTextToClipboard(
      logTag: 'home',
      context: context,
      text: terminalId,
      logAction: '复制机器终端 ID',
      successMessage: openHandLocalizedText(
        context,
        zh: '终端 ID 已复制。',
        en: 'Terminal ID copied.',
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
          _MachineTerminalHistoryDetailDialog(snapshot: snapshot),
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
        borderRadius: BorderRadius.circular(kOpenHandRadius18),
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
                borderRadius: kOpenHandBorderRadius12,
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
            kOpenHandHGap10,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '机器终端',
                      en: 'Machine Terminal',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  kOpenHandGap3,
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
              tooltip: openHandCopyIdLabel(context),
              onPressed: onCopyId,
            ),
            if (onPanelClose != null) ...[
              kOpenHandHGap7,
              _MachineTerminalIconButton(
                icon: Icons.close_rounded,
                tooltip: _homeMachineTerClosePanelLabel(context),
                onPressed: onPanelClose,
              ),
            ],
          ],
        ),
        kOpenHandGap10,
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
        kOpenHandGap10,
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _MachineTerminalIconButton(
              icon: Icons.add_rounded,
              tooltip: openHandLocalizedText(
                context,
                zh: '新建终端',
                en: 'New Terminal',
              ),
              onPressed: onNew,
            ),
            _MachineTerminalIconButton(
              icon: Icons.content_copy_rounded,
              tooltip: openHandLocalizedText(
                context,
                zh: '复制终端',
                en: 'Duplicate Terminal',
              ),
              onPressed: onDuplicate,
            ),
            _MachineTerminalIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: openHandStartLabel(context),
              onPressed: canStart ? onStart : null,
            ),
            _MachineTerminalIconButton(
              icon: Icons.stop_rounded,
              tooltip: openHandLocalizedText(
                context,
                zh: '关闭进程',
                en: 'Stop Process',
              ),
              onPressed: canStop ? onStop : null,
            ),
            _MachineTerminalIconButton(
              icon: Icons.restart_alt_rounded,
              tooltip: openHandRestartLabel(context),
              onPressed: onRestart,
            ),
            _MachineTerminalIconButton(
              icon: Icons.cleaning_services_rounded,
              tooltip: openHandLocalizedText(context, zh: '清屏', en: 'Clear'),
              onPressed: onClear,
            ),
            _MachineTerminalIconButton(
              icon: Icons.history_rounded,
              tooltip: openHandLocalizedText(
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
  final ScrollController _verticalScrollController = ScrollController();
  String? _deletingTerminalId;
  String? _restoringTerminalId;

  @override
  void dispose() {
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terminalService = context.watch<MachineTerminalService>();
    final workspace = terminalService.snapshot(widget.sessionId);
    final terminals = workspace?.terminals ?? const <MachineTerminalSnapshot>[];
    final activeTerminals =
        workspace?.attachedTerminals ?? const <MachineTerminalSnapshot>[];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(
      math.max(360.0, viewport.width - 24),
      kOpenHandDialogWidthFull,
    );
    final dialogHeight = math.min(
      viewport.height * 0.86,
      kOpenHandDialogHeightTall,
    );
    final activeTerminalId = workspace?.activeTerminalId ?? '';

    return buildOpenHandDialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.none,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: kOpenHandBorderRadius20,
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
              title: openHandLocalizedText(
                context,
                zh: '终端执行历史',
                en: 'Terminal History',
              ),
              subtitle: openHandLocalizedText(
                context,
                zh: '当前线程关联 ${terminals.length} 个终端会话 · 面板 ${activeTerminals.length} 个 · 当前 ${activeTerminalId.isEmpty ? '-' : activeTerminalId}',
                en: '${terminals.length} terminal sessions · ${activeTerminals.length} in panel · active ${activeTerminalId.isEmpty ? '-' : activeTerminalId}',
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
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
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
      return OpenHandInlineEmptyState(
        message: openHandLocalizedText(
          context,
          zh: '暂无终端会话历史。',
          en: 'No terminal history yet.',
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.54)),
      ),
      child: ClipRRect(
        borderRadius: kOpenHandBorderRadius14,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = _MachineTerminalHistoryColumnLayout.fromWidth(
              constraints.maxWidth,
            );
            return OpenHandSafeScrollbar(
              controller: _verticalScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _verticalScrollController,
                physics: kOpenHandDialogScrollPhysics,
                child: SizedBox(
                  width: columns.tableWidth,
                  child: Column(
                    children: [
                      _historyHeaderRow(context, columns),
                      ...terminals.map(
                        (terminal) => _historyDataRow(
                          context,
                          terminal,
                          active: terminal.terminalId == activeTerminalId,
                          columns: columns,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _historyHeaderRow(
    BuildContext context,
    _MachineTerminalHistoryColumnLayout columns,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      color: cs.surfaceContainerHigh.withValues(alpha: 0.92),
      child: Row(
        children: [
          _historyCell(
            context,
            _homeTerminalLabel(context),
            width: columns.terminal,
            header: true,
          ),
          _historyCell(
            context,
            openHandStatusLabel(context),
            width: columns.status,
            header: true,
          ),
          _historyCell(context, 'PID', width: columns.pid, header: true),
          _historyCell(
            context,
            openHandLocalizedText(context, zh: '尺寸', en: 'Size'),
            width: columns.size,
            header: true,
          ),
          _historyCell(
            context,
            openHandLocalizedText(context, zh: '命令', en: 'Commands'),
            width: columns.commands,
            header: true,
          ),
          _historyCell(
            context,
            openHandOutputLabel(context),
            width: columns.output,
            header: true,
          ),
          _historyCell(
            context,
            openHandLocalizedText(context, zh: '启动时间', en: 'Started'),
            width: columns.started,
            header: true,
          ),
          _historyCell(
            context,
            openHandUpdatedLabel(context),
            width: columns.updated,
            header: true,
          ),
          _historyCell(
            context,
            openHandLocalizedText(context, zh: '操作', en: 'Actions'),
            width: columns.actions,
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
    required _MachineTerminalHistoryColumnLayout columns,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final deleting = _deletingTerminalId == terminal.terminalId;
    final restoring = _restoringTerminalId == terminal.terminalId;
    final actionDisabled = deleting || restoring;
    return AnimatedContainer(
      duration: openHandMotionDuration(
        context,
        kOpenHandMotion160,
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
          SizedBox(
            width: columns.detailWidth,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: actionDisabled
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                onTap: actionDisabled ? null : () => widget.onReplay(terminal),
                hoverColor: cs.primary.withValues(alpha: 0.045),
                splashColor: cs.primary.withValues(alpha: 0.08),
                highlightColor: cs.primary.withValues(alpha: 0.055),
                child: Row(
                  children: [
                    _historyCell(
                      context,
                      terminal.terminalId,
                      width: columns.terminal,
                      leading: Icon(
                        Icons.terminal_rounded,
                        size: 16,
                        color: _terminalStatusColor(cs, terminal.status),
                      ),
                      trailing: active
                          ? _MachineTerminalTinyBadge(
                              label: openHandLocalizedText(
                                context,
                                zh: '当前',
                                en: 'Active',
                              ),
                            )
                          : !terminal.attached
                          ? _MachineTerminalTinyBadge(
                              label: openHandLocalizedText(
                                context,
                                zh: '已关闭',
                                en: 'Closed',
                              ),
                            )
                          : null,
                    ),
                    SizedBox(
                      width: columns.status,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: _MachineTerminalStatusPill(
                            status: terminal.status,
                          ),
                        ),
                      ),
                    ),
                    _historyCell(
                      context,
                      terminal.pid == null ? '-' : '${terminal.pid}',
                      width: columns.pid,
                      mono: true,
                    ),
                    _historyCell(
                      context,
                      '${terminal.columns}x${terminal.rows}',
                      width: columns.size,
                      mono: true,
                    ),
                    _historyCell(
                      context,
                      '${terminal.commandCount}',
                      width: columns.commands,
                      mono: true,
                    ),
                    _historyCell(
                      context,
                      formatByteSize(terminal.historyOutputCharacters),
                      width: columns.output,
                      scaleDown: true,
                    ),
                    _historyCell(
                      context,
                      _formatTerminalHistoryTime(terminal.startedAt),
                      width: columns.started,
                      mono: true,
                      scaleDown: true,
                    ),
                    _historyCell(
                      context,
                      _formatTerminalHistoryTime(terminal.updatedAt),
                      width: columns.updated,
                      mono: true,
                      scaleDown: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: columns.actions,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _MachineTerminalMiniActionButton(
                  icon: Icons.subject_rounded,
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '查看详情',
                    en: 'View Details',
                  ),
                  onPressed: actionDisabled
                      ? null
                      : () => widget.onReplay(terminal),
                ),
                kOpenHandHGap6,
                _MachineTerminalMiniActionButton(
                  icon: restoring
                      ? Icons.hourglass_top_rounded
                      : Icons.restore_rounded,
                  tooltip: terminal.attached
                      ? openHandLocalizedText(
                          context,
                          zh: '已在终端面板中',
                          en: 'Already in Panel',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '恢复到终端面板',
                          en: 'Restore to Panel',
                        ),
                  onPressed: actionDisabled || terminal.attached
                      ? null
                      : () => _restoreTerminal(terminal),
                ),
                kOpenHandHGap6,
                _MachineTerminalMiniActionButton(
                  icon: deleting
                      ? Icons.hourglass_top_rounded
                      : Icons.delete_outline_rounded,
                  tooltip: openHandDeleteLabel(context),
                  destructive: true,
                  onPressed: actionDisabled
                      ? null
                      : () => _deleteTerminal(terminal),
                ),
                kOpenHandHGap10,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreTerminal(MachineTerminalSnapshot terminal) async {
    if (_restoringTerminalId != null || _deletingTerminalId != null) return;
    setState(() => _restoringTerminalId = terminal.terminalId);
    try {
      await context.read<MachineTerminalService>().control(
        sessionId: widget.sessionId,
        action: 'restore',
        terminalId: terminal.terminalId,
      );
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '终端会话已恢复到面板。',
          en: 'Terminal restored to the panel.',
        ),
      );
    } catch (error, stack) {
      silentLog('home_machine_terminal_panel', '恢复机器终端历史', error, stack);
      if (!mounted) return;
      showFriendlyErrorSnackBar(
        context,
        message: '$error',
        fallback: openHandLocalizedText(
          context,
          zh: '恢复终端会话失败。',
          en: 'Failed to restore terminal.',
        ),
      );
    } finally {
      if (mounted) setState(() => _restoringTerminalId = null);
    }
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
    bool scaleDown = false,
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
    final label = Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: scaleDown ? TextOverflow.visible : TextOverflow.ellipsis,
      style: style,
    );
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (leading != null) ...[leading, kOpenHandHGap7],
            Flexible(
              child: Align(
                alignment: alignEnd
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: scaleDown
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: alignEnd
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: label,
                      )
                    : label,
              ),
            ),
            if (trailing != null) ...[kOpenHandHGap7, trailing],
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTerminal(MachineTerminalSnapshot terminal) async {
    if (_deletingTerminalId != null) return;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '删除终端历史？',
        en: 'Delete Terminal History?',
      ),
      message: openHandLocalizedText(
        context,
        zh: '将删除 ${terminal.terminalId} 的会话、命令记录和历史输出，此操作不可恢复。',
        en: 'This will delete ${terminal.terminalId}, including command records and output history. This cannot be undone.',
      ),
      confirmLabel: openHandDeleteLabel(context),
      destructive: true,
    );
    if (!confirmed || !mounted || _deletingTerminalId != null) return;
    setState(() => _deletingTerminalId = terminal.terminalId);
    try {
      await context.read<MachineTerminalService>().control(
        sessionId: widget.sessionId,
        action: 'delete',
        terminalId: terminal.terminalId,
      );
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(context, zh: '终端会话已删除。', en: 'Terminal deleted.'),
      );
    } catch (error, stack) {
      silentLog('home_machine_terminal_panel', '删除机器终端历史', error, stack);
      if (!mounted) return;
      showFriendlyErrorSnackBar(
        context,
        message: '$error',
        fallback: openHandLocalizedText(
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

class _MachineTerminalHistoryColumnLayout {
  const _MachineTerminalHistoryColumnLayout({
    required this.terminal,
    required this.status,
    required this.pid,
    required this.size,
    required this.commands,
    required this.output,
    required this.started,
    required this.updated,
    required this.actions,
  });

  static const double _preferredTerminal = 136;
  static const double _preferredStatus = 92;
  static const double _preferredPid = 72;
  static const double _preferredSize = 70;
  static const double _preferredCommands = 62;
  static const double _preferredOutput = 88;
  static const double _preferredTime = 168;
  static const double _preferredActions = 142;

  static const double _compactTerminal = 112;
  static const double _compactStatus = 84;
  static const double _compactPid = 62;
  static const double _compactSize = 62;
  static const double _compactCommands = 54;
  static const double _compactOutput = 76;
  static const double _compactTime = 154;
  static const double _compactActions = 116;

  static const double _preferredTableWidth =
      _preferredTerminal +
      _preferredStatus +
      _preferredPid +
      _preferredSize +
      _preferredCommands +
      _preferredOutput +
      _preferredTime * 2 +
      _preferredActions;
  static const double _compactTableWidth =
      _compactTerminal +
      _compactStatus +
      _compactPid +
      _compactSize +
      _compactCommands +
      _compactOutput +
      _compactTime * 2 +
      _compactActions;

  final double terminal;
  final double status;
  final double pid;
  final double size;
  final double commands;
  final double output;
  final double started;
  final double updated;
  final double actions;

  double get tableWidth =>
      terminal +
      status +
      pid +
      size +
      commands +
      output +
      started +
      updated +
      actions;
  double get detailWidth => tableWidth - actions;

  static _MachineTerminalHistoryColumnLayout fromWidth(double maxWidth) {
    final safeWidth = maxWidth.isFinite && maxWidth > 0
        ? maxWidth
        : _preferredTableWidth;
    if (safeWidth >= _preferredTableWidth) {
      final extra = safeWidth - _preferredTableWidth;
      return _MachineTerminalHistoryColumnLayout(
        terminal: _preferredTerminal + extra * 0.35,
        status: _preferredStatus,
        pid: _preferredPid,
        size: _preferredSize,
        commands: _preferredCommands,
        output: _preferredOutput + extra * 0.15,
        started: _preferredTime + extra * 0.15,
        updated: _preferredTime + extra * 0.15,
        actions: _preferredActions + extra * 0.20,
      );
    }
    if (safeWidth <= _compactTableWidth) {
      final scale = safeWidth / _compactTableWidth;
      return _MachineTerminalHistoryColumnLayout(
        terminal: _compactTerminal * scale,
        status: _compactStatus * scale,
        pid: _compactPid * scale,
        size: _compactSize * scale,
        commands: _compactCommands * scale,
        output: _compactOutput * scale,
        started: _compactTime * scale,
        updated: _compactTime * scale,
        actions: _compactActions * scale,
      );
    }
    final scale =
        (safeWidth - _compactTableWidth) /
        (_preferredTableWidth - _compactTableWidth);
    return _MachineTerminalHistoryColumnLayout(
      terminal: _lerp(_compactTerminal, _preferredTerminal, scale),
      status: _lerp(_compactStatus, _preferredStatus, scale),
      pid: _lerp(_compactPid, _preferredPid, scale),
      size: _lerp(_compactSize, _preferredSize, scale),
      commands: _lerp(_compactCommands, _preferredCommands, scale),
      output: _lerp(_compactOutput, _preferredOutput, scale),
      started: _lerp(_compactTime, _preferredTime, scale),
      updated: _lerp(_compactTime, _preferredTime, scale),
      actions: _lerp(_compactActions, _preferredActions, scale),
    );
  }

  static double _lerp(double start, double end, double t) {
    return start + (end - start) * t.clamp(0.0, 1.0);
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
        label: _homeTerminalsLabel(context),
        value: '$terminalCount',
      ),
      _MachineTerminalHistoryMetric(
        icon: Icons.code_rounded,
        label: openHandLocalizedText(context, zh: '命令记录', en: 'Commands'),
        value: '$commandCount',
      ),
      _MachineTerminalHistoryMetric(
        icon: Icons.storage_rounded,
        label: openHandLocalizedText(context, zh: '历史输出', en: 'Output'),
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
                  if (index != metrics.length - 1) kOpenHandGap8,
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                Expanded(child: metrics[index]),
                if (index != metrics.length - 1) kOpenHandHGap10,
              ],
            ],
          );
        },
      ),
    );
  }
}

enum _MachineTerminalHistoryView { commands, replay }

const int _machineTerminalReplayScrollbackLines = 10000;
const EdgeInsets _machineTerminalReplayPadding = EdgeInsets.fromLTRB(
  14,
  12,
  14,
  12,
);

class _MachineTerminalHistoryDetailDialog extends StatefulWidget {
  const _MachineTerminalHistoryDetailDialog({required this.snapshot});

  final MachineTerminalSnapshot snapshot;

  @override
  State<_MachineTerminalHistoryDetailDialog> createState() =>
      _MachineTerminalHistoryDetailDialogState();
}

class _MachineTerminalHistoryDetailDialogState
    extends State<_MachineTerminalHistoryDetailDialog> {
  static const double kOpenHandDialogWidthFull = 980;
  static const double kOpenHandDialogHeightTall = 760;

  late _MachineTerminalHistoryView _selectedView;

  @override
  void initState() {
    super.initState();
    _selectedView = widget.snapshot.commandHistory.isEmpty
        ? _MachineTerminalHistoryView.replay
        : _MachineTerminalHistoryView.commands;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(
      viewport.width * 0.94,
      kOpenHandDialogWidthFull,
    );
    final dialogHeight = math.min(
      viewport.height * 0.88,
      kOpenHandDialogHeightTall,
    );

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
          borderRadius: kOpenHandBorderRadius20,
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
              icon: Icons.subject_rounded,
              title: openHandLocalizedText(
                context,
                zh: '终端历史详情',
                en: 'Terminal History Details',
              ),
              subtitle:
                  '${widget.snapshot.terminalId} · ${formatByteSize(widget.snapshot.historyOutputCharacters)} · ${openHandLocalizedText(context, zh: '命令', en: 'commands')} ${widget.snapshot.commandCount}',
              trailingActions: [
                _MachineTerminalIconButton(
                  icon: Icons.copy_all_rounded,
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '复制详情',
                    en: 'Copy Details',
                  ),
                  onPressed: _copyDetails,
                ),
              ],
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: SizedBox(
                width: double.infinity,
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
                      label:
                          '${widget.snapshot.columns}x${widget.snapshot.rows}',
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_MachineTerminalHistoryView>(
                  selected: <_MachineTerminalHistoryView>{_selectedView},
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment<_MachineTerminalHistoryView>(
                      value: _MachineTerminalHistoryView.commands,
                      icon: const Icon(Icons.list_alt_rounded, size: 18),
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '命令输出',
                          en: 'Commands',
                        ),
                      ),
                    ),
                    ButtonSegment<_MachineTerminalHistoryView>(
                      value: _MachineTerminalHistoryView.replay,
                      icon: const Icon(Icons.terminal_rounded, size: 18),
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '终端回放',
                          en: 'Replay',
                        ),
                      ),
                    ),
                  ],
                  onSelectionChanged: (selection) {
                    final next = selection.isEmpty ? null : selection.first;
                    if (next == null || next == _selectedView) return;
                    setState(() => _selectedView = next);
                  },
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: AnimatedSwitcher(
                  duration: openHandMotionDuration(context, kOpenHandMotion180,
                  ),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: KeyedSubtree(
                    key: ValueKey<_MachineTerminalHistoryView>(_selectedView),
                    child: _selectedView == _MachineTerminalHistoryView.commands
                        ? _MachineTerminalCommandHistoryList(
                            snapshot: widget.snapshot,
                          )
                        : _MachineTerminalReplayView(snapshot: widget.snapshot),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyDetails() async {
    await copyOpenHandTextToClipboard(
      logTag: 'home',
      context: context,
      text: _terminalHistoryDetailText(widget.snapshot),
      logAction: '复制机器终端历史详情',
      successMessage: openHandLocalizedText(
        context,
        zh: '终端历史详情已复制。',
        en: 'Terminal history details copied.',
      ),
    );
  }
}

class _MachineTerminalReplayView extends StatefulWidget {
  const _MachineTerminalReplayView({required this.snapshot});

  final MachineTerminalSnapshot snapshot;

  @override
  State<_MachineTerminalReplayView> createState() =>
      _MachineTerminalReplayViewState();
}

class _MachineTerminalReplayViewState
    extends State<_MachineTerminalReplayView> {
  late Terminal _terminal;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'machine-terminal-replay');
  bool _replayScheduled = false;
  String? _renderedReplayKey;

  @override
  void initState() {
    super.initState();
    _terminal = _createTerminal();
  }

  @override
  void didUpdateWidget(covariant _MachineTerminalReplayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_snapshotReplayIdentity(oldWidget.snapshot) !=
        _snapshotReplayIdentity(widget.snapshot)) {
      _terminal = _createTerminal();
      _renderedReplayKey = null;
      _replayScheduled = false;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    _scheduleReplay();
    return DecoratedBox(
      decoration: _machineTerminalSurfaceDecoration(cs, radius: 14),
      child: ClipRRect(
        borderRadius: kOpenHandBorderRadius14,
        child: RepaintBoundary(
          child: TerminalView(
            _terminal,
            scrollController: _scrollController,
            focusNode: _focusNode,
            padding: _machineTerminalReplayPadding,
            theme: _machineTerminalTheme(),
            readOnly: true,
          ),
        ),
      ),
    );
  }

  Terminal _createTerminal() {
    return Terminal(maxLines: _machineTerminalReplayScrollbackLines);
  }

  void _scheduleReplay() {
    if (_replayScheduled) return;
    _replayScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _replayScheduled = false;
      final replayKey = _snapshotReplayIdentity(widget.snapshot);
      if (_renderedReplayKey == replayKey) return;
      _terminal.write(_replayAnsiOutput(widget.snapshot));
      _renderedReplayKey = replayKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.minScrollExtent);
      });
    });
  }

  String _snapshotReplayIdentity(MachineTerminalSnapshot snapshot) {
    return [
      snapshot.terminalId,
      snapshot.updatedAt.microsecondsSinceEpoch,
      snapshot.historyOutputCharacters,
      snapshot.outputCharacters,
      snapshot.commandCount,
    ].join(':');
  }
}

class _MachineTerminalCommandHistoryList extends StatelessWidget {
  const _MachineTerminalCommandHistoryList({required this.snapshot});

  final MachineTerminalSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final commands = snapshot.commandHistory;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (commands.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
          borderRadius: kOpenHandBorderRadius14,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.48)),
        ),
        child: OpenHandInlineEmptyState(
          message: openHandLocalizedText(
            context,
            zh: '暂无结构化命令记录。',
            en: 'No structured command records.',
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.48)),
      ),
      child: ClipRRect(
        borderRadius: kOpenHandBorderRadius14,
        child: ListView.separated(
          physics: kOpenHandDialogScrollPhysics,
          padding: const EdgeInsets.all(12),
          itemBuilder: (context, index) {
            final command = commands[index];
            return _MachineTerminalCommandHistoryTile(
              record: command,
              index: index + 1,
              total: commands.length,
            );
          },
          separatorBuilder: (_, _) => kOpenHandGap10,
          itemCount: commands.length,
        ),
      ),
    );
  }
}

class _MachineTerminalCommandHistoryTile extends StatelessWidget {
  const _MachineTerminalCommandHistoryTile({
    required this.record,
    required this.index,
    required this.total,
  });

  final MachineTerminalCommandRecord record;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _commandRecordColor(cs, record);
    final output = _commandRecordOutput(record);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.72),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.42)),
      ),
      child: OpenHandExpansionTile(
        initiallyExpanded: index == total,
        tilePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(kOpenHandRadius9),
            border: Border.all(color: color.withValues(alpha: 0.24)),
          ),
          child: Icon(_commandRecordIcon(record), size: 17, color: color),
        ),
        title: Text(
          record.command,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w800,
            fontFamily: kOpenHandMonospaceFontFamily,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 7,
            runSpacing: 5,
            children: [
              _MachineTerminalTinyBadge(label: '#$index'),
              _MachineTerminalTinyBadge(
                label: 'exit ${record.exitCode ?? '-'}',
              ),
              _MachineTerminalTinyBadge(label: '${record.durationMs}ms'),
              if (record.timedOut)
                _MachineTerminalTinyBadge(
                  label: openHandTimedOutLabel(context),
                ),
              _MachineTerminalTinyBadge(
                label: _formatTerminalHistoryTime(record.completedAt),
              ),
            ],
          ),
        ),
        trailing: _MachineTerminalMiniActionButton(
          icon: Icons.copy_rounded,
          tooltip: openHandLocalizedText(
            context,
            zh: '复制输出',
            en: 'Copy Output',
          ),
          onPressed: () => _copyCommandRecord(context, record),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              output,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
                fontFamily: kOpenHandMonospaceFontFamily,
              ),
            ),
          ),
        ],
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
    this.trailingActions = const <Widget>[],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final List<Widget> trailingActions;

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
              borderRadius: kOpenHandBorderRadius14,
              border: Border.all(color: cs.primary.withValues(alpha: 0.26)),
            ),
            child: Icon(icon, color: cs.primary, size: 22),
          ),
          kOpenHandHGap12,
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
                kOpenHandGap3,
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
          for (final action in trailingActions) ...[
            kOpenHandHGap7,
            action,
          ],
          if (trailingActions.isNotEmpty) kOpenHandHGap7,
          _MachineTerminalIconButton(
            icon: Icons.close_rounded,
            tooltip: openHandCloseLabel(context),
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
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.44)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.primary),
            kOpenHandHGap9,
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
            kOpenHandHGap8,
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
        borderRadius: kOpenHandPillBorderRadius,
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
        borderRadius: kOpenHandPillBorderRadius,
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
        borderRadius: BorderRadius.circular(kOpenHandRadius9),
        onTap: onPressed,
        child: AnimatedOpacity(
          duration: openHandMotionDuration(context, kOpenHandMotion140,
          ),
          opacity: enabled ? 1 : 0.45,
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: destructive ? 0.10 : 0.12),
              borderRadius: BorderRadius.circular(kOpenHandRadius9),
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
      kOpenHandMotion160,
    );
    final terminals = workspace.attachedTerminals;
    final canCloseTabs = terminals.isNotEmpty;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final terminal = terminals[index];
          final selected = terminal.terminalId == workspace.activeTerminalId;
          return InkWell(
            borderRadius: kOpenHandBorderRadius8,
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
                borderRadius: kOpenHandBorderRadius8,
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
                  kOpenHandHGap7,
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
                    kOpenHandHGap5,
                    _MachineTerminalTabCloseButton(
                      onPressed: () => onClosed(terminal.terminalId),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, _) => kOpenHandHGap7,
        itemCount: terminals.length,
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
      message: openHandLocalizedText(context, zh: '关闭终端', en: 'Close Terminal'),
      child: InkResponse(
        onTap: onPressed,
        radius: 13,
        containedInkWell: true,
        borderRadius: BorderRadius.circular(kOpenHandRadius7),
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
        borderRadius: kOpenHandBorderRadius8,
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
            kOpenHandGap5,
            _MachineTerminalMetaLine(
              icon: Icons.schedule_rounded,
              text:
                  '${openHandLocalizedText(context, zh: '更新', en: 'Updated')} ${formatYearMonthDayHmsLocal(snapshot.updatedAt)}',
            ),
            if (snapshot.errorMessage != null) ...[
              kOpenHandGap5,
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
        kOpenHandHGap7,
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
          borderRadius: kOpenHandBorderRadius8,
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              kOpenHandHGap6,
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
    final duration = openHandMotionDuration(context, kOpenHandMotion140,
    );
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: kOpenHandBorderRadius8,
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
              borderRadius: kOpenHandBorderRadius8,
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
    background: _machineTerminalBackground,
    black: Color(0xFF101217),
    red: Color(0xFFFF6B6B),
    green: _machineTerminalGreen,
    yellow: _machineTerminalYellow,
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
    searchHitBackground: _machineTerminalYellow,
    searchHitBackgroundCurrent: _machineTerminalGreen,
    searchHitForeground: _machineTerminalBackground,
  );
}

Color _terminalStatusColor(ColorScheme cs, MachineTerminalStatus status) {
  return switch (status) {
    MachineTerminalStatus.running => _machineTerminalRunningColor,
    MachineTerminalStatus.starting => cs.tertiary,
    MachineTerminalStatus.failed => cs.error,
    MachineTerminalStatus.stopped => cs.onSurfaceVariant,
    MachineTerminalStatus.idle => cs.secondary,
  };
}

String _statusLabel(BuildContext context, MachineTerminalStatus status) {
  return switch (status) {
    MachineTerminalStatus.running => openHandRunningLabel(context),
    MachineTerminalStatus.starting => _homeStartingLabel(context),
    MachineTerminalStatus.stopped => openHandStoppedLabel(context),
    MachineTerminalStatus.failed => _homeFailedLabel(context),
    MachineTerminalStatus.idle => openHandLocalizedText(
      context,
      zh: '待机',
      en: 'Idle',
    ),
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
  return formatYearMonthDayHmsLocal(value);
}

Future<void> _copyCommandRecord(
  BuildContext context,
  MachineTerminalCommandRecord record,
) async {
  await copyOpenHandTextToClipboard(
    logTag: 'home',
    context: context,
    text: _commandRecordDetailText(record),
    logAction: '复制机器终端命令输出',
    successMessage: openHandLocalizedText(
      context,
      zh: '命令输出已复制。',
      en: 'Command output copied.',
    ),
  );
}

Color _commandRecordColor(ColorScheme cs, MachineTerminalCommandRecord record) {
  if (record.timedOut) return cs.tertiary;
  if (record.error != null && record.error!.trim().isNotEmpty) return cs.error;
  return record.exitCode == 0 ? _machineTerminalRunningColor : cs.error;
}

IconData _commandRecordIcon(MachineTerminalCommandRecord record) {
  if (record.timedOut) return Icons.timer_off_rounded;
  if (record.error != null && record.error!.trim().isNotEmpty) {
    return Icons.error_outline_rounded;
  }
  return record.exitCode == 0
      ? Icons.check_rounded
      : record.exitCode == null
      ? Icons.error_outline_rounded
      : Icons.close_rounded;
}

String _commandRecordOutput(MachineTerminalCommandRecord record) {
  final output = record.output.trimRight();
  final error = record.error?.trim();
  if (output.isNotEmpty && error != null && error.isNotEmpty) {
    return '$output\n\nerror: $error';
  }
  if (output.isNotEmpty) return output;
  if (error != null && error.isNotEmpty) return 'error: $error';
  return '(no output)';
}

String _commandRecordDetailText(MachineTerminalCommandRecord record) {
  return [
    '\$ ${record.command}',
    'terminal_id: ${record.terminalId}',
    'started_at: ${record.startedAt.toLocal().toIso8601String()}',
    'completed_at: ${record.completedAt.toLocal().toIso8601String()}',
    'duration_ms: ${record.durationMs}',
    'exit_code: ${record.exitCode ?? '-'}',
    'timed_out: ${record.timedOut}',
    if (record.error != null && record.error!.trim().isNotEmpty)
      'error: ${record.error!.trim()}',
    'output:',
    _commandRecordOutput(record),
  ].join('\n');
}

String _terminalHistoryDetailText(MachineTerminalSnapshot snapshot) {
  final buffer = StringBuffer()
    ..writeln('terminal_id: ${snapshot.terminalId}')
    ..writeln('identity: ${snapshot.identity}')
    ..writeln('status: ${snapshot.status.storageValue}')
    ..writeln('shell: ${snapshot.shell}')
    ..writeln('working_directory: ${snapshot.workingDirectory}')
    ..writeln('size: ${snapshot.columns}x${snapshot.rows}')
    ..writeln('attached: ${snapshot.attached}')
    ..writeln('pid: ${snapshot.pid ?? '-'}')
    ..writeln('started_at: ${snapshot.startedAt.toLocal().toIso8601String()}')
    ..writeln('updated_at: ${snapshot.updatedAt.toLocal().toIso8601String()}')
    ..writeln('command_count: ${snapshot.commandCount}')
    ..writeln('history_output_characters: ${snapshot.historyOutputCharacters}');
  if (snapshot.commandHistory.isNotEmpty) {
    buffer.writeln('\ncommands:');
    for (final record in snapshot.commandHistory) {
      buffer
        ..writeln('\n--- ${record.id} ---')
        ..writeln(_commandRecordDetailText(record));
    }
  }
  final history = snapshot.historyOutput.trimRight();
  if (history.isNotEmpty) {
    buffer
      ..writeln('\nterminal_output:')
      ..write(history);
  }
  return buffer.toString().trimRight();
}

String _replayAnsiOutput(MachineTerminalSnapshot snapshot) {
  final history = snapshot.historyAnsiOutput.trimRight();
  if (history.isNotEmpty) return history;
  final live = snapshot.ansiOutput.trimRight();
  if (live.isNotEmpty) return live;
  if (snapshot.commandHistory.isNotEmpty) {
    final buffer = StringBuffer()
      ..writeln('\x1b[38;5;108mOpenHand 终端命令历史\x1b[0m');
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
  return '\x1b[38;5;245m暂无终端历史记录。\x1b[0m\r\n';
}

// ── 本文件内复用的文案 ──
// 同一标签在本文件里出现两次以上；抽成函数后措辞只有一个改动点。

String _homeMachineTerClosePanelLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '关闭面板', en: 'Close Panel');
}
