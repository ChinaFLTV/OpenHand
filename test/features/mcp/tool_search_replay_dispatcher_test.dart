// 2026-05-09 — `ToolSearchReplayDispatcher` 行为锁定，全部用 FakeAsync
// 控制 Timer，保证 onFire / onCancel 互斥且各自至多触发一次。
//
// 这些测试是 Phase 12 followup「把 Replay 撤销逻辑抽到独立单元测试」
// 的实现：避免再次出现 Phase 11 那种 Timer 泄漏到 dispose 后回调的隐患。

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/mcp/service/tool_search_replay_dispatcher.dart';

void main() {
  _replayLastCancelledTests();
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

  test('pendingListenable broadcasts true on schedule, false on fire', () {
    fakeAsync((async) {
      final dispatcher = ToolSearchReplayDispatcher(
        defaultWindow: const Duration(milliseconds: 100),
      );
      final transitions = <bool>[];
      dispatcher.pendingListenable
          .addListener(() => transitions.add(dispatcher.pendingListenable.value));

      dispatcher.schedule(onFire: () async {}, onCancel: () {});
      async.elapse(const Duration(milliseconds: 150));
      expect(transitions, [true, false]);
    });
  });

  test('pendingListenable broadcasts true on schedule, false on cancel', () {
    fakeAsync((async) {
      final dispatcher = ToolSearchReplayDispatcher(
        defaultWindow: const Duration(seconds: 10),
      );
      final transitions = <bool>[];
      dispatcher.pendingListenable
          .addListener(() => transitions.add(dispatcher.pendingListenable.value));

      dispatcher.schedule(onFire: () async {}, onCancel: () {});
      dispatcher.cancel();
      // Drain microtasks so the cancel branch's setter notifies.
      async.flushMicrotasks();
      expect(transitions, [true, false]);
    });
  });

  test('pendingDeadlineListenable mirrors pending bool with a real DateTime',
      () {
    fakeAsync((async) {
      final dispatcher = ToolSearchReplayDispatcher(
        defaultWindow: const Duration(milliseconds: 500),
      );
      expect(dispatcher.pendingDeadlineListenable.value, isNull);

      dispatcher.schedule(onFire: () async {}, onCancel: () {});
      final dl = dispatcher.pendingDeadlineListenable.value;
      expect(dl, isNotNull,
          reason: 'schedule should set deadline = now + window');

      async.elapse(const Duration(milliseconds: 600));
      expect(dispatcher.pendingDeadlineListenable.value, isNull,
          reason: 'after fire, deadline should clear back to null');
    });
  });

  test('pendingDeadlineListenable clears on cancel', () {
    fakeAsync((async) {
      final dispatcher = ToolSearchReplayDispatcher(
        defaultWindow: const Duration(seconds: 10),
      );
      dispatcher.schedule(onFire: () async {}, onCancel: () {});
      expect(dispatcher.pendingDeadlineListenable.value, isNotNull);
      dispatcher.cancel();
      async.flushMicrotasks();
      expect(dispatcher.pendingDeadlineListenable.value, isNull);
    });
  });
}

// ignore_for_file: lines_longer_than_80_chars

void _replayLastCancelledTests() {
  group('replayLastCancelled', () {
    test('refires the onFire that was just cancel()-ed and clears memory', () {
      fakeAsync((async) {
        final dispatcher = ToolSearchReplayDispatcher();
        var fired = 0;
        dispatcher.schedule(
          onFire: () async => fired++,
          onCancel: () {},
        );
        dispatcher.cancel();
        async.flushMicrotasks();
        expect(dispatcher.hasReplayable, isTrue);
        expect(dispatcher.replayableListenable.value, isTrue);

        // Drive the async replay through fakeAsync so we can assert on `fired`.
        var result = false;
        dispatcher.replayLastCancelled().then((v) => result = v);
        async.flushMicrotasks();
        expect(result, isTrue);
        expect(fired, 1);
        expect(dispatcher.hasReplayable, isFalse);
        expect(dispatcher.replayableListenable.value, isFalse);
      });
    });

    test('returns false when nothing has been cancelled yet', () {
      fakeAsync((async) {
        final dispatcher = ToolSearchReplayDispatcher();
        var result = true;
        dispatcher.replayLastCancelled().then((v) => result = v);
        async.flushMicrotasks();
        expect(result, isFalse);
      });
    });

    test('successful fire does NOT leave a replayable memory', () {
      fakeAsync((async) {
        final dispatcher =
            ToolSearchReplayDispatcher(defaultWindow: const Duration(seconds: 1));
        dispatcher.schedule(onFire: () async {}, onCancel: () {});
        async.elapse(const Duration(seconds: 2));
        expect(dispatcher.hasReplayable, isFalse,
            reason: 'fire path must clear replayable, only cancel persists it');
      });
    });

    test('a fresh schedule discards prior cancelled-replay memory', () {
      fakeAsync((async) {
        final dispatcher = ToolSearchReplayDispatcher();
        dispatcher.schedule(onFire: () async {}, onCancel: () {});
        dispatcher.cancel();
        async.flushMicrotasks();
        expect(dispatcher.hasReplayable, isTrue);

        dispatcher.schedule(onFire: () async {}, onCancel: () {});
        expect(dispatcher.hasReplayable, isFalse,
            reason: 'new schedule must wipe stale cancelled-replay memory');
      });
    });
  });
}
