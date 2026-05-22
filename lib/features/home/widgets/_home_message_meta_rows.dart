part of '../openhand_home_page.dart';

class _MessageMetaRow extends StatelessWidget {
  const _MessageMetaRow({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _ReasoningMetaRow extends StatefulWidget {
  const _ReasoningMetaRow({
    super.key,
    required this.message,
    required this.color,
    required this.showSweep,
    required this.expanded,
    required this.onTap,
  });

  final AiSessionMessage message;
  final Color color;
  final bool showSweep;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_ReasoningMetaRow> createState() => _ReasoningMetaRowState();
}

class _ReasoningMetaRowState extends State<_ReasoningMetaRow>
    with WidgetsBindingObserver {
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncElapsedTimer();
  }

  @override
  void didUpdateWidget(covariant _ReasoningMetaRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showSweep != widget.showSweep ||
        oldWidget.message.id != widget.message.id ||
        oldWidget.message.createdAt != widget.message.createdAt) {
      _syncElapsedTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 应用进入后台时立刻熄火秒级 tick，回到前台再续；避免后台持续唤醒
    // 主 isolate 浪费 CPU（思考耗时显示无需在不可见时刷新）。
    _syncElapsedTimer();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncElapsedTimer() {
    _elapsedTimer?.cancel();
    if (!widget.showSweep) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return;
    }
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = _localizedText(context, zh: '思考', en: 'Reasoning');
    final elapsedText = widget.showSweep
        ? ' (${_formatToolExecutionDuration(_reasoningElapsedMs(widget.message))})'
        : '';
    final pillContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.psychology_alt_outlined,
          size: 18,
          color: widget.color.withValues(alpha: widget.showSweep ? 0.94 : 0.88),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$labelText$elapsedText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: widget.color.withValues(
                alpha: widget.showSweep ? 0.94 : 0.88,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        AnimatedRotation(
          turns: widget.expanded ? 0.5 : 0,
          duration: cardMotionDurationFor(context, expanding: widget.expanded),
          curve: kCardMotionCurve,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: widget.color.withValues(alpha: 0.78),
            size: 18,
          ),
        ),
      ],
    );
    final capsule = widget.showSweep
        ? _SweepBadge(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            borderColor: Colors.white.withValues(alpha: 0.14),
            sweepColor: const Color(0x33E5E7EB),
            child: pillContent,
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: _borderRadius999,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: pillContent,
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: _borderRadius999,
        overlayColor: WidgetStatePropertyAll<Color>(
          Colors.white.withValues(alpha: 0.03),
        ),
        child: capsule,
      ),
    );
  }
}

class _ToolCallMetaRow extends StatelessWidget {
  const _ToolCallMetaRow({super.key, required this.data, required this.color});

  final _ToolCallStatusViewData data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSweep = data.shouldSweepBadge;
    final effectiveColor = showSweep
        ? theme.colorScheme.onSurfaceVariant
        : color;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(data.statusIcon, size: 18, color: effectiveColor),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            data.statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(color: effectiveColor),
          ),
        ),
      ],
    );
    if (showSweep) {
      return _SweepBadge(child: row);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: _borderRadius999,
      ),
      child: row,
    );
  }
}

class _ToolCallStatusViewData {
  const _ToolCallStatusViewData({
    required this.shouldSweepBadge,
    required this.statusIcon,
    required this.statusLabel,
  });

  factory _ToolCallStatusViewData.from(
    BuildContext context,
    AiSessionMessage message,
  ) {
    final presentation = _toolCallPresentation(context, message);
    final status = _toolExecutionStatus(message);
    final durationMs = _toolExecutionDurationMs(message);
    return _ToolCallStatusViewData(
      shouldSweepBadge: _shouldSweepToolStatus(status),
      statusIcon: _toolExecutionStatusIcon(status),
      statusLabel: _toolCallStatusLabelForData(
        context,
        presentation,
        status,
        durationMs,
      ),
    );
  }

  final bool shouldSweepBadge;
  final IconData statusIcon;
  final String statusLabel;
}

class _SweepBadge extends StatefulWidget {
  const _SweepBadge({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.backgroundColor,
    this.borderColor,
    this.sweepColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? sweepColor;

  @override
  State<_SweepBadge> createState() => _SweepBadgeState();
}

class _SweepBadgeState extends State<_SweepBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animationsEnabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (!animationsEnabled) {
      _controller.stop();
      return _buildBadge(context, progress: null);
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
    return AnimatedBuilder(
      animation: _controller,
      child: Padding(padding: widget.padding, child: widget.child),
      builder: (context, child) {
        return _buildBadge(context, progress: _controller.value, child: child);
      },
    );
  }

  Widget _buildBadge(
    BuildContext context, {
    required double? progress,
    Widget? child,
  }) {
    final theme = Theme.of(context);
    const borderRadius = BorderRadius.all(Radius.circular(999));
    final backgroundColor =
        widget.backgroundColor ?? theme.colorScheme.surfaceContainerHigh;
    final borderColor =
        widget.borderColor ??
        theme.colorScheme.outlineVariant.withValues(alpha: 0.45);
    final sweepColor =
        widget.sweepColor ??
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2);
    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
          border: borderColor.a <= 0 ? null : Border.all(color: borderColor),
        ),
        child: Stack(
          children: [
            if (progress != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1.8 + progress * 2.8, 0),
                      end: Alignment(-0.9 + progress * 2.8, 0),
                      colors: [
                        Colors.transparent,
                        sweepColor,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            child ?? Padding(padding: widget.padding, child: widget.child),
          ],
        ),
      ),
    );
  }
}
