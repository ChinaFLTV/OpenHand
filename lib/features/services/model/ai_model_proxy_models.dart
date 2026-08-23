import '../../../shared/util/input_value_parsing.dart';
import '../../ai/index.dart';

const String aiModelProxyDefaultListenHost = '127.0.0.1';
const int aiModelProxyDefaultListenPort = 6699;
const int aiModelProxyMinListenPort = 1;
const int aiModelProxyMaxListenPort = 65535;
const String aiModelProxyStatusPath = '/status.html';
const String aiModelProxyStatusAliasPath = '/status';
const String aiModelProxyStatusMode = 'status';
const String aiModelProxyPoolMode = 'pool';
const String aiModelProxySystemMode = 'system';
const String aiModelProxyDirectMode = 'direct';
const String aiModelProxyStatusModelId = 'status.html';
const String aiModelProxyLogoAsset = 'assets/branding/openhand_logo.png';
const String aiModelProxyLogoPath = '/openhand_logo.png';
const String aiModelProxyFaviconPath = '/favicon.ico';
const int aiModelProxyStatusHistoryDays = 90;
const int aiModelProxySlowLatencyMs = 3000;
const double aiModelProxyHealthHealthyRate = 0.99;
const double aiModelProxyHealthDegradedRate = 0.90;
const int aiModelProxyDailyModelCap = 64;

bool isAiModelProxyStatusPath(String path) {
  final value = path.trim();
  return value == aiModelProxyStatusPath ||
      value == aiModelProxyStatusAliasPath;
}

bool isAiModelProxyBrandingPath(String path) {
  final value = path.trim();
  return value == aiModelProxyLogoPath || value == aiModelProxyFaviconPath;
}

bool isAiModelProxyStatusRecord(AiModelProxyRequestRecord record) {
  if (record.proxyMode.trim().toLowerCase() == aiModelProxyStatusMode) {
    return true;
  }
  if (record.modelId.trim().toLowerCase() == aiModelProxyStatusModelId) {
    return true;
  }
  return isAiModelProxyStatusPath(record.requestPath);
}

typedef AiModelProxyLabelText =
    String Function({required String zh, required String en});

/// Maps stored dispatch-mode ids (`pool` / `system` / `direct` / `status`) to UI copy.
String aiModelProxyDispatchModeLabel(String mode, AiModelProxyLabelText text) {
  return switch (mode.trim().toLowerCase()) {
    aiModelProxyPoolMode => text(zh: '代理池', en: 'Proxy pool'),
    aiModelProxySystemMode => text(zh: '系统代理', en: 'System proxy'),
    aiModelProxyDirectMode => text(zh: '直连', en: 'Direct'),
    aiModelProxyStatusMode => text(zh: '状态页', en: 'Status page'),
    _ => text(zh: '未知模式', en: 'Unknown mode'),
  };
}

/// Maps stored API-style ids to display names; status probes are not a protocol.
String aiModelProxyApiStyleLabel(String raw, AiModelProxyLabelText text) {
  final id = raw.trim();
  if (id.isEmpty) return '';
  final normalized = id.toLowerCase();
  if (normalized == aiModelProxyStatusMode) {
    return text(zh: '状态页', en: 'Status page');
  }
  for (final style in AiModelProxyApiStyle.values) {
    if (style.id.toLowerCase() == normalized) return style.label;
  }
  return text(zh: '未知协议', en: 'Unknown protocol');
}

String aiModelProxyDayKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String aiModelProxyStatusUrl({
  required String listenHost,
  required int listenPort,
}) {
  var host = listenHost.trim();
  if (host.isEmpty ||
      host == '0.0.0.0' ||
      host == '*' ||
      host == '::' ||
      host == '[::]') {
    host = '127.0.0.1';
  }
  if (host.contains(':') && !host.startsWith('[')) {
    host = '[$host]';
  }
  return 'http://$host:$listenPort$aiModelProxyStatusPath';
}

enum AiModelProxyHealth { idle, healthy, degraded, outage }

