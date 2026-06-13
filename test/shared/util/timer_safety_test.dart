import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/timer_safety.dart';

void main() {
  group('timer safety', () {
    test('clamps unsafe periodic intervals', () {
      expect(
        safePeriodicTimerInterval(
          Duration.zero,
          min: const Duration(milliseconds: 10),
        ),
        const Duration(milliseconds: 10),
      );
      expect(
        safePeriodicTimerInterval(
          const Duration(days: 2),
          max: const Duration(hours: 6),
        ),
        const Duration(hours: 6),
      );
    });

    test('reports callback errors without stopping periodic timer', () async {
      final errors = <Object>[];
      var ticks = 0;
      late final Timer timer;

      timer = startSafePeriodicTimer(
        Duration.zero,
        (_) {
          ticks += 1;
          if (ticks == 1) {
            throw StateError('boom');
          }
          timer.cancel();
        },
        min: const Duration(milliseconds: 1),
        onError: (error, _) => errors.add(error),
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(ticks, greaterThanOrEqualTo(2));
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });

    test('cancels non-overlapping timer when callback times out', () async {
      final errors = <Object>[];
      var starts = 0;

      final timer = startNonOverlappingPeriodicTimer(
        const Duration(milliseconds: 2),
        (_) {
          starts += 1;
          return Completer<void>().future;
        },
        min: const Duration(milliseconds: 1),
        callbackTimeout: const Duration(milliseconds: 5),
        onError: (error, _) => errors.add(error),
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(starts, 1);
      expect(timer.isActive, isFalse);
      expect(errors, hasLength(1));
      expect(errors.single, isA<TimeoutException>());
    });
  });
}
