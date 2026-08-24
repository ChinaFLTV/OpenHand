import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../shared/net/bounded_http_request.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/net/http_status_utils.dart';
import '../../../shared/util/argument_guards.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/exponential_backoff.dart';
import '../../../shared/util/text_clip.dart';

const int _qdrantErrorPreviewCharacters = 4 * kBytesPerKiB;
const int _qdrantMaxRetryCount = 20;
const int _qdrantMaxRetryBackoffMs = 10000;
const int _qdrantMaxResponseBytes = 128 * kBytesPerMiB;
const Duration _qdrantMaxRequestTimeout = Duration(hours: 24);
const int _httpTooEarlyStatusCode = 425;
const Set<int> _qdrantRetryableStatusCodes = <int>{
  HttpStatus.requestTimeout,
  _httpTooEarlyStatusCode,
  HttpStatus.tooManyRequests,
  HttpStatus.internalServerError,
  HttpStatus.badGateway,
  HttpStatus.serviceUnavailable,
  HttpStatus.gatewayTimeout,
};

final class QdrantHttpResponse {
  const QdrantHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

final class QdrantRequestCancelledException implements Exception {
  const QdrantRequestCancelledException();
}

final class QdrantHttpException extends HttpException {
  QdrantHttpException({
    required this.statusCode,
    required String responseBody,
    required Uri uri,
  }) : super(_failureMessage(statusCode, responseBody), uri: uri);

  final int statusCode;

  bool get isRetryable => _qdrantRetryableStatusCodes.contains(statusCode);

  static String _failureMessage(int statusCode, String responseBody) {
    final preview = clipTextWithEllipsis(
      responseBody.trim(),
      _qdrantErrorPreviewCharacters,
    );
    final detail = preview.isEmpty ? '响应正文为空。' : preview;
    return 'Qdrant 请求失败（HTTP $statusCode）：$detail';
  }
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
  int retryCount = 0,
  Duration retryBackoff = const Duration(milliseconds: 800),
}) async {
  requirePositiveDurationAtMost(
    connectionTimeout,
    _qdrantMaxRequestTimeout,
    'connectionTimeout',
  );
  requirePositiveDurationAtMost(
    openTimeout,
    _qdrantMaxRequestTimeout,
    'openTimeout',
  );
  requirePositiveDurationAtMost(
    responseTimeout,
    _qdrantMaxRequestTimeout,
    'responseTimeout',
  );
  requirePositiveDurationAtMost(
    responseIdleTimeout,
    _qdrantMaxRequestTimeout,
    'responseIdleTimeout',
  );
  requirePositiveIntAtMost(
    maxResponseBytes,
    _qdrantMaxResponseBytes,
    'maxResponseBytes',
  );
  if (retryCount < 0 || retryCount > _qdrantMaxRetryCount) {
    throw RangeError.range(
      retryCount,
      0,
      _qdrantMaxRetryCount,
      'retryCount',
      '必须在有效范围内。',
    );
  }
  if (retryCount > 0) {
    requirePositiveDuration(retryBackoff, 'retryBackoff');
  }
  if (await isCancelSignalCompleted(cancelSignal)) {
    throw const QdrantRequestCancelledException();
  }

  final deadline = MonotonicDeadline(
    responseTimeout,
    timeoutMessage: 'Qdrant 请求超过总时限。',
  );
  try {
    for (var attempt = 0; ; attempt += 1) {
      try {
        return await _sendQdrantJsonRequestOnce(
          method: method,
          uri: uri,
          connectionTimeout: connectionTimeout,
          openTimeout: openTimeout,
          responseIdleTimeout: responseIdleTimeout,
          maxResponseBytes: maxResponseBytes,
          body: body,
          toleratedFailureStatuses: toleratedFailureStatuses,
          cancelSignal: cancelSignal,
          deadline: deadline,
        );
      } catch (error, stackTrace) {
        if (attempt >= retryCount || !_isRetryableQdrantError(error)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        final configuredBackoffMs = retryBackoff.inMilliseconds;
        final backoff = Duration(
          milliseconds: exponentialBackoffMs(
            attempt: attempt + 1,
            baseMs: configuredBackoffMs > _qdrantMaxRetryBackoffMs
                ? _qdrantMaxRetryBackoffMs
                : configuredBackoffMs,
            capMs: _qdrantMaxRetryBackoffMs,
          ),
        );
        final remaining = deadline.remaining();
        if (backoff >= remaining) throw deadline.timeoutException();
        final cancelled = await delayUntilCancelled(
          backoff,
          cancelSignal: cancelSignal,
        );
        if (cancelled) throw const QdrantRequestCancelledException();
        deadline.remaining();
      }
    }
  } finally {
    deadline.stop();
  }
}

Future<QdrantHttpResponse> _sendQdrantJsonRequestOnce({
  required String method,
  required Uri uri,
  required Duration connectionTimeout,
  required Duration openTimeout,
  required Duration responseIdleTimeout,
  required int maxResponseBytes,
  required Map<String, Object?>? body,
  required Set<int> toleratedFailureStatuses,
  required Future<void>? cancelSignal,
  required MonotonicDeadline deadline,
}) async {
  final client = HttpClient()
    ..connectionTimeout = deadline.limit(connectionTimeout);
  Future<QdrantHttpResponse> send() async {
    final openBudget = deadline.limit(openTimeout);
    final request = await openHttpClientRequestBounded(
      () => client.openUrl(method, uri),
      timeout: openBudget,
      timeoutMessage: 'Qdrant 连接建立超时。',
    );
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final responseBudget = deadline.remaining();
    final response = await closeHttpClientRequestBounded(
      request,
      timeout: responseBudget,
      timeoutMessage: 'Qdrant 等待响应超时。',
    );
    final bodyBudget = deadline.remaining();
    final idleBudget = responseIdleTimeout < bodyBudget
        ? responseIdleTimeout
        : bodyBudget;
    final responseBody = await readBoundedHttpResponseText(
      response,
      maxBytes: maxResponseBytes,
      idleTimeout: idleBudget,
      totalTimeout: bodyBudget,
      allowMalformed: isHttpFailureStatus(response.statusCode),
    );
    if (isHttpFailureStatus(response.statusCode) &&
        !toleratedFailureStatuses.contains(response.statusCode)) {
      throw QdrantHttpException(
        statusCode: response.statusCode,
        responseBody: responseBody,
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

bool _isRetryableQdrantError(Object error) {
  if (error is QdrantHttpException) return error.isRetryable;
  return error is TimeoutException ||
      error is SocketException ||
      error is HttpException && error is! ByteStreamSizeLimitException;
}
