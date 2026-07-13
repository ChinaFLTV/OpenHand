import 'dart:async';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/timer_safety.dart';
import 'throttle_cloud_sync_service.dart';

/// 节流配置自动同步服务。
///
/// 用户期望：
///   * 应用启动后静默从云端 pull 一次，让多设备无感同步；
///   * 设置变更时 debounce 5s 自动 push，避免每次按键都打一次接口；
///   * provider 不是 custom（iCloud / OAuth 占位）或 endpoint 为空时
///     直接关闭，不执行任何网络 IO。
///
/// 强化为「双向冲突解决」：
///   * 远端 payload 携带 `updated_at_ms`（epoch ms）；
///   * 本地 [SettingsController.aiStreamThrottleConfigUpdatedAtMs] 由
///     `_commitThrottleMutation` 自动 bump；
///   * pull 后若 remote_ms <= local_ms，则跳过 apply 并触发 push 把
///     本地新版本同步到云端，避免老覆新；
///   * native 端外部变更通知（`cloudConfigChanged`）会主动触发一次
///     pull，做到多设备实时联动。
///
/// 设计目标：
///   * 单 service，接管所有"自动"路径，UI 端不感知；
///   * 失败仅记入 silentLog，不打扰用户；
///   * dispose 时清理 Timer 与 listener，避免泄漏。
class ThrottleAutoSyncService {
  ThrottleAutoSyncService({
    required SettingsController settingsController,
    ThrottleCloudSyncService? cloudSyncService,
  }) : _settingsController = settingsController,
       _cloudSyncService = cloudSyncService ?? ThrottleCloudSyncService(),
       _ownsService = cloudSyncService == null;

  final SettingsController _settingsController;
  final ThrottleCloudSyncService _cloudSyncService;
  final bool _ownsService;

  Timer? _debounceTimer;
  Timer? _pullDebounceTimer;
  Timer? _bootPullTimer;
  StreamSubscription<void>? _cloudChangesSub;
  String? _lastConfigSignature;
  bool _started = false;
  bool _disposed = false;

