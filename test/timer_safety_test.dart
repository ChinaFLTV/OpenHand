import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/timer_safety.dart';

void main() {
  test('周期定时器将异步回调异常交给错误处理器', () async {
    final reported = Completer<Object>();
    late final Timer timer;
    timer = startSafePeriodicTimer(
      const Duration(milliseconds: 1),
      (_) async {
        timer.cancel();
        throw StateError('异步周期任务失败');
      },
      min: const Duration(milliseconds: 1),
      max: const Duration(milliseconds: 10),
      onError: (error, stackTrace) {
        if (!reported.isCompleted) reported.complete(error);
      },
    );
    addTearDown(timer.cancel);

    await expectLater(
      reported.future.timeout(const Duration(seconds: 1)),
      completion(isA<StateError>()),
    );
  });
}
