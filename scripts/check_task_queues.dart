import 'dart:async';
import 'dart:io';

import 'package:openhand/shared/util/serial_task_queue.dart';

Future<void> main() async {
  await _checkSerialOrderAndRecovery();
  await _checkCloseWhileBlocked();
  await _checkReentrantClose();
  await _checkDrainAndClose();
  await _checkKeyedParallelism();
  await _checkKeyedClose();
  await _checkLatestTaskReplacement();
  stdout.writeln('[异步队列检查] 通过。');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Object> _failure(Future<Object?> future) async {
  try {
    await future;
  } catch (error) {
    return error;
  }
  throw StateError('预期任务失败，实际成功。');
}

Future<void> _checkSerialOrderAndRecovery() async {
  final queue = SerialTaskQueue(maxPendingTasks: 3);
  final release = Completer<void>();
  final order = <int>[];
  final first = queue.enqueue(() async {
    order.add(1);
    await release.future;
    return 1;
  });
  final failed = _failure(
    queue.enqueue<int>(() {
      order.add(2);
      throw StateError('模拟任务失败');
    }),
  );
  final third = queue.enqueue(() async {
    order.add(3);
    return 3;
  });
  final overflow = await _failure(queue.enqueue(() async => -1));
  _expect(overflow is StateError, '容量耗尽时必须拒绝新任务。');
  release.complete();
  _expect(await first == 1 && await third == 3, '串行任务必须保留真实返回值。');
  _expect(await failed is StateError, '任务异常必须交给调用方。');
  await queue.idle;
  _expect(order.join(',') == '1,2,3', '失败不能改变顺序或阻塞后续任务。');
  _expect(await queue.enqueue(() async => 4) == 4, '任务结束后必须释放容量。');
}

Future<void> _checkCloseWhileBlocked() async {
  final queue = SerialTaskQueue(maxPendingTasks: 3);
  final started = Completer<void>();
  final release = Completer<int>();
  final active = queue.enqueue(() {
    started.complete();
    return release.future;
  });
  var calls = 0;
  final waiting = List.generate(
    2,
    (_) => _failure(queue.enqueue(() async => ++calls)),
  );
  await started.future;
  final reason = StateError('模拟所有者关闭');
  queue.close(reason);
  queue.close(StateError('重复关闭不能覆盖原始原因'));
  for (final error in await Future.wait(
    waiting,
  ).timeout(const Duration(seconds: 1))) {
    _expect(identical(error, reason), '未开始的任务必须立即收到原始关闭原因。');
  }
  _expect(
    identical(await _failure(queue.enqueue(() async => ++calls)), reason),
    '关闭后不能继续接收任务。',
  );
  var idle = false;
  unawaited(queue.idle.then((_) => idle = true));
  await Future<void>.delayed(Duration.zero);
  _expect(!idle, '取消等待任务不能把仍在运行的任务报告为已结束。');
  release.complete(7);
  _expect(await active == 7, '关闭不能伪造运行中任务的结果。');
  await queue.idle;
  _expect(calls == 0, '被取消的任务不能在前一个任务恢复后再次执行。');
}

Future<void> _checkReentrantClose() async {
  final queue = SerialTaskQueue();
  late Future<Object> waiting;
  final first = queue.enqueue(() async {
    waiting = _failure(queue.enqueue(() async => -1));
    queue.close();
    return 1;
  });
  _expect(await first == 1, '运行任务内关闭队列不能中断自身。');
  _expect(await waiting is StateError, '同步重入排队的任务必须被取消。');
  await queue.idle;

  final immediate = SerialTaskQueue();
  final cancelled = _failure(immediate.enqueue(() async => -1));
  immediate.close();
  _expect(await cancelled is StateError, '首个任务启动前关闭也必须立即取消。');
  await immediate.idle;
}

Future<void> _checkDrainAndClose() async {
  final queue = SerialTaskQueue();
  final completed = queue.enqueue(() async => 1);
  await queue.drainAndClose(const Duration(seconds: 1));
  _expect(await completed == 1, '正常关闭必须先完成已排队任务。');
  _expect(
    await _failure(queue.enqueue(() async => 2)) is StateError,
    '排空完成后必须拒绝新任务。',
  );

  final blocked = SerialTaskQueue();
  final started = Completer<void>();
  final release = Completer<void>();
  final active = blocked.enqueue(() {
    started.complete();
    return release.future;
  });
  final pending = _failure(blocked.enqueue(() async => -1));
  await started.future;
  final closing = blocked.drainAndClose(const Duration(milliseconds: 20));
  final timeoutFailure = _failure(closing);
  _expect(
    await _failure(blocked.enqueue(() async => 2)) is StateError,
    '排空开始后必须立即拒绝新任务。',
  );
  final timeout = await timeoutFailure;
  _expect(timeout is TimeoutException, '排空超时必须保留超时原因。');
  _expect(await pending is StateError, '排空超时不能遗留等待任务。');
  release.complete();
  await active;
  await blocked.idle;
}

Future<void> _checkKeyedParallelism() async {
  final queue = KeyedSerialTaskQueue<String>(maxPendingTasks: 3);
  final release = Completer<int>();
  final first = queue.enqueue('甲', () => release.future);
  var secondStarted = false;
  final second = queue.enqueue('甲', () async {
    secondStarted = true;
    return 2;
  });
  final other = queue.enqueue('乙', () async => 3);
  final overflow = _failure(queue.enqueue('丙', () async => 4));
  _expect(await other == 3 && !secondStarted, '不同键必须并行，同键必须串行。');
  _expect(await overflow is StateError, '键控队列必须限制总任务数。');
  release.complete(1);
  _expect(await first == 1 && await second == 2, '同键必须保留任务顺序。');
  final failed = await _failure(
    queue.enqueue<int>('甲', () => throw StateError('模拟同步失败')),
  );
  _expect(failed is StateError, '键控任务必须转交同步异常。');
  _expect(await queue.enqueue('甲', () async => 5) == 5, '失败后同键必须可再次执行。');
}

Future<void> _checkKeyedClose() async {
  final queue = KeyedSerialTaskQueue<String>(maxPendingTasks: 4);
  final started = Completer<void>();
  final release = Completer<int>();
  var idleNotifications = 0;
  var pendingCalls = 0;
  final active = queue.enqueue('甲', () {
    started.complete();
    return release.future;
  }, onIdle: () => idleNotifications++);
  final pending = _failure(
    queue.enqueue(
      '甲',
      () async => ++pendingCalls,
      onIdle: () => idleNotifications++,
    ),
  );
  final other = queue.enqueue(
    '乙',
    () async => 2,
    onIdle: () => idleNotifications++,
  );
  await started.future;
  _expect(await other == 2, '关闭前完成的其他键不能受阻塞键影响。');
  await Future<void>.delayed(Duration.zero);
  _expect(queue.containsKey('甲') && !queue.containsKey('乙'), '只保留仍有任务的键。');
  _expect(idleNotifications == 1, '同键队列未排空时不能触发空闲回调。');
  final reason = StateError('模拟会话关闭');
  queue.close(reason);
  queue.close();
  _expect(identical(await pending, reason), '阻塞键的等待任务必须立即收到关闭原因。');
  _expect(
    identical(await _failure(queue.enqueue('丙', () async => 3)), reason),
    '键控队列关闭后不能新增其他键。',
  );
  var idle = false;
  unawaited(queue.idle.then((_) => idle = true));
  await Future<void>.delayed(Duration.zero);
  _expect(!idle && queue.keys.single == '甲', '活动任务结束前必须保留真实等待状态。');
  release.complete(1);
  _expect(await active == 1, '关闭不能修改活动键的结果。');
  await queue.idle;
  _expect(queue.keys.isEmpty && pendingCalls == 0, '关闭后释放所有键且不执行取消任务。');
  _expect(idleNotifications == 2, '每个键只在本轮排空后通知一次。');
}

Future<void> _checkLatestTaskReplacement() async {
  final queue = LatestTaskQueue();
  final started = Completer<void>();
  final release = Completer<void>();
  final first = queue.enqueue(() {
    started.complete();
    return release.future;
  });
  await started.future;
  var calls = 0;
  final replaced = queue.enqueue(() async => calls += 100);
  final latest = queue.enqueue(() async => calls++);
  _expect(!await replaced, '最新任务必须替换尚未启动的旧任务。');
  release.complete();
  _expect(await first && await latest, '实际执行的任务必须报告成功。');
  await queue.idle;
  _expect(calls == 1, '被替换的任务不能执行。');
}
