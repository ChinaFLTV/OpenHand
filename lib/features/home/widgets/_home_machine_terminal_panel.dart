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
                child: TerminalView(
                  activeSession.terminal,
                  scrollController: _terminalScrollController,
                  focusNode: _terminalFocusNode,
                  autofocus: true,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  theme: _machineTerminalTheme(),
                  alwaysShowCursor: true,
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
    _showHomeSnackBar(
      context,
      SnackBar(
        content: Text(
          _localizedText(context, zh: '终端 ID 已复制。', en: 'Terminal ID copied.'),
        ),
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
          ],
        ),
      ],
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
