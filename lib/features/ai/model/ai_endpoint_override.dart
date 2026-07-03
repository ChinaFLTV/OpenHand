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
      nullIfBlank(path) == null &&
      nullIfBlank(url) == null &&
      nullIfBlank(method) == null &&
      nullIfBlank(transport) == null &&
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
    final json = <String, Object?>{};
    _putIfNotBlank(json, 'path', path);
    _putIfNotBlank(json, 'url', url);
    _putIfNotBlank(json, 'method', method);
    _putIfNotBlank(json, 'transport', transport);
    if (headers.isNotEmpty) json['headers'] = headers;
    if (queryDefaults.isNotEmpty) json['query_defaults'] = queryDefaults;
    return json;
  }

  static AiEndpointOverride? fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
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

  static void _putIfNotBlank(
    Map<String, Object?> json,
    String key,
    String? value,
  ) {
    final normalized = nullIfBlank(value);
    if (normalized != null) json[key] = normalized;
  }
}

Map<AiApiFamily, AiEndpointOverride> parseAiEndpointOverrides(Object? raw) {
  final json = optionalStringKeyedMapFromValueOrJsonText(raw);
  if (json == null) return const <AiApiFamily, AiEndpointOverride>{};
  final result = <AiApiFamily, AiEndpointOverride>{};
  for (final entry in json.entries) {
    final family = AiApiFamily.fromStorage(optionalStringFromValue(entry.key));
    final override = AiEndpointOverride.fromJson(entry.value);
    if (family == null || override == null || override.isEmpty) continue;
    result[family] = override;
  }
  return result;
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
