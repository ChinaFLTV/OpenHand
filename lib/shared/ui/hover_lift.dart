import 'package:flutter/material.dart';

import 'motion_preference.dart';

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

  double get _safeLiftDistance {
    return widget.liftDistance.isFinite && widget.liftDistance > 0
        ? widget.liftDistance
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = openHandReduceMotionOf(context);
    final lift = (_hovered && !reduceMotion) ? -_safeLiftDistance : 0.0;
    return MouseRegion(
      onEnter: (_) {
        if (_hovered) return;
        _hovered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      onExit: (_) {
        if (!_hovered) return;
        _hovered = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: lift),
        duration: openHandMotionDuration(context, widget.duration),
        curve: widget.curve,
        builder: (context, value, child) {
          return Transform.translate(offset: Offset(0, value), child: child);
        },
        child: widget.child,
      ),
    );
  }
}
