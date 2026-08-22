import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../shared/util/serial_task_queue.dart';
import '../ai/index.dart';
import 'data/ai_model_proxy_store.dart';
import 'model/ai_exposure_models.dart';
import 'model/ai_model_proxy_models.dart';

enum AiModelProxyLifecycle { stopped, starting, running, stopping, error }

class AiModelProxyController extends ChangeNotifier {
  AiModelProxyController({AiModelProxyStore? store})
    : _store = store ?? AiModelProxyStore();

  final AiModelProxyStore _store;
  final SerialTaskQueue _writes = SerialTaskQueue(maxPendingTasks: 2048);
  AiModelProxySettings _settings = const AiModelProxySettings();
  AiModelProxyLifecycle _lifecycle = AiModelProxyLifecycle.stopped;
  bool _busy = false;
  String? _errorMessage;
  bool _disposed = false;
  final Map<String, int> _roundRobinCursors = <String, int>{};
  final Map<String, int> _proxyRoundRobinCursors = <String, int>{};
  final List<DateTime> _rateWindow = <DateTime>[];
  int _rateWindowTokens = 0;
  List<AiModelConfig> Function()? _modelsProvider;
  AiExposureProxyConfiguration Function()? _networkProxyProvider;

  AiModelProxySettings get settings => _settings;
  AiModelProxyLifecycle get lifecycle => _lifecycle;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;

  /// 判断模型 Base URL 是否指向当前 OpenHand 中转站监听端点。
  ///
  /// 监听地址变化后通过 [settings] 读取最新配置，避免设置页和服务弹窗
  /// 各自维护一份可能失真的端点判断逻辑。
  bool isSelfProxyBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return false;
    try {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) return false;
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return false;
      final providerHost = _normalizeEndpointHost(uri.host);
      if (providerHost.isEmpty) return false;
      final providerPort = uri.hasPort
          ? uri.port
          : (scheme == 'https' ? 443 : 80);
      if (providerPort != _settings.listenPort) return false;