AiModelProxyHealth classifyAiModelProxyHealth({
  required int requests,
  required int successes,
  int slowCount = 0,
  int p95Ms = 0,
}) {
  if (requests <= 0) return AiModelProxyHealth.idle;
  final rate = successes / requests;
  if (rate < aiModelProxyHealthDegradedRate) {
    return AiModelProxyHealth.outage;
  }
  if (rate < aiModelProxyHealthHealthyRate ||
      p95Ms >= aiModelProxySlowLatencyMs ||
      slowCount / requests >= 0.2) {
    return AiModelProxyHealth.degraded;
  }
  return AiModelProxyHealth.healthy;
}

class AiModelProxyDailyComponent {
  const AiModelProxyDailyComponent({
    this.requests = 0,
    this.successes = 0,
    this.durationMs = 0,
    this.slowCount = 0,
  });

  factory AiModelProxyDailyComponent.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AiModelProxyDailyComponent(
      requests: _proxyBoundedInt(json['requests'], 0, 0, 1 << 31),
      successes: _proxyBoundedInt(json['successes'], 0, 0, 1 << 31),
      durationMs: _proxyBoundedInt(json['duration_ms'], 0, 0, 1 << 52),
      slowCount: _proxyBoundedInt(json['slow'], 0, 0, 1 << 31),
    );
  }

  final int requests;
  final int successes;
  final int durationMs;
  final int slowCount;

  int get failures => requests <= successes ? 0 : requests - successes;
  double get successRate =>
      requests <= 0 ? 0 : (successes / requests).clamp(0.0, 1.0).toDouble();
  int get avgMs => requests <= 0 ? 0 : (durationMs / requests).round();
  AiModelProxyHealth get health => classifyAiModelProxyHealth(
    requests: requests,
    successes: successes,
    slowCount: slowCount,
    p95Ms: avgMs >= aiModelProxySlowLatencyMs ? avgMs : 0,
  );

  AiModelProxyDailyComponent add({
    required bool success,
    required int durationMs,
  }) {
    final safeMs = durationMs.clamp(0, 1 << 30);
    return AiModelProxyDailyComponent(
      requests: requests + 1,
      successes: successes + (success ? 1 : 0),
      durationMs: this.durationMs + safeMs,
      slowCount: slowCount + (safeMs >= aiModelProxySlowLatencyMs ? 1 : 0),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'requests': requests,
    'successes': successes,
    if (durationMs > 0) 'duration_ms': durationMs,
    if (slowCount > 0) 'slow': slowCount,
  };
}

class AiModelProxyDailyHealth {
  const AiModelProxyDailyHealth({
    required this.day,
    this.total = const AiModelProxyDailyComponent(),
    this.statusPage = const AiModelProxyDailyComponent(),
    this.models = const <String, AiModelProxyDailyComponent>{},
  });

