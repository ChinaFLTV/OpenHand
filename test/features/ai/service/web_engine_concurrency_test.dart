import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/web_engine_concurrency.dart';

void main() {
  group('WebEngineSemaphore', () {
    test('grants up to maxCount permits without waiting', () async {
      final sem = WebEngineSemaphore(3);
      // Three immediate acquires must all complete in the same microtask turn.
      final results = await Future.wait([
        sem.acquire(),
        sem.acquire(),
        sem.acquire(),
      ]);
      expect(results, hasLength(3));
    });

    test('queues additional acquires until release', () async {
      final sem = WebEngineSemaphore(1);
      await sem.acquire();

      var secondAcquired = false;
      final pending = sem.acquire().then((_) => secondAcquired = true);

      // Without release, the second acquire stays pending.
      await Future<void>.delayed(Duration.zero);
      expect(secondAcquired, isFalse);

      sem.release();
      await pending;
      expect(secondAcquired, isTrue);
    });

    test('release without waiters refills available count, capped at maxCount',
        () async {
      final sem = WebEngineSemaphore(2);
      // Over-release must not push _available beyond maxCount.
      sem.release();
      sem.release();
      sem.release();
      // After three releases on a fresh semaphore we still only get 2 immediate
      // permits; the 3rd acquire must queue.
      await sem.acquire();
      await sem.acquire();

      var thirdAcquired = false;
      final pending = sem.acquire().then((_) => thirdAcquired = true);
      await Future<void>.delayed(Duration.zero);
      expect(thirdAcquired, isFalse);

      sem.release();
      await pending;
      expect(thirdAcquired, isTrue);
    });

    test('FIFO ordering for queued waiters', () async {
      final sem = WebEngineSemaphore(1);
      await sem.acquire();

      final completedOrder = <int>[];
      final f1 = sem.acquire().then((_) => completedOrder.add(1));
      final f2 = sem.acquire().then((_) => completedOrder.add(2));
      final f3 = sem.acquire().then((_) => completedOrder.add(3));

      sem.release();
      await f1;
      sem.release();
      await f2;
      sem.release();
      await f3;

      expect(completedOrder, [1, 2, 3]);
    });
  });
}
