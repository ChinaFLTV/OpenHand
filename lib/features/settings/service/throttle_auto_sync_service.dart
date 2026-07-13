import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/timer_safety.dart';
import 'throttle_cloud_sync_service.dart';

typedef _ThrottleSyncTarget = ({
  ThrottleCloudSyncProvider provider,
  String endpoint,
  String token,
  String gistId,
});

/// Keeps the global stream-throttle configuration synchronized in the
/// background. Pull and push requests share one coalescing queue so an older
/// response cannot race a newer operation and overwrite it.
class ThrottleAutoSyncService {
  ThrottleAutoSyncService({
    required SettingsController settingsController,
    ThrottleCloudSyncService? cloudSyncService,
    Duration bootPullDelay = const Duration(seconds: 1),
    Duration pushDebounce = const Duration(seconds: 5),
    Duration cloudChangeDebounce = const Duration(milliseconds: 600),
    Duration disposeTimeout = kOpenHandDefaultAsyncCleanupTimeout,
  }) : assert(!bootPullDelay.isNegative),
       assert(!pushDebounce.isNegative),
       assert(!cloudChangeDebounce.isNegative),
       assert(!disposeTimeout.isNegative),
       _settingsController = settingsController,
       _cloudSyncService = cloudSyncService ?? ThrottleCloudSyncService(),
       _ownsService = cloudSyncService == null,
       _bootPullDelay = bootPullDelay,
       _pushDebounce = pushDebounce,
       _cloudChangeDebounce = cloudChangeDebounce,
       _disposeTimeout = disposeTimeout;

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
  final Completer<void> _disposeSignal = Completer<void>();

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

  /// Registers listeners and schedules one delayed startup pull. Repeated
  /// calls are safe and have no effect.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _settingsController.addListener(_onSettingsChanged);
    _lastConfigSignature = signatureForConfig(
      _settingsController.exportAiStreamThrottleConfig(),
    );
    _lastSyncTarget = _readSyncTarget();
    _cloudChangesSub = _cloudSyncService.cloudChanges.listen(
      (_) => _schedulePullAfter(_cloudChangeDebounce),
      onError: (Object error, StackTrace stack) =>
          silentLog('throttle_auto_sync', 'cloud changes stream', error, stack),
    );
    _bootPullTimer = startSafeTimer(_bootPullDelay, _requestPull);
  }

  /// Stops every trigger and logically cancels the active operation. The
  /// worker is awaited with a bounded deadline so shutdown cannot hang on an
  /// injected client or platform channel that ignores cancellation.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!_disposeSignal.isCompleted) _disposeSignal.complete();
    _pullPending = false;
    _pushPending = false;
    _pushDebounceTimer?.cancel();
    _pushDebounceTimer = null;
    _pullDebounceTimer?.cancel();
    _pullDebounceTimer = null;
    _bootPullTimer?.cancel();
    _bootPullTimer = null;
    await cancelStreamSubscriptionBounded<void>(
      _cloudChangesSub,
      timeout: _disposeTimeout,
      onError: (error, stack) => silentLog(
        'throttle_auto_sync',
        'cancel cloud changes subscription',
        error,
        stack,
      ),
    );
    _cloudChangesSub = null;
    if (_started) {
      _settingsController.removeListener(_onSettingsChanged);
    }
    if (_ownsService) {
      await _cloudSyncService.dispose();
    }
    final syncLoop = _syncLoop;
    if (syncLoop != null) {
      await runAsyncCleanupBounded(
        () => syncLoop,
        timeout: _disposeTimeout,
        onError: (error, stack) => silentLog(
          'throttle_auto_sync',
          'await sync loop shutdown',
          error,
          stack,
        ),
      );
    }
  }

  void _onSettingsChanged() {
    if (_disposed) return;

    final target = _readSyncTarget();
    if (target != _lastSyncTarget) {
      _lastSyncTarget = target;
      // Never send a pending edit to a newly selected target before checking
      // which side has the newer timestamp.
      _pushDebounceTimer?.cancel();
      _pushDebounceTimer = null;
      _pushPending = false;
      if (_isTargetReady(target)) {
        _schedulePullAfter(_cloudChangeDebounce);
      }
    }

    final signature = signatureForConfig(
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
          silentLog('throttle_auto_sync', 'sync loop', error, stack);
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
      final result = await awaitWithCancelSignal(
        _cloudSyncService.pull(
          provider: target.provider,
          endpoint: target.endpoint,
          token: target.token,
          gistId: target.gistId,
        ),
        cancelSignal: _disposeSignal.future,
      );
      if (result == null || _disposed || target != _readSyncTarget()) return;
      if (!result.ok || result.config == null) {
        silentLog(
          'throttle_auto_sync',
          'pull',
          result.message,
          StackTrace.current,
        );
        return;
      }

      final remoteSignature = signatureForConfig(result.config!);
      final localSignature = signatureForConfig(
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
        silentLog(
          'throttle_auto_sync',
          'persist pulled config',
          'settings persistence failed',
          StackTrace.current,
        );
        return;
      }
      _lastConfigSignature = signatureForConfig(
        _settingsController.exportAiStreamThrottleConfig(),
      );
    } catch (error, stack) {
      silentLog('throttle_auto_sync', 'pull', error, stack);
    }
  }

  Future<void> _pushSilently() async {
    final target = _readSyncTarget();
    if (!_isTargetReady(target)) return;
    try {
      final config = _settingsController.exportAiStreamThrottleConfig();
      final result = await awaitWithCancelSignal(
        _cloudSyncService.push(
          provider: target.provider,
          endpoint: target.endpoint,
          token: target.token,
          config: config,
          updatedAtMs: _settingsController.aiStreamThrottleConfigUpdatedAtMs,
          gistId: target.gistId,
        ),
        cancelSignal: _disposeSignal.future,
      );
      if (result == null || _disposed || target != _readSyncTarget()) return;
      if (!result.ok) {
        silentLog(
          'throttle_auto_sync',
          'push',
          result.message,
          StackTrace.current,
        );
      }
    } catch (error, stack) {
      silentLog('throttle_auto_sync', 'push', error, stack);
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

  /// Produces escaped canonical JSON so delimiters inside values cannot make
  /// two different configurations share a signature.
  @visibleForTesting
  static String signatureForConfig(Map<String, Object?> config) {
    final keys =
        config.keys
            .where((key) => !_signatureMetadataKeys.contains(key))
            .toList(growable: false)
          ..sort();
    return jsonEncode(<String, Object?>{
      for (final key in keys) key: _canonicalJsonValue(config[key]),
    });
  }

  static Object? _canonicalJsonValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList(growable: false)
        ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      return <String, Object?>{
        for (final entry in entries)
          '${entry.key}': _canonicalJsonValue(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map<Object?>(_canonicalJsonValue).toList(growable: false);
    }
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    return '$value';
  }
}