  factory AiModelProxyDailyHealth.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    final modelsRaw = json['models'];
    final models = <String, AiModelProxyDailyComponent>{};
    if (modelsRaw is Map) {
      for (final entry in modelsRaw.entries) {
        final key = '${entry.key}'.trim();
        if (key.isEmpty) continue;
        models[key] = AiModelProxyDailyComponent.fromJson(entry.value);
        if (models.length >= aiModelProxyDailyModelCap) break;
      }
    }
    return AiModelProxyDailyHealth(
      day: '${json['day'] ?? ''}'.trim(),
      total: AiModelProxyDailyComponent.fromJson(json['total']),
      statusPage: AiModelProxyDailyComponent.fromJson(json['status_page']),
      models: models,
    );
  }

  final String day;
  final AiModelProxyDailyComponent total;
  final AiModelProxyDailyComponent statusPage;
  final Map<String, AiModelProxyDailyComponent> models;

  AiModelProxyDailyHealth add(AiModelProxyRequestRecord record) {
    final nextTotal = total.add(
      success: record.success,
      durationMs: record.durationMs,
    );
    if (isAiModelProxyStatusRecord(record)) {
      return AiModelProxyDailyHealth(
        day: day,
        total: nextTotal,
        statusPage: statusPage.add(
          success: record.success,
          durationMs: record.durationMs,
        ),
        models: models,
      );
    }
    final key = record.exposedModel.trim().isNotEmpty
        ? record.exposedModel.trim()
        : record.modelId.trim();
    if (key.isEmpty) {
      return AiModelProxyDailyHealth(
        day: day,
        total: nextTotal,
        statusPage: statusPage,
        models: models,
      );
    }
    final nextModels = Map<String, AiModelProxyDailyComponent>.from(models);
    final current = nextModels[key] ?? const AiModelProxyDailyComponent();
    if (!nextModels.containsKey(key) &&
        nextModels.length >= aiModelProxyDailyModelCap) {
      return AiModelProxyDailyHealth(
        day: day,
        total: nextTotal,
        statusPage: statusPage,
        models: models,
      );
    }
    nextModels[key] = current.add(
      success: record.success,
      durationMs: record.durationMs,
    );
    return AiModelProxyDailyHealth(
      day: day,
      total: nextTotal,
      statusPage: statusPage,
      models: nextModels,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'day': day,
    'total': total.toJson(),
    if (statusPage.requests > 0) 'status_page': statusPage.toJson(),
    if (models.isNotEmpty)
      'models': <String, Object?>{
        for (final entry in models.entries) entry.key: entry.value.toJson(),
      },
  };
}

List<AiModelProxyDailyHealth> _advanceDailyHealth(
  List<AiModelProxyDailyHealth> current,
  AiModelProxyRequestRecord record,
) {
  final day = aiModelProxyDayKey(record.startedAt);
  if (day.isEmpty) return current;
  final next = [...current];
  final index = next.indexWhere((item) => item.day == day);
  if (index >= 0) {
    next[index] = next[index].add(record);
  } else {
    next.add(AiModelProxyDailyHealth(day: day).add(record));
  }
  final cutoff = record.startedAt.toLocal().subtract(
    const Duration(days: aiModelProxyStatusHistoryDays),
  );
  final cutoffKey = aiModelProxyDayKey(cutoff);
  next.removeWhere(
    (item) => item.day.isEmpty || item.day.compareTo(cutoffKey) < 0,
  );
  if (next.length > aiModelProxyStatusHistoryDays) {
    next.removeRange(0, next.length - aiModelProxyStatusHistoryDays);
  }
  return next;
}

int _proxyBoundedInt(Object? value, int fallback, int min, int max) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return (parsed ?? fallback).clamp(min, max).toInt();
}

String _proxyModelKey(String value) => value.trim().toLowerCase();

List<AiModelProxyBackend> _normalizeProxyBackends(
  Iterable<AiModelProxyBackend> backends,
) {
  final result = <AiModelProxyBackend>[];
  final keys = <String>{};
  for (final backend in backends) {
    final providerId = backend.providerId.trim();
    final modelId = backend.modelId.trim();
    if (providerId.isEmpty || modelId.isEmpty) continue;
    final key = '${_proxyModelKey(providerId)}\u0000${_proxyModelKey(modelId)}';
    if (keys.add(key)) {
      result.add(
        providerId == backend.providerId && modelId == backend.modelId
            ? backend
            : AiModelProxyBackend(
                providerId: providerId,
                modelId: modelId,
                enabled: backend.enabled,
              ),
      );
    }
  }
  return result;
}

List<AiModelProxyRoute> _normalizeProxyRoutes(
  Iterable<AiModelProxyRoute> routes,
) {
  final result = <AiModelProxyRoute>[];
  final indexes = <String, int>{};
  for (final route in routes) {
    final exposedModel = route.exposedModel.trim();
    final key = _proxyModelKey(exposedModel);
    if (key.isEmpty) continue;
    final normalized = route.copyWith(exposedModel: exposedModel);
    final existingIndex = indexes[key];
    if (existingIndex == null) {
      indexes[key] = result.length;
      result.add(normalized);
      continue;
    }
    final existing = result[existingIndex];
    result[existingIndex] = existing.copyWith(
      backends: _normalizeProxyBackends([
        ...existing.backends,
        ...normalized.backends,
      ]),
    );
  }
  return result;
}

