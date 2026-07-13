import 'dart:async';

/// Runs asynchronous tasks in FIFO order without letting one failure poison
/// the queue. Each caller still receives its own task result or error.
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
