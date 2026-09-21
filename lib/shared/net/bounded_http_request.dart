import 'dart:async';
import 'dart:io';

import '../util/argument_guards.dart';
import '../util/async_concurrency.dart';
import 'network_limits.dart';

/// 在限定时限内打开 HTTP 请求；打开超时后会接管迟到的请求并主动中止。
Future<HttpClientRequest> openHttpClientRequestBounded(
  Future<HttpClientRequest> Function() open, {
  required Duration timeout,
  String timeoutMessage = 'HTTP 请求打开超时。',
}) async {
  requirePositiveDurationAtMost(
    timeout,
    kOpenHandMaxNetworkOperationTimeout,
    'timeout',
  );
  final openFuture = Future<HttpClientRequest>.sync(open);
  try {
    return await openFuture.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(timeoutMessage, timeout),
    );
  } on TimeoutException {
    unawaited(
      openFuture.then<void>(
        abortHttpClientRequest,
        onError: (Object _, StackTrace _) {},
      ),
    );
    rethrow;
  }
}

/// 在限定时限内获取响应头；超时后中止请求并释放迟到响应体。
Future<HttpClientResponse> closeHttpClientRequestBounded(
  HttpClientRequest request, {
  required Duration timeout,
  String timeoutMessage = 'HTTP 响应头获取超时。',
}) async {
  requirePositiveDurationAtMost(
    timeout,
    kOpenHandMaxNetworkOperationTimeout,
    'timeout',
  );
  final closeFuture = Future<HttpClientResponse>.sync(request.close);
  return closeFuture.timeout(
    timeout,
    onTimeout: () {
      final error = TimeoutException(timeoutMessage, timeout);
      abortHttpClientRequest(request, reason: error);
      unawaited(
        closeFuture.then<void>((response) async {
          await runAsyncCleanupBounded(() => response.listen(null).cancel());
        }, onError: (Object _, StackTrace _) {}),
      );
      throw error;
    },
  );
}

/// 尽力中止请求，避免关闭阶段的异常覆盖原始错误。
void abortHttpClientRequest(
  HttpClientRequest request, {
  Object? reason,
  StackTrace? stackTrace,
}) {
  try {
    if (reason == null) {
      request.abort();
    } else {
      request.abort(reason, stackTrace);
    }
  } catch (_) {
    // 请求已进入关闭流程时 abort 可能同步失败，不能覆盖原始超时。
  }
}