      final configuredHost = _normalizeEndpointHost(_settings.listenHost);
      if (configuredHost.isEmpty || providerHost == configuredHost) {
        return configuredHost.isNotEmpty && providerHost == configuredHost;
      }
      return _isLocalOrWildcardHost(providerHost) &&
          _isLocalOrWildcardHost(configuredHost);
    } on FormatException {
      // Uri 的端口在访问时才解析，非法端口需要安全降级为非匹配。
      return false;
    }
  }

  static String _normalizeEndpointHost(String host) {
    final value = host.trim().toLowerCase();
    if (value.length >= 2 && value.startsWith('[') && value.endsWith(']')) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  static bool _isLocalOrWildcardHost(String host) {
    if (host == 'localhost' || host == 'localhost.localdomain') return true;
    if (host == '0.0.0.0' || host == '*' || host == '::') return true;
    if (host == '::1' || host == '0:0:0:0:0:0:0:1') return true;
    if (RegExp(r'^127(?:\.\d{1,3}){3}$').hasMatch(host)) return true;
    return RegExp(r'^::ffff:127(?:\.\d{1,3}){3}$').hasMatch(host);
  }

  void attachModelsProvider(List<AiModelConfig> Function() provider) {
    _modelsProvider = provider;
  }

  /// 复用暴露面扫描服务的代理池配置，保证两个服务选择同一条网络策略。
  void attachNetworkProxyProvider(
    AiExposureProxyConfiguration Function() provider,
  ) {
    _networkProxyProvider = provider;
  }

  AiExposureProxyConfiguration? get networkProxyConfiguration =>
      _networkProxyProvider?.call();

  AiExposureProxyEndpoint? resolveProxyEndpoint({String targetHost = ''}) {
    final configuration = networkProxyConfiguration;
    if (configuration == null ||
        !configuration.enabled ||
        configuration.mode != AiExposureProxyMode.pool) {
      return null;
    }
    final endpoints = configuration.activeEndpoints;
    if (endpoints.isEmpty) return null;
    switch (configuration.strategy) {
      case AiExposureProxyStrategy.fixed:
        return endpoints.first;
      case AiExposureProxyStrategy.random:
        return endpoints[math.Random().nextInt(endpoints.length)];
      case AiExposureProxyStrategy.stickyHost:
        final key = targetHost.trim().toLowerCase();
        final index = key.isEmpty
            ? 0
            : (key.hashCode & 0x7fffffff) % endpoints.length;
        return endpoints[index];
      case AiExposureProxyStrategy.roundRobin:
        final key = targetHost.trim().toLowerCase().isEmpty
            ? 'default'
            : targetHost.trim().toLowerCase();
        final index = _proxyRoundRobinCursors.update(
          key,
          (value) => (value + 1) % endpoints.length,
          ifAbsent: () => 0,
        );
        return endpoints[index];
    }
  }

  bool authorize(Map<String, String> headers) {
    if (!_settings.requireAuthentication) return true;
    final expected = _settings.apiKey.trim();
    if (expected.isEmpty) return false;
    final authorization = headers.entries
        .firstWhere(
          (entry) => entry.key.toLowerCase() == 'authorization',
          orElse: () => const MapEntry<String, String>('', ''),
        )
        .value
        .trim();
    final apiKey = headers.entries
        .firstWhere(
          (entry) => entry.key.toLowerCase() == 'x-api-key',
          orElse: () => const MapEntry<String, String>('', ''),
        )
        .value
        .trim();
    return apiKey == expected ||
        authorization == expected ||
        authorization == 'Bearer $expected';
  }

  AiModelProxyBackend? resolveBackend(String exposedModel) {
    final route = _settings.routes
        .where((item) => item.exposedModel == exposedModel)
        .firstOrNull;
    if (route == null) return null;
    final enabled = route.backends
        .where((item) => item.enabled)
        .toList(growable: false);
    if (enabled.isEmpty) return null;
    return switch (_settings.scheduling) {
      AiModelProxySchedulingStrategy.random =>
        enabled[math.Random().nextInt(enabled.length)],
      AiModelProxySchedulingStrategy.roundRobin => _nextRoundRobin(
        exposedModel,
        enabled,
      ),
      AiModelProxySchedulingStrategy.priority ||
      AiModelProxySchedulingStrategy.conservative ||
      AiModelProxySchedulingStrategy.sticky => enabled.first,
    };
  }

  List<String> get endpointPaths => switch (_settings.apiStyle) {
    AiModelProxyApiStyle.openAiChatCompletions => const <String>[
      '/v1/models',
      '/v1/chat/completions',
    ],
    AiModelProxyApiStyle.openAiResponses => const <String>[
      '/v1/models',
      '/v1/responses',
    ],
    AiModelProxyApiStyle.claude => const <String>['/v1/models', '/v1/messages'],
    AiModelProxyApiStyle.gemini => const <String>[
      '/v1/models',
      '/v1beta/models:generateContent',
    ],
  };

  bool consumeRateLimit({required int tokens}) {
    final now = DateTime.now();
    _rateWindow.removeWhere(
      (time) => now.difference(time) >= const Duration(minutes: 1),
    );
    if (_settings.limitMode == AiModelProxyLimitMode.rpm) {
      if (_rateWindow.length >= _settings.limitThreshold) return false;
      _rateWindow.add(now);
      return true;
    }
    final safeTokens = tokens.clamp(0, 1 << 30);
    if (_rateWindowTokens + safeTokens > _settings.limitThreshold) return false;
    _rateWindow.add(now);
    _rateWindowTokens += safeTokens;
    return true;
  }

  Future<void> load() async {
    _settings = await _store.load();
    _notify();
  }

  Future<void> toggle() =>
      _lifecycle == AiModelProxyLifecycle.running ? stop() : start();

  Future<void> start() async {
    if (_busy || _lifecycle == AiModelProxyLifecycle.running) return;
    _busy = true;
    _lifecycle = AiModelProxyLifecycle.starting;
    _errorMessage = null;
    _notify();
    try {
      _ensureRoutesFromProviders();
      if (_settings.routes.every(
        (route) => route.backends.every((item) => !item.enabled),
      )) {
        throw StateError('至少需要一个启用的后备模型。');
      }
      _settings = _settings.copyWith(enabled: true);
      await _store.save(_settings);
      _lifecycle = AiModelProxyLifecycle.running;
    } catch (error) {
      _lifecycle = AiModelProxyLifecycle.error;
      _errorMessage = '$error';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> stop() async {
    if (_busy || _lifecycle == AiModelProxyLifecycle.stopped) return;
    _busy = true;
    _lifecycle = AiModelProxyLifecycle.stopping;
    _notify();
    try {
      _settings = _settings.copyWith(enabled: false);
      await _store.save(_settings);
      _lifecycle = AiModelProxyLifecycle.stopped;
    } catch (error) {
      _lifecycle = AiModelProxyLifecycle.error;
      _errorMessage = '$error';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> saveSettings(AiModelProxySettings settings) async {
    _settings = settings;
    _notify();
    await _writes.enqueue(() => _store.save(settings));
  }

  Future<void> saveRoutes(List<AiModelProxyRoute> routes) =>
      saveSettings(_settings.copyWith(routes: routes));

  Future<void> recordRequest({
    required bool success,
    required int tokens,
    required int durationMs,
    String providerId = '',
    String modelId = '',
    String apiStyle = '',
    String? error,
    String clientIp = '',
    String clientPort = '',
    String proxyMode = '',
    String proxyEndpoint = '',
    String remoteHost = '',
    String remotePort = '',
  }) => saveSettings(
    _settings.record(
      success: success,
      tokens: tokens,
      durationMs: durationMs,
      providerId: providerId,
      modelId: modelId,
      apiStyle: apiStyle,
      error: error,
      clientIp: clientIp,
      clientPort: clientPort,
      proxyMode: proxyMode,
      proxyEndpoint: proxyEndpoint,
      remoteHost: remoteHost,
      remotePort: remotePort,
    ),
  );

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  AiModelProxyBackend _nextRoundRobin(
    String exposedModel,
    List<AiModelProxyBackend> enabled,
  ) {
    final index = _roundRobinCursors.update(
      exposedModel,
      (value) => (value + 1) % enabled.length,
      ifAbsent: () => 0,
    );
    return enabled[index];
  }

  void _ensureRoutesFromProviders() {
    if (_settings.routes.isNotEmpty) return;
    final providers = _modelsProvider?.call() ?? const <AiModelConfig>[];
    final routes = <AiModelProxyRoute>[
      for (final provider in providers)
        for (final modelId in provider.allModelIds)
          AiModelProxyRoute(
            exposedModel: modelId,
            backends: <AiModelProxyBackend>[
              AiModelProxyBackend(providerId: provider.id, modelId: modelId),
            ],
          ),
    ];
    if (routes.isNotEmpty) {
      _settings = _settings.copyWith(routes: routes);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
