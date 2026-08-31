import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/serial_task_queue.dart';

void main() {
  test('串行队列保持顺序且单项失败不阻塞后续任务', () async {
    final queue = SerialTaskQueue();
    final order = <int>[];
    final first = queue.enqueue(() async {
      order.add(1);
      throw StateError('预期失败');
    });
    final second = queue.enqueue(() async {
      order.add(2);
      return 2;
    });

    await expectLater(first, throwsStateError);
    expect(await second, 2);
    await queue.idle;
    expect(order, <int>[1, 2]);
  });

  test('串行队列达到容量后立即拒绝新任务', () async {
    final queue = SerialTaskQueue(maxPendingTasks: 1);
    final gate = Completer<void>();
    final active = queue.enqueue(() => gate.future);

    await expectLater(queue.enqueue(() async {}), throwsA(isA<StateError>()));
    gate.complete();
    await active;
  });

  test('最新任务队列丢弃尚未开始的旧任务', () async {
    final queue = LatestTaskQueue();
    final gate = Completer<void>();
    final order = <int>[];
    final active = queue.enqueue(() async {
      order.add(1);
      await gate.future;
    });
    final discarded = queue.enqueue(() async => order.add(2));
    final latest = queue.enqueue(() async => order.add(3));

    expect(await discarded, isFalse);
    gate.complete();
    expect(await active, isTrue);
    expect(await latest, isTrue);
    await queue.idle;
    expect(order, <int>[1, 3]);
  });

  test('键控队列仅串行化相同键', () async {
    final queue = KeyedSerialTaskQueue<String>();
    final gate = Completer<void>();
    final events = <String>[];
    final firstA = queue.enqueue('a', () async {
      events.add('a1-start');
      await gate.future;
      events.add('a1-end');
    });
    final secondA = queue.enqueue('a', () async => events.add('a2'));
    final firstB = queue.enqueue('b', () async => events.add('b1'));

    await firstB;
    expect(events, <String>['a1-start', 'b1']);
    gate.complete();
    await Future.wait<void>(<Future<void>>[firstA, secondA]);
    expect(events, <String>['a1-start', 'b1', 'a1-end', 'a2']);
  });
}
