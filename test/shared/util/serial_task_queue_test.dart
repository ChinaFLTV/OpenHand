import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/serial_task_queue.dart';

void main() {
  test(
    'tasks run in FIFO order and a failure does not poison the queue',
    () async {
      final queue = SerialTaskQueue();
      final releaseFirst = Completer<void>();
      final order = <String>[];

      final first = queue.enqueue(() async {
        order.add('first:start');
        await releaseFirst.future;
        order.add('first:end');
        return 1;
      });
      final second = queue.enqueue<int>(() async {
        order.add('second');
        throw StateError('expected');
      });
      final third = queue.enqueue(() async {
        order.add('third');
        return 3;
      });
      final secondExpectation = expectLater(second, throwsStateError);

      await Future<void>.delayed(Duration.zero);
      expect(order, <String>['first:start']);

      releaseFirst.complete();
      expect(await first, 1);
      await secondExpectation;
      expect(await third, 3);
      expect(order, <String>['first:start', 'first:end', 'second', 'third']);
    },
  );
}
