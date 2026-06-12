import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/timer_safety.dart';

void main() {
  group('safePeriodicTimerInterval', () {
    test('clamps zero and negative intervals to the lower bound', () {
      expect(
        safePeriodicTimerInterval(
          Duration.zero,
          min: const Duration(seconds: 2),
        ),
        const Duration(seconds: 2),
      );
      expect(
        safePeriodicTimerInterval(
          const Duration(seconds: -1),
          min: const Duration(seconds: 2),
        ),
        const Duration(seconds: 2),
      );
    });

    test('clamps intervals above the upper bound', () {
      expect(
        safePeriodicTimerInterval(
          const Duration(hours: 48),
          max: const Duration(hours: 1),
        ),
        const Duration(hours: 1),
      );
    });

    test('normalizes an inverted min and max pair', () {
      expect(
        safePeriodicTimerInterval(
          const Duration(seconds: 10),
          min: const Duration(seconds: 30),
          max: const Duration(seconds: 5),
        ),
        const Duration(seconds: 30),
      );
    });
  });

  group('startSafePeriodicTimer', () {
    test('routes synchronous callback errors to the error handler', () async {
      final done = Completer<void>();
      final errors = <Object>[];
      final timer = startSafePeriodicTimer(
        const Duration(milliseconds: 1),
        (timer) {
          timer.cancel();
          throw StateError('sync timer failure');
        },
        min: const Duration(milliseconds: 1),
        onError: (error, stackTrace) {
          errors.add(error);
          if (!done.isCompleted) done.complete();
        },
      );
      addTearDown(timer.cancel);

      await done.future.timeout(const Duration(seconds: 1));

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });
  });

  group('startNonOverlappingPeriodicTimer', () {
    test('routes asynchronous callback errors to the error handler', () async {
      final done = Completer<void>();
      final errors = <Object>[];
      final timer = startNonOverlappingPeriodicTimer(
        const Duration(milliseconds: 1),
        (timer) async {
          timer.cancel();
          await Future<void>.delayed(Duration.zero);
          throw StateError('async timer failure');
        },
        min: const Duration(milliseconds: 1),
        onError: (error, stackTrace) {
          errors.add(error);
          if (!done.isCompleted) done.complete();
        },
      );
      addTearDown(timer.cancel);

      await done.future.timeout(const Duration(seconds: 1));

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });

    test('does not overlap slow asynchronous callbacks', () async {
      final done = Completer<void>();
      var activeCallbacks = 0;
      var maxActiveCallbacks = 0;
      var completedCallbacks = 0;
      final timer = startNonOverlappingPeriodicTimer(
        const Duration(milliseconds: 1),
        (timer) async {
          activeCallbacks += 1;
          if (activeCallbacks > maxActiveCallbacks) {
            maxActiveCallbacks = activeCallbacks;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
          activeCallbacks -= 1;
          completedCallbacks += 1;
          if (completedCallbacks >= 3 && !done.isCompleted) {
            timer.cancel();
            done.complete();
          }
        },
        min: const Duration(milliseconds: 1),
      );
      addTearDown(timer.cancel);

      await done.future.timeout(const Duration(seconds: 2));

      expect(maxActiveCallbacks, 1);
    });
  });
}
