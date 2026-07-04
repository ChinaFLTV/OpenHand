import 'dart:async';

const Duration kOpenHandMinPeriodicTimerInterval = Duration(milliseconds: 250);
const Duration kOpenHandMaxPeriodicTimerInterval = Duration(hours: 24);
const Duration kOpenHandMaxTimerDelay = Duration(hours: 24);
const Duration kOpenHandMinPeriodicCallbackTimeout = Duration(milliseconds: 1);
const Duration kOpenHandMaxPeriodicCallbackTimeout = Duration(hours: 24);
const Duration kOpenHandFramePeriodicTimerInterval = Duration(milliseconds: 16);

typedef OpenHandTimerErrorHandler =
    void Function(Object error, StackTrace stackTrace);

class OpenHandDebouncer {
  OpenHandDebouncer({
    required Duration delay,
    Duration minDelay = Duration.zero,
    Duration maxDelay = kOpenHandMaxTimerDelay,
    OpenHandTimerErrorHandler? onError,
  }) : _delay = delay,
       _minDelay = minDelay,
       _maxDelay = maxDelay,
       _onError = onError;

  final Duration _delay;
  final Duration _minDelay;
  final Duration _maxDelay;
  final OpenHandTimerErrorHandler? _onError;
  Timer? _timer;

  bool get isActive => _timer?.isActive ?? false;

  void schedule(
    FutureOr<void> Function() callback, {
    Duration? delay,
    OpenHandTimerErrorHandler? onError,
  }) {
    cancel();
    _timer = _start(callback, delay: delay, onError: onError);
  }

  bool scheduleIfIdle(
    FutureOr<void> Function() callback, {
    Duration? delay,
    OpenHandTimerErrorHandler? onError,
  }) {
    if (isActive) return false;
    _timer = _start(callback, delay: delay, onError: onError);
    return true;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();

  Timer _start(
    FutureOr<void> Function() callback, {
    Duration? delay,
    OpenHandTimerErrorHandler? onError,
  }) {
    return startSafeTimer(
      delay ?? _delay,
      () async {
        _timer = null;
        await callback();
      },
      min: _minDelay,
      max: _maxDelay,
      onError: onError ?? _onError,
    );
  }
}

Duration safePeriodicTimerInterval(
  Duration requested, {
  Duration min = kOpenHandMinPeriodicTimerInterval,
  Duration max = kOpenHandMaxPeriodicTimerInterval,
}) {
  return _clampTimerDuration(
    requested,
    min: min,
    fallbackMin: kOpenHandMinPeriodicTimerInterval,
    max: max,
  );
}

Duration safeTimerDelay(
  Duration requested, {
  Duration min = Duration.zero,
  Duration max = kOpenHandMaxTimerDelay,
}) {
  return _clampTimerDuration(
    requested,
    min: min,
    fallbackMin: Duration.zero,
    max: max,
  );
}

Timer startSafeTimer(
  Duration delay,
  FutureOr<void> Function() callback, {
  Duration min = Duration.zero,
  Duration max = kOpenHandMaxTimerDelay,
  OpenHandTimerErrorHandler? onError,
}) {
  final zone = Zone.current;
  return Timer(safeTimerDelay(delay, min: min, max: max), () {
    unawaited(
      Future<void>.sync(callback).catchError((Object error, StackTrace stack) {
        _reportTimerError(error, stack, zone, onError);
      }),
    );
  });
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
            timeoutTimer = startSafeTimer(
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
  return _clampTimerDuration(
    requested,
    min: min,
    fallbackMin: kOpenHandMinPeriodicCallbackTimeout,
    max: max,
  );
}

Duration _clampTimerDuration(
  Duration requested, {
  required Duration min,
  required Duration fallbackMin,
  required Duration max,
}) {
  final lower = min > Duration.zero ? min : fallbackMin;
  final upper = max < lower ? lower : max;
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