  /// 内部锁：apply 远端配置时设置为 true，避免 listener 把这次 import
  /// 当作本地变更再 push 回去（虽然 timestamp 比对会兜底，但能省一次
  /// push 网络 IO）。
  bool _applyingRemote = false;

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
    // 监听 native 推送的远端变更通知；订阅自身节流防止短时间内多次 pull。
    _cloudChangesSub = _cloudSyncService.cloudChanges.listen((_) {
      _pullDebounceTimer?.cancel();
      _pullDebounceTimer = startSafeTimer(
        const Duration(milliseconds: 600),
        () {
          if (_disposed) return;
          unawaited(_pullSilently());
        },
      );
    });
    _bootPullTimer = startSafeTimer(_bootPullDelay, () {
      if (_disposed) return;
      unawaited(_pullSilently());
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pullDebounceTimer?.cancel();
    _pullDebounceTimer = null;
    _bootPullTimer?.cancel();
    _bootPullTimer = null;
    await _cloudChangesSub?.cancel();
    _cloudChangesSub = null;
    if (_started) {
      _settingsController.removeListener(_onSettingsChanged);
    }
    if (_ownsService) {
      await _cloudSyncService.dispose();
    }
  }

  void _onSettingsChanged() {
    if (_disposed || _applyingRemote) return;
    final config = _settingsController.exportAiStreamThrottleConfig();
    final signature = _signatureFor(config);
    if (signature == _lastConfigSignature) return;
    _lastConfigSignature = signature;
    // 仅当配置发生有效变化时，重置 debounce timer。
    _debounceTimer?.cancel();
    _debounceTimer = startSafeTimer(_pushDebounce, () {
      if (_disposed) return;
      unawaited(_pushSilently());
    });
  }

  Future<void> _pullSilently() async {
    final provider = ThrottleCloudSyncProvider.fromStorage(
      _settingsController.aiStreamThrottleCloudSyncProvider,
    );
    final endpoint =
        nullIfBlank(_settingsController.aiStreamThrottleCloudSyncEndpoint) ??
        '';
    final token =
        nullIfBlank(_settingsController.aiStreamThrottleCloudSyncToken) ?? '';
    if (!_isProviderReady(provider, endpoint, token)) {
      return;
    }
    try {
      final result = await _cloudSyncService.pull(
        provider: provider,
        endpoint: endpoint,
        token: token,
        // gistGitHub provider 复用 endpoint 字段保存 gist id（避免再加
        // 一个独立字段）；其它 provider 这个值传了也无害。
        gistId: provider == ThrottleCloudSyncProvider.gistGitHub
            ? endpoint
            : '',
      );
      if (!result.ok || result.config == null) return;
      final remoteSig = _signatureFor(result.config!);
      final localSig = _signatureFor(
        _settingsController.exportAiStreamThrottleConfig(),
      );
      if (remoteSig == localSig) return;
      // 冲突解决：远端 timestamp 必须严格大于本地，才允许覆盖；
      // 远端无 timestamp（旧文档 / 0）时也允许覆盖（首次同步 / 兼容）。
      final localMs = _settingsController.aiStreamThrottleConfigUpdatedAtMs;
      final remoteMs = result.updatedAtMs;
      if (remoteMs > 0 && localMs > 0 && remoteMs <= localMs) {
        // 本地更新 → 反过来把本地推上去，让远端追上来。
        unawaited(_pushSilently());
        return;
      }
      _applyingRemote = true;
      try {
        await _settingsController.importAiStreamThrottleConfig(
          result.config!,
          overrideUpdatedAtMs: remoteMs > 0 ? remoteMs : null,
        );
      } finally {
        _applyingRemote = false;
      }
      _lastConfigSignature = remoteSig;
    } catch (error, stack) {
      silentLog('throttle_auto_sync', 'pullSilently', error, stack);
    }
  }

  Future<void> _pushSilently() async {
    final provider = ThrottleCloudSyncProvider.fromStorage(
      _settingsController.aiStreamThrottleCloudSyncProvider,
    );
    final endpoint =
        nullIfBlank(_settingsController.aiStreamThrottleCloudSyncEndpoint) ??
        '';
    final token =
        nullIfBlank(_settingsController.aiStreamThrottleCloudSyncToken) ?? '';
    if (!_isProviderReady(provider, endpoint, token)) {
      return;
    }
    try {
      final config = _settingsController.exportAiStreamThrottleConfig();
      final result = await _cloudSyncService.push(
        provider: provider,
        endpoint: endpoint,
        token: token,
        config: config,
        updatedAtMs: _settingsController.aiStreamThrottleConfigUpdatedAtMs,
        gistId: provider == ThrottleCloudSyncProvider.gistGitHub
            ? endpoint
            : '',
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

  bool _isProviderReady(
    ThrottleCloudSyncProvider provider,
    String endpoint,
    String token,
  ) {
    switch (provider) {
      case ThrottleCloudSyncProvider.custom:
        return nullIfBlank(endpoint) != null;
      case ThrottleCloudSyncProvider.iCloud:
        return true;
      case ThrottleCloudSyncProvider.gistGitHub:
        // endpoint 复用为 gist id；token 是 PAT。
        return nullIfBlank(endpoint) != null && nullIfBlank(token) != null;
      case ThrottleCloudSyncProvider.oauth:
        return false;
    }
  }

  /// 把 config 拍平成稳定签名字符串：内部排序后用 ; 拼接 key=val。
  /// 仅用于"是否有变化"的等值判断，不需要严格 JSON 序列化。
  String _signatureFor(Map<String, Object?> config) {
    final keys = config.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final k in keys) {
      // exported_at / updated_at_ms 都是时间戳类辅助字段，跳过避免
      // 假阳性变更（updated_at_ms 在每次 commit 都会 bump，但配置内
      // 容若没动我们也不该判定为"变更"）。
      // version 是 schema 标记位，不属于"用户数据"；跨版本时 migrate
      // 已经把缺失字段补齐，签名只要数据等价就视为相同，避免老远端
      // 触发不必要的 push/pull 循环。
      if (k == 'exported_at' || k == 'updated_at_ms' || k == 'version') {
        continue;
      }
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
