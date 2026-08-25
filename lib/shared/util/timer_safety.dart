import 'dart:async';

const Duration kOpenHandMinPeriodicTimerInterval = Duration(milliseconds: 250);
const Duration kOpenHandMaxPeriodicTimerInterval = Duration(hours: 24);
const Duration kOpenHandMaxTimerDelay = Duration(hours: 24);
const Duration kOpenHandMinPeriodicCallbackTimeout = Duration(milliseconds: 1);
const Duration kOpenHandDefaultPeriodicCallbackTimeout = Duration(minutes: 1);
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
    _runSafeTimerCallback(callback, zone: zone, onError: onError);
  });
}

/// 启动周期定时器，并统一转交同步与异步回调异常。
///
/// 周期回调不等待上一轮结束；需要防止重入时应使用
/// [startNonOverlappingPeriodicTimer]。
Timer startSafePeriodicTimer(
  Duration interval,
  FutureOr<void> Function(Timer timer) callback, {
  Duration min = kOpenHandMinPeriodicTimerInterval,
  Duration max = kOpenHandMaxPeriodicTimerInterval,
  OpenHandTimerErrorHandler? onError,
}) {
  final zone = Zone.current;
  return Timer.periodic(
    safePeriodicTimerInterval(interval, min: min, max: max),
    (timer) {
      _runSafeTimerCallback(
        () => callback(timer),
        zone: zone,
        onError: onError,
      );
    },
  );
}

void _runSafeTimerCallback(
  FutureOr<void> Function() callback, {
  required Zone zone,
  required OpenHandTimerErrorHandler? onError,
}) {
  unawaited(
    Future<void>.sync(callback).catchError((Object error, StackTrace stack) {
      _reportTimerError(error, stack, zone, onError);
    }),
  );
}

/// 启动非重入周期任务；回调超时后默认取消定时器，避免永久占用门闩。
Timer startNonOverlappingPeriodicTimer(
  Duration interval,
  FutureOr<void> Function(Timer timer) callback, {
  Duration min = kOpenHandMinPeriodicTimerInterval,
  Duration max = kOpenHandMaxPeriodicTimerInterval,
  Duration callbackTimeout = kOpenHandDefaultPeriodicCallbackTimeout,
  bool cancelOnCallbackTimeout = true,
  OpenHandTimerErrorHandler? onError,
}) {
  final zone = Zone.current;
  final effectiveCallbackTimeout = _clampTimerDuration(
    callbackTimeout,
    min: kOpenHandMinPeriodicCallbackTimeout,
    fallbackMin: kOpenHandMinPeriodicCallbackTimeout,
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
  final Duration callbackTimeout;
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
    final timeoutMarker = Object();
    final result = Completer<Object?>();
    Timer? timeoutTimer;
    void complete(Object? value) {
      if (!result.isCompleted) result.complete(value);
    }

    unawaited(
      pending.then<void>(
        (_) => complete(null),
        onError: (Object error, StackTrace stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        },
      ),
    );
    timeoutTimer = Timer(timeout, () => complete(timeoutMarker));
    late final Object? winner;
    try {
      winner = await result.future;
    } finally {
      timeoutTimer.cancel();
    }
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
