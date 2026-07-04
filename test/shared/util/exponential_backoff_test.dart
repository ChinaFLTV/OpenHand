import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/exponential_backoff.dart';

void main() {
  group('exponentialBackoffMs', () {
    test('returns zero for non-positive attempts', () {
      expect(exponentialBackoffMs(attempt: 0, baseMs: 250, capMs: 4000), 0);
      expect(exponentialBackoffMs(attempt: -1, baseMs: 250, capMs: 4000), 0);
    });

    test('doubles from the safe base until cap', () {
      expect(exponentialBackoffMs(attempt: 1, baseMs: 250, capMs: 4000), 250);
      expect(exponentialBackoffMs(attempt: 2, baseMs: 250, capMs: 4000), 500);
      expect(exponentialBackoffMs(attempt: 3, baseMs: 250, capMs: 4000), 1000);
      expect(exponentialBackoffMs(attempt: 5, baseMs: 250, capMs: 4000), 4000);
      expect(exponentialBackoffMs(attempt: 6, baseMs: 250, capMs: 4000), 4000);
    });

    test('normalizes invalid base and cap values', () {
      expect(exponentialBackoffMs(attempt: 1, baseMs: 0, capMs: 10), 1);
      expect(exponentialBackoffMs(attempt: 2, baseMs: -5, capMs: 10), 2);
      expect(exponentialBackoffMs(attempt: 3, baseMs: 100, capMs: 10), 100);
    });

    test('saturates very large attempts without unbounded calculation', () {
      expect(
        exponentialBackoffMs(attempt: 1 << 30, baseMs: 1, capMs: 300),
        300,
      );
    });
  });

  group('exponentialBackoffSeconds', () {
    test('uses the same bounded formula with second units', () {
      expect(
        exponentialBackoffSeconds(attempt: 4, baseSeconds: 1, capSeconds: 10),
        8,
      );
      expect(
        exponentialBackoffSeconds(attempt: 5, baseSeconds: 1, capSeconds: 10),
        10,
      );
    });
  });
}
