import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../../shared/net/abortable_http_request.dart';
import '../../../../shared/net/http_response_utils.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/text_clip.dart';

const int defaultWebEngineResponseMaxBytes = 8 * kBytesPerMiB;
const int _webEngineErrorPreviewCharacters = 2000;

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
    return clipTextWithEllipsis(text(), _webEngineErrorPreviewCharacters - 1);
  }
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
