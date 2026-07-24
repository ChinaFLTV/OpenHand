import '../../../shared/util/input_value_parsing.dart';

class AiProviderCoreSettings {
  const AiProviderCoreSettings({
    required this.enabled,
    required this.endpoint,
    required this.appId,
    required this.apiKey,
    required this.apiSecret,
    required this.accessToken,
    required this.region,
    required this.modelConfigId,
    required this.modelId,
    required this.extra,
  });

  AiProviderCoreSettings.from(AiProviderCoreSettings other)
    : enabled = other.enabled,
      endpoint = other.endpoint,
      appId = other.appId,
      apiKey = other.apiKey,
      apiSecret = other.apiSecret,
      accessToken = other.accessToken,
      region = other.region,
      modelConfigId = other.modelConfigId,
      modelId = other.modelId,
      extra = other.extra;

  factory AiProviderCoreSettings.fromJson(
    Map<String, Object?> json, {
    required AiProviderCoreSettings fallback,
  }) {
    return fallback.copyWith(
      enabled: optionalBoolFromValue(json['enabled']),
      endpoint: optionalStringFromValue(json['endpoint']),
      appId: optionalStringFromValue(json['app_id']),
      apiKey: optionalStringFromValue(json['api_key']),
      apiSecret: optionalStringFromValue(json['api_secret']),
      accessToken: optionalStringFromValue(json['access_token']),
      region: optionalStringFromValue(json['region']),
      modelConfigId: optionalStringFromValue(json['model_config_id']),
      modelId: optionalStringFromValue(json['model_id']),
      extra: json['extra'] is Map
          ? stringKeyedMapFromValue(json['extra'])
          : null,
    );
  }

  final bool enabled;
  final String endpoint;
  final String appId;
  final String apiKey;
  final String apiSecret;
  final String accessToken;
  final String region;
  final String modelConfigId;
  final String modelId;
  final Map<String, Object?> extra;

  AiProviderCoreSettings copyWith({
    bool? enabled,
    String? endpoint,
    String? appId,
    String? apiKey,
    String? apiSecret,
    String? accessToken,
    String? region,
    String? modelConfigId,
    String? modelId,
    Map<String, Object?>? extra,
  }) {
    return AiProviderCoreSettings(
      enabled: enabled ?? this.enabled,
      endpoint: endpoint ?? this.endpoint,
      appId: appId ?? this.appId,
      apiKey: apiKey ?? this.apiKey,
      apiSecret: apiSecret ?? this.apiSecret,
      accessToken: accessToken ?? this.accessToken,
      region: region ?? this.region,
      modelConfigId: modelConfigId ?? this.modelConfigId,
      modelId: modelId ?? this.modelId,
      extra: extra ?? this.extra,
    );
  }

  AiProviderCoreSettings normalizedCore({Map<String, Object?>? extra}) {
    return AiProviderCoreSettings(
      enabled: enabled,
      endpoint: endpoint.trim(),
      appId: appId.trim(),
      apiKey: apiKey.trim(),
      apiSecret: apiSecret.trim(),
      accessToken: accessToken.trim(),
      region: region.trim(),
      modelConfigId: modelConfigId.trim(),
      modelId: modelId.trim(),
      extra: Map<String, Object?>.unmodifiable(extra ?? this.extra),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'endpoint': endpoint,
      'app_id': appId,
      'api_key': apiKey,
      'api_secret': apiSecret,
      'access_token': accessToken,
      'region': region,
      'model_config_id': modelConfigId,
      'model_id': modelId,
      'extra': extra,
    };
  }
}

Map<P, S> parseAiProviderSettings<P, S>(
  Object? raw, {
  required Iterable<P> providers,
  required String Function(P provider) storageKey,
  required S Function(P provider, Object? raw) parse,
}) {
  final values = raw is Map ? raw : const <Object?, Object?>{};
  return <P, S>{
    for (final provider in providers)
      provider: parse(provider, values[storageKey(provider)]),
  };
}

List<P> parseAiProviderPriority<P>(
  Object? raw, {
  required List<P> fallback,
  required P Function(Object? raw) parse,
}) {
  final values = stringListFromValueOrJsonText(raw);
  if (values.isEmpty) return fallback;
  return values.map(parse).toSet().toList(growable: false);
}

List<P> normalizeAiProviderPriority<P>(
  Iterable<P> priority,
  Iterable<P> fallback,
) {
  return <P>{...priority, ...fallback}.toList(growable: false);
}
