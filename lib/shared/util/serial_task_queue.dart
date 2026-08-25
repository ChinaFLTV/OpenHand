import 'dart:async';

import 'argument_guards.dart';

/// 按 FIFO 顺序执行异步任务。单个任务失败不会阻断队列，调用方仍会收到
/// 对应任务的结果或异常。
final class SerialTaskQueue {
  SerialTaskQueue({this.maxPendingTasks = defaultMaxPendingTasks}) {
    requirePositiveIntAtMost(
      maxPendingTasks,
      maxAllowedPendingTasks,
      'maxPendingTasks',
    );
  }

  static const int defaultMaxPendingTasks = 256;
  static const int maxAllowedPendingTasks = 4096;

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

/// 串行执行任务，并且等待区仅保留最新任务。
///
/// 新任务会替换尚未开始的旧任务；返回值表示任务是否实际执行。
final class LatestTaskQueue {
  bool _running = false;
  _LatestTask? _pending;
  Future<void> _idle = Future<void>.value();

  /// 当前运行任务及其后续最新任务全部结束时完成。
  Future<void> get idle => _idle;

  Future<bool> enqueue(Future<void> Function() task) {
    final next = _LatestTask(task);
    if (_running) {
      _pending?.discard();
      _pending = next;
    } else {
      _running = true;
      _idle = _drain(next);
      unawaited(_idle);
    }
    return next.done;
  }

  void discardPending() {
    _pending?.discard();
    _pending = null;
  }

  Future<void> _drain(_LatestTask first) async {
    var current = first;
    while (true) {
      // 当前任务的异常已经交给对应的 done Future；队列本身必须继续消费
      // 后续最新任务，不能因单项失败而永久卡住。
      try {
        await current.run();
      } catch (_) {
        // 保持队列可用，调用方仍可通过当前任务的 done Future 获取原异常。
      }
      final next = _pending;
      _pending = null;
      if (next == null) {
        _running = false;
        return;
      }
      current = next;
    }
  }
}

final class _LatestTask {
  _LatestTask(this._task);

  final Future<void> Function() _task;
  final Completer<bool> _completer = Completer<bool>();

  Future<bool> get done => _completer.future;

  void discard() {
    if (!_completer.isCompleted) _completer.complete(false);
  }

  Future<void> run() async {
    try {
      await _task();
      _completer.complete(true);
    } catch (error, stack) {
      _completer.completeError(error, stack);
    }
  }
}

/// 按键分别串行执行任务，不同键之间保持并行。
///
/// 总待执行任务数受限，防止单键长队列或大量唯一键持续占用内存。
final class KeyedSerialTaskQueue<K> {
  KeyedSerialTaskQueue({
    this.maxPendingTasks = SerialTaskQueue.defaultMaxPendingTasks,
  }) {
    requirePositiveIntAtMost(
      maxPendingTasks,
      SerialTaskQueue.maxAllowedPendingTasks,
      'maxPendingTasks',
    );
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
