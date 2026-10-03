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
        Icon(icon, size: kOpenHandMessageActionIconSize, color: color),
        kOpenHandHGap8,
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: color),
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
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;
  final Color overlayColor;
  final Color sweepColor;
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
  );
}

abstract class _ElapsedMessageWidget extends StatefulWidget {
  const _ElapsedMessageWidget({super.key, required this.message});

  final AiSessionMessage message;

  bool get shouldTickElapsed;

  bool elapsedTimingChanged(covariant _ElapsedMessageWidget oldWidget);
}

abstract class _SweepElapsedMetaRow extends _ElapsedMessageWidget {
  const _SweepElapsedMetaRow({
    super.key,
    required super.message,
    required this.showSweep,
  });

  final bool showSweep;

  @override
  bool get shouldTickElapsed => showSweep;

  @override
  bool elapsedTimingChanged(covariant _SweepElapsedMetaRow oldWidget) {
    return oldWidget.showSweep != showSweep ||
        oldWidget.message.id != message.id ||
        oldWidget.message.createdAt != message.createdAt;
  }
}

class _ReasoningMetaRow extends _SweepElapsedMetaRow {
  const _ReasoningMetaRow({
    super.key,
    required super.message,
    required this.color,
    required super.showSweep,
    required this.expanded,
    required this.onTap,
  });

  final Color color;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_ReasoningMetaRow> createState() => _ReasoningMetaRowState();
}

class _ReasoningMetaRowState extends State<_ReasoningMetaRow>
    with WidgetsBindingObserver, _ForegroundElapsedTicker<_ReasoningMetaRow> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = AppLocalizations.of(context)!.messageReasoning;
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
          size: kOpenHandMessageActionIconSize,
          color: widget.color.withValues(alpha: widget.showSweep ? 0.94 : 0.88),
        ),
        kOpenHandHGap8,
        Flexible(
          child: Text(
            '$labelText$elapsedText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
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
            size: kOpenHandMessageActionIconSize,
          ),
        ),
      ],
    );
    final capsule = widget.showSweep
        ? _SweepBadge(
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            borderColor: Colors.white.withValues(alpha: 0.14),
            sweepColor: const Color(0x33E5E7EB),
            child: pillContent,
          )
        : Container(
            constraints: const BoxConstraints(
              minHeight: kOpenHandMessageActionChipHeight,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: kOpenHandMessageActionChipHorizontalPadding,
              vertical: kOpenHandMessageActionChipVerticalPadding,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(
                kOpenHandMessageActionChipRadius,
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: pillContent,
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(kOpenHandMessageActionChipRadius),
        overlayColor: WidgetStatePropertyAll<Color>(
          Colors.white.withValues(alpha: 0.03),
        ),
        child: capsule,
      ),
    );
  }
}

class _ResponseMetaRow extends _SweepElapsedMetaRow {
  const _ResponseMetaRow({
    super.key,
    required super.message,
    required super.showSweep,
    required this.expanded,
    required this.onTap,
  });

  final bool expanded;
  final VoidCallback? onTap;

  @override
  State<_ResponseMetaRow> createState() => _ResponseMetaRowState();
}

