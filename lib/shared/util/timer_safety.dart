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
  bool _isRunning = false;
  bool _isDisposed = false;
  FutureOr<void> Function()? _pendingCallback;
  OpenHandTimerErrorHandler? _pendingErrorHandler;

  bool get isActive =>
      (_timer?.isActive ?? false) || _isRunning || _pendingCallback != null;

  void schedule(
    FutureOr<void> Function() callback, {
    Duration? delay,
    OpenHandTimerErrorHandler? onError,
  }) {
    if (_isDisposed) return;
    cancel();
    _timer = _start(callback, delay: delay, onError: onError);
  }

  bool scheduleIfIdle(
    FutureOr<void> Function() callback, {
    Duration? delay,
    OpenHandTimerErrorHandler? onError,
  }) {
    if (_isDisposed || isActive) return false;
    _timer = _start(callback, delay: delay, onError: onError);
    return true;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pendingCallback = null;
    _pendingErrorHandler = null;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    cancel();
  }

  Timer _start(
    FutureOr<void> Function() callback, {
    Duration? delay,
    OpenHandTimerErrorHandler? onError,
  }) {
    return startSafeTimer(
      delay ?? _delay,
      () async {
        _timer = null;
        await _runOrQueue(callback, onError: onError);
      },
      min: _minDelay,
      max: _maxDelay,
      onError: onError ?? _onError,
    );
  }

  Future<void> _runOrQueue(
    FutureOr<void> Function() callback, {
    OpenHandTimerErrorHandler? onError,
  }) async {
    if (_isDisposed) return;
    if (_isRunning) {
      _pendingCallback = callback;
      _pendingErrorHandler = onError;
      return;
    }

    _isRunning = true;
    try {
      await callback();
    } finally {
      _isRunning = false;
      _schedulePendingRun();
    }
  }

  void _schedulePendingRun() {
    if (_isDisposed) {
      _pendingCallback = null;
      _pendingErrorHandler = null;
      return;
    }
    final callback = _pendingCallback;
    final onError = _pendingErrorHandler;
    _pendingCallback = null;
    _pendingErrorHandler = null;
    if (callback == null) return;
    _timer = _start(callback, delay: Duration.zero, onError: onError);
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
  final gate = _NonOverlappingPeriodicTimerGate(
    callback: callback,
    callbackTimeout: effectiveCallbackTimeout,
    cancelOnCallbackTimeout: cancelOnCallbackTimeout,
    zone: zone,
    onError: onError,
  );
  return startSafePeriodicTimer(
    interval,
    gate.handleTick,
    min: min,
    max: max,
    onError: onError,
  );
}

class _NonOverlappingPeriodicTimerGate {
  _NonOverlappingPeriodicTimerGate({
    required this.callback,
    required this.callbackTimeout,
    required this.cancelOnCallbackTimeout,
    required this.zone,
    required this.onError,
  });

  final FutureOr<void> Function(Timer timer) callback;
  final Duration? callbackTimeout;
  final bool cancelOnCallbackTimeout;
  final Zone zone;
  final OpenHandTimerErrorHandler? onError;
  bool _running = false;

  void handleTick(Timer timer) {
    if (_running) return;
    _running = true;
    unawaited(_run(timer));
  }

  Future<void> _run(Timer timer) async {
    try {
      await _runCallbackWithTimeout(timer);
    } catch (error, stack) {
      _reportTimerError(error, stack, zone, onError);
    } finally {
      _running = false;
    }
  }

  Future<void> _runCallbackWithTimeout(Timer timer) async {
    final pending = Future<void>.sync(() => callback(timer));
    final timeout = callbackTimeout;
    if (timeout == null) {
      await pending;
      return;
    }

    final timeoutMarker = Object();
    final winner = await Future.any<Object?>([
      pending.then<Object?>((_) => null),
      Future<void>.delayed(timeout).then<Object?>((_) => timeoutMarker),
    ]);
    if (!identical(winner, timeoutMarker)) return;

    _handleTimerCallbackTimeout(
      timer: timer,
      timeout: timeout,
      cancelTimer: cancelOnCallbackTimeout,
      zone: zone,
      onError: onError,
    );
    if (!cancelOnCallbackTimeout) {
      // 慢回调真正结束前保持门闩关闭，避免并发重入。
      await pending;
      return;
    }
    unawaited(
      pending.catchError(
        (Object error, StackTrace stack) =>
            _reportTimerError(error, stack, zone, onError),
      ),
    );
  }
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
    TimeoutException('周期定时器回调超过时限 $timeout', timeout),
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
