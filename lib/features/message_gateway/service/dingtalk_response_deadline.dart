import 'dart:async';

import '../../../shared/util/async_concurrency.dart';

/// 整轮响应共用总时限；先取消底层执行，再结束等待，禁止超时后启动后续步骤。
class DingTalkResponseDeadline {
  DingTalkResponseDeadline(Duration timeout, {required this.onTimeout})
    : _deadline = MonotonicDeadline(timeout, timeoutMessage: '钉钉 AI 响应超时。');

  final MonotonicDeadline _deadline;
  final void Function() onTimeout;
  bool _timedOut = false;

  bool get timedOut => _timedOut;

  Future<T> wait<T>(Future<T> Function() operation) {
    final remaining = _deadline.remainingOrNull();
    if (_timedOut || remaining == null) {
      return Future<T>.error(_expire());
    }
    return Future<T>.sync(
      operation,
    ).timeout(remaining, onTimeout: () => throw _expire());
  }

  TimeoutException _expire() {
    if (!_timedOut) {
      _timedOut = true;
      onTimeout();
    }
    return _deadline.timeoutException();
  }

  void dispose() => _deadline.stop();
}
