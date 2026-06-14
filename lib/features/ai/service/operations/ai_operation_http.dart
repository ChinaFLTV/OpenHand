import 'dart:convert';

import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';

final class AiOperationHttp {
  const AiOperationHttp._();

  static const String _acceptHeader = 'accept';
  static const String _authorizationHeader = 'authorization';
  static const String _contentTypeHeader = 'content-type';
  static const String _jsonMimeType = 'application/json';
  static const String _xApiKeyHeader = 'x-api-key';

  static Map<String, String> buildHeaders({
    required AiModelConfig model,
    required Map<String, String> endpointHeaders,
    bool includeJsonContentType = true,
    bool acceptJson = false,
  }) {
    final headers = <String, String>{
      if (includeJsonContentType) _contentTypeHeader: _jsonMimeType,
      if (acceptJson) _acceptHeader: _jsonMimeType,
      ...model.customHeaders,
      ...endpointHeaders,
    };
    final token = model.token.trim();
    if (token.isEmpty || model.authScheme == AiAuthScheme.none) {
      return headers;
    }
    final headerName = model.authScheme == AiAuthScheme.apiKey
        ? _xApiKeyHeader
        : _authorizationHeader;
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
        serverMessage: body,
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
}
