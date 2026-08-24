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

  final connectionTimeoutAbort = Completer<void>();
  final abortTrigger = combineCancelSignals(<Future<void>?>[
    cancelSignal,
    connectionTimeoutAbort.future,
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

  return client
      .send(abortableRequest)
      .timeout(
        connectionTimeout,
        onTimeout: () {
          if (!connectionTimeoutAbort.isCompleted) {
            connectionTimeoutAbort.complete();
          }
          throw TimeoutException('HTTP 响应头获取超过连接时限。', connectionTimeout);
        },
      );
}
