import 'dart:async';

const Duration kOpenHandMinPeriodicTimerInterval = Duration(milliseconds: 250);
const Duration kOpenHandMaxPeriodicTimerInterval = Duration(hours: 24);

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
  OpenHandTimerErrorHandler? onError,
}) {
  final zone = Zone.current;
  var running = false;
  return startSafePeriodicTimer(
    interval,
    (timer) {
      if (running) return;
      running = true;
      Future.sync(() => callback(timer))
          .catchError((Object error, StackTrace stack) {
            _reportTimerError(error, stack, zone, onError);
          })
          .whenComplete(() => running = false);
    },
    min: min,
    max: max,
    onError: onError,
  );
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
