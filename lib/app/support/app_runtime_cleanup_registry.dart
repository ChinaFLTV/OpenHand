import 'dart:async';

import '../../shared/util/argument_guards.dart';
import '../../shared/util/async_concurrency.dart';
import 'silent_log.dart';

typedef AppRuntimeCleanup = FutureOr<void> Function();
typedef AppRuntimeCleanupErrorHandler =
    void Function(String name, Object error, StackTrace stackTrace);

const Duration kOpenHandDefaultRuntimeCleanupTotalTimeout = Duration(
  seconds: 30,
);
const Duration kOpenHandApplicationRuntimeCleanupTotalTimeout = Duration(
  seconds: 60,
);
const Duration kOpenHandMaxRuntimeCleanupTotalTimeout = Duration(minutes: 2);

/// 统一管理 Provider 树创建前产生的应用级资源，并按注册逆序释放依赖。
final class AppRuntimeCleanupRegistry {
  AppRuntimeCleanupRegistry({
    Duration cleanupTimeout = kOpenHandDefaultAsyncCleanupTimeout,
    Duration totalTimeout = kOpenHandDefaultRuntimeCleanupTotalTimeout,
    this._onError,
  }) : _cleanupTimeout = _positiveCleanupDuration(
         cleanupTimeout,
         'cleanupTimeout',
       ),
       _totalTimeout = _positiveCleanupDuration(
         totalTimeout,
         'totalTimeout',
         maximum: kOpenHandMaxRuntimeCleanupTotalTimeout,
       );

  final Duration _cleanupTimeout;
  final Duration _totalTimeout;
  final AppRuntimeCleanupErrorHandler? _onError;
  final List<({String name, AppRuntimeCleanup cleanup, Duration timeout})>
  _entries = <({String name, AppRuntimeCleanup cleanup, Duration timeout})>[];
  final OpenHandAsyncOnce _disposeOnce = OpenHandAsyncOnce();
  bool _disposing = false;

  void register(String name, AppRuntimeCleanup cleanup, {Duration? timeout}) {
    if (_disposing) {
      throw StateError('运行时资源释放开始后不能再注册：$name');
    }
    _entries.add((
      name: name,
      cleanup: cleanup,
      timeout: timeout == null
          ? _cleanupTimeout
          : _positiveCleanupDuration(
              timeout,
              'timeout',
              maximum: kOpenHandMaxAsyncCleanupTimeout,
            ),
    ));
  }

  Future<void> dispose() => _disposeOnce.run(() async {
    _disposing = true;
    try {
      await _disposeAll();
    } catch (error, stack) {
      _reportError('运行时资源释放注册表', error, stack);
    }
  });

  Future<void> _disposeAll() async {
    final deadline = MonotonicDeadline(
      _totalTimeout,
      timeoutMessage: '运行时资源释放超过总时限。',
    );
    try {
      while (_entries.isNotEmpty) {
        final remaining = deadline.remainingOrNull();
        if (remaining == null) {
          final skippedCount = _entries.length;
          _entries.clear();
          _reportError(
            '运行时资源释放总时限',
            TimeoutException('总时限已耗尽，已跳过 $skippedCount 项清理。'),
            StackTrace.current,
          );
          break;
        }
        final entry = _entries.removeLast();
        await runAsyncCleanupBounded(
          entry.cleanup,
          timeout: remaining < entry.timeout ? remaining : entry.timeout,
          onError: (error, stack) => _reportError(entry.name, error, stack),
        );
      }
    } finally {
      deadline.stop();
    }
  }

  void _reportError(String name, Object error, StackTrace stack) {
    final handler = _onError;
    if (handler != null) {
      try {
        handler(name, error, stack);
      } catch (handlerError, handlerStack) {
        silentLog(
          'app_runtime_cleanup',
          '上报运行时资源释放异常',
          handlerError,
          handlerStack,
        );
      }
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
  requirePositiveDuration(value, name);
  if (maximum != null && value > maximum) return maximum;
  return value;
}
