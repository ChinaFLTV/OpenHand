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
        kOpenHandHGap8,
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

class _MetaCapsulePalette {
  const _MetaCapsulePalette({
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
    required this.overlayColor,
    required this.sweepColor,
    required this.shadowColor,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;
  final Color overlayColor;
  final Color sweepColor;
  final Color shadowColor;
}

_MetaCapsulePalette _responseMetaCapsulePalette(
  ThemeData theme, {
  required bool active,
}) {
  final colorScheme = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  final accent = colorScheme.primary;
  final baseSurface = dark
      ? colorScheme.surfaceContainerHighest
      : colorScheme.surfaceContainerLowest;
  final backgroundAlpha = active ? (dark ? 0.30 : 0.18) : (dark ? 0.24 : 0.14);
  final borderAlpha = active ? (dark ? 0.58 : 0.42) : (dark ? 0.46 : 0.34);
  return _MetaCapsulePalette(
    backgroundColor: Color.alphaBlend(
      accent.withValues(alpha: backgroundAlpha),
      baseSurface,
    ),
    borderColor: accent.withValues(alpha: borderAlpha),
    foregroundColor: dark ? colorScheme.primaryContainer : accent,
    overlayColor: accent.withValues(alpha: dark ? 0.16 : 0.10),
    sweepColor: (dark ? colorScheme.onPrimaryContainer : accent).withValues(
      alpha: active ? 0.24 : 0.16,
    ),
    shadowColor: accent.withValues(alpha: dark ? 0.20 : 0.12),
  );
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
    with WidgetsBindingObserver, _ForegroundElapsedTicker<_ReasoningMetaRow> {
  @override
  bool get shouldTickElapsed => widget.showSweep;

  @override
  void didUpdateWidget(covariant _ReasoningMetaRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showSweep != widget.showSweep ||
        oldWidget.message.id != widget.message.id ||
        oldWidget.message.createdAt != widget.message.createdAt) {
      syncElapsedTicker();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = openHandLocalizedText(context, zh: '思考', en: 'Reasoning');
    final fixedElapsedMs = _reasoningFixedElapsedMs(widget.message);
    final elapsedMs = widget.showSweep
        ? _reasoningElapsedMs(widget.message)
        : fixedElapsedMs;
    final elapsedText = elapsedMs != null
        ? ' (${formatCompactDurationMs(elapsedMs)})'
        : '';
    final pillContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.psychology_alt_outlined,
          size: 18,
          color: widget.color.withValues(alpha: widget.showSweep ? 0.94 : 0.88),
        ),
        kOpenHandHGap8,
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
        kOpenHandHGap6,
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
              borderRadius: kOpenHandPillBorderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: pillContent,
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: kOpenHandPillBorderRadius,
        overlayColor: WidgetStatePropertyAll<Color>(
          Colors.white.withValues(alpha: 0.03),
        ),
        child: capsule,
      ),
    );
  }
}

