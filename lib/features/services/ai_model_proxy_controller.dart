import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../app/support/silent_log.dart';
import '../../shared/util/serial_task_queue.dart';
import '../ai/index.dart';
import 'data/ai_model_proxy_store.dart';
import 'model/ai_exposure_models.dart';
import 'model/ai_model_proxy_models.dart';
import 'service/ai_model_proxy_http_server.dart';

enum AiModelProxyLifecycle { stopped, starting, running, stopping, error }

class AiModelProxyController extends ChangeNotifier {
  AiModelProxyController({AiModelProxyStore? store})
    : _store = store ?? AiModelProxyStore();

  final AiModelProxyStore _store;
  // 设置变更只需保证最终快照落盘，丢弃尚未开始的旧快照即可避免快速操作堆积。
  final LatestTaskQueue _writes = LatestTaskQueue();
  AiModelProxySettings _settings = const AiModelProxySettings();
  AiModelProxyLifecycle _lifecycle = AiModelProxyLifecycle.stopped;
  bool _busy = false;
  Completer<void>? _busyCompleter;
  String? _errorMessage;
  bool _disposed = false;
  final Map<String, int> _roundRobinCursors = <String, int>{};
  final Map<String, int> _proxyRoundRobinCursors = <String, int>{};
  final List<DateTime> _rateWindow = <DateTime>[];
  final List<int> _rateWindowTokenCounts = <int>[];
  int _rateWindowTokens = 0;
  AiExposureProxyConfiguration Function()? _networkProxyProvider;
  List<AiModelConfig> Function()? _modelsProvider;
  AiModelProxyHttpServer? _httpServer;

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

