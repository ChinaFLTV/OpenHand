import 'dart:async';

typedef OpenHandAsyncContinuePredicate = bool Function();

const int kOpenHandMaxAsyncConcurrency = 64;
const Duration _kOpenHandAsyncDelayCheckInterval = Duration(milliseconds: 50);

int _boundedConcurrency({required int itemCount, required int maxConcurrency}) {
  if (itemCount <= 0) return 0;
  final requestedLimit = maxConcurrency < 1 ? 1 : maxConcurrency;
  final safeLimit = requestedLimit > kOpenHandMaxAsyncConcurrency
      ? kOpenHandMaxAsyncConcurrency
      : requestedLimit;
  return safeLimit < itemCount ? safeLimit : itemCount;
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
  final results = List<T?>.filled(itemCount, null);
  await _runIndexedWithConcurrencyLimit(
    itemCount: itemCount,
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
  await _runIndexedWithConcurrencyLimit(
    itemCount: itemCount,
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
