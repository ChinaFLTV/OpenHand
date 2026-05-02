import 'package:flutter/material.dart';

/// Wraps a child with a subtle pointer-hover lift: on hover, the child
/// translates upwards by [liftDistance] pixels and gains a slightly
/// stronger shadow. Designed for list/grid cards where a faint
/// "rises to meet the cursor" affordance is desired.
///
/// Honors `MediaQuery.disableAnimationsOf(context)` (reduceMotion):
/// when on, the lift / shadow animation is skipped and the child
/// renders flat.
///
/// On touch-only platforms `MouseRegion` simply never fires, so this
/// wrapper is a no-op in that case — no extra cost on mobile.
class HoverLift extends StatefulWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.liftDistance = 2.0,
    this.duration = const Duration(milliseconds: 180),
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;

  /// Vertical translation distance at the lifted peak (pixels).
  final double liftDistance;

  final Duration duration;
  final Curve curve;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lift = (_hovered && !reduceMotion) ? -widget.liftDistance : 0.0;
    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: lift),
        duration: reduceMotion ? Duration.zero : widget.duration,
        curve: widget.curve,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, value),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
