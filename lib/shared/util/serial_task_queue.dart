import 'dart:async';

/// 按 FIFO 顺序执行异步任务。单个任务失败不会阻断队列，调用方仍会收到
/// 对应任务的结果或异常。
final class SerialTaskQueue {
  SerialTaskQueue({this.maxPendingTasks = defaultMaxPendingTasks}) {
    if (maxPendingTasks < 1) {
      throw ArgumentError.value(maxPendingTasks, 'maxPendingTasks', '必须大于零。');
    }
  }

  static const int defaultMaxPendingTasks = 4096;

  final int maxPendingTasks;
  Future<void> _tail = Future<void>.value();
  int _pendingTasks = 0;

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
