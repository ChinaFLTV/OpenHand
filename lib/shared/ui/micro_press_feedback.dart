import 'package:flutter/material.dart';

import 'motion_preference.dart';

/// Wraps a tappable child (typically an [IconButton] or small action
/// affordance) and provides an 80 ms press-down scale + 140 ms ease-out
/// rebound on pointer events. The wrapper does NOT consume the tap —
/// it uses [Listener] with translucent hit-test behavior so the inner
/// child still receives the actual gesture and runs its `onPressed`.
///
/// Honors `MediaQuery.disableAnimationsOf(context)` (reduceMotion):
/// when on, the animation is skipped and the child renders unscaled.
///
/// Use sparingly on toolbar buttons / chip actions where a brief
/// tactile "click" feel is desired.
class MicroPressFeedback extends StatefulWidget {
  const MicroPressFeedback({
    super.key,
    required this.child,
    this.scale = 0.88,
    this.enabled = true,
  });

  final Widget child;

  /// Target scale at the depressed peak. 1.0 = no shrink.
  final double scale;

  /// Set to false to bypass the wrapper entirely (e.g. when the child
  /// is disabled and visually shouldn't react to pointer-down).
  final bool enabled;

  @override
  State<MicroPressFeedback> createState() => _MicroPressFeedbackState();
}

class _MicroPressFeedbackState extends State<MicroPressFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 140),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDown() {
    if (!widget.enabled) return;
    if (openHandReduceMotionOf(context)) return;
    _ctrl.forward();
  }

  void _onUp() {
    if (_ctrl.value == 0) return;
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onDown(),
      onPointerUp: (_) => _onUp(),
      onPointerCancel: (_) => _onUp(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_ctrl.value);
          final s = 1.0 - (1.0 - widget.scale) * t;
          return Transform.scale(scale: s, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
