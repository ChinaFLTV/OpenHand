import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../app/support/system_proxy.dart';
import '../../app/theme/openhand_theme_preset.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/sensitive_data.dart';
import '../../shared/util/serial_task_queue.dart';
import '../../shared/util/timer_safety.dart';
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
  static const Duration _runtimeResponseNotifyDelay = Duration(
    milliseconds: 40,
  );
  // 设置变更只需保证最终快照落盘，丢弃尚未开始的旧快照即可避免快速操作堆积。
  final LatestTaskQueue _writes = LatestTaskQueue();
  AiModelProxySettings _settings = const AiModelProxySettings();
  AiModelProxyLifecycle _lifecycle = AiModelProxyLifecycle.stopped;
  bool _busy = false;
  Completer<void>? _busyCompleter;
  String? _errorMessage;
  bool _disposed = false;
  int _unknownConnectionRequests = 0;
  int _runtimeRequestSequence = 0;
  int _runtimeInboundBytes = 0;
  int _runtimeOutboundBytes = 0;
  int _runtimeRequestCount = 0;
  int _runtimeErrorCount = 0;
  DateTime? _startedAt;
  final Map<String, _LiveConnectionState> _liveConnections =
      <String, _LiveConnectionState>{};
  final Map<int, String> _runtimeRequests = <int, String>{};
  final math.Random _random = math.Random();
  final Map<String, int> _roundRobinCursors = <String, int>{};
  final Map<String, int> _proxyRoundRobinCursors = <String, int>{};
  final Map<String, _RateLimitWindowState> _rateLimitWindows =
      <String, _RateLimitWindowState>{};
  AiExposureProxyConfiguration Function()? _networkProxyProvider;
  List<AiModelConfig> Function()? _modelsProvider;
  ({ThemeMode themeMode, OpenHandThemePreset preset, Locale locale}) Function()?
  _themeProvider;
  AiModelProxyHttpServer? _httpServer;
  Future<void>? _rebindFuture;
  bool _rebindRequested = false;
  Timer? _runtimeResponseNotifyTimer;

  AiModelProxySettings get settings => _settings;
  AiModelProxyLifecycle get lifecycle => _lifecycle;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;
  int get currentConnections =>
      _liveConnections.length + _unknownConnectionRequests;
  int get unknownLiveConnections => _unknownConnectionRequests;
  int get activeRequests => _runtimeRequests.length;
  int get concurrentRequestLimit => aiModelProxyMaxConcurrentRequests;
  List<AiModelProxyLiveConnection> get liveConnections => [
    for (final entry in _liveConnections.entries)
      AiModelProxyLiveConnection(
        endpoint: entry.key,
        inflight: entry.value.inflight,
        userAgent: entry.value.userAgent,
        firstSeenAt: entry.value.firstSeenAt,
        lastSeenAt: entry.value.lastSeenAt,
      ),
  ];
  int get runtimeInboundBytes => _runtimeInboundBytes;
  int get runtimeOutboundBytes => _runtimeOutboundBytes;
  int get runtimeRequestCount => _runtimeRequestCount;
  int get runtimeErrorCount => _runtimeErrorCount;
  DateTime? get startedAt => _startedAt;
  Duration get uptime {
    final start = _startedAt;
    if (start == null || _lifecycle != AiModelProxyLifecycle.running) {
      return Duration.zero;
    }
    return DateTime.now().difference(start);
  }

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
    if (isLoopbackListenHost(host)) return true;
    if (host == '0.0.0.0' || host == '*' || host == '::') return true;
    return false;
  }

  static bool isLoopbackListenHost(String host) {
    return isLoopbackHost(_normalizeEndpointHost(host));
  }

  /// 复用暴露面扫描服务的代理池配置，保证两个服务选择同一条网络策略。
  void attachNetworkProxyProvider(
    AiExposureProxyConfiguration Function() provider,
  ) {
    _networkProxyProvider = provider;
  }

  AiExposureProxyConfiguration? get networkProxyConfiguration =>
      _networkProxyProvider?.call();

  AiExposureProxyEndpoint? resolveProxyEndpoint({
    String targetHost = '',
    Set<String> excludedUrls = const <String>{},
  }) {
    final configuration = networkProxyConfiguration;
    if (configuration == null ||
        !configuration.enabled ||
        configuration.mode != AiExposureProxyMode.pool) {
      return null;
    }
    final activeEndpoints = configuration.activeEndpoints;
    if (activeEndpoints.isEmpty) return null;
    final excluded = excludedUrls
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    final endpoints = activeEndpoints
        .where((endpoint) => !excluded.contains(endpoint.url))
        .toList(growable: false);
    // 当前请求已明确排除代理时，不能在候选耗尽后重新选回失败节点。
    // 返回 null 让调用方决定是否直连或结束本次重试。
    if (endpoints.isEmpty && excluded.isNotEmpty) return null;
    final candidates = endpoints;
    switch (configuration.strategy) {
      case AiExposureProxyStrategy.fixed:
        return candidates.first;
      case AiExposureProxyStrategy.random:
        return candidates[_random.nextInt(candidates.length)];
      case AiExposureProxyStrategy.stickyHost:
        final key = targetHost.trim().toLowerCase();
        final index = key.isEmpty
            ? 0
            : (key.hashCode & 0x7fffffff) % candidates.length;
        return candidates[index];
      case AiExposureProxyStrategy.roundRobin:
        final key = targetHost.trim().toLowerCase().isEmpty
            ? 'default'
            : targetHost.trim().toLowerCase();
        final index = _proxyRoundRobinCursors.update(
          key,
          (value) => (value + 1) % candidates.length,
          ifAbsent: () => 0,
        );
        return candidates[index];
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

  /// 状态页跟随应用当前主题、明暗与界面语言，而不是写死一套外观。
  void attachThemeProvider(
    ({ThemeMode themeMode, OpenHandThemePreset preset, Locale locale})
    Function()
    provider,
  ) {
    if (_disposed) return;
    _themeProvider = provider;
  }

  ({ThemeMode themeMode, OpenHandThemePreset preset, Locale locale})
  resolveThemeLook() {
    return _themeProvider?.call() ??
        (
          themeMode: ThemeMode.system,
          preset: OpenHandThemePreset.deepSeaBlue,
          locale: openHandAmbientLocale,
        );
  }

  String get publicStatusUrl => aiModelProxyStatusUrl(
    listenHost: _settings.listenHost,
    listenPort: boundPort ?? _settings.listenPort,
  );

  int? get boundPort => _httpServer?.boundPort;

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
    return constantTimeStringEquals(apiKey, expected) ||
        constantTimeStringEquals(authorizationValue, expected);
  }

  /// 只有已启用的暴露模型才会出现在中转服务的模型空间中。
  bool isExposedModelEnabled(String exposedModel) => _settings.routes.any(
    (route) =>
        route.enabled &&
        route.exposedModel.trim().toLowerCase() ==
            exposedModel.trim().toLowerCase(),
  );

  AiModelProxyBackend? resolveBackend(
    String exposedModel, {
    Set<AiModelProxyBackend> excludedBackends = const <AiModelProxyBackend>{},
    String affinityKey = '',
  }) {
    final normalizedModel = exposedModel.trim().toLowerCase();
    final route = _settings.routes
        .where(
          (item) =>
              item.enabled &&
              item.exposedModel.trim().toLowerCase() == normalizedModel,
        )
        .firstOrNull;
    if (route == null) return null;
    final enabled = route.backends
        .where((item) => item.enabled && !excludedBackends.contains(item))
        .toList(growable: false);
    if (enabled.isEmpty) return null;
    return switch (_settings.scheduling) {
      AiModelProxySchedulingStrategy.random =>
        enabled[_random.nextInt(enabled.length)],
      AiModelProxySchedulingStrategy.roundRobin => _nextRoundRobin(
        normalizedModel,
        enabled,
      ),
      AiModelProxySchedulingStrategy.priority => enabled.first,
      AiModelProxySchedulingStrategy.sticky =>
        enabled[affinityKey.trim().isEmpty
            ? 0
            : (affinityKey.trim().toLowerCase().hashCode & 0x7fffffff) %
                  enabled.length],
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
      '/messages',
    ],
    AiModelProxyApiStyle.gemini => const <String>[
      '/v1beta/models',
      '/v1beta/models/{model}',
      '/v1beta/models:generateContent',
      '/v1beta/models:streamGenerateContent?alt=sse',
      '/v1beta/models/{model}:streamGenerateContent?alt=sse',
    ],
  };

  bool consumeRateLimit({
    required int tokens,
    String clientIp = '',
    String userAgent = '',
  }) {
    final now = DateTime.now();
    _pruneRateLimitWindows(now);
    final key = _rateLimitKey(clientIp: clientIp, userAgent: userAgent);
    var window = _rateLimitWindows[key];
    if (window == null) {
      if (_rateLimitWindows.length >= _maxRateLimitBuckets) {
        _evictOldestRateLimitWindow();
      }
      window = _RateLimitWindowState(now);
      _rateLimitWindows[key] = window;
    }
    window.lastUsed = now;
    if (_settings.limitMode == AiModelProxyLimitMode.rpm) {
      if (window.requestCount >= _settings.limitThreshold) return false;
      window.add(now, 0);
      return true;
    }
    // TPM 模式下 continuation 等无显式正文的请求仍会占用上游资源，至少按
    // 一个令牌计入窗口，避免零令牌请求绕过限流。
    final safeTokens = tokens.clamp(1, 1 << 30);
    if (window.tokenTotal + safeTokens > _settings.limitThreshold) return false;
    window.add(now, safeTokens);
    return true;
  }

  static const Duration _rateLimitWindowDuration = Duration(minutes: 1);
  static const int _maxRateLimitBuckets = 256;

  String _rateLimitKey({required String clientIp, required String userAgent}) {
    if (_settings.limitScope == AiModelProxyLimitScope.clientClass) {
      return 'client:${_clientClassKey(userAgent)}';
    }
    var ip = clientIp.trim().toLowerCase();
    final comma = ip.indexOf(',');
    if (comma >= 0) ip = ip.substring(0, comma).trim();
    final normalizedIp = ip.isEmpty
        ? 'unknown-client'
        : ip.substring(0, ip.length > 128 ? 128 : ip.length);
    return 'ip:$normalizedIp';
  }

  static String _clientClassKey(String userAgent) {
    final raw = userAgent.trim().toLowerCase();
    final value = raw.length <= 512 ? raw : raw.substring(0, 512);
    if (value.isEmpty) return 'unknown-client';
    if (value.contains('claude')) return 'claude';
    if (value.contains('edg/') || value.contains('edge/')) return 'edge';
    if (value.contains('opr/') || value.contains('opera')) return 'opera';
    if (value.contains('samsungbrowser')) return 'samsung-browser';
    if (value.contains('chrome/') || value.contains('crios/')) return 'chrome';
    if (value.contains('firefox/') || value.contains('fxios/')) {
      return 'firefox';
    }
    if (value.contains('safari/')) return 'safari';
    if (value.contains('curl/')) return 'curl';
    if (value.contains('python-requests') || value.contains('python/')) {
      return 'python';
    }
    if (value.contains('dart/')) {
      return 'dart';
    }
    if (value.contains('node.js') || value.contains('node/')) {
      return 'node';
    }
    final token = RegExp(
      r'^[a-z0-9][a-z0-9._-]{0,31}',
    ).firstMatch(value)?.group(0);
    return token == null ? 'unknown-client' : 'other:$token';
  }

  void _pruneRateLimitWindows(DateTime now) {
    final expired = <String>[];
    for (final entry in _rateLimitWindows.entries) {
      final window = entry.value;
      window.prune(now, _rateLimitWindowDuration);
      if (window.isEmpty &&
          now.difference(window.lastUsed) >= _rateLimitWindowDuration) {
        expired.add(entry.key);
      }
    }
    for (final key in expired) {
      _rateLimitWindows.remove(key);
    }
  }

  void _evictOldestRateLimitWindow() {
    String? oldestKey;
    DateTime? oldestAt;
    for (final entry in _rateLimitWindows.entries) {
      if (oldestAt == null || entry.value.lastUsed.isBefore(oldestAt)) {
        oldestKey = entry.key;
        oldestAt = entry.value.lastUsed;
      }
    }
    if (oldestKey != null) _rateLimitWindows.remove(oldestKey);
  }

  void _resetRateLimitWindows() => _rateLimitWindows.clear();

  Future<void> load() async {
    final previous = _settings;
    _settings = await _store.load();
    if (previous.limitScope != _settings.limitScope ||
        previous.limitMode != _settings.limitMode ||
        previous.limitThreshold != _settings.limitThreshold) {
      _resetRateLimitWindows();
    }
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
      _validateSecuritySettings(_settings);
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
      _resetRuntimeOccupancy();
      _resetRateLimitWindows();
      _resetRuntimeMetrics();
      await server.start();
      if (!server.isRunning) throw StateError('中转站监听未能保持运行。');
      _startedAt = DateTime.now();
      _settings = _settings.copyWith(enabled: true);
      _lifecycle = AiModelProxyLifecycle.running;
      await _writes.enqueue(() => _store.save(_settings));
    } catch (error) {
      await _httpServer?.stop();
      _startedAt = null;
      _resetRuntimeOccupancy();
      _resetRateLimitWindows();
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
      _startedAt = null;
      _resetRuntimeOccupancy();
      _resetRateLimitWindows();
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
    _rebindRequested = false;
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
    _startedAt = null;
    _resetRuntimeOccupancy();
    _resetRateLimitWindows();
    await _writes.idle;
  }

  /// 保存并立即应用配置；监听端点变更会在当前生命周期操作结束后自动重绑定。
  Future<void> saveSettings(AiModelProxySettings settings) async {
    final previous = _settings;
    final normalized = settings.copyWith();
    _validateSecuritySettings(normalized);
    final listenEndpointChanged =
        previous.listenHost != normalized.listenHost ||
        previous.listenPort != normalized.listenPort;
    _settings = normalized;
    if (previous.limitScope != normalized.limitScope ||
        previous.limitMode != normalized.limitMode ||
        previous.limitThreshold != normalized.limitThreshold) {
      _resetRateLimitWindows();
    }
    _notify();
    try {
      await _writes.enqueue(() => _store.save(normalized));
    } catch (_) {
      if (identical(_settings, normalized)) {
        _settings = previous;
        _resetRateLimitWindows();
        _notify();
      }
      rethrow;
    }
    if (listenEndpointChanged) await _requestServerRebind();
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
    String clientUserAgent = '',
    String proxyMode = '',
    String proxyEndpoint = '',
    String remoteHost = '',
    String remotePort = '',
    String exposedModel = '',
    String requestPath = '',
    int promptTokens = 0,
    int completionTokens = 0,
    int inboundBytes = 0,
    int outboundBytes = 0,
    int statusCode = 0,
    int attempt = 1,
    bool stream = false,
  }) async {
    try {
      // 统计请求可能并发完成。先在内存中基于最新快照累加，再让最新任务落盘，
      // 避免 LatestTaskQueue 丢弃等待任务时覆盖前一个请求的统计。
      _settings = _settings.record(
        success: success,
        tokens: tokens,
        durationMs: durationMs,
        providerId: providerId,
        modelId: modelId,
        apiStyle: apiStyle,
        error: error,
        clientIp: clientIp,
        clientPort: clientPort,
        clientUserAgent: clientUserAgent,
        proxyMode: proxyMode,
        proxyEndpoint: proxyEndpoint,
        remoteHost: remoteHost,
        remotePort: remotePort,
        exposedModel: exposedModel,
        requestPath: requestPath,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        inboundBytes: inboundBytes,
        outboundBytes: outboundBytes,
        statusCode: statusCode,
        attempt: attempt,
        stream: stream,
      );
      _notify();
      await _writes.enqueue(() => _store.save(_settings));
    } catch (error, stack) {
      silentLog('ai_model_proxy_controller', '记录中转站请求统计', error, stack);
    }
  }

  /// 记录已进入服务入口的请求，包含被限流或鉴权拒绝的请求。
  void runtimeRequestObserved({int inboundBytes = 0}) {
    if (_disposed) return;
    _runtimeInboundBytes =
        (_runtimeInboundBytes + inboundBytes.clamp(0, 1 << 31))
            .clamp(0, 1 << 62)
            .toInt();
    _runtimeRequestCount = (_runtimeRequestCount + 1).clamp(0, 1 << 62).toInt();
    _notify();
  }

  /// 记录进入并发执行阶段的请求，供服务运维面板展示实时并发。
  int? runtimeRequestStarted({String? connectionKey, String? userAgent}) {
    if (_disposed) return null;
    final requestId = ++_runtimeRequestSequence;
    final key = connectionKey?.trim() ?? '';
    _runtimeRequests[requestId] = key;
    if (key.isEmpty) {
      _unknownConnectionRequests = (_unknownConnectionRequests + 1)
          .clamp(0, 1 << 30)
          .toInt();
    } else {
      final now = DateTime.now();
      final agent = userAgent?.trim() ?? '';
      final existing = _liveConnections[key];
      if (existing == null) {
        _liveConnections[key] = _LiveConnectionState(
          inflight: 1,
          userAgent: agent,
          firstSeenAt: now,
          lastSeenAt: now,
        );
      } else {
        existing.inflight = (existing.inflight + 1).clamp(0, 1 << 30).toInt();
        existing.lastSeenAt = now;
        if (agent.isNotEmpty) existing.userAgent = agent;
      }
    }
    _notify();
    return requestId;
  }

  /// 记录响应载荷大小，避免把展示层的流量指标写死为零。
  void runtimeResponseWritten({int outboundBytes = 0, int statusCode = 200}) {
    if (_disposed) return;
    _runtimeOutboundBytes =
        (_runtimeOutboundBytes + outboundBytes.clamp(0, 1 << 31))
            .clamp(0, 1 << 62)
            .toInt();
    if (statusCode >= 400) {
      _runtimeErrorCount = (_runtimeErrorCount + 1).clamp(0, 1 << 62).toInt();
    }
    _runtimeResponseNotifyTimer ??= startSafeTimer(
      _runtimeResponseNotifyDelay,
      () {
        _runtimeResponseNotifyTimer = null;
        _notify();
      },
    );
  }

  void runtimeRequestFinished(int? requestId) {
    if (_disposed) return;
    final key = requestId == null ? null : _runtimeRequests.remove(requestId);
    if (key == null) return;
    if (key.isEmpty) {
      _unknownConnectionRequests = (_unknownConnectionRequests - 1)
          .clamp(0, 1 << 30)
          .toInt();
    } else {
      final existing = _liveConnections[key];
      if (existing == null || existing.inflight <= 1) {
        _liveConnections.remove(key);
      } else {
        existing.inflight -= 1;
      }
    }
    _notify();
  }

  void runtimeServerStoppedUnexpectedly(Object? error) {
    if (_disposed ||
        (_lifecycle != AiModelProxyLifecycle.starting &&
            _lifecycle != AiModelProxyLifecycle.running)) {
      return;
    }
    _startedAt = null;
    _resetRuntimeOccupancy();
    _resetRateLimitWindows();
    final stoppedSettings = _settings.copyWith(enabled: false);
    _settings = stoppedSettings;
    _lifecycle = AiModelProxyLifecycle.error;
    _errorMessage = error == null ? '中转站监听已意外终止。' : '中转站监听异常：$error';
    _notify();
    unawaited(
      _writes
          .enqueue(() => _store.save(stoppedSettings))
          .then<void>(
            (_) {},
            onError: (Object persistError, StackTrace stack) {
              silentLog(
                'ai_model_proxy_controller',
                '保存中转站意外停止状态',
                persistError,
                stack,
              );
            },
          ),
    );
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notify();
  }

  void _notify() {
    _runtimeResponseNotifyTimer?.cancel();
    _runtimeResponseNotifyTimer = null;
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
    _runtimeResponseNotifyTimer?.cancel();
    _runtimeResponseNotifyTimer = null;
    _startedAt = null;
    _resetRuntimeOccupancy();
    _resetRateLimitWindows();
    unawaited(_httpServer?.dispose());
    _httpServer = null;
    super.dispose();
  }

  Future<void> _requestServerRebind() {
    _rebindRequested = true;
    final existing = _rebindFuture;
    if (existing != null) return existing;
    final future = _drainServerRebindRequests();
    _rebindFuture = future;
    unawaited(
      future
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(() {
            if (identical(_rebindFuture, future)) _rebindFuture = null;
          }),
    );
    return future;
  }

  Future<void> _drainServerRebindRequests() async {
    while (_rebindRequested) {
      _rebindRequested = false;
      while (_busy) {
        final busy = _busyCompleter?.future;
        if (busy == null) break;
        await busy;
      }
      if (_disposed || _lifecycle != AiModelProxyLifecycle.running) continue;
      await _rebindServer();
    }
  }

  Future<void> _rebindServer() async {
    if (_lifecycle != AiModelProxyLifecycle.running) return;
    _beginBusy();
    _lifecycle = AiModelProxyLifecycle.starting;
    _errorMessage = null;
    _notify();
    try {
      final server = _httpServer;
      if (server == null) throw StateError('中转站 HTTP 服务未初始化。');
      await server.stop();
      _resetRuntimeOccupancy();
      _resetRateLimitWindows();
      await server.start();
      if (!server.isRunning) throw StateError('中转站监听未能保持运行。');
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

  void _resetRuntimeOccupancy() {
    _runtimeRequests.clear();
    _unknownConnectionRequests = 0;
    _liveConnections.clear();
  }

  void _resetRuntimeMetrics() {
    _runtimeResponseNotifyTimer?.cancel();
    _runtimeResponseNotifyTimer = null;
    _runtimeInboundBytes = 0;
    _runtimeOutboundBytes = 0;
    _runtimeRequestCount = 0;
    _runtimeErrorCount = 0;
  }

  static void _validateSecuritySettings(AiModelProxySettings settings) {
    if (settings.requireAuthentication && settings.apiKey.trim().isEmpty) {
      throw StateError('启用 API 鉴权后必须配置密钥。');
    }
    if (!settings.requireAuthentication &&
        !isLoopbackListenHost(settings.listenHost)) {
      throw StateError('监听非本机回环地址时必须启用 API 鉴权。');
    }
  }
}

class _LiveConnectionState {
  _LiveConnectionState({
    required this.inflight,
    required this.userAgent,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  int inflight;
  String userAgent;
  DateTime firstSeenAt;
  DateTime lastSeenAt;
}

class _RateLimitWindowState {
  _RateLimitWindowState(this.lastUsed);

  final List<DateTime> timestamps = <DateTime>[];
  final List<int> tokenCounts = <int>[];
  DateTime lastUsed;
  int offset = 0;
  int tokenTotal = 0;

  int get requestCount => timestamps.length - offset;
  bool get isEmpty => offset >= timestamps.length;

  void add(DateTime timestamp, int tokens) {
    timestamps.add(timestamp);
    tokenCounts.add(tokens);
    tokenTotal += tokens;
  }

  void prune(DateTime now, Duration duration) {
    while (offset < timestamps.length &&
        now.difference(timestamps[offset]) >= duration) {
      tokenTotal -= tokenCounts[offset];
      offset += 1;
    }
    if (tokenTotal < 0) tokenTotal = 0;
    if (offset > 128 && offset * 2 >= timestamps.length) {
      timestamps.removeRange(0, offset);
      tokenCounts.removeRange(0, offset);
      offset = 0;
    }
  }
}
