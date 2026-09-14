import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/frame_coalesced_rebuild.dart';
import 'package:openhand/shared/util/serial_task_queue.dart';
import 'package:openhand/shared/util/timer_safety.dart';

void main() {
  testWidgets('静止界面主动请求帧，并合并为最新状态的一次构建', (tester) async {
    final key = GlobalKey<_RefreshProbeState>();
    await tester.pumpWidget(_RefreshProbe(key: key));
    final state = key.currentState!;
    final builds = state.builds;
    state.scheduleCoalescedRebuild(() => state.value = 1);
    state.scheduleCoalescedRebuild(() => state.value = 2);
    state.scheduleCoalescedRebuild();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(state.value, 2);
    expect(state.builds, builds + 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('组件释放后取消待执行刷新及其状态回调', (tester) async {
    final key = GlobalKey<_RefreshProbeState>();
    await tester.pumpWidget(_RefreshProbe(key: key));
    var called = false;
    // 在本帧构建前登记下一帧刷新，本帧随即卸载组件。
    tester.binding.scheduleFrameCallback((_) {
      key.currentState!.scheduleCoalescedRebuild(() => called = true);
    });
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump();
    expect(called, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('任务内部读取 idle 必须等待本轮完成', () async {
    final queue = LatestTaskQueue();
    final started = Completer<void>();
    final finish = Completer<void>();
    var becameIdle = false;
    final running = queue.enqueue(() async {
      unawaited(queue.idle.then((_) => becameIdle = true));
      started.complete();
      await finish.future;
    });
    await started.future;
    await Future<void>.delayed(Duration.zero);
    expect(becameIdle, isFalse);
    finish.complete();
    expect(await running, isTrue);
    await queue.idle;
    expect(becameIdle, isTrue);
  });

  test('最新任务替换排队任务，失败不阻塞下一项', () async {
    final queue = LatestTaskQueue();
    final finish = Completer<void>();
    final order = <int>[];
    final first = queue.enqueue(() async {
      await finish.future;
      throw StateError('模拟任务失败');
    });
    final failure = expectLater(first, throwsStateError);
    final discarded = queue.enqueue(() async => order.add(1));
    final last = queue.enqueue(() async => order.add(2));
    expect(await discarded, isFalse);
    finish.complete();
    await failure;
    expect(await last, isTrue);
    await queue.idle;
    expect(order, <int>[2]);
  });

  test('串行队列拒绝超额任务，失败后释放容量并维持顺序', () async {
    final queue = SerialTaskQueue(maxPendingTasks: 2);
    final finish = Completer<void>();
    final first = queue.enqueue(() async {
      await finish.future;
      throw StateError('模拟任务失败');
    });
    final failure = expectLater(first, throwsStateError);
    final second = queue.enqueue(() async => 2);
    await expectLater(queue.enqueue(() async => 3), throwsStateError);
    finish.complete();
    await failure;
    expect(await second, 2);
    await queue.idle;
    expect(await queue.enqueue(() async => 4), 4);
  });

  testWidgets('周期任务超时后保持互斥，真正结束后才能重试', (tester) async {
    final finish = Completer<void>();
    final errors = <Object>[];
    var calls = 0;
    final timer = startNonOverlappingPeriodicTimer(
      const Duration(milliseconds: 10),
      (_) async {
        calls += 1;
        if (calls == 1) await finish.future;
      },
      min: const Duration(milliseconds: 1),
      callbackTimeout: const Duration(milliseconds: 20),
      cancelOnCallbackTimeout: false,
      onError: (error, _) => errors.add(error),
    );
    try {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, 1);
      expect(errors.single, isA<TimeoutException>());
      finish.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(calls, 2);
    } finally {
      timer.cancel();
    }
  });
}

class _RefreshProbe extends StatefulWidget {
  const _RefreshProbe({super.key});

  @override
  State<_RefreshProbe> createState() => _RefreshProbeState();
}

class _RefreshProbeState extends State<_RefreshProbe>
    with FrameCoalescedRebuild<_RefreshProbe> {
  int value = 0;
  int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds += 1;
    return const SizedBox.shrink();
  }
}
