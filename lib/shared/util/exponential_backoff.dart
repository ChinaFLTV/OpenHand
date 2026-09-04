const int _kMinimumBackoffUnit = 1;
const int _kMaxBackoffDoublings = 62;

/// 通用指数退避公式：第 `attempt` 次重试前等待 `base * 2^(attempt-1)`，
/// 并限制在 [base, cap] 内。
int exponentialBackoffMs({
  required int attempt,
  required int baseMs,
  required int capMs,
}) {
  if (attempt <= 0) return 0;
  final safeBaseMs = baseMs <= 0 ? _kMinimumBackoffUnit : baseMs;
  final safeCapMs = capMs < safeBaseMs ? safeBaseMs : capMs;

  var value = safeBaseMs;
  var remainingDoublings = attempt - 1;
  var doublings = 0;
  while (remainingDoublings > 0 && doublings < _kMaxBackoffDoublings) {
    if (value >= safeCapMs || value > safeCapMs ~/ 2) {
      return safeCapMs;
    }
    value *= 2;
    remainingDoublings--;
    doublings++;
  }
  return remainingDoublings > 0 ? safeCapMs : value;
}

/// 秒级糖：和 [exponentialBackoffMs] 同一公式，仅单位换成秒。
int exponentialBackoffSeconds({
  required int attempt,
  required int baseSeconds,
  required int capSeconds,
}) {
  return exponentialBackoffMs(
    attempt: attempt,
    baseMs: baseSeconds,
    capMs: capSeconds,
  );
}

/// Duration 糖：和 [exponentialBackoffMs] 同一公式。
Duration exponentialBackoffDuration({
  required int attempt,
  required Duration base,
  required Duration cap,
}) {
  return Duration(
    milliseconds: exponentialBackoffMs(
      attempt: attempt,
      baseMs: base.inMilliseconds,
      capMs: cap.inMilliseconds,
    ),
  );
}
