import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/exponential_backoff.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';

void main() {
  group('clamped parsing', () {
    test('clamps int values with inverted bounds', () {
      expect(clampedIntFromText('20', fallback: 5, min: 10, max: 1), 10);
      expect(clampedIntFromText('-5', fallback: 5, min: 10, max: 1), 1);
    });

    test('uses safe fallback for non-finite double fallback', () {
      expect(
        clampedDoubleFromValue(
          'not-a-number',
          fallback: double.nan,
          min: 0,
          max: 1,
        ),
        0,
      );
    });
  });

  group('exponentialBackoffMs', () {
    test('returns zero for non-retry attempts', () {
      expect(exponentialBackoffMs(attempt: 0, baseMs: 100, capMs: 1000), 0);
      expect(exponentialBackoffMs(attempt: -1, baseMs: 100, capMs: 1000), 0);
    });

    test('normalizes invalid base and cap values', () {
      expect(exponentialBackoffMs(attempt: 1, baseMs: 0, capMs: 0), 1);
      expect(exponentialBackoffMs(attempt: 3, baseMs: -5, capMs: -1), 1);
    });

    test('caps large attempts', () {
      expect(exponentialBackoffMs(attempt: 30, baseMs: 100, capMs: 500), 500);
    });
  });
}