  /// 接入应用当前的模型配置。使用回调避免控制器复制一份可能过期的列表。
  void attachModelsProvider(List<AiModelConfig> Function() provider) {
    if (_disposed) return;
    _modelsProvider = provider;
    if (_httpServer != null) return;
    _httpServer = AiModelProxyHttpServer(
      controller: this,
      modelsProvider: () => _modelsProvider?.call() ?? const <AiModelConfig>[],
    );
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
          (entry) =>
              entry.key.toLowerCase() == 'x-api-key' ||
              entry.key.toLowerCase() == 'x-goog-api-key' ||
              entry.key.toLowerCase() == 'api-key',
          orElse: () => const MapEntry<String, String>('', ''),
        )
        .value
        .trim();
    final authorizationValue = authorization.replaceFirst(
      RegExp(r'^bearer\s+', caseSensitive: false),
      '',
    );
    return apiKey == expected || authorizationValue == expected;
  }

  /// 只有已启用的暴露模型才会出现在中转服务的模型空间中。
  bool isExposedModelEnabled(String exposedModel) => _settings.routes.any(
    (route) => route.enabled && route.exposedModel == exposedModel.trim(),
  );

  AiModelProxyBackend? resolveBackend(String exposedModel) {
    final route = _settings.routes
        .where(
          (item) => item.enabled && item.exposedModel == exposedModel.trim(),
        )
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
      '/v1/models/{model}',
      '/v1/chat/completions',
    ],
    AiModelProxyApiStyle.openAiResponses => const <String>[
      '/v1/models',
      '/v1/models/{model}',
      '/v1/responses',
    ],
    AiModelProxyApiStyle.claude => const <String>[
      '/v1/models',
      '/v1/models/{model}',
      '/v1/messages',
    ],
    AiModelProxyApiStyle.gemini => const <String>[
      '/v1beta/models',
      '/v1beta/models/{model}',
      '/v1beta/models:generateContent',
      '/v1beta/models:streamGenerateContent?alt=sse',
      '/v1beta/models/{model}:streamGenerateContent?alt=sse',
    ],
  };

  bool consumeRateLimit({required int tokens}) {
    final now = DateTime.now();
    for (var index = _rateWindow.length - 1; index >= 0; index -= 1) {
      if (now.difference(_rateWindow[index]) < const Duration(minutes: 1)) {
        continue;
      }
      _rateWindowTokens -= _rateWindowTokenCounts[index];
      _rateWindow.removeAt(index);
      _rateWindowTokenCounts.removeAt(index);
    }
    if (_rateWindowTokens < 0) _rateWindowTokens = 0;
    if (_settings.limitMode == AiModelProxyLimitMode.rpm) {
      if (_rateWindow.length >= _settings.limitThreshold) return false;
      _rateWindow.add(now);
      _rateWindowTokenCounts.add(0);
      return true;
    }
    final safeTokens = tokens.clamp(0, 1 << 30);
    if (_rateWindowTokens + safeTokens > _settings.limitThreshold) return false;
    _rateWindow.add(now);
    _rateWindowTokenCounts.add(safeTokens);
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
    _beginBusy();
    _lifecycle = AiModelProxyLifecycle.starting;
    _errorMessage = null;
    _notify();
    try {
      final enabledRoutes = _settings.routes
          .where((route) => route.enabled)
          .toList(growable: false);
      if (enabledRoutes.isEmpty) {
        throw StateError('至少需要配置一个对外暴露模型。');
      }
      if (enabledRoutes.any(
        (route) => !route.backends.any((item) => item.enabled),
      )) {
        throw StateError('每个对外暴露模型至少需要一个启用的后备模型。');
      }
      final server = _httpServer ??= AiModelProxyHttpServer(
        controller: this,
        modelsProvider: () =>
            _modelsProvider?.call() ?? const <AiModelConfig>[],
      );
      await server.start();
      _settings = _settings.copyWith(enabled: true);
      await _writes.enqueue(() => _store.save(_settings));
      _lifecycle = AiModelProxyLifecycle.running;
    } catch (error) {
      await _httpServer?.stop();
      _settings = _settings.copyWith(enabled: false);
      try {
        await _writes.enqueue(() => _store.save(_settings));
      } catch (_) {
        // 监听失败时保留原始绑定错误，持久化失败不再覆盖它。
      }
      _lifecycle = AiModelProxyLifecycle.error;
      _errorMessage = '$error';
    } finally {
      _endBusy();
      _notify();
    }
  }

  Future<void> stop() async {
    if (_busy || _lifecycle == AiModelProxyLifecycle.stopped) return;
    _beginBusy();
    _lifecycle = AiModelProxyLifecycle.stopping;
    _notify();
    try {
      await _httpServer?.stop();
      _settings = _settings.copyWith(enabled: false);
      await _writes.enqueue(() => _store.save(_settings));
      _lifecycle = AiModelProxyLifecycle.stopped;
    } catch (error) {
      _lifecycle = AiModelProxyLifecycle.error;
      _errorMessage = '$error';
    } finally {
      _endBusy();
      _notify();
    }
  }

  /// 进程退出前释放监听端口和中转请求客户端。
  Future<void> shutdown() async {
    if (_disposed) return;
    final busy = _busyCompleter?.future;
    if (busy != null) {
      try {
        await busy.timeout(const Duration(seconds: 15));
      } on Object {
        // 启停操作已超过退出预算时继续强制关闭句柄。
      }
    }
    await _httpServer?.dispose();
    _httpServer = null;
    _lifecycle = AiModelProxyLifecycle.stopped;
    await _writes.idle;
  }

  Future<void> saveSettings(AiModelProxySettings settings) async {
    final previous = _settings;
    final normalized = settings.copyWith();
    _settings = normalized;
    _notify();
    await _writes.enqueue(() => _store.save(normalized));
    if (_lifecycle == AiModelProxyLifecycle.running &&
        (previous.listenHost != normalized.listenHost ||
            previous.listenPort != normalized.listenPort)) {
      await _rebindServer();
    }
  }

  Future<void> saveRoutes(List<AiModelProxyRoute> routes) =>
      saveSettings(_settings.copyWith(routes: routes));

  /// 构建 OpenAI 兼容的 `/v1/models` 元数据，不暴露提供商密钥和地址。
  List<Map<String, Object?>> buildModelsMetadata() {
    return List<Map<String, Object?>>.unmodifiable(
      _settings.routes.where((route) => route.enabled).map(_buildModelMetadata),
    );
  }

  /// 构建可直接作为 `/v1/models` 响应体的对象。
  Map<String, Object?> buildModelsResponse() => <String, Object?>{
    'object': 'list',
    'data': buildModelsMetadata(),
  };

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
  }) async {
    try {
      await saveSettings(
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
    } catch (error, stack) {
      silentLog('ai_model_proxy_controller', '记录中转站请求统计', error, stack);
    }
  }

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

  Map<String, Object?> _buildModelMetadata(AiModelProxyRoute route) {
    final profile = route.profile;
    final metadata = <String, Object?>{
      'id': route.exposedModel,
      'object': 'model',
      'owned_by': 'OpenHand',
      'display_name': profile.displayName ?? route.exposedModel,
      if (profile.description != null) 'description': profile.description,
      if (profile.created != null) 'created': profile.created,
      if (profile.isMultimodal != null) 'is_multimodal': profile.isMultimodal,
      if (profile.supportedModalities.isNotEmpty)
        'supported_modalities': profile.supportedModalities
            .map((item) => item.storageValue)
            .toList(growable: false),
      if (profile.maxContextLength != null)
        'context_length': profile.maxContextLength,
      if (profile.maxOutputLength != null)
        'max_output_tokens': profile.maxOutputLength,
      if (profile.maxThinkingLength != null)
        'max_thinking_tokens': profile.maxThinkingLength,
      if (profile.thinkingEnabled != null)
        'thinking_enabled': profile.thinkingEnabled,
      if (profile.reasoningEffort != null)
        'reasoning_effort': profile.reasoningEffort,
      if (profile.capabilities.isNotEmpty)
        'capabilities': profile.capabilities
            .map((item) => item.storageValue)
            .toList(growable: false),
      if (profile.supportsAttachments != null)
        'supports_attachments': profile.supportsAttachments,
      if (profile.supportedParameters.isNotEmpty)
        'supported_parameters': profile.supportedParameters,
      if (profile.defaultParameters.isNotEmpty)
        'default_parameters': profile.defaultParameters,
      if (profile.inputUsdPer1M != null ||
          profile.outputUsdPer1M != null ||
          profile.cacheReadUsdPer1M != null ||
          profile.cacheWriteUsdPer1M != null)
        'pricing': <String, Object?>{
          if (profile.inputUsdPer1M != null)
            'input_usd_per_1m': profile.inputUsdPer1M,
          if (profile.outputUsdPer1M != null)
            'output_usd_per_1m': profile.outputUsdPer1M,
          if (profile.cacheReadUsdPer1M != null)
            'cache_read_usd_per_1m': profile.cacheReadUsdPer1M,
          if (profile.cacheWriteUsdPer1M != null)
            'cache_write_usd_per_1m': profile.cacheWriteUsdPer1M,
        },
      if (profile.canonicalSlug != null)
        'canonical_slug': profile.canonicalSlug,
      if (profile.huggingFaceId != null)
        'hugging_face_id': profile.huggingFaceId,
      if (profile.knowledgeCutoff != null)
        'knowledge_cutoff': profile.knowledgeCutoff,
      if (profile.expirationDate != null)
        'expiration_date': profile.expirationDate,
      if (profile.links != null && !profile.links!.isEmpty)
        'links': profile.links!.toJson(),
      'metadata': profile.toJson(),
    };
    return metadata;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_httpServer?.dispose());
    _httpServer = null;
    super.dispose();
  }

  Future<void> _rebindServer() async {
    if (_busy || _lifecycle != AiModelProxyLifecycle.running) return;
    _beginBusy();
    _lifecycle = AiModelProxyLifecycle.starting;
    _errorMessage = null;
    _notify();
    try {
      final server = _httpServer;
      if (server == null) throw StateError('中转站 HTTP 服务未初始化。');
      await server.stop();
      await server.start();
      _lifecycle = AiModelProxyLifecycle.running;
    } catch (error) {
      _lifecycle = AiModelProxyLifecycle.error;
      _errorMessage = '重新绑定中转站端口失败：$error';
      _settings = _settings.copyWith(enabled: false);
      try {
        await _writes.enqueue(() => _store.save(_settings));
      } catch (_) {
        // 绑定失败时持久化失败不覆盖原始错误。
      }
    } finally {
      _endBusy();
      _notify();
    }
  }

  void _beginBusy() {
    _busy = true;
    _busyCompleter = Completer<void>();
  }

  void _endBusy() {
    _busy = false;
    final completer = _busyCompleter;
    _busyCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }
}
