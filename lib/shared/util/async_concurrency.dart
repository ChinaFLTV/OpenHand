import 'dart:async';
import 'dart:collection';
import 'argument_guards.dart';
import 'duration_bounds.dart';

typedef OpenHandAsyncContinuePredicate = bool Function();
typedef OpenHandAsyncCleanupErrorHandler =
    void Function(Object error, StackTrace stackTrace);

const int kOpenHandMaxAsyncConcurrency = 64;
const int kOpenHandMaxAsyncWaiters = 4096;
const Duration kOpenHandDefaultAsyncCleanupTimeout = Duration(seconds: 2);
const Duration kOpenHandMaxAsyncCleanupTimeout = Duration(seconds: 30);
const Duration _kOpenHandAsyncDelayCheckInterval = Duration(milliseconds: 50);

/// 基于单调时钟管理总时限，避免系统时间校准影响超时判断。
final class MonotonicDeadline {
  MonotonicDeadline(this.timeout, {this.timeoutMessage = '操作超过总时限。'})
    : _stopwatch = Stopwatch() {
    requirePositiveDuration(timeout, 'timeout');
    _stopwatch.start();
  }

  final Duration timeout;
  final String timeoutMessage;
  final Stopwatch _stopwatch;

  Duration get elapsed => _stopwatch.elapsed;
  bool get isExpired => remainingOrNull() == null;

  Duration? remainingOrNull() {
    final remainingMicroseconds =
        timeout.inMicroseconds - _stopwatch.elapsedMicroseconds;
    return remainingMicroseconds <= 0
        ? null
        : Duration(microseconds: remainingMicroseconds);
  }

  Duration remaining() {
    return remainingOrNull() ?? (throw timeoutException());
  }

  TimeoutException timeoutException() {
    return TimeoutException(timeoutMessage, timeout);
  }

  Duration limit(Duration maximum) {
    requirePositiveDuration(maximum, 'maximum');
    return shorterDuration(maximum, remaining());
  }

  void stop() => _stopwatch.stop();
}

/// 尽力执行异步清理，同时防止异常资源永久阻塞关闭流程。
///
/// 失败会交给 [onError] 并转换为 `false`；调用方提供的超大时限也会被截断，
/// 避免设置或依赖注入重新引入无界关闭路径。
Future<bool> runAsyncCleanupBounded(
  FutureOr<void> Function() cleanup, {
  Duration timeout = kOpenHandDefaultAsyncCleanupTimeout,
  OpenHandAsyncCleanupErrorHandler? onError,
}) async {
  final effectiveTimeout = shorterDuration(
    nonNegativeDuration(timeout),
    kOpenHandMaxAsyncCleanupTimeout,
  );
  try {
    await Future<void>.sync(cleanup).timeout(effectiveTimeout);
    return true;
  } catch (error, stack) {
    try {
      onError?.call(error, stack);
    } catch (_) {
      // 清理日志异常不能覆盖原始关闭结果。
    }
    return false;
  }
}

/// 通过 [runAsyncCleanupBounded] 取消流订阅。
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

/// 仅启动一次异步操作；重复调用共享首次操作的结果。
///
/// 操作开始前先登记 Future，确保同步回调重入时不会重复启动。
final class OpenHandAsyncOnce {
  Future<void>? _future;

  Future<void> run(FutureOr<void> Function() operation) {
    final active = _future;
    if (active != null) return active;
    final completer = Completer<void>();
    final future = completer.future;
    _future = future;
    unawaited(
      Future<void>.sync(operation).then<void>(
        (_) => completer.complete(),
        onError: (Object error, StackTrace stack) =>
            completer.completeError(error, stack),
      ),
    );
    return future;
  }
}

/// 控制异步扇出的轻量 FIFO 信号量。
///
/// 并发数和等待数都会归一化，避免异常配置创建无界工作器或等待队列。
class OpenHandAsyncSemaphore {
  OpenHandAsyncSemaphore(
    int maxPermits, {
    int maxAllowedPermits = kOpenHandMaxAsyncConcurrency,
    int maxWaiters = kOpenHandMaxAsyncWaiters,
  }) : maxPermits = _normalizeAsyncConcurrencyLimit(
         maxPermits,
         maxAllowedPermits: maxAllowedPermits,
       ),
       maxWaiters = _normalizeAsyncWaiterLimit(maxWaiters),
       _available = _normalizeAsyncConcurrencyLimit(
         maxPermits,
         maxAllowedPermits: maxAllowedPermits,
       );

