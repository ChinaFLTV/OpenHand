import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/timer_safety.dart';

void main() {
  group('safePeriodicTimerInterval', () {
    test('clamps non-positive and out-of-range intervals', () {
      expect(
        safePeriodicTimerInterval(Duration.zero),
        kOpenHandMinPeriodicTimerInterval,
      );
      expect(
        safePeriodicTimerInterval(
          const Duration(milliseconds: 1),
          min: const Duration(milliseconds: 10),
        ),
        const Duration(milliseconds: 10),
      );
      expect(
        safePeriodicTimerInterval(
          const Duration(seconds: 5),
          max: const Duration(seconds: 1),
        ),
        const Duration(seconds: 1),
      );
    });

    test('uses the lower bound when max is below min', () {
      expect(
        safePeriodicTimerInterval(
          const Duration(seconds: 10),
          min: const Duration(seconds: 3),
          max: const Duration(seconds: 1),
        ),
        const Duration(seconds: 3),
      );
    });
  });

  group('safeTimerDelay', () {
    test('allows zero by default and clamps to configured bounds', () {
      expect(safeTimerDelay(Duration.zero), Duration.zero);
      expect(
        safeTimerDelay(
          const Duration(milliseconds: -1),
          min: const Duration(milliseconds: 10),
        ),
        const Duration(milliseconds: 10),
      );
      expect(
        safeTimerDelay(
          const Duration(seconds: 5),
          max: const Duration(seconds: 1),
        ),
        const Duration(seconds: 1),
      );
    });
  });

  group('startSafeTimer', () {
    test('routes callback errors to the provided handler', () async {
      final completer = Completer<Object>();

      startSafeTimer(
        Duration.zero,
        () => throw StateError('timer failed'),
        onError: (error, _) => completer.complete(error),
      );

      final error = await completer.future.timeout(const Duration(seconds: 1));
      expect(error, isA<StateError>());
    });
  });

  group('OpenHandDebouncer', () {
    test('runs only the latest scheduled callback', () async {
      final debouncer = OpenHandDebouncer(delay: Duration.zero);
      final completer = Completer<List<int>>();
      final values = <int>[];

      debouncer.schedule(() => values.add(1));
      debouncer.schedule(() {
        values.add(2);
        completer.complete(values);
      });

      expect(await completer.future.timeout(const Duration(seconds: 1)), <int>[
        2,
      ]);
      debouncer.dispose();
    });

    test('scheduleIfIdle refuses while a timer is active', () {
      final debouncer = OpenHandDebouncer(delay: const Duration(seconds: 1));

      expect(debouncer.scheduleIfIdle(() {}), isTrue);
      expect(debouncer.scheduleIfIdle(() {}), isFalse);

      debouncer.dispose();
    });

    test('scheduleIfIdle refuses while an async callback is running', () async {
      final debouncer = OpenHandDebouncer(delay: Duration.zero);
      final started = Completer<void>();
      final gate = Completer<void>();

      expect(
        debouncer.scheduleIfIdle(() async {
          started.complete();
          await gate.future;
        }),
        isTrue,
      );

      await started.future.timeout(const Duration(seconds: 1));
      expect(debouncer.isActive, isTrue);
      expect(debouncer.scheduleIfIdle(() {}), isFalse);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(debouncer.isActive, isFalse);
      expect(debouncer.scheduleIfIdle(() {}), isTrue);

      debouncer.dispose();
    });
  });
}
