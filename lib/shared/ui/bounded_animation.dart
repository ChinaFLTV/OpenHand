import 'package:flutter/animation.dart';

const double kOpenHandAnimationProgressMin = 0.0;
const double kOpenHandAnimationProgressMax = 1.0;

/// Bounds animation progress before it reaches Flutter primitives that require
/// a strict 0..1 value, such as opacity, sizeFactor, or another Curve.
class OpenHandBoundedDoubleAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  const OpenHandBoundedDoubleAnimation(
    this.parent, {
    this.min = kOpenHandAnimationProgressMin,
    this.max = kOpenHandAnimationProgressMax,
  });

  @override
  final Animation<double> parent;
  final double min;
  final double max;

  @override
  double get value {
    final raw = parent.value;
    if (raw.isNaN) return min;
    if (!raw.isFinite) return raw.isNegative ? min : max;
    return raw.clamp(min, max).toDouble();
  }
}

Animation<double> openHandBoundedCurveAnimation({
  required Animation<double> parent,
  required Curve curve,
  Curve? reverseCurve,
}) {
  final safeParent = OpenHandBoundedDoubleAnimation(parent);
  return OpenHandBoundedDoubleAnimation(
    CurvedAnimation(
      parent: safeParent,
      curve: curve,
      reverseCurve: reverseCurve,
    ),
  );
}
