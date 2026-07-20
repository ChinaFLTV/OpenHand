import 'dart:async';

import '../../shared/util/async_concurrency.dart';
import 'silent_log.dart';

typedef AppRuntimeCleanup = FutureOr<void> Function();
typedef AppRuntimeCleanupErrorHandler =
    void Function(String name, Object error, StackTrace stackTrace);

const Duration kOpenHandDefaultRuntimeCleanupTotalTimeout = Duration(
  seconds: 30,
);
const Duration kOpenHandMaxRuntimeCleanupTotalTimeout = Duration(minutes: 2);

/// 统一管理 Provider 树创建前产生的应用级资源，并按注册逆序释放依赖。
final class AppRuntimeCleanupRegistry {
  AppRuntimeCleanupRegistry({
    Duration cleanupTimeout = kOpenHandDefaultAsyncCleanupTimeout,
    Duration totalTimeout = kOpenHandDefaultRuntimeCleanupTotalTimeout,
    AppRuntimeCleanupErrorHandler? onError,
  }) : _cleanupTimeout = _positiveCleanupDuration(
         cleanupTimeout,
         'cleanupTimeout',
       ),
       _totalTimeout = _positiveCleanupDuration(
         totalTimeout,
         'totalTimeout',
         maximum: kOpenHandMaxRuntimeCleanupTotalTimeout,
       ),
       _onError = onError;

  final Duration _cleanupTimeout;
  final Duration _totalTimeout;
  final AppRuntimeCleanupErrorHandler? _onError;
  final List<({String name, AppRuntimeCleanup cleanup})> _entries =
      <({String name, AppRuntimeCleanup cleanup})>[];
  Future<void>? _disposeFuture;

  void register(String name, AppRuntimeCleanup cleanup) {
    if (_disposeFuture != null) {
      throw StateError('运行时资源释放开始后不能再注册：$name');
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
          _reportError('运行时资源释放注册表', error, stack);
          completer.complete();
        },
      ),
    );
    return completer.future;
  }

  Future<void> _disposeAll() async {
    final stopwatch = Stopwatch()..start();
    while (_entries.isNotEmpty) {
      final entry = _entries.removeLast();
      final remainingEntries = _entries.length + 1;
      final remainingMicros =
          _totalTimeout.inMicroseconds - stopwatch.elapsedMicroseconds;
      final fairShare = Duration(
        microseconds: remainingMicros <= 0
            ? 0
            : remainingMicros ~/ remainingEntries,
      );
      await runAsyncCleanupBounded(
        entry.cleanup,
        timeout: fairShare < _cleanupTimeout ? fairShare : _cleanupTimeout,
        onError: (error, stack) => _reportError(entry.name, error, stack),
      );
    }
    stopwatch.stop();
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

Duration _positiveCleanupDuration(
  Duration value,
  String name, {
  Duration? maximum,
}) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, '必须大于零。');
  }
  if (maximum != null && value > maximum) return maximum;
  return value;
}
