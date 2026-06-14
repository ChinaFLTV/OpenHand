import 'dart:async';

const Duration kOpenHandMinPeriodicTimerInterval = Duration(milliseconds: 250);
const Duration kOpenHandMaxPeriodicTimerInterval = Duration(hours: 24);
const Duration kOpenHandMinPeriodicCallbackTimeout = Duration(milliseconds: 1);
const Duration kOpenHandMaxPeriodicCallbackTimeout = Duration(hours: 24);

typedef OpenHandTimerErrorHandler =
    void Function(Object error, StackTrace stackTrace);

Duration safePeriodicTimerInterval(
  Duration requested, {
  Duration min = kOpenHandMinPeriodicTimerInterval,
  Duration max = kOpenHandMaxPeriodicTimerInterval,
}) {
  final lower = min > Duration.zero ? min : kOpenHandMinPeriodicTimerInterval;
  final upper = max < lower ? lower : max;
  if (requested <= Duration.zero) return lower;
  if (requested < lower) return lower;
  if (requested > upper) return upper;
  return requested;
}

Timer startSafePeriodicTimer(
  Duration interval,
  void Function(Timer timer) callback, {
  Duration min = kOpenHandMinPeriodicTimerInterval,
  Duration max = kOpenHandMaxPeriodicTimerInterval,
  OpenHandTimerErrorHandler? onError,
}) {
  final zone = Zone.current;
  return Timer.periodic(
    safePeriodicTimerInterval(interval, min: min, max: max),
    (timer) {
      try {
        callback(timer);
      } catch (error, stack) {
        _reportTimerError(error, stack, zone, onError);
      }
    },
  );
}

Timer startNonOverlappingPeriodicTimer(
  Duration interval,
  FutureOr<void> Function(Timer timer) callback, {
  Duration min = kOpenHandMinPeriodicTimerInterval,
  Duration max = kOpenHandMaxPeriodicTimerInterval,
  Duration? callbackTimeout,
  bool cancelOnCallbackTimeout = true,
  OpenHandTimerErrorHandler? onError,
}) {
  final zone = Zone.current;
  final effectiveCallbackTimeout = _safeOptionalTimerDuration(
    callbackTimeout,
    min: kOpenHandMinPeriodicCallbackTimeout,
    max: kOpenHandMaxPeriodicCallbackTimeout,
  );
  var running = false;
  return startSafePeriodicTimer(
    interval,
    (timer) {
      if (running) return;
      running = true;
      unawaited(() async {
        Timer? timeoutTimer;
        try {
          final pending = Future<void>.sync(() => callback(timer));
          if (effectiveCallbackTimeout != null) {
            timeoutTimer = Timer(
              effectiveCallbackTimeout,
              () => _handleTimerCallbackTimeout(
                timer: timer,
                timeout: effectiveCallbackTimeout,
                cancelTimer: cancelOnCallbackTimeout,
                zone: zone,
                onError: onError,
              ),
            );
          }
          await pending;
        } catch (error, stack) {
          _reportTimerError(error, stack, zone, onError);
        } finally {
          timeoutTimer?.cancel();
          running = false;
        }
      }());
    },
    min: min,
    max: max,
    onError: onError,
  );
}

void _handleTimerCallbackTimeout({
  required Timer timer,
  required Duration timeout,
  required bool cancelTimer,
  required Zone zone,
  required OpenHandTimerErrorHandler? onError,
}) {
  if (cancelTimer) {
    timer.cancel();
  }
  _reportTimerError(
    TimeoutException('Periodic timer callback exceeded $timeout', timeout),
    StackTrace.current,
    zone,
    onError,
  );
}

Duration? _safeOptionalTimerDuration(
  Duration? requested, {
  required Duration min,
  required Duration max,
}) {
  if (requested == null) return null;
  final lower = min > Duration.zero ? min : kOpenHandMinPeriodicCallbackTimeout;
  final upper = max < lower ? lower : max;
  if (requested <= Duration.zero) return lower;
  if (requested < lower) return lower;
  if (requested > upper) return upper;
  return requested;
}

void _reportTimerError(
  Object error,
  StackTrace stack,
  Zone fallbackZone,
  OpenHandTimerErrorHandler? onError,
) {
  try {
    (onError ?? fallbackZone.handleUncaughtError)(error, stack);
  } catch (secondaryError, secondaryStack) {
    fallbackZone.handleUncaughtError(secondaryError, secondaryStack);
  }
}
