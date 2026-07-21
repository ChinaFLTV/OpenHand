import 'dart:async';

import 'package:flutter/foundation.dart';

import '../util/serial_task_queue.dart';

/// 为功能控制器统一提供安全通知、串行异步操作和轻量成功信号。
abstract class ManagedChangeNotifier extends ChangeNotifier {
  bool _isDisposed = false;
  final SerialTaskQueue _operationQueue = SerialTaskQueue();

  StateError get _disposedError => StateError('$runtimeType 已释放');

  @override
  void notifyListeners() {
    if (_isDisposed) {
      return;
    }
    super.notifyListeners();
  }

  @protected
  Future<T> enqueueOperation<T>(Future<T> Function() operation) {
    if (_isDisposed) {
      return Future<T>.error(_disposedError);
    }
    return _operationQueue.enqueue(() async {
      if (_isDisposed) {
        throw _disposedError;
      }
      final result = await operation();
      if (_isDisposed) {
        throw _disposedError;
      }
      return result;
    });
  }

  @protected
  Future<void> get operationsIdle => _operationQueue.idle;

  @override
  @mustCallSuper
  void dispose() {
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
