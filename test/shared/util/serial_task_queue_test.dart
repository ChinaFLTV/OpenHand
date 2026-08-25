import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/serial_task_queue.dart';

void main() {
  group('LatestTaskQueue', () {
    test('当前任务失败后仍继续执行最新任务', () async {
      final queue = LatestTaskQueue();
      final gate = Completer<void>();
      var executed = 0;

      final failed = queue.enqueue(() async {
        await gate.future;
        throw StateError('模拟任务失败');
      });
      final next = queue.enqueue(() async {
        executed += 1;
      });

      gate.complete();

      await expectLater(failed, throwsStateError);
      await expectLater(next, completion(isTrue));
      await queue.idle;

      expect(executed, 1);
    });

    test('丢弃待执行任务后不会再次调度', () async {
      final queue = LatestTaskQueue();
      final gate = Completer<void>();
      var executed = 0;

      final running = queue.enqueue(() async {
        await gate.future;
      });
      final pending = queue.enqueue(() async {
        executed += 1;
      });

      queue.discardPending();
      gate.complete();

      await expectLater(running, completion(isTrue));
      await expectLater(pending, completion(isFalse));
      await queue.idle;

      expect(executed, 0);
    });
  });
}
