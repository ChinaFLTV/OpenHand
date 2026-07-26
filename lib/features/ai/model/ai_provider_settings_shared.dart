import '../../../shared/util/input_value_parsing.dart';

class AiProviderCoreSettings {
  /// 各字段默认取“未配置”值，便于子类的出厂值构造只声明有差异的项。
  ///
  /// 子类对外暴露的构造仍应把字段重新标记为 `required`，避免调用方漏填凭据。
  const AiProviderCoreSettings({
    this.enabled = false,
    this.endpoint = '',
    this.appId = '',
    this.apiKey = '',
    this.apiSecret = '',
    this.accessToken = '',
    this.region = '',
    this.modelConfigId = '',
    this.modelId = '',
    this.extra = const <String, Object?>{},
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

/// 提供商映射与优先级的落库形态，供设置类的 `toJson` 展开。
///
/// 解析侧早有 [parseAiProviderSettings] / [parseAiProviderPriority]，序列化侧
/// 却由各设置类各写一遍相同的两个键，键名只靠人工对齐——改错一处就是存进去
/// 读不回来。补上这一半让两侧同源。
Map<String, Object?> aiProviderSettingsToJson<P, S>({
  required Map<P, S> providers,
  required List<P> priority,
  required String Function(P provider) storageKey,
  required Map<String, Object?> Function(S settings) toJson,
}) {
  return <String, Object?>{
    'provider_priority': priority.map(storageKey).toList(growable: false),
    'providers': <String, Object?>{
      for (final entry in providers.entries)
        storageKey(entry.key): toJson(entry.value),
    },
  };
}
