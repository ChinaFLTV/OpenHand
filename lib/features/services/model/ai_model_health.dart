import '../../../shared/util/input_value_parsing.dart';

abstract final class AiModelProbeTimeoutPolicy {
  static const int defaultConnectTimeoutSeconds = 30;
  static const int minConnectTimeoutSeconds = 5;
  static const int maxConnectTimeoutSeconds = 300;
  static const int defaultResponseTimeoutSeconds = 30;
  static const int minResponseTimeoutSeconds = 10;
  static const int maxResponseTimeoutSeconds = 600;
}

enum AiModelHealthRequestMode {
  direct('direct'),
  systemProxy('system_proxy'),
  proxyPool('proxy_pool');

  const AiModelHealthRequestMode(this.storageValue);
  final String storageValue;

  static AiModelHealthRequestMode fromStorage(Object? value) =>
      enumByStorageValueOr(
        values,
        value,
        (item) => item.storageValue,
        fallback: AiModelHealthRequestMode.direct,
      );
}

String classifyAiModelProbeFailurePhase(String message, {int? responseCode}) {
  final normalized = message.toLowerCase();
  if (responseCode == 408 || responseCode == 504) return 'http_status';
  if (normalized.contains('connection timed out') ||
      normalized.contains('connection timeout') ||
      normalized.contains('连接超时')) {
    return 'connection_timeout';
  }
  if (normalized.contains('timed out') ||
      normalized.contains('timeout') ||
      normalized.contains('请求时限') ||
      normalized.contains('响应超时') ||
      normalized.contains('请求超时')) {
    return 'response_timeout';
  }
  if (normalized.contains('handshake') ||
      normalized.contains('certificate') ||
      normalized.contains('握手') ||
      normalized.contains('证书')) {
    return 'tls';
  }
  if (normalized.contains('failed host lookup') ||
      normalized.contains('name or service not known') ||
      normalized.contains('dns') ||
      normalized.contains('域名解析') ||
      normalized.contains('无法解析主机')) {
    return 'dns';
  }
  if (normalized.contains('socketexception') ||
      normalized.contains('connection refused') ||
      normalized.contains('network is unreachable') ||
      normalized.contains('连接被拒绝') ||
      normalized.contains('网络不可达')) {
    return 'connection';
  }
  if (responseCode != null) return 'http_status';
  return 'response';
}

class AiModelHealthSettings {
  const AiModelHealthSettings({
    this.enabled = false,
    this.intervalMinutes = 30,
    this.concurrency = 8,
    this.connectTimeoutSeconds =
        AiModelProbeTimeoutPolicy.defaultConnectTimeoutSeconds,
    this.responseTimeoutSeconds =
        AiModelProbeTimeoutPolicy.defaultResponseTimeoutSeconds,
    this.useSystemProxy = false,
    this.requestMode = AiModelHealthRequestMode.direct,
    this.retentionDays = 90,
  });

