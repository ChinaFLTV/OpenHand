import 'dart:async';

/// 按 FIFO 顺序执行异步任务。单个任务失败不会阻断队列，调用方仍会收到
/// 对应任务的结果或异常。
final class SerialTaskQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await task());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }
}
