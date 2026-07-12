import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../../shared/net/http_response_utils.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/text_clip.dart';

const int defaultWebFetchResponseMaxBytes = 8 * kBytesPerMiB;
const int _webFetchErrorPreviewCharacters = 2000;

class BoundedWebFetchHttpResponse {
  const BoundedWebFetchHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
    required this.requestUrl,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;
  final Uri? requestUrl;

  String text({bool allowMalformed = true}) {
    return utf8.decode(bodyBytes, allowMalformed: allowMalformed);
  }

  String errorPreview() {
    return clipTextWithEllipsis(text(), _webFetchErrorPreviewCharacters - 1);
  }
}

Future<BoundedWebFetchHttpResponse> sendBoundedWebFetchRequest({
  required http.Client client,
  required http.BaseRequest request,
  required Duration connectionTimeout,
  required Duration responseTimeout,
  int maxBytes = defaultWebFetchResponseMaxBytes,
}) async {
  if (connectionTimeout <= Duration.zero) {
    throw ArgumentError.value(
      connectionTimeout,
      'connectionTimeout',
      'Must be positive.',
    );
  }
  final streamed = await client.send(request).timeout(connectionTimeout);
  return collectBoundedWebFetchResponse(
    streamed,
    responseTimeout: responseTimeout,
    maxBytes: maxBytes,
  );
}

Future<BoundedWebFetchHttpResponse> collectBoundedWebFetchResponse(
  http.StreamedResponse response, {
  required Duration responseTimeout,
  int maxBytes = defaultWebFetchResponseMaxBytes,
}) async {
  final bodyBytes = await readBoundedByteStream(
    response.stream,
    maxBytes: maxBytes,
    idleTimeout: responseTimeout,
    totalTimeout: responseTimeout,
  );
  return BoundedWebFetchHttpResponse(
    statusCode: response.statusCode,
    headers: Map<String, String>.unmodifiable(response.headers),
    bodyBytes: bodyBytes,
    requestUrl: response.request?.url,
  );
}
