import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/web_engine/web_engine_concurrency.dart';

void main() {
  group('WebEngineSemaphore', () {
    test('normalizes non-positive max counts to one permit', () async {
      final semaphore = WebEngineSemaphore(0);
      expect(semaphore.maxCount, 1);

      await semaphore.acquire();
      var secondAcquired = false;
      final second = semaphore.acquire().then((_) {
        secondAcquired = true;
      });

      await Future<void>.delayed(Duration.zero);
      expect(secondAcquired, isFalse);

      semaphore.release();
      await second;
      expect(secondAcquired, isTrue);
    });

    test('releases waiters in FIFO order', () async {
      final semaphore = WebEngineSemaphore(1);
      final order = <int>[];

      await semaphore.acquire();
      final second = semaphore.withPermit(() async {
        order.add(2);
      });
      final third = semaphore.withPermit(() async {
        order.add(3);
      });

      await Future<void>.delayed(Duration.zero);
      expect(order, isEmpty);

      semaphore.release();
      await Future.wait(<Future<void>>[second, third]);
      expect(order, <int>[2, 3]);
    });

    test('withPermit releases permits after errors', () async {
      final semaphore = WebEngineSemaphore(1);

      await expectLater(
        semaphore.withPermit<void>(() async {
          throw StateError('failed');
        }),
        throwsStateError,
      );

      var ran = false;
      await semaphore.withPermit<void>(() async {
        ran = true;
      });
      expect(ran, isTrue);
    });
  });
}
