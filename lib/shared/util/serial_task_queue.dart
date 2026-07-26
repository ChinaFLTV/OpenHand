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
