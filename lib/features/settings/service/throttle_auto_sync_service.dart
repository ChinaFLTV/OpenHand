import 'dart:async';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/silent_log.dart';
import 'throttle_cloud_sync_service.dart';

/// 节流配置自动同步服务。
///
/// 2026-05-18 — 用户期望：
///   * 应用启动后静默从云端 pull 一次，让多设备无感同步；
///   * 设置变更时 debounce 5s 自动 push，避免每次按键都打一次接口；
///   * provider 不是 custom（iCloud / OAuth 占位）或 endpoint 为空时
///     直接关闭，不执行任何网络 IO。
///
/// 设计目标：
///   * 单 service，接管所有"自动"路径，UI 端不感知；
///   * 失败仅记入 silentLog，不打扰用户；
///   * dispose 时清理 Timer 与 listener，避免泄漏。
class ThrottleAutoSyncService {
  ThrottleAutoSyncService({
    required SettingsController settingsController,
    ThrottleCloudSyncService? cloudSyncService,
  })  : _settingsController = settingsController,
        _cloudSyncService = cloudSyncService ?? ThrottleCloudSyncService();

  final SettingsController _settingsController;
  final ThrottleCloudSyncService _cloudSyncService;

  Timer? _debounceTimer;
  String? _lastConfigSignature;
  bool _started = false;
  bool _disposed = false;

  static const Duration _bootPullDelay = Duration(seconds: 1);
  static const Duration _pushDebounce = Duration(seconds: 5);

  /// 启动 service：注册 settings listener；1s 后静默 pull 一次。
  /// 多次调用安全（仅首次生效）。
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _settingsController.addListener(_onSettingsChanged);
    // 记录初始签名，避免初始化触发 listener 时被当成 push 信号。
    _lastConfigSignature = _signatureFor(
      _settingsController.exportAiStreamThrottleConfig(),
    );
    Future<void>.delayed(_bootPullDelay, () {
      if (_disposed) return;
      unawaited(_pullSilently());
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_started) {
      _settingsController.removeListener(_onSettingsChanged);
    }
  }

  void _onSettingsChanged() {
    if (_disposed) return;
    final config = _settingsController.exportAiStreamThrottleConfig();
    final signature = _signatureFor(config);
    if (signature == _lastConfigSignature) return;
    _lastConfigSignature = signature;
    // 仅当配置发生有效变化时，重置 debounce timer。
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_pushDebounce, () {
      if (_disposed) return;
      unawaited(_pushSilently());
    });
  }

  Future<void> _pullSilently() async {
    final provider = ThrottleCloudSyncProvider.fromStorage(
      _settingsController.aiStreamThrottleCloudSyncProvider,
    );
    final endpoint = _settingsController.aiStreamThrottleCloudSyncEndpoint;
    final token = _settingsController.aiStreamThrottleCloudSyncToken;
    // 2026-05-18 — custom 必须配 endpoint；iCloud 走 native 桥不依赖
    // endpoint，直接放行。
    final isCustomReady =
        provider == ThrottleCloudSyncProvider.custom && endpoint.isNotEmpty;
    final isIcloud = provider == ThrottleCloudSyncProvider.iCloud;
    if (!isCustomReady && !isIcloud) {
      return;
    }
    try {
      final result = await _cloudSyncService.pull(
        provider: provider,
        endpoint: endpoint,
        token: token,
      );
      if (!result.ok || result.config == null) return;
      final remoteSig = _signatureFor(result.config!);
      final localSig = _signatureFor(
        _settingsController.exportAiStreamThrottleConfig(),
      );
      if (remoteSig == localSig) return;
      await _settingsController.importAiStreamThrottleConfig(result.config!);
      _lastConfigSignature = remoteSig;
    } catch (error, stack) {
      silentLog('throttle_auto_sync', 'pullSilently', error, stack);
    }
  }

  Future<void> _pushSilently() async {
    final provider = ThrottleCloudSyncProvider.fromStorage(
      _settingsController.aiStreamThrottleCloudSyncProvider,
    );
    final endpoint = _settingsController.aiStreamThrottleCloudSyncEndpoint;
    final token = _settingsController.aiStreamThrottleCloudSyncToken;
    final isCustomReady =
        provider == ThrottleCloudSyncProvider.custom && endpoint.isNotEmpty;
    final isIcloud = provider == ThrottleCloudSyncProvider.iCloud;
    if (!isCustomReady && !isIcloud) {
      return;
    }
    try {
      final config = _settingsController.exportAiStreamThrottleConfig();
      final result = await _cloudSyncService.push(
        provider: provider,
        endpoint: endpoint,
        token: token,
        config: config,
      );
      if (!result.ok) {
        silentLog(
          'throttle_auto_sync',
          'pushSilently',
          result.message,
          StackTrace.current,
        );
      }
    } catch (error, stack) {
      silentLog('throttle_auto_sync', 'pushSilently', error, stack);
    }
  }

  /// 把 config 拍平成稳定签名字符串：内部排序后用 ; 拼接 key=val。
  /// 仅用于"是否有变化"的等值判断，不需要严格 JSON 序列化。
  String _signatureFor(Map<String, Object?> config) {
    final keys = config.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final k in keys) {
      // exported_at 是时间戳，每次 export 都会变，跳过避免假阳性变更。
      if (k == 'exported_at') continue;
      final v = config[k];
      buffer
        ..write(k)
        ..write('=')
        ..write(_stringify(v))
        ..write(';');
    }
    return buffer.toString();
  }

  String _stringify(Object? v) {
    if (v == null) return 'null';
    if (v is Map) {
      final keys = v.keys.toList()..sort((a, b) => '$a'.compareTo('$b'));
      final inner = StringBuffer('{');
      for (final k in keys) {
        inner
          ..write(k)
          ..write('=')
          ..write(_stringify(v[k]))
          ..write(',');
      }
      inner.write('}');
      return inner.toString();
    }
    return '$v';
  }
}
