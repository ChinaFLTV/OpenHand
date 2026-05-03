// 2026-05-09 — `ToolSearchReplayDispatcher` 行为锁定，全部用 FakeAsync
// 控制 Timer，保证 onFire / onCancel 互斥且各自至多触发一次。
//
// 这些测试是 Phase 12 followup「把 Replay 撤销逻辑抽到独立单元测试」
// 的实现：避免再次出现 Phase 11 那种 Timer 泄漏到 dispose 后回调的隐患。

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/mcp/service/tool_search_replay_dispatcher.dart';

void main() {
  test('onFire fires after window when not cancelled', () {
    fakeAsync((async) {
      final dispatcher =
          ToolSearchReplayDispatcher();
      var fired = 0;
      var cancelled = 0;
      dispatcher.schedule(
        onFire: () async => fired++,
        onCancel: () => cancelled++,
      );
      expect(dispatcher.hasPending, isTrue);

      async.elapse(const Duration(seconds: 2));
      expect(fired, 0);

      async.elapse(const Duration(seconds: 1, milliseconds: 1));
      expect(fired, 1);
      expect(cancelled, 0);
      expect(dispatcher.hasPending, isFalse);
    });
  });

  test('cancel() within window invokes onCancel and suppresses onFire', () {
    fakeAsync((async) {
      final dispatcher =
          ToolSearchReplayDispatcher();
      var fired = 0;
      var cancelled = 0;
      dispatcher.schedule(
        onFire: () async => fired++,
        onCancel: () => cancelled++,
      );

      async.elapse(const Duration(seconds: 1));
      dispatcher.cancel();
      expect(cancelled, 1);

      async.elapse(const Duration(seconds: 5));
      expect(fired, 0);
      expect(cancelled, 1);
    });
  });

  test('cancel() after fire is a no-op', () {
    fakeAsync((async) {
      final dispatcher = ToolSearchReplayDispatcher(
        defaultWindow: const Duration(milliseconds: 50),
      );
      var fired = 0;
      var cancelled = 0;
      dispatcher.schedule(
        onFire: () async => fired++,
        onCancel: () => cancelled++,
      );
      async.elapse(const Duration(milliseconds: 80));
      expect(fired, 1);

      dispatcher.cancel();
      expect(cancelled, 0);
    });
  });

  test('schedule() while pending replaces previous and silently drops it', () {
    fakeAsync((async) {
      final dispatcher =
          ToolSearchReplayDispatcher();
      var firedA = 0;
      var firedB = 0;
      var cancelledA = 0;
      var cancelledB = 0;
      dispatcher.schedule(
        onFire: () async => firedA++,
        onCancel: () => cancelledA++,
      );
      async.elapse(const Duration(seconds: 1));
      dispatcher.schedule(
        onFire: () async => firedB++,
        onCancel: () => cancelledB++,
      );
      // Original A is silently dropped (neither fired nor cancelled).
      async.elapse(const Duration(seconds: 4));
      expect(firedA, 0);
      expect(cancelledA, 0);
      expect(firedB, 1);
      expect(cancelledB, 0);
    });
  });

  test('dispose() cancels pending without firing either callback', () {
    fakeAsync((async) {
      final dispatcher =
          ToolSearchReplayDispatcher();
      var fired = 0;
      var cancelled = 0;
      dispatcher.schedule(
        onFire: () async => fired++,
        onCancel: () => cancelled++,
      );
      async.elapse(const Duration(seconds: 1));
      dispatcher.dispose();
      async.elapse(const Duration(seconds: 5));
      expect(fired, 0);
      expect(cancelled, 0);
    });
  });

  test('schedule() after dispose is a no-op', () {
    fakeAsync((async) {
      final dispatcher =
          ToolSearchReplayDispatcher();
      dispatcher.dispose();
      var fired = 0;
      dispatcher.schedule(
        onFire: () async => fired++,
        onCancel: () {},
      );
      async.elapse(const Duration(seconds: 5));
      expect(fired, 0);
      expect(dispatcher.hasPending, isFalse);
    });
  });

  test('schedule() per-call `window` overrides defaultWindow', () {
    fakeAsync((async) {
      final dispatcher = ToolSearchReplayDispatcher(
        defaultWindow: const Duration(seconds: 10),
      );
      var fired = 0;
      dispatcher.schedule(
        onFire: () async => fired++,
        onCancel: () {},
        window: const Duration(milliseconds: 200),
      );
      async.elapse(const Duration(milliseconds: 250));
      expect(fired, 1, reason: 'override should fire well before defaultWindow');
    });
  });
}
