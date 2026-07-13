import 'dart:convert';
import 'dart:io';

import '../../../shared/net/http_response_utils.dart';
import '../../../shared/net/http_status_utils.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/text_clip.dart';

const int _qdrantErrorPreviewCharacters = 4 * 1024;

final class QdrantHttpResponse {
  const QdrantHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

final class QdrantRequestCancelledException implements Exception {
  const QdrantRequestCancelledException();
}

Future<QdrantHttpResponse> sendQdrantJsonRequest({
  required String method,
  required Uri uri,
  required Duration connectionTimeout,
  required Duration openTimeout,
  required Duration responseTimeout,
  required Duration responseIdleTimeout,
  required int maxResponseBytes,
  Map<String, Object?>? body,
  Set<int> toleratedFailureStatuses = const <int>{},
  Future<void>? cancelSignal,
}) async {
  _requirePositiveDuration(connectionTimeout, 'connectionTimeout');
  _requirePositiveDuration(openTimeout, 'openTimeout');
  _requirePositiveDuration(responseTimeout, 'responseTimeout');
  _requirePositiveDuration(responseIdleTimeout, 'responseIdleTimeout');
  if (maxResponseBytes < 1) {
    throw ArgumentError.value(
      maxResponseBytes,
      'maxResponseBytes',
      'Must be positive.',
    );
  }
  if (await isCancelSignalCompleted(cancelSignal)) {
    throw const QdrantRequestCancelledException();
  }

  final client = HttpClient()..connectionTimeout = connectionTimeout;
  Future<QdrantHttpResponse> send() async {
    final request = await client.openUrl(method, uri).timeout(openTimeout);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(responseTimeout);
    final responseBody = await readBoundedHttpResponseText(
      response,
      maxBytes: maxResponseBytes,
      idleTimeout: responseIdleTimeout,
      totalTimeout: responseTimeout,
    );
    if (isHttpFailureStatus(response.statusCode) &&
        !toleratedFailureStatuses.contains(response.statusCode)) {
      throw HttpException(
        'Qdrant ${response.statusCode}: '
        '${clipTextWithEllipsis(responseBody, _qdrantErrorPreviewCharacters)}',
        uri: uri,
      );
    }
    return QdrantHttpResponse(
      statusCode: response.statusCode,
      body: responseBody,
    );
  }

  try {
    final result = await awaitWithCancelSignal(
      send(),
      cancelSignal: cancelSignal,
    );
    if (result == null) throw const QdrantRequestCancelledException();
    return result;
  } finally {
    client.close(force: true);
  }
}

void _requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'Must be positive.');
  }
}
