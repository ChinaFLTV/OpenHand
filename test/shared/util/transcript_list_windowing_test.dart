import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/html_webview_mount_limiter.dart';
import 'package:openhand/shared/util/transcript_list_windowing.dart';

void main() {
  group('TranscriptListWindowing', () {
    test('initial window is full list below threshold', () {
      expect(TranscriptListWindowing.initialWindowStartIndex(10), 0);
      expect(TranscriptListWindowing.initialWindowStartIndex(12), 0);
    });

    test('initial window keeps a bounded latest tail for large N', () {
      const n = 1000;
      final start = TranscriptListWindowing.initialWindowStartIndex(n);
      expect(start, n - 8);
      expect(TranscriptListWindowing.visibleCount(n, start), 8);
      expect(start, greaterThan(0));
    });

    test('initial window for N=200 stays within open-path bound', () {
      final start = TranscriptListWindowing.initialWindowStartIndex(200);
      final visible = TranscriptListWindowing.visibleCount(200, start);
      expect(
        visible,
        lessThanOrEqualTo(TranscriptListWindowing.defaultInitialWindowSize),
      );
      expect(visible, greaterThan(0));
      expect(start, TranscriptListWindowing.clampWindowStart(start, 200));
    });

    test('clamp and open first-paint tail math', () {
      expect(TranscriptListWindowing.clampWindowStart(-3, 50), 0);
      expect(TranscriptListWindowing.clampWindowStart(80, 50), 50);
      expect(TranscriptListWindowing.clampWindowStart(12, 50), 12);

      expect(TranscriptListWindowing.openFirstPaintStartIndex(3), 0);
      expect(TranscriptListWindowing.openFirstPaintStartIndex(20), 16);
      final firstPaintVisible =
          20 - TranscriptListWindowing.openFirstPaintStartIndex(20);
      expect(firstPaintVisible, 4);
    });

    test('history prepend and reveal-older adjust window start', () {
      expect(
        TranscriptListWindowing.windowStartAfterHistoryPrepend(
          previousWindowStart: 40,
          addedDisplayCount: 12,
        ),
        46,
      );
      expect(TranscriptListWindowing.revealOlderWindowStart(18), 12);
      expect(TranscriptListWindowing.revealOlderWindowStart(3), 0);
    });

    test('open-path cap never materializes more than max rows', () {
      const count = 500;
      final preferred = TranscriptListWindowing.initialWindowStartIndex(count);
      final capped = TranscriptListWindowing.cappedWindowStart(
        preferredWindowStart: 0,
        messageCount: count,
      );
      expect(TranscriptListWindowing.visibleCount(count, capped), 48);
      expect(
        TranscriptListWindowing.visibleCount(
          count,
          TranscriptListWindowing.cappedWindowStart(
            preferredWindowStart: preferred,
            messageCount: count,
          ),
        ),
        lessThanOrEqualTo(48),
      );
    });

    test('warmup budget is bounded and non-zero', () {
      final budget = TranscriptListWindowing.warmupMessageBudget();
      expect(budget, inInclusiveRange(1, 8));
    });
  });

  group('HtmlWebViewMountLimiter', () {
    test('grants at most maxMounted concurrent permits immediately', () {
      final limiter = HtmlWebViewMountLimiter();

      final a = limiter.request(() {});
      final b = limiter.request(() {});
      final c = limiter.request(() {});

      expect(a.granted, isTrue);
      expect(b.granted, isTrue);
      expect(c.granted, isFalse);
      expect(limiter.activeCount, 2);
      expect(limiter.waitingCount, 1);
    });

    test('priority waiter is drained before normal queue', () {
      final order = <String>[];
      final scheduled = <void Function()>[];
      final limiter = HtmlWebViewMountLimiter(
        maxMounted: 1,
        scheduleGranted: scheduled.add,
      );

      final active = limiter.request(() => order.add('active'));
      expect(active.granted, isTrue);

      final normal = limiter.request(() => order.add('normal'));
      final priority = limiter.request(
        () => order.add('priority'),
        priority: true,
      );
      expect(normal.granted, isFalse);
      expect(priority.granted, isFalse);

      active.release();
      expect(scheduled, hasLength(1));
      scheduled.removeAt(0)();
      expect(priority.granted, isTrue);
      expect(normal.granted, isFalse);
      expect(order, ['priority']);

      priority.release();
      expect(scheduled, hasLength(1));
      scheduled.removeAt(0)();
      expect(normal.granted, isTrue);
      expect(order, ['priority', 'normal']);
    });

    test('release before grant removes waiter without callback', () {
      final calls = <int>[];
      final scheduled = <void Function()>[];
      final limiter = HtmlWebViewMountLimiter(
        maxMounted: 1,
        scheduleGranted: scheduled.add,
      );
      final active = limiter.request(() => calls.add(0));
      final waiting = limiter.request(() => calls.add(1));
      waiting.release();
      active.release();
      expect(scheduled, isEmpty);
      expect(calls, isEmpty);
      expect(limiter.activeCount, 0);
      expect(limiter.waitingCount, 0);
    });

    test('clear releases waiters and drops active set', () {
      final limiter = HtmlWebViewMountLimiter();
      final a = limiter.request(() {});
      final b = limiter.request(() {});
      final c = limiter.request(() {});
      expect(a.granted, isTrue);
      expect(b.granted, isTrue);
      expect(c.granted, isFalse);
      limiter.clear();
      expect(limiter.activeCount, 0);
      expect(limiter.waitingCount, 0);
      expect(c.released, isTrue);
    });

    test('large concurrent request storm stays within maxMounted', () {
      final limiter = HtmlWebViewMountLimiter();
      final permits = <HtmlWebViewMountPermit>[
        for (var i = 0; i < 200; i++) limiter.request(() {}),
      ];
      final granted = permits.where((p) => p.granted).length;
      expect(granted, 2);
      expect(limiter.activeCount, 2);
      expect(limiter.waitingCount, 198);

      for (final permit in permits) {
        permit.release();
      }
      expect(limiter.activeCount, 0);
      expect(limiter.waitingCount, 0);
    });

    test('invalid maxMounted gracefully falls back to one', () {
      final limiter = HtmlWebViewMountLimiter(maxMounted: 0);

      final active = limiter.request(() {});
      final waiting = limiter.request(() {});

      expect(limiter.maxMounted, 1);
      expect(active.granted, isTrue);
      expect(waiting.granted, isFalse);
      expect(limiter.activeCount, 1);
      expect(limiter.waitingCount, 1);
    });
  });
}
