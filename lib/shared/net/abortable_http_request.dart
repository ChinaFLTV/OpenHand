import 'dart:async';

import 'package:http/http.dart' as http;

import '../util/argument_guards.dart';
import '../util/async_concurrency.dart';
import 'network_limits.dart';

/// 将普通 package:http 请求作为 [http.AbortableRequest] 发送。
///
/// 外部取消会中止响应头获取及后续响应流；响应头超时也会终止底层 I/O，
/// 而不是只解除调用方等待。
Future<http.StreamedResponse> sendAbortableHttpRequest({
  required http.Client client,
  required http.Request request,
  required Duration connectionTimeout,
  Future<void>? cancelSignal,
}) async {
  requirePositiveDurationAtMost(
    connectionTimeout,
    kOpenHandMaxNetworkOperationTimeout,
    'connectionTimeout',
  );
  if (request.finalized) {
    throw StateError('不能重复发送已完成构建的 HTTP 请求。');
  }

  final requestLifetime = Completer<void>();
  final abortTrigger = combineCancelSignals(<Future<void>?>[
    cancelSignal,
    requestLifetime.future,
  ])!;
  final abortableRequest =
      http.AbortableRequest(
          request.method,
          request.url,
          abortTrigger: abortTrigger,
        )
        ..headers.addAll(request.headers)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection
        ..bodyBytes = request.bodyBytes;

  try {
    final response = await client
        .send(abortableRequest)
        .timeout(
          connectionTimeout,
          onTimeout: () {
            if (!requestLifetime.isCompleted) {
              requestLifetime.complete();
            }
            throw TimeoutException('HTTP 响应头获取超过连接时限。', connectionTimeout);
          },
        );
    final responseUrl = response is http.BaseResponseWithUrl
        ? (response as http.BaseResponseWithUrl).url
        : request.url;
    return _OpenHandAbortableStreamedResponse(
      _trackResponseLifetime(response.stream, requestLifetime),
      response.statusCode,
      url: responseUrl,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  } catch (_) {
    if (!requestLifetime.isCompleted) requestLifetime.complete();
    rethrow;
  }
}

Stream<List<int>> _trackResponseLifetime(
  Stream<List<int>> stream,
  Completer<void> lifetime,
) async* {
  try {
    yield* stream;
  } finally {
    if (!lifetime.isCompleted) lifetime.complete();
  }
}

final class _OpenHandAbortableStreamedResponse extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _OpenHandAbortableStreamedResponse(
    super.stream,
    super.statusCode, {
    required this.url,
    super.contentLength,
    super.request,
    super.headers,
    super.isRedirect,
    super.persistentConnection,
    super.reasonPhrase,
  });

  @override
  final Uri url;
}
