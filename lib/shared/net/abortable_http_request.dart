import 'dart:async';

import 'package:http/http.dart' as http;

import '../util/argument_guards.dart';
import '../util/async_concurrency.dart';
import 'network_limits.dart';

/// 外部取消或 [http.AbortableRequest.abortTrigger] 中止请求。
bool isHttpRequestAborted(Object error) {
  if (error is http.RequestAbortedException) return true;
  if (error is! http.ClientException) return false;
  final message = error.message.toLowerCase();
  return message.contains('aborted') && message.contains('aborttrigger');
}

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
  if (cancelSignal != null && await isCancelSignalCompleted(cancelSignal)) {
    throw http.RequestAbortedException(request.url);
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

  final responseFuture = Future<http.StreamedResponse>.sync(
    () => client.send(abortableRequest),
  );
  try {
    final response =
        await awaitWithCancelSignal(
          responseFuture,
          cancelSignal: abortTrigger,
        ).timeout(
          connectionTimeout,
          onTimeout: () {
            throw TimeoutException('HTTP 响应头获取超过连接时限。', connectionTimeout);
          },
        );
    if (response == null) throw http.RequestAbortedException(request.url);
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
    // 自定义传输可能忽略取消或超时，失败后统一释放迟到响应体。
    unawaited(
      responseFuture.then<void>((response) async {
        await runAsyncCleanupBounded(
          () => response.stream.listen(null).cancel(),
        );
      }, onError: (Object _, StackTrace _) {}),
    );
    rethrow;
  }
}

Stream<List<int>> _trackResponseLifetime(
  Stream<List<int>> stream,
  Completer<void> lifetime,
) {
  void release() {
    // 当前事件收尾后再中止请求，避免最后一块数据被误判为取消。
    scheduleMicrotask(() {
      if (!lifetime.isCompleted) lifetime.complete();
    });
  }

  late final StreamController<List<int>> controller;
  StreamSubscription<List<int>>? subscription;
  controller = StreamController<List<int>>(
    sync: true,
    onListen: () {
      // 同步接管底层流，保证订阅后立即取消也能释放资源。
      try {
        subscription = stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            release();
            unawaited(controller.close());
          },
        );
      } catch (error, stack) {
        release();
        controller.addError(error, stack);
        unawaited(controller.close());
      }
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () {
      release();
      return subscription?.cancel();
    },
  );
  return controller.stream;
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
