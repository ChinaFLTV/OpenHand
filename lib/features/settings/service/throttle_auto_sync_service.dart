import 'dart:async';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/util/argument_guards.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/stable_hash.dart';
import '../../../shared/util/timer_safety.dart';
import 'throttle_cloud_sync_service.dart';

typedef _ThrottleSyncTarget = ({
  ThrottleCloudSyncProvider provider,
  String endpoint,
  String token,
  String gistId,
});

/// 在后台同步全局流式节流配置。拉取和推送共用合并队列，避免旧响应
/// 与新操作竞争并覆盖较新的配置。
class ThrottleAutoSyncService {
  ThrottleAutoSyncService({
    required this._settingsController,
    ThrottleCloudSyncService? cloudSyncService,
    Duration bootPullDelay = const Duration(seconds: 1),
    Duration pushDebounce = const Duration(seconds: 5),
    Duration cloudChangeDebounce = const Duration(milliseconds: 600),
    Duration disposeTimeout = kOpenHandDefaultAsyncCleanupTimeout,
  }) : _bootPullDelay = _validatedNonNegativeDuration(
         bootPullDelay,
         'bootPullDelay',
       ),
       _pushDebounce = _validatedNonNegativeDuration(
         pushDebounce,
         'pushDebounce',
       ),
       _cloudChangeDebounce = _validatedNonNegativeDuration(
         cloudChangeDebounce,
         'cloudChangeDebounce',
       ),
       _disposeTimeout = _validatedNonNegativeDuration(
         disposeTimeout,
         'disposeTimeout',
       ),
       _cloudSyncService = cloudSyncService ?? ThrottleCloudSyncService(),
       _ownsService = cloudSyncService == null;

  static const Set<String> _signatureMetadataKeys = <String>{
    'exported_at',
    'updated_at_ms',
    'version',
  };

  final SettingsController _settingsController;
  final ThrottleCloudSyncService _cloudSyncService;
  final bool _ownsService;
  final Duration _bootPullDelay;
  final Duration _pushDebounce;
  final Duration _cloudChangeDebounce;
  final Duration _disposeTimeout;
  final OpenHandAsyncOnce _disposeOnce = OpenHandAsyncOnce();

  Timer? _pushDebounceTimer;
  Timer? _pullDebounceTimer;
  Timer? _bootPullTimer;
  StreamSubscription<void>? _cloudChangesSub;
  Future<void>? _syncLoop;
  _ThrottleSyncTarget? _lastSyncTarget;
  String? _lastConfigSignature;
  bool _pullPending = false;
  bool _pushPending = false;
  bool _applyingRemote = false;
  bool _started = false;
  bool _disposed = false;

