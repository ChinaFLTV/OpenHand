import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/async_concurrency.dart';

void main() {
  group('OpenHandAsyncSemaphore', () {
    test('达到上限后按先进先出顺序放行', () async {
      final semaphore = OpenHandAsyncSemaphore(1);
      await semaphore.acquire();
      final acquired = <int>[];

      final first = semaphore.acquire().then((_) => acquired.add(1));
      final second = semaphore.acquire().then((_) => acquired.add(2));

      semaphore.release();
      await first;
      expect(acquired, <int>[1]);

      semaphore.release();
      await second;
      expect(acquired, <int>[1, 2]);
      semaphore.release();
    });

    test('重复释放时直接报告调用错误', () {
      final semaphore = OpenHandAsyncSemaphore(1);

      expect(semaphore.release, throwsStateError);
    });

    test('任务失败后仍归还许可', () async {
      final semaphore = OpenHandAsyncSemaphore(1);

      await expectLater(
        semaphore.withPermit<void>(() => throw StateError('任务失败')),
        throwsStateError,
      );
      await semaphore.acquire();
      semaphore.release();
    });

    test('取消排队后立即移除等待者且不占用许可', () async {
      final semaphore = OpenHandAsyncSemaphore(1);
      final cancellation = Completer<void>();
      await semaphore.acquire();

      final cancelledAcquire = semaphore.acquireUnlessCancelled(
        cancellation.future,
      );
      final nextAcquire = semaphore.acquire();
      cancellation.complete();

      expect(await cancelledAcquire, isFalse);
      semaphore.release();
      await nextAcquire;
      semaphore.release();
    });

    test('已取消时不获取空闲许可', () async {
      final semaphore = OpenHandAsyncSemaphore(1);
      final cancellation = Completer<void>()..complete();

      expect(
        await semaphore.acquireUnlessCancelled(cancellation.future),
        isFalse,
      );
      await semaphore.acquire();
      semaphore.release();
    });
  });

  group('并发工作池', () {
    test('保持结果顺序并限制并发数', () async {
      var active = 0;
      var peak = 0;

      final results = await runOrderedWithConcurrencyLimit<int>(
        itemCount: 8,
        maxConcurrency: 3,
        task: (index) async {
          active += 1;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 2));
          active -= 1;
          return index * 2;
        },
      );

      expect(results, <int>[0, 2, 4, 6, 8, 10, 12, 14]);
      expect(peak, 3);
    });

    test('首个任务失败后不再领取新任务', () async {
      final firstFailure = Completer<void>();
      final secondFinished = Completer<void>();
      final bothStarted = Completer<void>();
      final started = <int>[];

      final operation = forEachIndexWithConcurrencyLimit(
        itemCount: 6,
        maxConcurrency: 2,
        task: (index) async {
          started.add(index);
          if (started.length == 2 && !bothStarted.isCompleted) {
            bothStarted.complete();
          }
          if (index == 0) {
            await firstFailure.future;
            throw StateError('首个任务失败');
          }
          await secondFinished.future;
        },
      );

      await bothStarted.future;
      firstFailure.complete();
      await Future<void>.delayed(Duration.zero);
      secondFinished.complete();

      await expectLater(operation, throwsStateError);
      expect(started, <int>[0, 1]);
    });
  });
}
