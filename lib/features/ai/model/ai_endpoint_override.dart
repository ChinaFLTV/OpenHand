import '../../../shared/util/input_value_parsing.dart';
import 'ai_api_family.dart';

class AiEndpointOverride {
  const AiEndpointOverride({
    this.path,
    this.url,
    this.method,
    this.transport,
    this.headers = const <String, String>{},
    this.queryDefaults = const <String, String>{},
  });

  final String? path;
  final String? url;
  final String? method;
  final String? transport;
  final Map<String, String> headers;
  final Map<String, String> queryDefaults;

  bool get isEmpty =>
      (path == null || path!.trim().isEmpty) &&
      (url == null || url!.trim().isEmpty) &&
      (method == null || method!.trim().isEmpty) &&
      (transport == null || transport!.trim().isEmpty) &&
      headers.isEmpty &&
      queryDefaults.isEmpty;

  AiEndpointOverride copyWith({
    String? path,
    String? url,
    String? method,
    String? transport,
    Map<String, String>? headers,
    Map<String, String>? queryDefaults,
    bool clearPath = false,
    bool clearUrl = false,
    bool clearMethod = false,
    bool clearTransport = false,
  }) {
    return AiEndpointOverride(
      path: clearPath ? null : (path ?? this.path),
      url: clearUrl ? null : (url ?? this.url),
      method: clearMethod ? null : (method ?? this.method),
      transport: clearTransport ? null : (transport ?? this.transport),
      headers: headers ?? this.headers,
      queryDefaults: queryDefaults ?? this.queryDefaults,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (path != null && path!.trim().isNotEmpty) 'path': path,
      if (url != null && url!.trim().isNotEmpty) 'url': url,
      if (method != null && method!.trim().isNotEmpty) 'method': method,
      if (transport != null && transport!.trim().isNotEmpty)
        'transport': transport,
      if (headers.isNotEmpty) 'headers': headers,
      if (queryDefaults.isNotEmpty) 'query_defaults': queryDefaults,
    };
  }

  static AiEndpointOverride? fromJson(Object? raw) {
    final json = _mapFromValueOrJsonText(raw);
    if (json == null) return null;
    return AiEndpointOverride(
      path: optionalStringFromValue(json['path']),
      url: optionalStringFromValue(json['url']),
      method: optionalStringFromValue(json['method']),
      transport: optionalStringFromValue(json['transport']),
      headers: _parseStringMap(json['headers']),
      queryDefaults: _parseStringMap(json['query_defaults']),
    );
  }

  static Map<String, String> _parseStringMap(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      final key = optionalStringFromValue(entry.key);
      final value = optionalStringFromValue(entry.value);
      if (key == null || value == null) continue;
      result[key] = value;
    }
    return result;
  }
}

Map<AiApiFamily, AiEndpointOverride> parseAiEndpointOverrides(Object? raw) {
  final json = _mapFromValueOrJsonText(raw);
  if (json == null) return const <AiApiFamily, AiEndpointOverride>{};
  final result = <AiApiFamily, AiEndpointOverride>{};
  for (final entry in json.entries) {
    final family = AiApiFamily.fromStorage(entry.key.trim());
    final override = AiEndpointOverride.fromJson(entry.value);
    if (family == null || override == null || override.isEmpty) continue;
    result[family] = override;
  }
  return result;
}

Map<String, Object?>? _mapFromValueOrJsonText(Object? raw) {
  if (raw is Map) return stringKeyedMapFromValue(raw);
  if (raw is String) return optionalStringKeyedMapFromJsonText(raw);
  return null;
}

Map<String, Object?> aiEndpointOverridesToJson(
  Map<AiApiFamily, AiEndpointOverride> overrides,
) {
  final result = <String, Object?>{};
  for (final entry in overrides.entries) {
    if (!entry.value.isEmpty) {
      result[entry.key.storageValue] = entry.value.toJson();
    }
  }
  return result;
}
