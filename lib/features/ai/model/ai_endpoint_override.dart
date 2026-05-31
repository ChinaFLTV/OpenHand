import 'dart:convert';

import '../../../app/support/silent_log.dart';
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
    Map<String, Object?>? json;
    if (raw is Map) {
      json = Map<String, Object?>.from(raw);
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          json = Map<String, Object?>.from(decoded);
        }
      } catch (error, stack) {
        silentLog('ai_endpoint_override', 'decode JSON string', error, stack);
      }
    }
    if (json == null) return null;
    return AiEndpointOverride(
      path: json['path'] is String ? json['path'] as String : null,
      url: json['url'] is String ? json['url'] as String : null,
      method: json['method'] is String ? json['method'] as String : null,
      transport: json['transport'] is String
          ? json['transport'] as String
          : null,
      headers: _parseStringMap(json['headers']),
      queryDefaults: _parseStringMap(json['query_defaults']),
    );
  }

  static Map<String, String> _parseStringMap(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      final key = '${entry.key}'.trim();
      final value = '${entry.value}'.trim();
      if (key.isEmpty || value.isEmpty) continue;
      result[key] = value;
    }
    return result;
  }
}

Map<AiApiFamily, AiEndpointOverride> parseAiEndpointOverrides(Object? raw) {
  if (raw is! Map) return const <AiApiFamily, AiEndpointOverride>{};
  final result = <AiApiFamily, AiEndpointOverride>{};
  for (final entry in raw.entries) {
    final family = AiApiFamily.fromStorage('${entry.key}'.trim());
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