enum AiModelProxyApiStyle {
  openAiChatCompletions('openai_chat_completions', 'OpenAI Chat Completions'),
  openAiResponses('openai_responses', 'OpenAI Responses'),
  claude('claude', 'Claude'),
  gemini('gemini', 'Gemini');

  const AiModelProxyApiStyle(this.id, this.label);
  final String id;
  final String label;

  static AiModelProxyApiStyle fromId(Object? value) => enumByStorageValueOr(
    values,
    value,
    (item) => item.id,
    fallback: openAiResponses,
  );
}

enum AiModelProxyLimitMode {
  rpm('rpm', 'RPM'),
  tpm('tpm', 'TPM');

  const AiModelProxyLimitMode(this.id, this.label);
  final String id;
  final String label;

  static AiModelProxyLimitMode fromId(Object? value) =>
      enumByStorageValueOr(values, value, (item) => item.id, fallback: rpm);
}

enum AiModelProxyLimitScope {
  perIp('per_ip', '单个IP'),
  clientClass('client_class', '同一类客户端');

  const AiModelProxyLimitScope(this.id, this.label);
  final String id;
  final String label;

  static AiModelProxyLimitScope fromId(Object? value) =>
      enumByStorageValueOr(values, value, (item) => item.id, fallback: perIp);
}

enum AiModelProxyRetryPolicy {
  failFast('fail_fast', '立即失败'),
  retrySame('retry_same', '重试后失败'),
  retryAndFailover('retry_and_failover', '重试后接力');

  const AiModelProxyRetryPolicy(this.id, this.label);
  final String id;
  final String label;

  static AiModelProxyRetryPolicy fromId(Object? value) => enumByStorageValueOr(
    values,
    value,
    (item) => item.id,
    fallback: failFast,
  );
}

enum AiModelProxySchedulingStrategy {
  roundRobin('round_robin', '轮询调度'),
  random('random', '随机调度'),
  priority('priority', '优先级调度'),
  conservative('conservative', '保守调度'),
  sticky('sticky', '粘性调度');

  const AiModelProxySchedulingStrategy(this.id, this.label);
  final String id;
  final String label;

  static AiModelProxySchedulingStrategy fromId(Object? value) =>
      enumByStorageValueOr(
        values,
        value,
        (item) => item.id,
        fallback: roundRobin,
      );
}

class AiModelProxyBackend {
  const AiModelProxyBackend({
    required this.providerId,
    required this.modelId,
    this.enabled = true,
  });

  factory AiModelProxyBackend.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AiModelProxyBackend(
      providerId: '${json['provider_id'] ?? ''}'.trim(),
      modelId: '${json['model_id'] ?? ''}'.trim(),
      enabled: boolFromValue(json['enabled'], defaultValue: true),
    );
  }

  final String providerId;
  final String modelId;
  final bool enabled;

  AiModelProxyBackend copyWith({bool? enabled}) => AiModelProxyBackend(
    providerId: providerId,
    modelId: modelId,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'provider_id': providerId,
    'model_id': modelId,
    'enabled': enabled,
  };
}

class AiModelProxyRequestRecord {
  const AiModelProxyRequestRecord({
    required this.id,
    required this.startedAt,
    required this.providerId,
    required this.modelId,
    required this.apiStyle,
    required this.tokens,
    required this.durationMs,
    required this.success,
    this.error,
    this.clientIp = '',
    this.clientPort = '',
    this.clientUserAgent = '',
    this.proxyMode = '',
    this.proxyEndpoint = '',
    this.remoteHost = '',
    this.remotePort = '',
    this.exposedModel = '',
    this.requestPath = '',
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.inboundBytes = 0,
    this.outboundBytes = 0,
    this.statusCode = 0,
    this.attempt = 1,
    this.stream = false,
  });

