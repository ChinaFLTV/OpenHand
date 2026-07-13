import 'dart:async';
import 'dart:collection';

typedef OpenHandAsyncContinuePredicate = bool Function();
typedef OpenHandAsyncCleanupErrorHandler =
    void Function(Object error, StackTrace stackTrace);

const int kOpenHandMaxAsyncConcurrency = 64;
const Duration kOpenHandDefaultAsyncCleanupTimeout = Duration(seconds: 2);
const Duration kOpenHandMaxAsyncCleanupTimeout = Duration(seconds: 30);
const Duration _kOpenHandAsyncDelayCheckInterval = Duration(milliseconds: 50);

/// Runs best-effort asynchronous cleanup without allowing a broken resource to
/// hold shutdown forever.
///
/// Failures are delivered to [onError] and converted to `false`. Oversized
/// caller-provided timeouts are capped so settings or dependency injection
/// cannot reintroduce an effectively unbounded shutdown path.
Future<bool> runAsyncCleanupBounded(
  FutureOr<void> Function() cleanup, {
  Duration timeout = kOpenHandDefaultAsyncCleanupTimeout,
  OpenHandAsyncCleanupErrorHandler? onError,
}) async {
  final effectiveTimeout = timeout <= Duration.zero
      ? Duration.zero
      : timeout > kOpenHandMaxAsyncCleanupTimeout
      ? kOpenHandMaxAsyncCleanupTimeout
      : timeout;
  try {
    await Future<void>.sync(cleanup).timeout(effectiveTimeout);
    return true;
  } catch (error, stack) {
    try {
      onError?.call(error, stack);
    } catch (_) {
      // A cleanup logger must never replace the primary shutdown result.
    }
    return false;
  }
}

/// Cancels a stream subscription through [runAsyncCleanupBounded].
Future<bool> cancelStreamSubscriptionBounded<T>(
  StreamSubscription<T>? subscription, {
  Duration timeout = kOpenHandDefaultAsyncCleanupTimeout,
  OpenHandAsyncCleanupErrorHandler? onError,
}) {
  if (subscription == null) return Future<bool>.value(true);
  return runAsyncCleanupBounded(
    subscription.cancel,
    timeout: timeout,
    onError: onError,
  );
}

/// Small FIFO semaphore for bounded async fan-out.
///
/// Invalid or oversized limits are normalized so caller mistakes cannot create
/// unbounded workers or a permanently closed semaphore.
class OpenHandAsyncSemaphore {
  OpenHandAsyncSemaphore(
    int maxPermits, {
    int maxAllowedPermits = kOpenHandMaxAsyncConcurrency,
  }) : maxPermits = _normalizeAsyncConcurrencyLimit(
         maxPermits,
         maxAllowedPermits: maxAllowedPermits,
       ),
       _available = _normalizeAsyncConcurrencyLimit(
         maxPermits,
         maxAllowedPermits: maxAllowedPermits,
       );

  final int maxPermits;
  int _available;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  int get availableCount => _available;

  int get waitingCount => _waiters.length;

  Future<void> acquire() {
    if (_available > 0) {
      _available -= 1;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    if (_available < maxPermits) {
      _available += 1;
    }
  }

  Future<T> withPermit<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }
}

Future<bool> isCancelSignalCompleted(Future<void>? cancelSignal) {
  if (cancelSignal == null) return Future<bool>.value(false);
  return Future.any<bool>([
    cancelSignal.then((_) => true, onError: (_) => true),
    Future<void>.delayed(Duration.zero).then((_) => false),
  ]);
}

Future<bool> delayUntilCancelled(
  Duration delay, {
  Future<void>? cancelSignal,
}) async {
  if (delay <= Duration.zero) return isCancelSignalCompleted(cancelSignal);
  if (cancelSignal == null) {
    await Future<void>.delayed(delay);
    return false;
  }
  return Future.any<bool>([
    cancelSignal.then((_) => true, onError: (_) => true),
    Future<void>.delayed(delay).then((_) => false),
  ]);
}

Future<T?> awaitWithCancelSignal<T>(
  Future<T> future, {
  Future<void>? cancelSignal,
}) async {
  if (cancelSignal == null) return future;
  final sentinel = Object();
  final firstResult = await Future.any<Object?>([
    future.then<Object?>((value) => value),
    cancelSignal.then<Object?>((_) => sentinel, onError: (_) => sentinel),
  ]);
  if (identical(firstResult, sentinel)) {
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    return null;
  }
  return firstResult as T;
}

