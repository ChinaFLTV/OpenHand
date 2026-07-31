import 'dart:async';
import 'argument_guards.dart';

/// 按 FIFO 顺序执行异步任务。单个任务失败不会阻断队列，调用方仍会收到
/// 对应任务的结果或异常。
final class SerialTaskQueue {
  SerialTaskQueue({this.maxPendingTasks = defaultMaxPendingTasks}) {
    requirePositiveInt(maxPendingTasks, 'maxPendingTasks');
  }

  static const int defaultMaxPendingTasks = 4096;

  final int maxPendingTasks;
  Future<void> _tail = Future<void>.value();
  int _pendingTasks = 0;

  /// 当前已入队任务全部结束时完成；后续新任务不包含在本次等待中。
  Future<void> get idle => _tail;

  Future<T> enqueue<T>(Future<T> Function() task) {
    if (_pendingTasks >= maxPendingTasks) {
      return Future<T>.error(StateError('串行任务队列已满，拒绝继续堆积任务。'));
    }
    _pendingTasks += 1;
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await task());
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _pendingTasks -= 1;
      }
    });
    return completer.future;
  }
}

/// 按键分别串行执行任务，不同键之间保持并行。
///
/// 总待执行任务数受限，防止单键长队列或大量唯一键持续占用内存。
final class KeyedSerialTaskQueue<K> {
  KeyedSerialTaskQueue({
    this.maxPendingTasks = SerialTaskQueue.defaultMaxPendingTasks,
  }) {
    requirePositiveInt(maxPendingTasks, 'maxPendingTasks');
  }

  final int maxPendingTasks;
  final Map<K, Future<void>> _tails = <K, Future<void>>{};
  int _pendingTasks = 0;

  Future<T> enqueue<T>(K key, Future<T> Function() task) {
    if (_pendingTasks >= maxPendingTasks) {
      return Future<T>.error(StateError('键控串行任务队列已满，拒绝继续堆积任务。'));
    }

    _pendingTasks += 1;
    final previous = _tails[key] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> tail;
    tail = previous.then<void>((_) async {
      try {
        completer.complete(await task());
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _pendingTasks -= 1;
      }
    });
    _tails[key] = tail;
    unawaited(
      tail.then<void>((_) {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }),
    );
    return completer.future;
  }
}
