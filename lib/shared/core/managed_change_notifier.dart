import 'dart:async';

import 'package:flutter/foundation.dart';

/// Lightweight controller foundation for feature notifiers that need:
/// - dispose-safe [notifyListeners]
/// - serialized async mutations / refreshes
/// - tiny success pulse signals for transient UI feedback
abstract class ManagedChangeNotifier extends ChangeNotifier {
  bool _isDisposed = false;
  Future<void> _operationQueue = Future<void>.value();

  @protected
  bool get isDisposed => _isDisposed;

  StateError get _disposedError => StateError('$runtimeType is disposed');

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
    final completer = Completer<T>();
    _operationQueue = _operationQueue.catchError((error, stackTrace) {}).then((
      _,
    ) async {
      if (_isDisposed) {
        if (!completer.isCompleted) {
          completer.completeError(_disposedError);
        }
        return;
      }
      try {
        final result = await operation();
        if (_isDisposed) {
          completer.completeError(_disposedError);
        } else {
          completer.complete(result);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

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
