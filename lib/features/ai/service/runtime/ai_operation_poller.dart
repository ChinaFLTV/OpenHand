import 'dart:async';
import 'dart:math' as math;

class AiOperationPoller {
  const AiOperationPoller();

  static final math.Random _jitter = math.Random();
  static const Duration _minDelay = Duration(milliseconds: 250);
  static const Duration _jitterWindow = Duration(milliseconds: 400);

  Future<T> pollUntil<T>({
    required Future<T?> Function() tick,
    required bool Function(T value) isTerminal,
    required Duration timeout,
    Duration initialDelay = const Duration(milliseconds: 1500),
    Duration maxDelay = const Duration(seconds: 5),
  }) async {
    if (timeout <= Duration.zero) {
      throw TimeoutException('Operation polling timed out.', timeout);
    }
    final startedAt = DateTime.now().toUtc();
    final deadline = startedAt.add(timeout);
    var delay = _normalizeDelay(initialDelay, fallback: _minDelay);
    final delayCap = _normalizeDelay(maxDelay, fallback: delay);
    while (DateTime.now().toUtc().isBefore(deadline)) {
      final tickBudget = deadline.difference(DateTime.now().toUtc());
      if (tickBudget <= Duration.zero) break;
      final value = await tick().timeout(tickBudget);
      if (value != null && isTerminal(value)) {
        return value;
      }
      final remaining = deadline.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero) break;
      final jitterMs =
          _jitter.nextInt(_jitterWindow.inMilliseconds + 1) -
          (_jitterWindow.inMilliseconds ~/ 2);
      final effectiveDelay = Duration(
        milliseconds: math.max(
          _minDelay.inMilliseconds,
          delay.inMilliseconds + jitterMs,
        ),
      );
      await Future<void>.delayed(
        effectiveDelay < remaining ? effectiveDelay : remaining,
      );
      if (delay < delayCap) {
        final doubled = delay.inMilliseconds * 2;
        delay = Duration(
          milliseconds: doubled > delayCap.inMilliseconds
              ? delayCap.inMilliseconds
              : doubled,
        );
      }
    }
    throw TimeoutException('Operation polling timed out.', timeout);
  }

  Duration _normalizeDelay(Duration value, {required Duration fallback}) {
    if (value <= Duration.zero) return fallback;
    if (value < _minDelay) return _minDelay;
    return value;
  }
}