  factory AiModelHealthSettings.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AiModelHealthSettings(
      enabled: optionalBoolFromValue(json['enabled']) ?? false,
      intervalMinutes: clampedIntFromValue(
        json['interval_minutes'],
        fallback: 30,
        min: 1,
        max: 1440,
      ),
      concurrency: clampedIntFromValue(
        json['concurrency'],
        fallback: 8,
        min: 1,
        max: 32,
      ),
      connectTimeoutSeconds: clampedIntFromValue(
        json['connect_timeout_seconds'],
        fallback: AiModelProbeTimeoutPolicy.defaultConnectTimeoutSeconds,
        min: AiModelProbeTimeoutPolicy.minConnectTimeoutSeconds,
        max: AiModelProbeTimeoutPolicy.maxConnectTimeoutSeconds,
      ),
      responseTimeoutSeconds: clampedIntFromValue(
        json['response_timeout_seconds'],
        fallback: AiModelProbeTimeoutPolicy.defaultResponseTimeoutSeconds,
        min: AiModelProbeTimeoutPolicy.minResponseTimeoutSeconds,
        max: AiModelProbeTimeoutPolicy.maxResponseTimeoutSeconds,
      ),
      useSystemProxy: optionalBoolFromValue(json['use_system_proxy']) ?? false,
      requestMode: AiModelHealthRequestMode.fromStorage(json['request_mode']),
      retentionDays: clampedIntFromValue(
        json['retention_days'],
        fallback: 90,
        min: 1,
        max: 3650,
      ),
    );
  }

  final bool enabled;
  final int intervalMinutes;
  final int concurrency;
  final int connectTimeoutSeconds;
  final int responseTimeoutSeconds;
  final bool useSystemProxy;
  final AiModelHealthRequestMode requestMode;
  final int retentionDays;

  AiModelHealthSettings copyWith({
    bool? enabled,
    int? intervalMinutes,
    int? concurrency,
    int? connectTimeoutSeconds,
    int? responseTimeoutSeconds,
    bool? useSystemProxy,
    AiModelHealthRequestMode? requestMode,
    int? retentionDays,
  }) => AiModelHealthSettings(
    enabled: enabled ?? this.enabled,
    intervalMinutes: clampedIntFromValue(
      intervalMinutes,
      fallback: this.intervalMinutes,
      min: 1,
      max: 1440,
    ),
    concurrency: clampedIntFromValue(
      concurrency,
      fallback: this.concurrency,
      min: 1,
      max: 32,
    ),
    connectTimeoutSeconds: clampedIntFromValue(
      connectTimeoutSeconds,
      fallback: this.connectTimeoutSeconds,
      min: AiModelProbeTimeoutPolicy.minConnectTimeoutSeconds,
      max: AiModelProbeTimeoutPolicy.maxConnectTimeoutSeconds,
    ),
    responseTimeoutSeconds: clampedIntFromValue(
      responseTimeoutSeconds,
      fallback: this.responseTimeoutSeconds,
      min: AiModelProbeTimeoutPolicy.minResponseTimeoutSeconds,
      max: AiModelProbeTimeoutPolicy.maxResponseTimeoutSeconds,
    ),
    useSystemProxy: useSystemProxy ?? this.useSystemProxy,
    requestMode: requestMode ?? this.requestMode,
    retentionDays: clampedIntFromValue(
      retentionDays,
      fallback: this.retentionDays,
      min: 1,
      max: 3650,
    ),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'interval_minutes': intervalMinutes,
    'concurrency': concurrency,
    'connect_timeout_seconds': connectTimeoutSeconds,
    'response_timeout_seconds': responseTimeoutSeconds,
    'use_system_proxy': useSystemProxy,
    'request_mode': requestMode.storageValue,
    'retention_days': retentionDays,
  };

  @override
  bool operator ==(Object other) =>
      other is AiModelHealthSettings &&
      other.enabled == enabled &&
      other.intervalMinutes == intervalMinutes &&
      other.concurrency == concurrency &&
      other.connectTimeoutSeconds == connectTimeoutSeconds &&
      other.responseTimeoutSeconds == responseTimeoutSeconds &&
      other.useSystemProxy == useSystemProxy &&
      other.requestMode == requestMode &&
      other.retentionDays == retentionDays;

  @override
  int get hashCode => Object.hash(
    enabled,
    intervalMinutes,
    concurrency,
    connectTimeoutSeconds,
    responseTimeoutSeconds,
    useSystemProxy,
    requestMode,
    retentionDays,
  );
}

class AiModelHealthRecord {
  const AiModelHealthRecord({
    required this.id,
    required this.providerConfigId,
    required this.providerName,
    required this.modelId,
    required this.checkedAt,
    required this.success,
    required this.status,
    required this.latencyMs,
    required this.durationMs,
    required this.requestMode,
    this.responseCode,
    this.host = '',
    this.port,
    this.modelKind = 'text',
    this.errorMessage = '',
    this.metadata = const <String, Object?>{},
  });

  factory AiModelHealthRecord.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AiModelHealthRecord(
      id: stringFromValue(json['id']),
      providerConfigId: stringFromValue(json['provider_config_id']),
      providerName: stringFromValue(json['provider_name']),
      modelId: stringFromValue(json['model_id']),
      checkedAt:
          DateTime.tryParse(stringFromValue(json['checked_at'])) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      success: optionalBoolFromValue(json['success']) ?? false,
      status: stringFromValue(json['status']),
      latencyMs: clampedIntFromValue(
        json['latency_ms'],
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
      requestMode: AiModelHealthRequestMode.fromStorage(json['request_mode']),
      responseCode: optionalIntFromValue(json['response_code']),
      host: stringFromValue(json['host']),
      port: optionalIntFromValue(json['port']),
      modelKind: stringFromValue(json['model_kind'], fallback: 'text'),
      errorMessage: stringFromValue(json['error_message']),
      metadata: stringKeyedMapFromValue(json['metadata']),
    );
  }

  final String id;
  final String providerConfigId;
  final String providerName;
  final String modelId;
  final DateTime checkedAt;
  final bool success;
  final String status;
  final int latencyMs;
  final int durationMs;
  final AiModelHealthRequestMode requestMode;
  final int? responseCode;
  final String host;
  final int? port;
  final String modelKind;
  final String errorMessage;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'provider_config_id': providerConfigId,
    'provider_name': providerName,
    'model_id': modelId,
    'checked_at': checkedAt.toUtc().toIso8601String(),
    'success': success,
    'status': status,
    'latency_ms': latencyMs,
    'duration_ms': durationMs,
    'request_mode': requestMode.storageValue,
    if (responseCode != null) 'response_code': responseCode,
    'host': host,
    if (port != null) 'port': port,
    'model_kind': modelKind,
    'error_message': errorMessage,
    'metadata': metadata,
  };
}
