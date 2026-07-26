/// 时长的边界裁剪与取小。
///
/// 收敛全库重复出现的两类写法：把倒计时 / 剩余预算裁剪回非负，以及把单步超时
/// 压到总预算之内。此前这两段各自在超时控制、原子写盘、倒计时弹窗里手写多份，
/// 边界条件（`<` 还是 `<=`、零值怎么算）随文件漂移。
library;

/// 负时长归零。用于倒计时、剩余预算一类不允许出现负值的场景。
Duration nonNegativeDuration(Duration value) {
  return value.isNegative ? Duration.zero : value;
}

/// 取两个时长中较短者。用于「单步超时不得超过总预算」。
Duration shorterDuration(Duration first, Duration second) {
  return first <= second ? first : second;
}

/// [deadline] 距当前时刻的剩余时长，已过期时返回零。
///
/// [deadline] 与 `DateTime.now()` 必须同为 UTC 或同为本地时区，否则得到的差值
/// 会带上时区偏移。
Duration remainingUntil(DateTime deadline) {
  return nonNegativeDuration(deadline.difference(DateTime.now().toUtc()));
}
