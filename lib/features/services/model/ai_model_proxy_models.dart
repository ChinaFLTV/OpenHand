import 'dart:math' as math;

import '../../../shared/net/tcp_port_utils.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart';

const String aiModelProxyDefaultListenHost = '127.0.0.1';
const int aiModelProxyDefaultListenPort = 6699;
const int aiModelProxyMinListenPort = kTcpPortMin;
const int aiModelProxyMaxListenPort = kTcpPortMax;
const String aiModelProxyStatusPath = '/status.html';
const String aiModelProxyStatusAliasPath = '/status';
const String aiModelProxyStatusJsonPath = '/status.json';
const String aiModelProxyStatusMode = 'status';
const String aiModelProxyPoolMode = 'pool';
const String aiModelProxySystemMode = 'system';
const String aiModelProxyDirectMode = 'direct';
const String aiModelProxyLocalMode = 'local';
const String aiModelProxyStatusModelId = 'status.html';
const String aiModelProxyLogoAsset = 'assets/branding/openhand_logo.png';
const String aiModelProxyLogoPath = '/openhand_logo.png';
const String aiModelProxyFaviconPath = '/favicon.ico';
const int aiModelProxyStatusHistoryDays = 90;
const int aiModelProxyRecentRequestLimit = 200;
const int aiModelProxyRecentStatusRequestLimit = 24;
const int aiModelProxyStatusLivePollMs = 8000;
const int aiModelProxyStatusLivePollHiddenMs = 30000;
const int aiModelProxyStatusLivePollTimeoutMs = 8000;
const int aiModelProxyStatusLivePollBackoffMaxMs = 60000;
const int aiModelProxySlowLatencyMs = 3000;
const int aiModelProxySevereLatencyMs = 6000;
const double aiModelProxyHealthHealthyRate = 0.95;
const double aiModelProxyHealthWarningRate = 0.80;
const double aiModelProxyHealthDegradedRate = 0.60;
const double aiModelProxyHealthSlowRate = 0.20;
const double aiModelProxyHealthSevereSlowRate = 0.40;

String aiModelProxyHealthPercentLabel(double rate) {
  return '${(rate * 100).round()}%';
}

int aiModelProxyLatencySeconds(int milliseconds) {
  return (milliseconds / 1000).round();
}

const int aiModelProxyDailyModelCap = 64;
const int aiModelProxyMaxConcurrentRequests = 16;
const int aiModelProxyTelemetryBucketMs = 60000;
const int aiModelProxyTelemetryRetentionDays = 90;
const int aiModelProxyTelemetryLoadLimit = 2880;
const int aiModelProxyMaxRequestTextCharacters = 8 * kBytesPerKiB;

bool isAiModelProxyStatusPath(String path) {
  final value = path.trim();
  return value == aiModelProxyStatusPath ||
      value == aiModelProxyStatusAliasPath;
}

bool isAiModelProxyStatusJsonPath(String path) {
  return path.trim() == aiModelProxyStatusJsonPath;
}

bool isAiModelProxyStatusSurfacePath(String path) {
  return isAiModelProxyStatusPath(path) || isAiModelProxyStatusJsonPath(path);
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
  return isAiModelProxyStatusSurfacePath(record.requestPath);
}

/// 统一客户端对端展示：IPv6 加方括号，避免与端口号粘连。
String aiModelProxyClientEndpoint(String ip, String port) {
  final host = ip.trim();
  if (host.isEmpty) return '';
  final service = port.trim();
  if (service.isEmpty) return host;
  final displayHost = host.contains(':') && !host.startsWith('[')
      ? '[$host]'
      : host;
  return '$displayHost:$service';
}

typedef AiModelProxyLabelText =
    String Function({required String zh, required String en});

