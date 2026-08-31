import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/async_concurrency.dart';

void main() {
  group('异步单航班', () {
    test('并发调用共享同一次执行结果', () async {
      final gate = Completer<int>();
      final flight = OpenHandSingleFlight<int>();
      var calls = 0;

      Future<int> load() {
        calls += 1;
        return gate.future;
      }

      final first = flight.run(load);
      final second = flight.run(load);
      expect(identical(first, second), isTrue);
      expect(calls, 1);
      expect(flight.isRunning, isTrue);

      gate.complete(7);
      expect(await first, 7);
      expect(flight.isRunning, isFalse);
    });

    test('可重试缓存仅缓存成功结果', () async {
      var calls = 0;
      final cache = OpenHandRetryableAsyncCache<int>(() async {
        calls += 1;
        if (calls == 1) throw StateError('首次失败');
        return 9;
      });

      await expectLater(cache.load(), throwsStateError);
      expect(await cache.load(), 9);
      expect(await cache.load(), 9);
      expect(calls, 2);
    });
  });

  group('异步信号量', () {
    test('等待者按进入顺序获得许可', () async {
      final semaphore = OpenHandAsyncSemaphore(1);
      await semaphore.acquire();
      final order = <int>[];

      Future<void> waitForPermit(int value) async {
        await semaphore.acquire();
        order.add(value);
        semaphore.release();
      }

      final second = waitForPermit(2);
      final third = waitForPermit(3);
      semaphore.release();
      await Future.wait<void>(<Future<void>>[second, third]);
      expect(order, <int>[2, 3]);
    });

    test('超时等待会从队列移除且不吞掉许可', () async {
      final semaphore = OpenHandAsyncSemaphore(1);
      await semaphore.acquire();

      expect(
        await semaphore.acquireWithin(const Duration(milliseconds: 5)),
        isFalse,
      );
      semaphore.release();
      await semaphore.acquire();
      semaphore.release();
    });

    test('取消全部等待者不影响当前持有者', () async {
      final semaphore = OpenHandAsyncSemaphore(1);
      await semaphore.acquire();
      final waiting = semaphore.acquireUnlessCancelled(
        Completer<void>().future,
      );

      semaphore.cancelWaiters();
      expect(await waiting, isFalse);
      semaphore.release();
    });
  });

  test('有界工作池保持结果顺序和并发上限', () async {
    var running = 0;
    var peak = 0;
    final results = await runOrderedWithConcurrencyLimit<int>(
      itemCount: 8,
      maxConcurrency: 3,
      task: (index) async {
        running += 1;
        if (running > peak) peak = running;
        await Future<void>.delayed(Duration(milliseconds: 8 - index));
        running -= 1;
        return index * 2;
      },
    );

    expect(results, <int>[0, 2, 4, 6, 8, 10, 12, 14]);
    expect(peak, lessThanOrEqualTo(3));
  });
}
