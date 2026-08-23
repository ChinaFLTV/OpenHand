import '../../../shared/util/input_value_parsing.dart';

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

class AiModelHealthSettings {
  const AiModelHealthSettings({
    this.enabled = false,
    this.intervalMinutes = 30,
    this.useSystemProxy = false,
    this.requestMode = AiModelHealthRequestMode.direct,
    this.retentionDays = 90,
  });

  factory AiModelHealthSettings.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AiModelHealthSettings(
      enabled: optionalBoolFromValue(json['enabled']) ?? false,
      intervalMinutes: _clampInt(json['interval_minutes'], 30, 1, 1440),
      useSystemProxy: optionalBoolFromValue(json['use_system_proxy']) ?? false,
      requestMode: AiModelHealthRequestMode.fromStorage(json['request_mode']),
      retentionDays: _clampInt(json['retention_days'], 90, 1, 3650),
    );
  }

  final bool enabled;
  final int intervalMinutes;
  final bool useSystemProxy;
  final AiModelHealthRequestMode requestMode;
  final int retentionDays;

  AiModelHealthSettings copyWith({
    bool? enabled,
    int? intervalMinutes,
    bool? useSystemProxy,
    AiModelHealthRequestMode? requestMode,
    int? retentionDays,
  }) => AiModelHealthSettings(
    enabled: enabled ?? this.enabled,
    intervalMinutes: _clampInt(intervalMinutes, this.intervalMinutes, 1, 1440),
    useSystemProxy: useSystemProxy ?? this.useSystemProxy,
    requestMode: requestMode ?? this.requestMode,
    retentionDays: _clampInt(retentionDays, this.retentionDays, 1, 3650),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'interval_minutes': intervalMinutes,
    'use_system_proxy': useSystemProxy,
    'request_mode': requestMode.storageValue,
    'retention_days': retentionDays,
  };

  @override
  bool operator ==(Object other) =>
      other is AiModelHealthSettings &&
      other.enabled == enabled &&
      other.intervalMinutes == intervalMinutes &&
      other.useSystemProxy == useSystemProxy &&
      other.requestMode == requestMode &&
      other.retentionDays == retentionDays;

  @override
  int get hashCode => Object.hash(
    enabled,
    intervalMinutes,
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
      latencyMs: _clampInt(json['latency_ms'], 0, 0, 1 << 31),
      durationMs: _clampInt(json['duration_ms'], 0, 0, 1 << 31),
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

int _clampInt(Object? raw, int fallback, int min, int max) {
  final value = optionalIntFromValue(raw) ?? fallback;
  return value.clamp(min, max).toInt();
}