/// 将持久化的调度模式标识转换为界面文案。
String aiModelProxyDispatchModeLabel(String mode, AiModelProxyLabelText text) {
  return switch (mode.trim().toLowerCase()) {
    aiModelProxyPoolMode => text(zh: '代理池', en: 'Proxy pool'),
    aiModelProxySystemMode => text(zh: '系统代理', en: 'System proxy'),
    aiModelProxyDirectMode => text(zh: '直连', en: 'Direct'),
    aiModelProxyLocalMode ||
    aiModelProxyStatusMode => text(zh: '本地响应', en: 'Local response'),
    _ => text(zh: '未知模式', en: 'Unknown mode'),
  };
}

/// 将持久化的接口风格标识转换为界面文案。
String aiModelProxyApiStyleLabel(String raw, AiModelProxyLabelText text) {
  final id = raw.trim();
  if (id.isEmpty) return '';
  final normalized = id.toLowerCase();
  if (normalized == aiModelProxyStatusMode) {
    return text(zh: 'HTTP 状态接口', en: 'HTTP status API');
  }
  for (final style in AiModelProxyApiStyle.values) {
    if (style.id.toLowerCase() == normalized) return style.label;
  }
  return text(zh: '未知协议', en: 'Unknown protocol');
}

/// 返回请求使用的模型；状态资源不经过模型，统一返回空值。
String aiModelProxyRequestModelLabel(AiModelProxyRequestRecord record) {
  if (isAiModelProxyStatusRecord(record)) return '';
  return record.modelId.trim();
}

/// 按请求语义展示接口协议，状态资源统一标记为 HTTP 状态接口。
String aiModelProxyRequestProtocolLabel(
  AiModelProxyRequestRecord record,
  AiModelProxyLabelText text,
) {
  if (isAiModelProxyStatusRecord(record)) {
    return text(zh: 'HTTP 状态接口', en: 'HTTP status API');
  }
  return aiModelProxyApiStyleLabel(record.apiStyle, text);
}

/// 按请求语义展示调度路径，状态资源由本地直接响应。
String aiModelProxyRequestDispatchLabel(
  AiModelProxyRequestRecord record,
  AiModelProxyLabelText text,
) {
  if (isAiModelProxyStatusRecord(record)) {
    return text(zh: '本地响应', en: 'Local response');
  }
  return aiModelProxyDispatchModeLabel(record.proxyMode, text);
}

String aiModelProxyDayKey(DateTime value) {
  return formatYearMonthDayLocal(value);
}

String aiModelProxyStatusUrl({
  required String listenHost,
  required int listenPort,
}) {
  var host = normalizeAiModelProxyListenHost(listenHost);
  if (host.isEmpty ||
      host == '0.0.0.0' ||
      host == '*' ||
      host == '::' ||
      host == '::0') {
    host = '127.0.0.1';
  }
  try {
    return Uri(
      scheme: 'http',
      host: host,
      port: listenPort,
      path: aiModelProxyStatusPath,
    ).toString();
  } on FormatException {
    return 'http://${Uri.encodeComponent(host)}:$listenPort'
        '$aiModelProxyStatusPath';
  }
}

String normalizeAiModelProxyListenHost(Object? value) {
  final host = '$value'.trim();
  if (host.isEmpty || host == 'null') return aiModelProxyDefaultListenHost;
  return host.length > 2 && host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;
}

enum AiModelProxyHealth { idle, healthy, warning, degraded, outage }

