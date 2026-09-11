/// 负时长归零。用于倒计时、剩余预算一类不允许出现负值的场景。
Duration nonNegativeDuration(Duration value) {
  return value.isNegative ? Duration.zero : value;
}

/// 取两个时长中较短者。用于「单步超时不得超过总预算」。
Duration shorterDuration(Duration first, Duration second) {
  return first <= second ? first : second;
}

/// 把时长夹到 [min, max]。两端颠倒时按实际大小排序，避免调用方写反边界。
Duration clampDuration(
  Duration value, {
  required Duration min,
  required Duration max,
}) {
  final lower = min <= max ? min : max;
  final upper = min <= max ? max : min;
  if (value < lower) return lower;
  if (value > upper) return upper;
  return value;
}

/// 按比例缩放时长并限制在合法范围内。
///
/// 手势或外部输入可能提供零值、负值或非有限比例；这些值无法产生可靠
/// 的缩放结果，统一返回空值交由调用方忽略本次更新。
Duration? scaledDurationWithinRange(
  Duration value,
  double scale, {
  required Duration min,
  required Duration max,
}) {
  if (!scale.isFinite || scale <= 0) return null;
  final scaledMilliseconds = value.inMilliseconds / scale;
  if (!scaledMilliseconds.isFinite) return null;

  final firstBound = min.inMilliseconds;
  final secondBound = max.inMilliseconds;
  final lowerBound = firstBound <= secondBound ? firstBound : secondBound;
  final upperBound = firstBound <= secondBound ? secondBound : firstBound;
  final milliseconds = scaledMilliseconds.round().clamp(lowerBound, upperBound);
  return Duration(milliseconds: milliseconds);
}