  /// 注册监听并安排一次延迟启动拉取。重复调用安全且不会产生副作用。
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _settingsController.addListener(_onSettingsChanged);
    _lastConfigSignature = _signatureForConfig(
      _settingsController.exportAiStreamThrottleConfig(),
    );
    _lastSyncTarget = _readSyncTarget();
    _cloudChangesSub = _cloudSyncService.cloudChanges.listen(
      (_) {
        if (_readSyncTarget().provider == ThrottleCloudSyncProvider.iCloud) {
          _schedulePullAfter(_cloudChangeDebounce);
        }
      },
      onError: (Object error, StackTrace stack) =>
          silentLog('throttle_auto_sync', '监听云端变更流', error, stack),
    );
    _bootPullTimer = startSafeTimer(_bootPullDelay, _requestPull);
  }

  /// 停止所有触发器并逻辑取消当前操作。等待 worker 时使用有界期限，
  /// 避免注入的客户端或平台通道忽略取消而阻塞退出。
  Future<void> dispose() => _disposeOnce.run(_dispose);

  Future<void> _dispose() async {
    _disposed = true;
    _pullPending = false;
    _pushPending = false;
    _pushDebounceTimer?.cancel();
    _pushDebounceTimer = null;
    _pullDebounceTimer?.cancel();
    _pullDebounceTimer = null;
    _bootPullTimer?.cancel();
    _bootPullTimer = null;
    final cloudChangesSub = _cloudChangesSub;
    _cloudChangesSub = null;
    if (_started) {
      _settingsController.removeListener(_onSettingsChanged);
      _started = false;
    }
    await cancelStreamSubscriptionBounded<void>(
      cloudChangesSub,
      timeout: _disposeTimeout,
      onError: (error, stack) =>
          silentLog('throttle_auto_sync', '取消云端变更订阅', error, stack),
    );
    final syncLoop = _syncLoop;
    if (syncLoop != null) {
      await runAsyncCleanupBounded(
        () => syncLoop,
        timeout: _disposeTimeout,
        onError: (error, stack) =>
            silentLog('throttle_auto_sync', '等待同步循环结束', error, stack),
      );
    }
    if (_ownsService) {
      await _cloudSyncService.dispose();
    }
  }

  void _onSettingsChanged() {
    if (_disposed) return;

    final target = _readSyncTarget();
    if (target != _lastSyncTarget) {
      _lastSyncTarget = target;
      // 切换目标后先比较时间戳，再发送待处理的本地修改。
      _pushDebounceTimer?.cancel();
      _pushDebounceTimer = null;
      _pushPending = false;
      if (_isTargetReady(target)) {
        _schedulePullAfter(_cloudChangeDebounce);
      }
    }

    final signature = _signatureForConfig(
      _settingsController.exportAiStreamThrottleConfig(),
    );
    if (signature == _lastConfigSignature) return;
    _lastConfigSignature = signature;
    if (_applyingRemote) return;
    _pushDebounceTimer?.cancel();
    _pushDebounceTimer = startSafeTimer(_pushDebounce, _requestPush);
  }

  void _schedulePullAfter(Duration delay) {
    if (_disposed) return;
    _pullDebounceTimer?.cancel();
    _pullDebounceTimer = startSafeTimer(delay, _requestPull);
  }

  void _requestPull() {
    if (_disposed) return;
    _pullPending = true;
    _ensureSyncLoop();
  }

  void _requestPush() {
    if (_disposed) return;
    _pushPending = true;
    _ensureSyncLoop();
  }

  void _ensureSyncLoop() {
    if (_disposed || _syncLoop != null) return;
    final loop = Future<void>.microtask(_drainSyncQueue);
    _syncLoop = loop;
    unawaited(
      loop.then<void>(
        (_) => _finishSyncLoop(loop),
        onError: (Object error, StackTrace stack) {
          silentLog('throttle_auto_sync', '执行同步循环', error, stack);
          _finishSyncLoop(loop);
        },
      ),
    );
  }

  void _finishSyncLoop(Future<void> loop) {
    if (!identical(_syncLoop, loop)) return;
    _syncLoop = null;
    if (!_disposed && (_pullPending || _pushPending)) {
      _ensureSyncLoop();
    }
  }

  Future<void> _drainSyncQueue() async {
    while (!_disposed) {
      if (_pullPending) {
        _pullPending = false;
        await _pullSilently();
        continue;
      }
      if (_pushPending) {
        _pushPending = false;
        await _pushSilently();
        continue;
      }
      return;
    }
  }

  Future<void> _pullSilently() async {
    final target = _readSyncTarget();
    if (!_isTargetReady(target)) return;
    try {
      final result = await _cloudSyncService.pull(
        provider: target.provider,
        endpoint: target.endpoint,
        token: target.token,
        gistId: target.gistId,
      );
      if (_disposed || target != _readSyncTarget()) return;
      if (!result.ok || result.config == null) {
        silentLog('throttle_auto_sync', '拉取云端配置', result.message);
        return;
      }

      final remoteSignature = _signatureForConfig(result.config!);
      final localSignature = _signatureForConfig(
        _settingsController.exportAiStreamThrottleConfig(),
      );
      if (remoteSignature == localSignature) {
        _lastConfigSignature = localSignature;
        return;
      }

      final localUpdatedAtMs =
          _settingsController.aiStreamThrottleConfigUpdatedAtMs;
      final remoteUpdatedAtMs = result.updatedAtMs;
      if (localUpdatedAtMs > 0 &&
          (remoteUpdatedAtMs <= 0 || remoteUpdatedAtMs <= localUpdatedAtMs)) {
        _requestPush();
        return;
      }

      _applyingRemote = true;
      late final AiStreamThrottleConfigImportOutcome outcome;
      try {
        outcome = await _settingsController.importAiStreamThrottleConfig(
          result.config!,
          overrideUpdatedAtMs: remoteUpdatedAtMs > 0 ? remoteUpdatedAtMs : null,
        );
      } finally {
        _applyingRemote = false;
      }
      if (outcome == AiStreamThrottleConfigImportOutcome.failed) {
        silentLog('throttle_auto_sync', '持久化已拉取配置', '设置持久化失败');
        return;
      }
      _lastConfigSignature = _signatureForConfig(
        _settingsController.exportAiStreamThrottleConfig(),
      );
    } catch (error, stack) {
      silentLog('throttle_auto_sync', '拉取云端配置', error, stack);
    }
  }

  Future<void> _pushSilently() async {
    final target = _readSyncTarget();
    if (!_isTargetReady(target)) return;
    try {
      final config = _settingsController.exportAiStreamThrottleConfig();
      final result = await _cloudSyncService.push(
        provider: target.provider,
        endpoint: target.endpoint,
        token: target.token,
        config: config,
        updatedAtMs: _settingsController.aiStreamThrottleConfigUpdatedAtMs,
        gistId: target.gistId,
      );
      if (_disposed || target != _readSyncTarget()) return;
      if (!result.ok) {
        silentLog('throttle_auto_sync', '推送本地配置', result.message);
      }
    } catch (error, stack) {
      silentLog('throttle_auto_sync', '推送本地配置', error, stack);
    }
  }

  _ThrottleSyncTarget _readSyncTarget() {
    final provider = ThrottleCloudSyncProvider.fromStorage(
      _settingsController.aiStreamThrottleCloudSyncProvider,
    );
    final endpoint =
        nullIfBlank(_settingsController.aiStreamThrottleCloudSyncEndpoint) ??
        '';
    final token =
        nullIfBlank(_settingsController.aiStreamThrottleCloudSyncToken) ?? '';
    return (
      provider: provider,
      endpoint: endpoint,
      token: token,
      gistId: provider == ThrottleCloudSyncProvider.gistGitHub ? endpoint : '',
    );
  }

  bool _isTargetReady(_ThrottleSyncTarget target) {
    return switch (target.provider) {
      ThrottleCloudSyncProvider.custom => target.endpoint.isNotEmpty,
      ThrottleCloudSyncProvider.iCloud => true,
      ThrottleCloudSyncProvider.gistGitHub =>
        target.gistId.isNotEmpty && target.token.isNotEmpty,
    };
  }

  /// 生成稳定指纹；元数据变化不应触发配置同步。
  static String _signatureForConfig(Map<String, Object?> config) {
    return stableJsonSha256(<String, Object?>{
      for (final entry in config.entries)
        if (!_signatureMetadataKeys.contains(entry.key)) entry.key: entry.value,
    });
  }
}

Duration _validatedNonNegativeDuration(Duration value, String name) {
  requireNonNegativeDuration(value, name);
  return value;
}
