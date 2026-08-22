import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../shared/net/http_error_message.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';

final class AiOperationHttp {
  const AiOperationHttp._();

  static const String _jsonMimeType = kApplicationJsonMimeType;
  static const String _xApiKeyHeader = 'x-api-key';
  static const String _apiKeyHeader = 'api-key';
  static const String _xGoogApiKeyHeader = 'x-goog-api-key';
  static const Duration defaultRequestTimeout = Duration(seconds: 60);

  static const String extrasGlobalKey = 'global';
  static const String extrasBodyKey = 'body';
  static const String extrasQueryKey = 'query';
  static const String extrasHeadersKey = 'headers';

  static bool isSparkBaseUrl(String baseUrl) {
    final normalized = baseUrl.toLowerCase();
    return normalized.contains('xf-yun.com') ||
        normalized.contains('xfyun') ||
        normalized.contains('xunfei');
  }

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
      if (includeJsonContentType) kContentTypeHeaderName: _jsonMimeType,
      if (acceptJson) kAcceptHeaderName: _jsonMimeType,
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
      AiAuthScheme.apiKey
          when model.protocolType == AiProtocolType.mimo ||
              model.protocolType == AiProtocolType.dots =>
        _apiKeyHeader,
      AiAuthScheme.apiKey => _xApiKeyHeader,
      _ => kAuthorizationHeaderName,
    };
    headers[headerName] = model.authScheme.apply(token);
    return headers;
  }

  static Future<http.Response> sendJsonForFamily({
    required AiTransportClient transport,
    required AiResolvedEndpoint endpoint,
    required AiModelConfig model,
    required AiApiFamily family,
    required Map<String, Object?> body,
    required Duration timeout,
    bool includeJsonContentType = true,
    bool acceptJson = false,
    int maxResponseBytes = defaultAiTransportResponseMaxBytes,
    Future<void>? cancelSignal,
  }) {
    return transport.sendJson(
      uri: uriWithExtraQuery(endpoint.url, model, family),
      method: endpoint.method,
      headers: buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: family,
        includeJsonContentType: includeJsonContentType,
        acceptJson: acceptJson,
      ),
      body: body,
      timeout: timeout,
      maxResponseBytes: maxResponseBytes,
      cancelSignal: cancelSignal,
    );
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

  static Object? decodeSuccessfulJsonResponse({
    required int statusCode,
    required String body,
    required String contextHint,
  }) {
    throwIfFailed(statusCode: statusCode, body: body, contextHint: contextHint);
    return decodeJsonResponse(body, contextHint: contextHint);
  }

  static Map<String, Object?> decodeSuccessfulJsonMap({
    required int statusCode,
    required String body,
    required String contextHint,
  }) {
    return jsonMapOrEmpty(
      decodeSuccessfulJsonResponse(
        statusCode: statusCode,
        body: body,
        contextHint: contextHint,
      ),
    );
  }

  /// Throws when a provider reports an application-level failure inside a
  /// successful HTTP response. MiniMax consistently returns these failures in
  /// `base_resp.status_code`, so checking only the HTTP status would otherwise
  /// turn a useful provider error into a misleading "empty payload" error.
  static void throwIfProviderFailed(
    Map<String, Object?> payload, {
    required String contextHint,
  }) {
    final baseResponse = stringKeyedMap(payload['base_resp']);
    if (baseResponse.isEmpty) return;
    final statusCode = optionalIntFromValue(baseResponse['status_code']);
    if (statusCode == null || statusCode == 0) return;
    final message =
        optionalStringFromValue(baseResponse['status_msg']) ??
        optionalStringFromValue(payload['message']) ??
        'Provider request failed.';
    throw Exception('$contextHint failed ($statusCode): $message');
  }

  static Map<String, Object?> jsonMapOrEmpty(Object? decoded) {
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return stringKeyedMapFromValue(decoded);
    return const <String, Object?>{};
  }

  static Map<String, Object?> stringKeyedMap(Object? raw) {
    if (raw is Map) {
      return Map<String, Object?>.from(stringKeyedMapFromValue(raw));
    }
    return const <String, Object?>{};
  }

  /// 合并对象字段，并仅对指定键递归合并子对象。
  static Map<String, Object?> deepMergeObjectMaps(
    Map<String, Object?> defaults,
    Map<String, Object?> overrides, {
    required Set<String> deepMergeKeys,
  }) {
    if (defaults.isEmpty) return overrides;
    if (overrides.isEmpty) return Map<String, Object?>.from(defaults);
    final merged = Map<String, Object?>.from(defaults);
    for (final entry in overrides.entries) {
      final defaultMap = stringKeyedMap(merged[entry.key]);
      final overrideMap = stringKeyedMap(entry.value);
      if (deepMergeKeys.contains(entry.key) &&
          defaultMap.isNotEmpty &&
          overrideMap.isNotEmpty) {
        merged[entry.key] = deepMergeObjectMaps(
          defaultMap,
          overrideMap,
          deepMergeKeys: deepMergeKeys,
        );
      } else {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
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
    final merged = <String, Object?>{...body, ...directExtras};
    // OpenAI 官方协议不允许同时提交两种输出 token 字段，优先保留调用方明确传入的新版字段。
    if (merged['max_completion_tokens'] != null &&
        merged['max_tokens'] != null) {
      if (directExtras.containsKey('max_completion_tokens') ||
          !directExtras.containsKey('max_tokens')) {
        merged.remove('max_tokens');
      } else {
        merged.remove('max_completion_tokens');
      }
    }
    // 官方请求体中的 generationConfig/text/reasoning 等对象通常只覆盖
    // 其中一两个字段；递归合并可保留适配器已经计算出的安全默认值。
    final result = deepMergeObjectMaps(
      merged,
      <String, Object?>{...directExtras, ...extraBody},
      deepMergeKeys: const <String>{
        'generationConfig',
        'generation_config',
        'text',
        'reasoning',
        'response_format',
      },
    );
    if (result['max_completion_tokens'] != null &&
        result['max_tokens'] != null) {
      if (directExtras.containsKey('max_completion_tokens') ||
          extraBody.containsKey('max_completion_tokens') ||
          !directExtras.containsKey('max_tokens')) {
        result.remove('max_tokens');
      } else {
        result.remove('max_completion_tokens');
      }
    }
    return result;
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
    return extractApiErrorMessage(body);
  }
}
