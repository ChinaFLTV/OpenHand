import 'dart:async';

import '../../shared/util/async_concurrency.dart';
import 'silent_log.dart';

typedef AppRuntimeCleanup = FutureOr<void> Function();
typedef AppRuntimeCleanupErrorHandler =
    void Function(String name, Object error, StackTrace stackTrace);

/// Owns application-scoped resources created before the Provider tree.
/// Cleanups run in reverse registration order, matching dependency teardown.
final class AppRuntimeCleanupRegistry {
  AppRuntimeCleanupRegistry({
    Duration cleanupTimeout = kOpenHandDefaultAsyncCleanupTimeout,
    AppRuntimeCleanupErrorHandler? onError,
  }) : _cleanupTimeout = cleanupTimeout,
       _onError = onError;

  final Duration _cleanupTimeout;
  final AppRuntimeCleanupErrorHandler? _onError;
  final List<({String name, AppRuntimeCleanup cleanup})> _entries =
      <({String name, AppRuntimeCleanup cleanup})>[];
  Future<void>? _disposeFuture;

  void register(String name, AppRuntimeCleanup cleanup) {
    if (_disposeFuture != null) {
      throw StateError('Cannot register $name after runtime cleanup started.');
    }
    _entries.add((name: name, cleanup: cleanup));
  }

  Future<void> dispose() {
    final active = _disposeFuture;
    if (active != null) return active;
    final completer = Completer<void>();
    _disposeFuture = completer.future;
    unawaited(
      _disposeAll().then<void>(
        (_) => completer.complete(),
        onError: (Object error, StackTrace stack) {
          _reportError('runtime cleanup registry', error, stack);
          completer.complete();
        },
      ),
    );
    return completer.future;
  }

  Future<void> _disposeAll() async {
    while (_entries.isNotEmpty) {
      final entry = _entries.removeLast();
      await runAsyncCleanupBounded(
        entry.cleanup,
        timeout: _cleanupTimeout,
        onError: (error, stack) => _reportError(entry.name, error, stack),
      );
    }
  }

  void _reportError(String name, Object error, StackTrace stack) {
    final handler = _onError;
    if (handler != null) {
      handler(name, error, stack);
      return;
    }
    silentLog('app_runtime_cleanup', name, error, stack);
  }
}