class _ResponseMetaRowState extends State<_ResponseMetaRow>
    with WidgetsBindingObserver, _ForegroundElapsedTicker<_ResponseMetaRow> {
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
        Icon(
          Icons.smart_toy_outlined,
          size: kOpenHandMessageActionIconSize,
          color: effectiveColor,
        ),
        kOpenHandHGap8,
        Flexible(
          child: Text(
            '$labelText$elapsedText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: effectiveColor),
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
              size: kOpenHandMessageActionIconSize,
            ),
          ),
        ],
      ],
    );
    final capsule = widget.showSweep
        ? _SweepBadge(
            backgroundColor: palette.backgroundColor,
            borderColor: palette.borderColor,
            sweepColor: palette.sweepColor,
            child: pillContent,
          )
        : AnimatedContainer(
            constraints: const BoxConstraints(
              minHeight: kOpenHandMessageActionChipHeight,
            ),
            duration: cardMotionDurationFor(context, expanding: false),
            curve: kCardDecorationMotionCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: kOpenHandMessageActionChipHorizontalPadding,
              vertical: kOpenHandMessageActionChipVerticalPadding,
            ),
            decoration: BoxDecoration(
              color: palette.backgroundColor,
              borderRadius: BorderRadius.circular(
                kOpenHandMessageActionChipRadius,
              ),
              border: Border.all(color: palette.borderColor),
            ),
            child: pillContent,
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(kOpenHandMessageActionChipRadius),
        overlayColor: WidgetStatePropertyAll<Color>(palette.overlayColor),
        child: capsule,
      ),
    );
  }
}

mixin _ForegroundElapsedTicker<T extends _ElapsedMessageWidget>
    on State<T>, WidgetsBindingObserver {
  Timer? _elapsedTimer;

  bool get shouldTickElapsed => widget.shouldTickElapsed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    syncElapsedTicker();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.elapsedTimingChanged(oldWidget)) {
      syncElapsedTicker();
    }
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

class _ToolCallMetaRow extends _ElapsedMessageWidget {
  const _ToolCallMetaRow({super.key, required super.message});

  @override
  bool get shouldTickElapsed => _shouldTickToolExecutionElapsed(message);

  @override
  bool elapsedTimingChanged(covariant _ToolCallMetaRow oldWidget) {
    return _toolExecutionTimingChanged(oldWidget.message, message);
  }

  @override
  State<_ToolCallMetaRow> createState() => _ToolCallMetaRowState();
}

class _ToolCallMetaRowState extends State<_ToolCallMetaRow>
    with WidgetsBindingObserver, _ForegroundElapsedTicker<_ToolCallMetaRow> {
  @override
  Widget build(BuildContext context) {
    final data = _ToolCallStatusViewData.from(context, widget.message);
    final theme = Theme.of(context);
    final showSweep = data.shouldSweepBadge;
    final status = _toolExecutionStatus(widget.message).toLowerCase();
    final effectiveColor = _isFailureStatus(status)
        ? theme.colorScheme.error
        : showSweep
        ? theme.colorScheme.primary
        : const {'success', 'ok', 'completed'}.contains(status)
        ? Color.alphaBlend(
            theme.colorScheme.onSurface.withValues(alpha: 0.35),
            OpenHandStatusColors.success,
          )
        : theme.colorScheme.onSurfaceVariant;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          data.statusIcon,
          size: kOpenHandMessageActionIconSize,
          color: effectiveColor,
        ),
        kOpenHandHGap8,
        Flexible(
          child: Text(
            data.statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: effectiveColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    if (showSweep) {
      return _SweepBadge(child: row);
    }
    return Container(
      constraints: const BoxConstraints(
        minHeight: kOpenHandMessageActionChipHeight,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: kOpenHandMessageActionChipHorizontalPadding,
        vertical: kOpenHandMessageActionChipVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kOpenHandMessageActionChipRadius),
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
    this.padding = const EdgeInsets.symmetric(
      horizontal: kOpenHandMessageActionChipHorizontalPadding,
      vertical: kOpenHandMessageActionChipVerticalPadding,
    ),
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
  Widget build(BuildContext context) {
    return _buildBadge(context);
  }

  Widget _buildBadge(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(
      kOpenHandMessageActionChipRadius,
    );
    final backgroundColor =
        this.backgroundColor ?? theme.colorScheme.surfaceContainerHigh;
    final borderColor =
        this.borderColor ??
        theme.colorScheme.outlineVariant.withValues(alpha: 0.45);
    final sweepColor =
        this.sweepColor ??
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius),
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kOpenHandMessageActionChipHeight,
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
