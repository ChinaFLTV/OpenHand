/// 负时长归零。用于倒计时、剩余预算一类不允许出现负值的场景。
Duration nonNegativeDuration(Duration value) {
  return value.isNegative ? Duration.zero : value;
}

/// 取两个时长中较短者。用于「单步超时不得超过总预算」。
Duration shorterDuration(Duration first, Duration second) {
  return first <= second ? first : second;
}
