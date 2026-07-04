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
    return openHandBoundedProgress(parent.value, min: min, max: max);
  }
}

double openHandBoundedProgress(
  double value, {
  double min = kOpenHandAnimationProgressMin,
  double max = kOpenHandAnimationProgressMax,
}) {
  final (:lower, :upper) = _orderedFiniteAnimationBounds(min, max);
  if (value.isNaN) return lower;
  if (!value.isFinite) return value.isNegative ? lower : upper;
  return value.clamp(lower, upper).toDouble();
}

({double lower, double upper}) _orderedFiniteAnimationBounds(
  double min,
  double max,
) {
  final safeMin = min.isFinite ? min : kOpenHandAnimationProgressMin;
  final safeMax = max.isFinite ? max : kOpenHandAnimationProgressMax;
  return safeMin <= safeMax
      ? (lower: safeMin, upper: safeMax)
      : (lower: safeMax, upper: safeMin);
}

class OpenHandCurveAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  const OpenHandCurveAnimation({
    required this.parent,
    required this.curve,
    this.reverseCurve,
    this.clampOutput = false,
  });

  @override
  final Animation<double> parent;
  final Curve curve;
  final Curve? reverseCurve;
  final bool clampOutput;

  @override
  double get value {
    final rawProgress = openHandBoundedProgress(parent.value);
    final activeCurve = switch (parent.status) {
      AnimationStatus.reverse ||
      AnimationStatus.dismissed => reverseCurve ?? curve,
      AnimationStatus.forward || AnimationStatus.completed => curve,
    };
    final transformed = activeCurve.transform(rawProgress);
    if (clampOutput) return openHandBoundedProgress(transformed);
    if (transformed.isNaN) return kOpenHandAnimationProgressMin;
    if (!transformed.isFinite) {
      return transformed.isNegative
          ? kOpenHandAnimationProgressMin
          : kOpenHandAnimationProgressMax;
    }
    return transformed;
  }
}

Animation<double> openHandCurveAnimation({
  required Animation<double> parent,
  required Curve curve,
  Curve? reverseCurve,
  bool clampOutput = false,
}) {
  return OpenHandCurveAnimation(
    parent: parent,
    curve: curve,
    reverseCurve: reverseCurve,
    clampOutput: clampOutput,
  );
}

Animation<double> openHandBoundedCurveAnimation({
  required Animation<double> parent,
  required Curve curve,
  Curve? reverseCurve,
}) {
  return openHandCurveAnimation(
    parent: parent,
    curve: curve,
    reverseCurve: reverseCurve,
    clampOutput: true,
  );
}
