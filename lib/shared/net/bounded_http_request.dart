import 'dart:async';
import 'dart:io';

import '../util/argument_guards.dart';
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

/// 在限定时限内关闭 HTTP 请求；响应头超时后立即中止底层请求。
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
  try {
    return await closeFuture.timeout(
      timeout,
      onTimeout: () {
        final error = TimeoutException(timeoutMessage, timeout);
        abortHttpClientRequest(request, reason: error);
        throw error;
      },
    );
  } on TimeoutException {
    // timeout Future 会继续监听迟到的 close 结果；这里仅确保请求已中止。
    rethrow;
  }
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
