import 'dart:convert';

import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
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
  static const int _maxExtractedErrorMessageLength = 4000;
  static const String _emptyErrorResponseMessage = 'Empty error response.';

  static final RegExp _htmlTagPattern = RegExp(r'<[^>]*>');

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
    final token = nullIfBlank(model.token);
    if (token == null || model.authScheme == AiAuthScheme.none) {
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
    if (isHttpSuccessStatus(statusCode)) return;
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
    if (decoded is Map) return stringKeyedMapFromValue(decoded);
    return const <String, Object?>{};
  }

  static List<Object?> jsonListOrEmpty(Object? decoded) {
    if (decoded is List<Object?>) return decoded;
    if (decoded is List) return List<Object?>.from(decoded);
    return const <Object?>[];
  }

  static Map<String, Object?> stringKeyedMap(Object? raw) {
    if (raw is Map) {
      return Map<String, Object?>.from(stringKeyedMapFromValue(raw));
    }
    return const <String, Object?>{};
  }

  static Map<String, String> stringMap(Object? raw) {
    final map = stringKeyedMap(raw);
    if (map.isEmpty) return const <String, String>{};
    final result = <String, String>{};
    final entries = map.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in entries) {
      final key = nullIfBlank(entry.key);
      final value = optionalStringFromValue(entry.value);
      if (key == null || value == null) continue;
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
      final map = _stableJsonMap(raw);
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
    final extraBody = _stableJsonMap(extras[extrasBodyKey]);
    final directExtras = <String, Object?>{};
    final directEntries = extras.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in directEntries) {
      if (entry.key == extrasBodyKey ||
          entry.key == extrasQueryKey ||
          entry.key == extrasHeadersKey) {
        continue;
      }
      directExtras[entry.key] = _stableJsonValue(entry.value);
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

  static Map<String, Object?> _stableJsonMap(Object? raw) {
    final map = stringKeyedMap(raw);
    if (map.isEmpty) return const <String, Object?>{};
    final entries = map.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in entries) entry.key: _stableJsonValue(entry.value),
    });
  }

  static Object? _stableJsonValue(Object? value) {
    if (value is Map) {
      return _stableJsonMap(value);
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map(_stableJsonValue));
    }
    return value;
  }

  static String extractErrorMessage(String body) {
    final trimmed = nullIfBlank(body);
    if (trimmed == null) return _emptyErrorResponseMessage;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, Object?>) {
        final error = decoded['error'];
        final errorText = optionalStringFromValue(error);
        if (errorText != null) {
          return _boundedErrorMessage(errorText);
        }
        if (error is Map) {
          final map = stringKeyedMapFromValue(error);
          final message =
              optionalStringFromValue(map['message']) ??
              optionalStringFromValue(map['error']);
          if (message != null) return _boundedErrorMessage(message);
          final code = optionalStringFromValue(map['code']);
          if (code != null) return _boundedErrorMessage(code);
        }
        final message =
            optionalStringFromValue(decoded['message']) ??
            optionalStringFromValue(decoded['error_description']);
        if (message != null) return _boundedErrorMessage(message);
      }
    } catch (_) {
      // Plain text or HTML error response.
    }
    if (trimmed.contains('<html') || trimmed.contains('<HTML')) {
      final stripped = collapseInlineWhitespace(
        trimmed.replaceAll(_htmlTagPattern, ' '),
      );
      return _boundedErrorMessage(stripped.isEmpty ? trimmed : stripped);
    }
    return _boundedErrorMessage(trimmed);
  }

  static String _boundedErrorMessage(String message) {
    final normalized = collapseInlineWhitespace(message);
    return clipText(normalized, _maxExtractedErrorMessageLength);
  }
}
