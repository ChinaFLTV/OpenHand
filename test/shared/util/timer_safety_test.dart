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
}