AiModelProxyHealth classifyAiModelProxyHealth({
  required int requests,
  required int successes,
  int slowCount = 0,
  int p95Ms = 0,
}) {
  if (requests <= 0) return AiModelProxyHealth.idle;
  final rate = successes.clamp(0, requests) / requests;
  final slowRate = slowCount.clamp(0, requests) / requests;
  if (rate < aiModelProxyHealthDegradedRate) {
    return AiModelProxyHealth.outage;
  }
  if (rate < aiModelProxyHealthWarningRate ||
      p95Ms >= aiModelProxySevereLatencyMs ||
      slowRate >= aiModelProxyHealthSevereSlowRate) {
    return AiModelProxyHealth.degraded;
  }
  if (rate < aiModelProxyHealthHealthyRate ||
      p95Ms >= aiModelProxySlowLatencyMs ||
      slowRate >= aiModelProxyHealthSlowRate) {
    return AiModelProxyHealth.warning;
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
      requests: clampedIntFromValue(
        json['requests'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
      successes: clampedIntFromValue(
        json['successes'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
      durationMs: clampedIntFromValue(
        json['duration_ms'],
        fallback: 0,
        min: 0,
        max: 1 << 52,
      ),
      slowCount: clampedIntFromValue(
        json['slow'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
    );
  }

  final int requests;
  final int successes;
  final int durationMs;
  final int slowCount;

  int get failures => requests <= successes ? 0 : requests - successes;
  double get successRate =>
      requests <= 0 ? 0 : (successes / requests).clamp(0.0, 1.0);
  int get avgMs => requests <= 0 ? 0 : (durationMs / requests).round();
  AiModelProxyHealth get health => classifyAiModelProxyHealth(
    requests: requests,
    successes: successes,
    slowCount: slowCount,
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

List<AiModelProxyRequestRecord> _trimRecentProxyRecords(
  List<AiModelProxyRequestRecord> records,
) {
  if (records.isEmpty) return const <AiModelProxyRequestRecord>[];
  final next = List<AiModelProxyRequestRecord>.from(records);
  var statusKept = 0;
  for (var i = next.length - 1; i >= 0; i--) {
    if (!isAiModelProxyStatusRecord(next[i])) continue;
    statusKept += 1;
    if (statusKept > aiModelProxyRecentStatusRequestLimit) {
      next.removeAt(i);
    }
  }
  if (next.length > aiModelProxyRecentRequestLimit) {
    next.removeRange(0, next.length - aiModelProxyRecentRequestLimit);
  }
  return next;
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
  sticky('sticky', '粘性调度');

  const AiModelProxySchedulingStrategy(this.id, this.label);
  final String id;
  final String label;

  static AiModelProxySchedulingStrategy fromId(Object? value) {
    // 旧版“保守调度”与优先级调度实现完全相同，读取时归并为唯一语义。
    if ('$value'.trim().toLowerCase() == 'conservative') return priority;
    return enumByStorageValueOr(
      values,
      value,
      (item) => item.id,
      fallback: roundRobin,
    );
  }
}

String aiModelProxyLimitScopeLabel(
  AiModelProxyLimitScope scope,
  AiModelProxyLabelText text,
) => switch (scope) {
  AiModelProxyLimitScope.perIp => text(zh: '单个 IP', en: 'Per IP'),
  AiModelProxyLimitScope.clientClass => text(zh: '同类客户端', en: 'Client class'),
};

String aiModelProxyRetryPolicyLabel(
  AiModelProxyRetryPolicy policy,
  AiModelProxyLabelText text,
) => switch (policy) {
  AiModelProxyRetryPolicy.failFast => text(zh: '立即失败', en: 'Fail fast'),
  AiModelProxyRetryPolicy.retrySame => text(
    zh: '同后备重试',
    en: 'Retry same backend',
  ),
  AiModelProxyRetryPolicy.retryAndFailover => text(
    zh: '重试并接力',
    en: 'Retry with failover',
  ),
};

String aiModelProxySchedulingLabel(
  AiModelProxySchedulingStrategy strategy,
  AiModelProxyLabelText text,
) => switch (strategy) {
  AiModelProxySchedulingStrategy.roundRobin => text(
    zh: '轮询调度',
    en: 'Round robin',
  ),
  AiModelProxySchedulingStrategy.random => text(zh: '随机调度', en: 'Random'),
  AiModelProxySchedulingStrategy.priority => text(zh: '优先级调度', en: 'Priority'),
  AiModelProxySchedulingStrategy.sticky => text(
    zh: '客户端粘性',
    en: 'Client affinity',
  ),
};

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiModelProxyBackend &&
          providerId == other.providerId &&
          modelId == other.modelId &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(providerId, modelId, enabled);

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
    this.clientProcessId = '',
    this.clientProcessName = '',
    this.clientServiceName = '',
    this.clientMacAddress = '',
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

  factory AiModelProxyRequestRecord.capture({
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
    String clientProcessId = '',
    String clientProcessName = '',
    String clientServiceName = '',
    String clientMacAddress = '',
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
    DateTime? startedAt,
  }) {
    final capturedAt = startedAt ?? DateTime.now();
    return AiModelProxyRequestRecord(
      id: 'proxy-${capturedAt.microsecondsSinceEpoch}',
      startedAt: capturedAt,
      providerId: _boundedProxyRequestText(providerId),
      modelId: _boundedProxyRequestText(modelId),
      apiStyle: _boundedProxyRequestText(apiStyle),
      tokens: tokens.clamp(0, 1 << 30),
      durationMs: durationMs.clamp(0, 1 << 30),
      success: success,
      error: _boundedNullableProxyRequestText(error),
      clientIp: _boundedProxyRequestText(clientIp),
      clientPort: _boundedProxyRequestText(clientPort),
      clientUserAgent: _boundedProxyRequestText(clientUserAgent),
      clientProcessId: _boundedProxyRequestText(clientProcessId),
      clientProcessName: _boundedProxyRequestText(clientProcessName),
      clientServiceName: _boundedProxyRequestText(clientServiceName),
      clientMacAddress: _boundedProxyRequestText(clientMacAddress),
      proxyMode: _boundedProxyRequestText(proxyMode),
      proxyEndpoint: _boundedProxyRequestText(proxyEndpoint),
      remoteHost: _boundedProxyRequestText(remoteHost),
      remotePort: _boundedProxyRequestText(remotePort),
      exposedModel: _boundedProxyRequestText(exposedModel),
      requestPath: _boundedProxyRequestText(requestPath),
      promptTokens: promptTokens.clamp(0, 1 << 30),
      completionTokens: completionTokens.clamp(0, 1 << 30),
      inboundBytes: inboundBytes.clamp(0, 1 << 30),
      outboundBytes: outboundBytes.clamp(0, 1 << 30),
      statusCode: statusCode.clamp(0, 599),
      attempt: attempt.clamp(1, 32),
      stream: stream,
    );
  }

  factory AiModelProxyRequestRecord.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AiModelProxyRequestRecord(
      id: _boundedProxyRequestText(json['id']),
      startedAt:
          DateTime.tryParse('${json['started_at'] ?? ''}')?.toLocal() ??
          DateTime.now(),
      providerId: _boundedProxyRequestText(json['provider_id']),
      modelId: _boundedProxyRequestText(json['model_id']),
      apiStyle: _boundedProxyRequestText(json['api_style']),
      tokens: clampedIntFromValue(
        json['tokens'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
      durationMs: clampedIntFromValue(
        json['duration_ms'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
      success: boolFromValue(json['success']),
      error: _boundedNullableProxyRequestText(json['error']),
      clientIp: _boundedProxyRequestText(json['client_ip']),
      clientPort: _boundedProxyRequestText(json['client_port']),
      clientUserAgent: _boundedProxyRequestText(json['client_user_agent']),
      clientProcessId: _boundedProxyRequestText(json['client_process_id']),
      clientProcessName: _boundedProxyRequestText(json['client_process_name']),
      clientServiceName: _boundedProxyRequestText(json['client_service_name']),
      clientMacAddress: _boundedProxyRequestText(json['client_mac_address']),
      proxyMode: _boundedProxyRequestText(json['proxy_mode']),
      proxyEndpoint: _boundedProxyRequestText(json['proxy_endpoint']),
      remoteHost: _boundedProxyRequestText(json['remote_host']),
      remotePort: _boundedProxyRequestText(json['remote_port']),
      exposedModel: _boundedProxyRequestText(json['exposed_model']),
      requestPath: _boundedProxyRequestText(json['request_path']),
      promptTokens: clampedIntFromValue(
        json['prompt_tokens'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
      completionTokens: clampedIntFromValue(
        json['completion_tokens'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
      inboundBytes: clampedIntFromValue(
        json['inbound_bytes'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
      outboundBytes: clampedIntFromValue(
        json['outbound_bytes'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
      statusCode: clampedIntFromValue(
        json['status_code'],
        fallback: 0,
        min: 0,
        max: 599,
      ),
      attempt: clampedIntFromValue(
        json['attempt'],
        fallback: 1,
        min: 1,
        max: 32,
      ),
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
  final String clientProcessId;
  final String clientProcessName;
  final String clientServiceName;
  final String clientMacAddress;
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
  String get clientEndpoint => aiModelProxyClientEndpoint(clientIp, clientPort);

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
    if (clientProcessId.trim().isNotEmpty)
      'client_process_id': clientProcessId.trim(),
    if (clientProcessName.trim().isNotEmpty)
      'client_process_name': clientProcessName.trim(),
    if (clientServiceName.trim().isNotEmpty)
      'client_service_name': clientServiceName.trim(),
    if (clientMacAddress.trim().isNotEmpty)
      'client_mac_address': clientMacAddress.trim(),
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

String _boundedProxyRequestText(Object? value) {
  final text = value == null ? '' : '$value'.trim();
  return clipText(text, aiModelProxyMaxRequestTextCharacters, suffix: '');
}

String? _boundedNullableProxyRequestText(Object? value) {
  return nullIfBlank(_boundedProxyRequestText(value));
}

/// 分钟级中转站遥测桶。计数与字节采用增量合并，连接数据采用采样峰值。
class AiModelProxyTelemetryBucket {
  const AiModelProxyTelemetryBucket({
    required this.bucketAtMs,
    this.ingressCount = 0,
    this.successCount = 0,
    this.failureCount = 0,
    this.ingressErrorCount = 0,
    this.inboundBytes = 0,
    this.outboundBytes = 0,
    this.connectionSampleCount = 0,
    this.connectionTotal = 0,
    this.lastConnections = 0,
    this.peakConnections = 0,
    this.peakActiveRequests = 0,
    this.durationTotalMs = 0,
    this.tokenCount = 0,
    this.metadata = const <String, Object?>{},
    this.environment = const <String, Object?>{},
  });

  final int bucketAtMs;
  final int ingressCount;
  final int successCount;
  final int failureCount;
  final int ingressErrorCount;
  final int inboundBytes;
  final int outboundBytes;
  final int connectionSampleCount;
  final int connectionTotal;
  final int lastConnections;
  final int peakConnections;
  final int peakActiveRequests;
  final int durationTotalMs;
  final int tokenCount;
  final Map<String, Object?> metadata;
  final Map<String, Object?> environment;

  DateTime get bucketAt =>
      DateTime.fromMillisecondsSinceEpoch(bucketAtMs, isUtc: true).toLocal();

  int get recordedRequestCount => successCount + failureCount;
  double get averageDurationMs =>
      recordedRequestCount <= 0 ? 0 : durationTotalMs / recordedRequestCount;

  AiModelProxyTelemetryBucket merge(AiModelProxyTelemetryBucket other) {
    assert(bucketAtMs == other.bucketAtMs);
    final hasConnectionSample = other.connectionSampleCount > 0;
    return AiModelProxyTelemetryBucket(
      bucketAtMs: bucketAtMs,
      ingressCount: ingressCount + other.ingressCount,
      successCount: successCount + other.successCount,
      failureCount: failureCount + other.failureCount,
      ingressErrorCount: ingressErrorCount + other.ingressErrorCount,
      inboundBytes: inboundBytes + other.inboundBytes,
      outboundBytes: outboundBytes + other.outboundBytes,
      connectionSampleCount:
          connectionSampleCount + other.connectionSampleCount,
      connectionTotal: connectionTotal + other.connectionTotal,
      lastConnections: hasConnectionSample
          ? other.lastConnections
          : lastConnections,
      peakConnections: math.max(peakConnections, other.peakConnections),
      peakActiveRequests: math.max(
        peakActiveRequests,
        other.peakActiveRequests,
      ),
      durationTotalMs: durationTotalMs + other.durationTotalMs,
      tokenCount: tokenCount + other.tokenCount,
      metadata: other.metadata.isEmpty
          ? metadata
          : <String, Object?>{...metadata, ...other.metadata},
      environment: other.environment.isEmpty
          ? environment
          : <String, Object?>{...environment, ...other.environment},
    );
  }
}

int aiModelProxyTelemetryBucketKey(DateTime value) {
  final milliseconds = value.toUtc().millisecondsSinceEpoch;
  return milliseconds - milliseconds.remainder(aiModelProxyTelemetryBucketMs);
}

/// 当前仍占用中转入口的客户端连接，按对端地址去重。
class AiModelProxyLiveConnection {
  const AiModelProxyLiveConnection({
    required this.endpoint,
    required this.inflight,
    this.userAgent = '',
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  final String endpoint;
  final int inflight;
  final String userAgent;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
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
      listenHost: normalizeAiModelProxyListenHost(json['listen_host']),
      listenPort: clampedIntFromValue(
        json['listen_port'],
        fallback: aiModelProxyDefaultListenPort,
        min: aiModelProxyMinListenPort,
        max: aiModelProxyMaxListenPort,
      ),
      requireAuthentication: boolFromValue(json['require_authentication']),
      apiKey: '${json['api_key'] ?? ''}',
      apiStyle: AiModelProxyApiStyle.fromId(json['api_style']),
      limitScope: AiModelProxyLimitScope.fromId(json['limit_scope']),
      limitMode: AiModelProxyLimitMode.fromId(json['limit_mode']),
      limitThreshold: clampedIntFromValue(
        json['limit_threshold'],
        fallback: 30,
        min: 1,
        max: 1000000,
      ),
      retryPolicy: AiModelProxyRetryPolicy.fromId(json['retry_policy']),
      retryCount: clampedIntFromValue(
        json['retry_count'],
        fallback: 2,
        min: 1,
        max: 10,
      ),
      scheduling: AiModelProxySchedulingStrategy.fromId(json['scheduling']),
      routes: routes,
      requestCount: clampedIntFromValue(
        json['request_count'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
      successCount: clampedIntFromValue(
        json['success_count'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
      failureCount: clampedIntFromValue(
        json['failure_count'],
        fallback: 0,
        min: 0,
        max: 1 << 31,
      ),
      totalTokens: clampedIntFromValue(
        json['total_tokens'],
        fallback: 0,
        min: 0,
        max: 1 << 52,
      ),
      totalDurationMs: clampedIntFromValue(
        json['total_duration_ms'],
        fallback: 0,
        min: 0,
        max: 1 << 52,
      ),
      lastRequestAt: DateTime.tryParse(
        '${json['last_request_at'] ?? ''}',
      )?.toLocal(),
      recentRequests: _trimRecentProxyRecords(records),
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
    listenHost: normalizeAiModelProxyListenHost(listenHost ?? this.listenHost),
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

  AiModelProxySettings record(AiModelProxyRequestRecord record) {
    final nextRecords = _trimRecentProxyRecords(<AiModelProxyRequestRecord>[
      ...recentRequests,
      record,
    ]);
    return copyWith(
      requestCount: requestCount + 1,
      successCount: successCount + (record.success ? 1 : 0),
      failureCount: failureCount + (record.success ? 0 : 1),
      totalTokens: totalTokens + record.tokens,
      totalDurationMs: totalDurationMs + record.durationMs,
      lastRequestAt: record.startedAt,
      recentRequests: nextRecords,
      dailyHealth: _advanceDailyHealth(dailyHealth, record),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'listen_host': normalizeAiModelProxyListenHost(listenHost),
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
    'recent_requests': _trimRecentProxyRecords(
      recentRequests,
    ).map((item) => item.toJson()).toList(growable: false),
    if (dailyHealth.isNotEmpty)
      'daily_health': dailyHealth
          .map((item) => item.toJson())
          .toList(growable: false),
  };
}