  factory AiModelProxyRequestRecord.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AiModelProxyRequestRecord(
      id: '${json['id'] ?? ''}',
      startedAt:
          DateTime.tryParse('${json['started_at'] ?? ''}')?.toLocal() ??
          DateTime.now(),
      providerId: '${json['provider_id'] ?? ''}',
      modelId: '${json['model_id'] ?? ''}',
      apiStyle: '${json['api_style'] ?? ''}',
      tokens: _proxyBoundedInt(json['tokens'], 0, 0, 1 << 31),
      durationMs: _proxyBoundedInt(json['duration_ms'], 0, 0, 1 << 31),
      success: boolFromValue(json['success']),
      error: nullIfBlank('${json['error'] ?? ''}'),
      clientIp: '${json['client_ip'] ?? ''}',
      clientPort: '${json['client_port'] ?? ''}',
      clientUserAgent: '${json['client_user_agent'] ?? ''}',
      proxyMode: '${json['proxy_mode'] ?? ''}',
      proxyEndpoint: '${json['proxy_endpoint'] ?? ''}',
      remoteHost: '${json['remote_host'] ?? ''}',
      remotePort: '${json['remote_port'] ?? ''}',
      exposedModel: '${json['exposed_model'] ?? ''}',
      requestPath: '${json['request_path'] ?? ''}',
      promptTokens: _proxyBoundedInt(json['prompt_tokens'], 0, 0, 1 << 31),
      completionTokens: _proxyBoundedInt(
        json['completion_tokens'],
        0,
        0,
        1 << 31,
      ),
      inboundBytes: _proxyBoundedInt(json['inbound_bytes'], 0, 0, 1 << 31),
      outboundBytes: _proxyBoundedInt(json['outbound_bytes'], 0, 0, 1 << 31),
      statusCode: _proxyBoundedInt(json['status_code'], 0, 0, 599),
      attempt: _proxyBoundedInt(json['attempt'], 1, 1, 32),
      stream: boolFromValue(json['stream']),
    );
  }

  final String id;
  final DateTime startedAt;
  final String providerId;
  final String modelId;
  final String apiStyle;
  final int tokens;
  final int durationMs;
  final bool success;
  final String? error;
  final String clientIp;
  final String clientPort;
  final String clientUserAgent;
  final String proxyMode;
  final String proxyEndpoint;
  final String remoteHost;
  final String remotePort;
  final String exposedModel;
  final String requestPath;
  final int promptTokens;
  final int completionTokens;
  final int inboundBytes;
  final int outboundBytes;
  final int statusCode;
  final int attempt;
  final bool stream;

  /// 返回用于观测展示的客户端端点，兼容旧记录和 IPv6 地址。
  String get clientEndpoint {
    final ip = clientIp.trim();
    final port = clientPort.trim();
    if (ip.isEmpty) return '';
    if (port.isEmpty) return ip;
    final displayIp = ip.contains(':') && !ip.startsWith('[') ? '[$ip]' : ip;
    return '$displayIp:$port';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'started_at': startedAt.toUtc().toIso8601String(),
    'provider_id': providerId,
    'model_id': modelId,
    'api_style': apiStyle,
    'tokens': tokens,
    'duration_ms': durationMs,
    'success': success,
    if (error != null) 'error': error,
    if (clientIp.trim().isNotEmpty) 'client_ip': clientIp.trim(),
    if (clientPort.trim().isNotEmpty) 'client_port': clientPort.trim(),
    if (clientUserAgent.trim().isNotEmpty)
      'client_user_agent': clientUserAgent.trim(),
    if (proxyMode.trim().isNotEmpty) 'proxy_mode': proxyMode.trim(),
    if (proxyEndpoint.trim().isNotEmpty) 'proxy_endpoint': proxyEndpoint.trim(),
    if (remoteHost.trim().isNotEmpty) 'remote_host': remoteHost.trim(),
    if (remotePort.trim().isNotEmpty) 'remote_port': remotePort.trim(),
    if (exposedModel.trim().isNotEmpty) 'exposed_model': exposedModel.trim(),
    if (requestPath.trim().isNotEmpty) 'request_path': requestPath.trim(),
    if (promptTokens > 0) 'prompt_tokens': promptTokens,
    if (completionTokens > 0) 'completion_tokens': completionTokens,
    if (inboundBytes > 0) 'inbound_bytes': inboundBytes,
    if (outboundBytes > 0) 'outbound_bytes': outboundBytes,
    if (statusCode > 0) 'status_code': statusCode,
    if (attempt > 1) 'attempt': attempt,
    if (stream) 'stream': true,
  };
}