class _ResponseMetaRow extends StatefulWidget {
  const _ResponseMetaRow({
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
  final VoidCallback? onTap;

  @override
  State<_ResponseMetaRow> createState() => _ResponseMetaRowState();
}

class _ResponseMetaRowState extends State<_ResponseMetaRow>
    with WidgetsBindingObserver, _ForegroundElapsedTicker<_ResponseMetaRow> {
  @override
  bool get shouldTickElapsed => widget.showSweep;

  @override
  void didUpdateWidget(covariant _ResponseMetaRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showSweep != widget.showSweep ||
        oldWidget.message.id != widget.message.id ||
        oldWidget.message.createdAt != widget.message.createdAt) {
      syncElapsedTicker();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = openHandResponseLabel(context);
    final elapsedText = widget.showSweep
        ? ' (${formatCompactDurationMs(_reasoningElapsedMs(widget.message))})'
        : '';
    final palette = _responseMetaCapsulePalette(
      theme,
      active: widget.showSweep,
    );
    final effectiveColor = palette.foregroundColor.withValues(
      alpha: widget.showSweep ? 0.98 : 0.94,
    );
    final pillContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.smart_toy_outlined, size: 18, color: effectiveColor),
        kOpenHandHGap8,
        Flexible(
          child: Text(
            '$labelText$elapsedText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(color: effectiveColor),
          ),
        ),
        if (widget.onTap != null) ...[
          kOpenHandHGap6,
          AnimatedRotation(
            turns: widget.expanded ? 0.5 : 0,
            duration: cardMotionDurationFor(
              context,
              expanding: widget.expanded,
            ),
            curve: kCardMotionCurve,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: palette.foregroundColor.withValues(alpha: 0.80),
              size: 18,
            ),
          ),
        ],
      ],
    );
    final capsule = widget.showSweep
        ? _SweepBadge(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            backgroundColor: palette.backgroundColor,
            borderColor: palette.borderColor,
            sweepColor: palette.sweepColor,
            boxShadow: [
              BoxShadow(
                color: palette.shadowColor,
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
            child: pillContent,
          )
        : AnimatedContainer(
            duration: cardMotionDurationFor(context, expanding: false),
            curve: kCardDecorationMotionCurve,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: palette.backgroundColor,
              borderRadius: kOpenHandPillBorderRadius,
              border: Border.all(color: palette.borderColor),
              boxShadow: [
                BoxShadow(
                  color: palette.shadowColor,
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: pillContent,
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: kOpenHandPillBorderRadius,
        overlayColor: WidgetStatePropertyAll<Color>(palette.overlayColor),
        child: capsule,
      ),
    );
  }
}

mixin _ForegroundElapsedTicker<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  Timer? _elapsedTimer;

  bool get shouldTickElapsed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    syncElapsedTicker();
  }

  void syncElapsedTicker() {
    _elapsedTimer?.cancel();
    if (!shouldTickElapsed) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return;
    }
    _elapsedTimer = startSafePeriodicTimer(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 应用进入后台时立刻熄火秒级 tick，回到前台再续；避免后台持续唤醒
    // 主 isolate 浪费 CPU（耗时显示无需在不可见时刷新）。
    syncElapsedTicker();
  }
}

class _ToolCallMetaRow extends StatefulWidget {
  const _ToolCallMetaRow({
    super.key,
    required this.message,
    required this.color,
  });

  final AiSessionMessage message;
  final Color color;

  @override
  State<_ToolCallMetaRow> createState() => _ToolCallMetaRowState();
}

class _ToolCallMetaRowState extends State<_ToolCallMetaRow>
    with WidgetsBindingObserver, _ForegroundElapsedTicker<_ToolCallMetaRow> {
  @override
  bool get shouldTickElapsed => _shouldTickToolExecutionElapsed(widget.message);

  @override
  void didUpdateWidget(covariant _ToolCallMetaRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_toolExecutionTimingChanged(oldWidget.message, widget.message)) {
      syncElapsedTicker();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _ToolCallStatusViewData.from(context, widget.message);
    final theme = Theme.of(context);
    final showSweep = data.shouldSweepBadge;
    final effectiveColor = showSweep
        ? theme.colorScheme.onSurfaceVariant
        : widget.color;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(data.statusIcon, size: 18, color: effectiveColor),
        kOpenHandHGap8,
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
        borderRadius: kOpenHandPillBorderRadius,
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

class _SweepBadge extends StatelessWidget {
  const _SweepBadge({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.backgroundColor,
    this.borderColor,
    this.sweepColor,
    this.boxShadow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? sweepColor;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    return _buildBadge(context);
  }

  Widget _buildBadge(BuildContext context) {
    final theme = Theme.of(context);
    const borderRadius = kOpenHandPillBorderRadius;
    final backgroundColor =
        this.backgroundColor ?? theme.colorScheme.surfaceContainerHigh;
    final borderColor =
        this.borderColor ??
        theme.colorScheme.outlineVariant.withValues(alpha: 0.45);
    final sweepColor =
        this.sweepColor ??
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: borderColor.a <= 0 ? null : Border.all(color: borderColor),
          ),
          child: OpenHandSweepShimmer(
            sweepColor: sweepColor,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
