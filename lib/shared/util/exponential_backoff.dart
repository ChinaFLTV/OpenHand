/// 通用指数退避公式：第 `attempt` 次重试前等待 `baseMs * 2^(attempt-1)` 毫秒，
/// clamp 到 [baseMs, capMs]。
///
/// 设计点：
/// * 用 1<<(attempt-1) 而非 pow，避免 double 误差与中间装箱。
/// * `attempt` 必须 ≥ 1（attempt=1 即首次重试，等待 `baseMs`）；attempt ≤ 0 时
///   返回零等待（让调用方按"零延迟立刻重试"的约定走）。
/// * `cap < base` 时按 `base` 处理（避免负 clamp 抛 RangeError）。
/// * 不做 jitter——目前的 web_engine / cron_executor 都不需要；如未来要加，
///   在此添加即可，调用方都共享。
///
/// 单位完全交给调用方：把 `baseMs` / `capMs` 替换成秒/分钟 helper 时，整体保持
/// 同一公式即可。
int exponentialBackoffMs({
  required int attempt,
  required int baseMs,
  required int capMs,
}) {
  if (attempt <= 0) return 0;
  // 防 1<<(attempt-1) 在大 attempt 时溢出：6 次后 base*32 已经远超 capMs，
  // 提前 clamp attempt 到 30 已绰绰有余。
  final safeAttempt = attempt.clamp(1, 30);
  final raw = baseMs * (1 << (safeAttempt - 1));
  final lo = baseMs;
  final hi = capMs < baseMs ? baseMs : capMs;
  if (raw < lo) return lo;
  if (raw > hi) return hi;
  return raw;
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