int _boundedConcurrency({required int itemCount, required int maxConcurrency}) {
  if (itemCount <= 0) return 0;
  final safeLimit = _normalizeAsyncConcurrencyLimit(maxConcurrency);
  return safeLimit < itemCount ? safeLimit : itemCount;
}

int _safeAsyncItemCount(int itemCount) => itemCount < 0 ? 0 : itemCount;

int _normalizeAsyncConcurrencyLimit(
  int value, {
  int maxAllowedPermits = kOpenHandMaxAsyncConcurrency,
}) {
  final upper = maxAllowedPermits < 1 ? 1 : maxAllowedPermits;
  if (value < 1) return 1;
  return value > upper ? upper : value;
}

/// Runs indexed async work with a bounded worker pool and preserves result order.
///
/// [maxConcurrency] is clamped to [kOpenHandMaxAsyncConcurrency] so accidental
/// oversized inputs cannot spawn an unbounded number of workers.
Future<List<T>> runOrderedWithConcurrencyLimit<T>({
  required int itemCount,
  required int maxConcurrency,
  required Future<T> Function(int index) task,
}) async {
  final safeItemCount = _safeAsyncItemCount(itemCount);
  final results = List<T?>.filled(safeItemCount, null);
  await _runIndexedWithConcurrencyLimit(
    itemCount: safeItemCount,
    maxConcurrency: maxConcurrency,
    task: (index) async {
      results[index] = await task(index);
    },
  );
  return results.cast<T>();
}

/// Runs indexed async side effects with bounded concurrency.
///
/// [shouldContinue] is checked before acquiring each new item and after each
/// task, so disposed widgets/controllers can stop scheduling new work promptly.
/// [maxConcurrency] is clamped to [kOpenHandMaxAsyncConcurrency].
Future<void> forEachIndexWithConcurrencyLimit({
  required int itemCount,
  required int maxConcurrency,
  required Future<void> Function(int index) task,
  OpenHandAsyncContinuePredicate? shouldContinue,
  Duration delayBetweenItems = Duration.zero,
}) async {
  final safeItemCount = _safeAsyncItemCount(itemCount);
  await _runIndexedWithConcurrencyLimit(
    itemCount: safeItemCount,
    maxConcurrency: maxConcurrency,
    task: task,
    shouldContinue: shouldContinue,
    delayBetweenItems: delayBetweenItems,
  );
}

Future<void> _runIndexedWithConcurrencyLimit({
  required int itemCount,
  required int maxConcurrency,
  required Future<void> Function(int index) task,
  OpenHandAsyncContinuePredicate? shouldContinue,
  Duration delayBetweenItems = Duration.zero,
}) async {
  final workerCount = _boundedConcurrency(
    itemCount: itemCount,
    maxConcurrency: maxConcurrency,
  );
  if (workerCount == 0) return;

  var nextIndex = 0;
  bool keepGoing() => shouldContinue?.call() ?? true;

  Future<void> worker() async {
    while (keepGoing()) {
      final index = nextIndex;
      nextIndex += 1;
      if (index >= itemCount) return;
      await task(index);
      if (!keepGoing()) return;
      if (delayBetweenItems > Duration.zero &&
          index < itemCount - 1 &&
          nextIndex < itemCount) {
        final stillActive = await _delayWhileContinuing(
          delayBetweenItems,
          keepGoing,
        );
        if (!stillActive) return;
      }
    }
  }

  await Future.wait<void>(
    List<Future<void>>.generate(workerCount, (_) => worker()),
  );
}

Future<bool> _delayWhileContinuing(
  Duration delay,
  OpenHandAsyncContinuePredicate shouldContinue,
) async {
  if (delay <= Duration.zero) return shouldContinue();
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < delay) {
    if (!shouldContinue()) return false;
    final remaining = delay - stopwatch.elapsed;
    final step = remaining < _kOpenHandAsyncDelayCheckInterval
        ? remaining
        : _kOpenHandAsyncDelayCheckInterval;
    if (step > Duration.zero) {
      await Future<void>.delayed(step);
    }
  }
  return shouldContinue();
}