class AiModelProxyRoute {
  const AiModelProxyRoute({
    required this.exposedModel,
    this.profile = const AiModelProfile(),
    this.enabled = true,
    required this.backends,
  });

  factory AiModelProxyRoute.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    final exposedModel = '${json['exposed_model'] ?? ''}'.trim();
    final backends = _normalizeProxyBackends(
      (json['backends'] is List ? json['backends'] as List : const <Object?>[])
          .map(AiModelProxyBackend.fromJson),
    );
    final profile = json['profile'] is Map
        ? AiModelProfile.fromJson(stringKeyedMapFromValue(json['profile']))
        : const AiModelProfile();
    return AiModelProxyRoute(
      exposedModel: exposedModel,
      profile: profile,
      enabled: boolFromValue(json['enabled'], defaultValue: true),
      backends: backends,
    );
  }

  final String exposedModel;
  final AiModelProfile profile;
  final bool enabled;
  final List<AiModelProxyBackend> backends;

  AiModelProxyRoute copyWith({
    String? exposedModel,
    AiModelProfile? profile,
    bool? enabled,
    List<AiModelProxyBackend>? backends,
  }) => AiModelProxyRoute(
    exposedModel: (exposedModel ?? this.exposedModel).trim(),
    profile: profile ?? this.profile,
    enabled: enabled ?? this.enabled,
    backends: _normalizeProxyBackends(backends ?? this.backends),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'exposed_model': exposedModel,
    'enabled': enabled,
    if (profile.hasUserOverrides) 'profile': profile.toJson(),
    'backends': backends.map((item) => item.toJson()).toList(growable: false),
  };
}

class AiModelProxySettings {
  const AiModelProxySettings({
    this.enabled = false,
    this.listenHost = aiModelProxyDefaultListenHost,
    this.listenPort = aiModelProxyDefaultListenPort,
    this.requireAuthentication = false,
    this.apiKey = '',
    this.apiStyle = AiModelProxyApiStyle.openAiResponses,
    this.limitScope = AiModelProxyLimitScope.perIp,
    this.limitMode = AiModelProxyLimitMode.rpm,
    this.limitThreshold = 30,
    this.retryPolicy = AiModelProxyRetryPolicy.failFast,
    this.retryCount = 2,
    this.scheduling = AiModelProxySchedulingStrategy.roundRobin,
    this.routes = const <AiModelProxyRoute>[],
    this.requestCount = 0,
    this.successCount = 0,
    this.failureCount = 0,
    this.totalTokens = 0,
    this.totalDurationMs = 0,
    this.lastRequestAt,
    this.recentRequests = const <AiModelProxyRequestRecord>[],
    this.dailyHealth = const <AiModelProxyDailyHealth>[],
  });

