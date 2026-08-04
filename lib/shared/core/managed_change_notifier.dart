import 'dart:async';

import 'package:flutter/foundation.dart';

import '../util/serial_task_queue.dart';

const Duration _kManagedControllerShutdownTimeout = Duration(seconds: 3);

/// 为功能控制器统一提供安全通知、串行异步操作和轻量成功信号。
abstract class ManagedChangeNotifier extends ChangeNotifier {
  bool _isDisposed = false;
  bool _isShuttingDown = false;
  final SerialTaskQueue _operationQueue = SerialTaskQueue();
  Future<void>? _shutdownFuture;

  @protected
  bool get isDisposed => _isDisposed;

  @protected
  bool get isShuttingDown => _isShuttingDown;

  @protected
  Duration get operationShutdownTimeout => _kManagedControllerShutdownTimeout;

  StateError get _unavailableError => StateError('$runtimeType 正在关闭或已释放');

  @override
  void notifyListeners() {
    if (_isDisposed) {
      return;
    }
    super.notifyListeners();
  }

  @protected
  Future<T> enqueueOperation<T>(Future<T> Function() operation) {
    if (_isDisposed || _isShuttingDown) {
      return Future<T>.error(_unavailableError);
    }
    return _operationQueue.enqueue(() async {
      if (_isDisposed) {
        throw _unavailableError;
      }
      final result = await operation();
      if (_isDisposed) {
        throw _unavailableError;
      }
      return result;
    });
  }

  /// 停止接收新操作，并有界等待已经入队的操作结束。
  Future<void> shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    _isShuttingDown = true;
    final shutdown = () async {
      try {
        await _operationQueue.idle.timeout(operationShutdownTimeout);
      } finally {
        if (!_isDisposed) dispose();
      }
    }();
    _shutdownFuture = shutdown;
    return shutdown;
  }

  @override
  @mustCallSuper
  void dispose() {
    if (_isDisposed) return;
    _isShuttingDown = true;
    _isDisposed = true;
    super.dispose();
  }
}

final class ChangePulse {
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);
  bool _isDisposed = false;

  ValueListenable<int> get listenable => _notifier;

  void emit() {
    if (_isDisposed) return;
    _notifier.value = _notifier.value + 1;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _notifier.dispose();
  }
}
