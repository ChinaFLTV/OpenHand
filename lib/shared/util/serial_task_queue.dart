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
  bool _draining = false;
  Object? _closedError;
  final Set<_SerialTask<dynamic>> _pending = <_SerialTask<dynamic>>{};

  /// 当前已入队任务全部结束时完成；后续新任务不包含在本次等待中。
  Future<void> get idle => _tail;

  /// 在退出预算内等待已排队任务；完成或超时后统一关闭队列。
  Future<void> drainAndClose(Duration timeout) async {
    requirePositiveDuration(timeout, 'timeout');
    _draining = true;
    try {
      await idle.timeout(timeout);
    } finally {
      close();
    }
  }

  Future<T> enqueue<T>(Future<T> Function() task) {
    final closedError = _closedError;
    if (closedError != null) return Future<T>.error(closedError);
    if (_draining) return Future<T>.error(StateError('串行任务队列正在关闭。'));
    if (_pendingTasks >= maxPendingTasks) {
      return Future<T>.error(StateError('串行任务队列已满，拒绝继续堆积任务。'));
    }
    _pendingTasks += 1;
    final entry = _SerialTask<T>(task);
    _pending.add(entry);
    _tail = _tail.then((_) async {
      if (!_pending.remove(entry)) return;
      try {
        await entry.run();
      } finally {
        _pendingTasks -= 1;
      }
    });
    return entry.done;
  }

  /// 拒绝新任务并立即取消尚未开始的任务；运行中的任务仍由所有者负责终止。
  void close([Object? error]) {
    if (_closedError != null) return;
    final reason = _closedError = error ?? StateError('串行任务队列已关闭。');
    final pending = _pending.toList(growable: false);
    _pending.clear();
    _pendingTasks -= pending.length;
    for (final entry in pending) {
      entry.cancel(reason);
    }
  }
}

/// 任务取消后立即解除业务闭包引用，不依赖前一个任务是否结束。
final class _SerialTask<T> {
  _SerialTask(this._operation);

  Future<T> Function()? _operation;
  final Completer<T> _completer = Completer<T>();

  Future<T> get done => _completer.future;

  Future<void> run() async {
    final operation = _operation!;
    _operation = null;
    try {
      _completer.complete(await operation());
    } catch (error, stack) {
      _completer.completeError(error, stack);
    }
  }

  void cancel(Object error) {
    _operation = null;
    _completer.completeError(error, StackTrace.current);
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
      // 先登记整轮完成信号，再启动任务，保证同步重入读取 idle 时拿到当前轮次。
      _idle = Future<void>.microtask(() => _drain(next));
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
      await current.run();
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
  Object? _closedError;
  final Set<_SerialTask<dynamic>> _pending = <_SerialTask<dynamic>>{};

  Iterable<K> get keys => _tails.keys;
  bool containsKey(K key) => _tails.containsKey(key);

  /// 等待当前已入队的所有键结束；后续任务不包含在本次等待中。
  Future<void> get idle => Future.wait<void>(_tails.values).then<void>((_) {});

  Future<T> enqueue<T>(
    K key,
    Future<T> Function() task, {
    void Function()? onIdle,
  }) {
    final closedError = _closedError;
    if (closedError != null) return Future<T>.error(closedError);
    if (_pendingTasks >= maxPendingTasks) {
      return Future<T>.error(StateError('键控串行任务队列已满，拒绝继续堆积任务。'));
    }

    _pendingTasks += 1;
    final previous = _tails[key] ?? Future<void>.value();
    final entry = _SerialTask<T>(task);
    _pending.add(entry);
    late final Future<void> tail;
    tail = previous.then<void>((_) async {
      if (!_pending.remove(entry)) return;
      try {
        await entry.run();
      } finally {
        _pendingTasks -= 1;
      }
    });
    _tails[key] = tail;
    unawaited(
      tail.then<void>((_) {
        if (!identical(_tails[key], tail)) return;
        _tails.remove(key);
        onIdle?.call();
      }),
    );
    return entry.done;
  }

  void close([Object? error]) {
    if (_closedError != null) return;
    final reason = _closedError = error ?? StateError('键控串行任务队列已关闭。');
    final pending = _pending.toList(growable: false);
    _pending.clear();
    _pendingTasks -= pending.length;
    for (final entry in pending) {
      entry.cancel(reason);
    }
  }
}