  factory AiModelProxySettings.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    final routes = _normalizeProxyRoutes(
      (json['routes'] is List ? json['routes'] as List : const <Object?>[]).map(
        AiModelProxyRoute.fromJson,
      ),
    );
    final records =
        (json['recent_requests'] is List
                ? json['recent_requests'] as List
                : const <Object?>[])
            .map(AiModelProxyRequestRecord.fromJson)
            .where((item) => item.id.isNotEmpty)
            .toList(growable: false);
    final daily =
        (json['daily_health'] is List
                ? json['daily_health'] as List
                : const <Object?>[])
            .map(AiModelProxyDailyHealth.fromJson)
            .where((item) => item.day.isNotEmpty)
            .toList(growable: false);
    return AiModelProxySettings(
      enabled: boolFromValue(json['enabled']),
      listenHost: _normalizeListenHost(json['listen_host']),
      listenPort: _boundedInt(
        json['listen_port'],
        aiModelProxyDefaultListenPort,
        aiModelProxyMinListenPort,
        aiModelProxyMaxListenPort,
      ),
      requireAuthentication: boolFromValue(json['require_authentication']),
      apiKey: '${json['api_key'] ?? ''}',
      apiStyle: AiModelProxyApiStyle.fromId(json['api_style']),
      limitScope: AiModelProxyLimitScope.fromId(json['limit_scope']),
      limitMode: AiModelProxyLimitMode.fromId(json['limit_mode']),
      limitThreshold: _boundedInt(json['limit_threshold'], 30, 1, 1000000),
      retryPolicy: AiModelProxyRetryPolicy.fromId(json['retry_policy']),
      retryCount: _boundedInt(json['retry_count'], 2, 1, 10),
      scheduling: AiModelProxySchedulingStrategy.fromId(json['scheduling']),
      routes: routes,
      requestCount: _boundedInt(json['request_count'], 0, 0, 1 << 31),
      successCount: _boundedInt(json['success_count'], 0, 0, 1 << 31),
      failureCount: _boundedInt(json['failure_count'], 0, 0, 1 << 31),
      totalTokens: _boundedInt(json['total_tokens'], 0, 0, 1 << 52),
      totalDurationMs: _boundedInt(json['total_duration_ms'], 0, 0, 1 << 52),
      lastRequestAt: DateTime.tryParse(
        '${json['last_request_at'] ?? ''}',
      )?.toLocal(),
      recentRequests: records.length <= 200
          ? records
          : records.sublist(records.length - 200),
      dailyHealth: daily.length <= aiModelProxyStatusHistoryDays
          ? daily
          : daily.sublist(daily.length - aiModelProxyStatusHistoryDays),
    );
  }

  final bool enabled;
  final String listenHost;
  final int listenPort;
  final bool requireAuthentication;
  final String apiKey;
  final AiModelProxyApiStyle apiStyle;
  final AiModelProxyLimitScope limitScope;
  final AiModelProxyLimitMode limitMode;
  final int limitThreshold;
  final AiModelProxyRetryPolicy retryPolicy;
  final int retryCount;
  final AiModelProxySchedulingStrategy scheduling;
  final List<AiModelProxyRoute> routes;
  final int requestCount;
  final int successCount;
  final int failureCount;
  final int totalTokens;
  final int totalDurationMs;
  final DateTime? lastRequestAt;
  final List<AiModelProxyRequestRecord> recentRequests;
  final List<AiModelProxyDailyHealth> dailyHealth;

  double get successRate => requestCount == 0 ? 0 : successCount / requestCount;
  double get averageDurationMs =>
      requestCount == 0 ? 0 : totalDurationMs / requestCount;

  AiModelProxySettings copyWith({
    bool? enabled,
    String? listenHost,
    int? listenPort,
    bool? requireAuthentication,
    String? apiKey,
    AiModelProxyApiStyle? apiStyle,
    AiModelProxyLimitScope? limitScope,
    AiModelProxyLimitMode? limitMode,
    int? limitThreshold,
    AiModelProxyRetryPolicy? retryPolicy,
    int? retryCount,
    AiModelProxySchedulingStrategy? scheduling,
    List<AiModelProxyRoute>? routes,
    int? requestCount,
    int? successCount,
    int? failureCount,
    int? totalTokens,
    int? totalDurationMs,
    DateTime? lastRequestAt,
    List<AiModelProxyRequestRecord>? recentRequests,
    List<AiModelProxyDailyHealth>? dailyHealth,
  }) => AiModelProxySettings(
    enabled: enabled ?? this.enabled,
    listenHost: _normalizeListenHost(listenHost ?? this.listenHost),
    listenPort: (listenPort ?? this.listenPort).clamp(
      aiModelProxyMinListenPort,
      aiModelProxyMaxListenPort,
    ),
    requireAuthentication: requireAuthentication ?? this.requireAuthentication,
    apiKey: apiKey ?? this.apiKey,
    apiStyle: apiStyle ?? this.apiStyle,
    limitScope: limitScope ?? this.limitScope,
    limitMode: limitMode ?? this.limitMode,
    limitThreshold: limitThreshold ?? this.limitThreshold,
    retryPolicy: retryPolicy ?? this.retryPolicy,
    retryCount: retryCount ?? this.retryCount,
    scheduling: scheduling ?? this.scheduling,
    routes: _normalizeProxyRoutes(routes ?? this.routes),
    requestCount: requestCount ?? this.requestCount,
    successCount: successCount ?? this.successCount,
    failureCount: failureCount ?? this.failureCount,
    totalTokens: totalTokens ?? this.totalTokens,
    totalDurationMs: totalDurationMs ?? this.totalDurationMs,
    lastRequestAt: lastRequestAt ?? this.lastRequestAt,
    recentRequests: recentRequests ?? this.recentRequests,
    dailyHealth: dailyHealth ?? this.dailyHealth,
  );

  AiModelProxySettings record({
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
  }) {
    final now = DateTime.now();
    final record = AiModelProxyRequestRecord(
      id: 'proxy-${now.microsecondsSinceEpoch}',
      startedAt: now,
      providerId: providerId,
      modelId: modelId,
      apiStyle: apiStyle,
      tokens: tokens.clamp(0, 1 << 30),
      durationMs: durationMs.clamp(0, 1 << 30),
      success: success,
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
      promptTokens: promptTokens.clamp(0, 1 << 30),
      completionTokens: completionTokens.clamp(0, 1 << 30),
      inboundBytes: inboundBytes.clamp(0, 1 << 30),
      outboundBytes: outboundBytes.clamp(0, 1 << 30),
      statusCode: statusCode.clamp(0, 599),
      attempt: attempt.clamp(1, 32),
      stream: stream,
    );
    final nextRecords = <AiModelProxyRequestRecord>[...recentRequests, record];
    if (nextRecords.length > 200) {
      nextRecords.removeRange(0, nextRecords.length - 200);
    }
    return copyWith(
      requestCount: requestCount + 1,
      successCount: successCount + (success ? 1 : 0),
      failureCount: failureCount + (success ? 0 : 1),
      totalTokens: totalTokens + tokens.clamp(0, 1 << 30),
      totalDurationMs: totalDurationMs + durationMs.clamp(0, 1 << 30),
      lastRequestAt: now,
      recentRequests: nextRecords,
      dailyHealth: _advanceDailyHealth(dailyHealth, record),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'listen_host': _normalizeListenHost(listenHost),
    'listen_port': listenPort.clamp(
      aiModelProxyMinListenPort,
      aiModelProxyMaxListenPort,
    ),
    'require_authentication': requireAuthentication,
    'api_key': apiKey,
    'api_style': apiStyle.id,
    'limit_scope': limitScope.id,
    'limit_mode': limitMode.id,
    'limit_threshold': limitThreshold,
    'retry_policy': retryPolicy.id,
    'retry_count': retryCount,
    'scheduling': scheduling.id,
    'routes': _normalizeProxyRoutes(
      routes,
    ).map((item) => item.toJson()).toList(growable: false),
    'request_count': requestCount,
    'success_count': successCount,
    'failure_count': failureCount,
    'total_tokens': totalTokens,
    'total_duration_ms': totalDurationMs,
    if (lastRequestAt != null)
      'last_request_at': lastRequestAt!.toUtc().toIso8601String(),
    'recent_requests': recentRequests
        .take(200)
        .map((item) => item.toJson())
        .toList(growable: false),
    if (dailyHealth.isNotEmpty)
      'daily_health': dailyHealth
          .map((item) => item.toJson())
          .toList(growable: false),
  };

  static int _boundedInt(Object? value, int fallback, int min, int max) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return (parsed ?? fallback).clamp(min, max).toInt();
  }

  static String _normalizeListenHost(Object? value) {
    final host = '$value'.trim();
    return host.isEmpty || host == 'null'
        ? aiModelProxyDefaultListenHost
        : host;
  }
}
