import 'dart:convert';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';

final class AiOperationHttp {
  const AiOperationHttp._();

  static const String _acceptHeader = 'accept';
  static const String _authorizationHeader = 'authorization';
  static const String _contentTypeHeader = 'content-type';
  static const String _jsonMimeType = 'application/json';
  static const String _xApiKeyHeader = 'x-api-key';
  static const String _xGoogApiKeyHeader = 'x-goog-api-key';

  static const String extrasGlobalKey = 'global';
  static const String extrasBodyKey = 'body';
  static const String extrasQueryKey = 'query';
  static const String extrasHeadersKey = 'headers';

  static Map<String, String> buildHeaders({
    required AiModelConfig model,
    required Map<String, String> endpointHeaders,
    AiApiFamily? family,
    bool includeJsonContentType = true,
    bool acceptJson = false,
  }) {
    final extraHeaders = family == null
        ? const <String, String>{}
        : stringMap(extrasForFamily(model, family)[extrasHeadersKey]);
    final headers = <String, String>{
      if (includeJsonContentType) _contentTypeHeader: _jsonMimeType,
      if (acceptJson) _acceptHeader: _jsonMimeType,
      ...model.customHeaders,
      ...endpointHeaders,
      ...extraHeaders,
    };
    final token = model.token.trim();
    if (token.isEmpty || model.authScheme == AiAuthScheme.none) {
      return headers;
    }
    final headerName = switch (model.authScheme) {
      AiAuthScheme.apiKey when model.protocolType == AiProtocolType.gemini =>
        _xGoogApiKeyHeader,
      AiAuthScheme.apiKey => _xApiKeyHeader,
      _ => _authorizationHeader,
    };
    headers[headerName] = model.authScheme.apply(token);
    return headers;
  }

  static void throwIfFailed({
    required int statusCode,
    required String body,
    required String contextHint,
  }) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw Exception(
      AiTransportDiagnosticMessages.httpStatus(
        statusCode,
        serverMessage: extractErrorMessage(body),
        contextHint: contextHint,
      ),
    );
  }

  static Object? decodeJsonResponse(
    String body, {
    required String contextHint,
  }) {
    try {
      return jsonDecode(body);
    } on FormatException catch (error) {
      throw FormatException(
        'Invalid JSON response for $contextHint: ${error.message}',
      );
    }
  }

  static Map<String, Object?> jsonMapOrEmpty(Object? decoded) {
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    return const <String, Object?>{};
  }

  static List<Object?> jsonListOrEmpty(Object? decoded) {
    if (decoded is List<Object?>) return decoded;
    if (decoded is List) return List<Object?>.from(decoded);
    return const <Object?>[];
  }

  static Map<String, Object?> stringKeyedMap(Object? raw) {
    if (raw is Map<String, Object?>) {
      return Map<String, Object?>.from(raw);
    }
    if (raw is Map) {
      return Map<String, Object?>.from(raw);
    }
    return const <String, Object?>{};
  }

  static Map<String, String> stringMap(Object? raw) {
    final map = stringKeyedMap(raw);
    if (map.isEmpty) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in map.entries) {
      final key = entry.key.trim();
      final value = '${entry.value ?? ''}'.trim();
      if (key.isEmpty || value.isEmpty) continue;
      result[key] = value;
    }
    return result;
  }

  static Map<String, Object?> extrasForFamily(
    AiModelConfig model,
    AiApiFamily family,
  ) {
    final extras = model.operationExtras;
    if (extras.isEmpty) return const <String, Object?>{};
    final merged = <String, Object?>{};
    for (final key in <String>[extrasGlobalKey, family.storageValue]) {
      final raw = extras[key];
      final map = stringKeyedMap(raw);
      if (map.isNotEmpty) {
        merged.addAll(map);
      }
    }
    return merged;
  }

  static Map<String, Object?> mergeBodyExtras(
    AiModelConfig model,
    AiApiFamily family,
    Map<String, Object?> body,
  ) {
    final extras = extrasForFamily(model, family);
    if (extras.isEmpty) return body;
    final extraBody = stringKeyedMap(extras[extrasBodyKey]);
    final directExtras = <String, Object?>{};
    for (final entry in extras.entries) {
      if (entry.key == extrasBodyKey ||
          entry.key == extrasQueryKey ||
          entry.key == extrasHeadersKey) {
        continue;
      }
      directExtras[entry.key] = entry.value;
    }
    if (extraBody.isEmpty && directExtras.isEmpty) return body;
    return <String, Object?>{...body, ...directExtras, ...extraBody};
  }

  static Uri uriWithExtraQuery(
    String url,
    AiModelConfig model,
    AiApiFamily family,
  ) {
    final uri = Uri.parse(url);
    final query = stringMap(extrasForFamily(model, family)[extrasQueryKey]);
    if (query.isEmpty) return uri;
    return uri.replace(
      queryParameters: <String, String>{...uri.queryParameters, ...query},
    );
  }

  static String extractErrorMessage(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return 'Empty error response.';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, Object?>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return error.trim();
        }
        if (error is Map) {
          final map = Map<String, Object?>.from(error);
          final message = '${map['message'] ?? map['error'] ?? ''}'.trim();
          if (message.isNotEmpty) return message;
          final code = '${map['code'] ?? ''}'.trim();
          if (code.isNotEmpty) return code;
        }
        final message =
            '${decoded['message'] ?? decoded['error_description'] ?? ''}'
                .trim();
        if (message.isNotEmpty) return message;
      }
    } catch (_) {
      // Plain text or HTML error response.
    }
    if (trimmed.contains('<html') || trimmed.contains('<HTML')) {
      final stripped = trimmed
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return stripped.isEmpty ? trimmed : stripped;
    }
    return trimmed;
  }
}
