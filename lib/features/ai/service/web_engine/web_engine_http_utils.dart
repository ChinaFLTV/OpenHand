import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../../shared/net/abortable_http_request.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_response_utils.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/text_clip.dart';
import 'web_engine_http_exception.dart';
import 'web_engine_json_utils.dart';

const int defaultWebEngineResponseMaxBytes = 8 * kBytesPerMiB;
const int _webEngineErrorPreviewCharacters = 2000;

/// WebSearch 与 WebFetch 共用浏览器标识，保持站点访问行为一致。
const String kWebEngineSafariUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Version/17.0 Safari/605.1.15';

const String kWebEngineChromeUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/121.0 Safari/537.36';

class BoundedWebEngineHttpResponse {
  const BoundedWebEngineHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
    required this.requestUrl,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;
  final Uri? requestUrl;

  String get body => text();

  String text({bool allowMalformed = true}) {
    return utf8.decode(bodyBytes, allowMalformed: allowMalformed);
  }

  String errorPreview() {
    return clipTextWithEllipsis(text(), _webEngineErrorPreviewCharacters);
  }
}

/// 校验成功状态并将响应解析为 JSON 对象，统一保留错误预览和来源信息。
Map<String, Object?> decodeSuccessfulWebEngineJsonResponse(
  BoundedWebEngineHttpResponse response, {
  required String engineLabel,
  String? source,
}) {
  if (response.statusCode != HttpStatus.ok) {
    throw WebEngineHttpException(
      '$engineLabel ${response.statusCode}: ${response.errorPreview()}',
    );
  }
  return decodeJsonObjectBytes(
    response.bodyBytes,
    source: source ?? '$engineLabel response',
  );
}

mixin BoundedWebEngineHttpClient {
  http.Client get httpClient;
  Duration get fetchTimeout;

  Future<BoundedWebEngineHttpResponse> sendWebEngineHttpRequest(
    String method,
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    String? body,
    Future<void>? cancelSignal,
    int maxBytes = defaultWebEngineResponseMaxBytes,
  }) {
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = body;
    final connectionTimeout = fetchTimeout < const Duration(seconds: 10)
        ? fetchTimeout
        : const Duration(seconds: 10);
    return sendBoundedWebEngineRequest(
      client: httpClient,
      request: request,
      connectionTimeout: connectionTimeout,
      responseTimeout: fetchTimeout,
      cancelSignal: cancelSignal,
      maxBytes: maxBytes,
    );
  }
}

/// Grok Live Search 调用使用的模型名与端点。
const String kGrokLiveSearchModel = 'grok-4-latest';
const String kGrokChatCompletionsEndpoint =
    'https://api.x.ai/v1/chat/completions';

/// WebSearch 与 WebFetch 共用的 Grok Live Search 请求。
extension GrokLiveSearchRequest on BoundedWebEngineHttpClient {
  Future<Map<String, Object?>> requestGrokLiveSearch({
    required String? apiKey,
    required String systemPrompt,
    required String userPrompt,
    required int maxSearchResults,
    Future<void>? cancelSignal,
  }) async {
    final key = apiKey?.trim() ?? '';
    if (key.isEmpty) {
      throw WebEngineHttpException('Grok API key is missing');
    }
    final response = await sendWebEngineHttpRequest(
      'POST',
      Uri.parse(kGrokChatCompletionsEndpoint),
      headers: {
        kAuthorizationHeaderName: 'Bearer $key',
        kContentTypeHeaderName: kApplicationJsonMimeType,
      },
      body: jsonEncode({
        'model': kGrokLiveSearchModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'search_parameters': {
          'mode': 'on',
          'max_search_results': maxSearchResults,
          'return_citations': true,
        },
      }),
      cancelSignal: cancelSignal,
    );
    return decodeSuccessfulWebEngineJsonResponse(response, engineLabel: 'Grok');
  }
}

/// Gemini grounding 调用使用的模型名。
const String kGeminiGroundingModel = 'gemini-2.0-flash';

/// WebSearch 与 WebFetch 共用的 Gemini 搜索增强请求。
extension GeminiGroundedContentRequest on BoundedWebEngineHttpClient {
  Future<Map<String, Object?>> requestGeminiGroundedContent({
    required String? apiKey,
    required String prompt,
    Future<void>? cancelSignal,
  }) async {
    final key = apiKey?.trim() ?? '';
    if (key.isEmpty) {
      throw WebEngineHttpException('Gemini API key is missing');
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/'
      'models/$kGeminiGroundingModel:generateContent?key=$key',
    );
    final response = await sendWebEngineHttpRequest(
      'POST',
      uri,
      headers: const {kContentTypeHeaderName: kApplicationJsonMimeType},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'tools': [
          {'googleSearch': <String, Object?>{}},
        ],
      }),
      cancelSignal: cancelSignal,
    );
    return decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Gemini',
    );
  }
}

Future<BoundedWebEngineHttpResponse> sendBoundedWebEngineRequest({
  required http.Client client,
  required http.Request request,
  required Duration connectionTimeout,
  required Duration responseTimeout,
  Future<void>? cancelSignal,
  int maxBytes = defaultWebEngineResponseMaxBytes,
}) async {
  final streamed = await sendAbortableHttpRequest(
    client: client,
    request: request,
    connectionTimeout: connectionTimeout,
    cancelSignal: cancelSignal,
  );
  return collectBoundedWebEngineResponse(
    streamed,
    responseTimeout: responseTimeout,
    maxBytes: maxBytes,
  );
}

Future<BoundedWebEngineHttpResponse> collectBoundedWebEngineResponse(
  http.StreamedResponse response, {
  required Duration responseTimeout,
  int maxBytes = defaultWebEngineResponseMaxBytes,
}) async {
  final bodyBytes = await readBoundedByteStream(
    response.stream,
    maxBytes: maxBytes,
    idleTimeout: responseTimeout,
    totalTimeout: responseTimeout,
  );
  return BoundedWebEngineHttpResponse(
    statusCode: response.statusCode,
    headers: Map<String, String>.unmodifiable(response.headers),
    bodyBytes: bodyBytes,
    requestUrl: response.request?.url,
  );
}