  final int maxPermits;
  final int maxWaiters;
  int _available;
  final Queue<_OpenHandAsyncSemaphoreWaiter> _waiters =
      Queue<_OpenHandAsyncSemaphoreWaiter>();

  Future<void> acquire() async {
    await _acquire();
  }

  /// 等待许可；取消信号先完成时从队列移除并返回 `false`。
  Future<bool> acquireUnlessCancelled(Future<void> cancelSignal) {
    return _acquire(cancelSignal: cancelSignal);
  }

  Future<bool> _acquire({Future<void>? cancelSignal}) async {
    if (cancelSignal != null && await isCancelSignalCompleted(cancelSignal)) {
      return false;
    }
    if (_available > 0) {
      _available -= 1;
      return true;
    }
    if (_waiters.length >= maxWaiters) {
      throw StateError('异步信号量等待队列已满。');
    }
    final waiter = _OpenHandAsyncSemaphoreWaiter();
    _waiters.add(waiter);
    if (cancelSignal != null) {
      unawaited(
        cancelSignal.then<void>(
          (_) => _cancelWaiter(waiter),
          onError: (Object _, StackTrace _) => _cancelWaiter(waiter),
        ),
      );
    }
    return waiter.completer.future;
  }

  void _cancelWaiter(_OpenHandAsyncSemaphoreWaiter waiter) {
    if (waiter.settled || !_waiters.remove(waiter)) return;
    waiter.settled = true;
    waiter.completer.complete(false);
  }

  void release() {
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (waiter.settled) continue;
      waiter.settled = true;
      waiter.completer.complete(true);
      return;
    }
    if (_available >= maxPermits) {
      throw StateError('异步信号量被重复释放。');
    }
    _available += 1;
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

class _OpenHandAsyncSemaphoreWaiter {
  final Completer<bool> completer = Completer<bool>();
  bool settled = false;
}

Future<bool> isCancelSignalCompleted(Future<void>? cancelSignal) {
  if (cancelSignal == null) return Future<bool>.value(false);
  return Future.any<bool>([
    cancelSignal.then((_) => true, onError: (_) => true),
    Future<void>.delayed(Duration.zero).then((_) => false),
  ]);
}

/// 合并多个取消信号；任一信号正常或异常完成时，合并信号均正常完成。
///
/// 空集合返回 `null`，避免调用方重复维护空集合和单信号分支。
Future<void>? combineCancelSignals(Iterable<Future<void>?> signals) {
  final normalized = signals
      .whereType<Future<void>>()
      .map(
        (signal) =>
            signal.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      )
      .toList(growable: false);
  if (normalized.isEmpty) return null;
  if (normalized.length == 1) return normalized.single;
  return Future.any<void>(normalized);
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

int _normalizeAsyncWaiterLimit(int value) {
  if (value < 1) return 1;
  return value > kOpenHandMaxAsyncWaiters ? kOpenHandMaxAsyncWaiters : value;
}

/// 使用有界工作池执行索引任务，并保持结果顺序。
///
/// [maxConcurrency] 会限制到 [kOpenHandMaxAsyncConcurrency]，避免异常参数
/// 创建无界工作器。
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

/// 以有界并发执行索引副作用任务。
///
/// 每次获取新任务前及任务结束后都会检查 [shouldContinue]，使已销毁的组件或
/// 控制器及时停止调度；[maxConcurrency] 同样受全局上限约束。
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
  Object? firstError;
  StackTrace? firstStackTrace;
  var failed = false;
  bool keepGoing() => shouldContinue?.call() ?? true;

  Future<void> worker() async {
    try {
      while (!failed && keepGoing()) {
        final index = nextIndex;
        nextIndex += 1;
        if (index >= itemCount) return;
        await task(index);
        if (failed || !keepGoing()) return;
        if (delayBetweenItems > Duration.zero &&
            index < itemCount - 1 &&
            nextIndex < itemCount) {
          final stillActive = await _delayWhileContinuing(
            delayBetweenItems,
            () => !failed && keepGoing(),
          );
          if (!stillActive) return;
        }
      }
    } catch (error, stack) {
      if (!failed) {
        failed = true;
        firstError = error;
        firstStackTrace = stack;
      }
    }
  }

  await Future.wait<void>(
    List<Future<void>>.generate(workerCount, (_) => worker()),
  );
  if (failed) {
    Error.throwWithStackTrace(firstError!, firstStackTrace!);
  }
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
