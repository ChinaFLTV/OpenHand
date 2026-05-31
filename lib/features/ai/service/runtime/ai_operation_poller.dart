import 'dart:async';
import 'dart:math' as math;

class AiOperationPoller {
  const AiOperationPoller();

  Future<T> pollUntil<T>({
    required Future<T?> Function() tick,
    required bool Function(T value) isTerminal,
    required Duration timeout,
    Duration initialDelay = const Duration(milliseconds: 1500),
    Duration maxDelay = const Duration(seconds: 5),
  }) async {
    final startedAt = DateTime.now().toUtc();
    var delay = initialDelay;
    while (DateTime.now().toUtc().difference(startedAt) < timeout) {
      final value = await tick();
      if (value != null && isTerminal(value)) {
        return value;
      }
      final jitterMs = math.Random().nextInt(400) - 200;
      final effectiveDelay = Duration(
        milliseconds: math.max(250, delay.inMilliseconds + jitterMs),
      );
      await Future<void>.delayed(effectiveDelay);
      if (delay < maxDelay) {
        final doubled = delay.inMilliseconds * 2;
        delay = Duration(
          milliseconds:
              doubled > maxDelay.inMilliseconds
                  ? maxDelay.inMilliseconds
                  : doubled,
        );
      }
    }
    throw TimeoutException('Operation polling timed out.');
  }
}
