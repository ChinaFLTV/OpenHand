import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/async_concurrency.dart';

void main() {
  group('OpenHandAsyncSemaphore', () {
    test('normalizes invalid and oversized limits', () {
      expect(OpenHandAsyncSemaphore(0).maxPermits, 1);
      expect(
        OpenHandAsyncSemaphore(kOpenHandMaxAsyncConcurrency + 1).maxPermits,
        kOpenHandMaxAsyncConcurrency,
      );
      expect(OpenHandAsyncSemaphore(10, maxAllowedPermits: 3).maxPermits, 3);
      expect(OpenHandAsyncSemaphore(0, maxAllowedPermits: 0).maxPermits, 1);
    });

    test('grants waiters in FIFO order', () async {
      final semaphore = OpenHandAsyncSemaphore(1);
      final order = <String>[];

      await semaphore.acquire();
      final second = semaphore.acquire().then((_) => order.add('second'));
      final third = semaphore.acquire().then((_) => order.add('third'));

      expect(semaphore.availableCount, 0);
      expect(semaphore.waitingCount, 2);

      semaphore.release();
      await second;
      expect(order, ['second']);
      expect(semaphore.waitingCount, 1);

      semaphore.release();
      await third;
      expect(order, ['second', 'third']);
      expect(semaphore.waitingCount, 0);
    });

    test('withPermit releases after failures', () async {
      final semaphore = OpenHandAsyncSemaphore(1);

      await expectLater(
        semaphore.withPermit<void>(() async {
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      await semaphore.acquire();
      expect(semaphore.availableCount, 0);
      semaphore.release();
      expect(semaphore.availableCount, 1);
    });
  });
}
