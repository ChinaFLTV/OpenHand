import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/exponential_backoff.dart';

void main() {
  group('exponentialBackoffMs', () {
    test('attempt<=0 returns zero (immediate retry contract)', () {
      expect(exponentialBackoffMs(attempt: 0, baseMs: 250, capMs: 4000), 0);
      expect(exponentialBackoffMs(attempt: -3, baseMs: 250, capMs: 4000), 0);
    });

    test('doubles per attempt up to cap', () {
      // attempt=1 → base, 2 → 2*base, 3 → 4*base, 4 → 8*base, then clamped.
      expect(exponentialBackoffMs(attempt: 1, baseMs: 250, capMs: 4000), 250);
      expect(exponentialBackoffMs(attempt: 2, baseMs: 250, capMs: 4000), 500);
      expect(exponentialBackoffMs(attempt: 3, baseMs: 250, capMs: 4000), 1000);
      expect(exponentialBackoffMs(attempt: 4, baseMs: 250, capMs: 4000), 2000);
      expect(exponentialBackoffMs(attempt: 5, baseMs: 250, capMs: 4000), 4000);
      expect(exponentialBackoffMs(attempt: 6, baseMs: 250, capMs: 4000), 4000);
      expect(exponentialBackoffMs(attempt: 100, baseMs: 250, capMs: 4000), 4000);
    });

    test('cap < base coerces to base (no negative clamp range)', () {
      expect(exponentialBackoffMs(attempt: 1, baseMs: 1000, capMs: 100), 1000);
      expect(exponentialBackoffMs(attempt: 5, baseMs: 1000, capMs: 100), 1000);
    });

    test('large attempt does not overflow int shift', () {
      // attempt safe-clamped to 30 internally; result must still respect cap.
      expect(
        exponentialBackoffMs(attempt: 9999, baseMs: 250, capMs: 4000),
        4000,
      );
    });
  });

  group('exponentialBackoffSeconds', () {
    test('cron-shaped backoff matches old (1<<(attempt-1)) clamp', () {
      // Reproduces the cron_executor pre-refactor behavior:
      //   delaySeconds = (1 << (attempt-1)).clamp(1, capSeconds)
      // for attempt >= 1, capSeconds = 300.
      expect(exponentialBackoffSeconds(attempt: 1, baseSeconds: 1, capSeconds: 300), 1);
      expect(exponentialBackoffSeconds(attempt: 2, baseSeconds: 1, capSeconds: 300), 2);
      expect(exponentialBackoffSeconds(attempt: 3, baseSeconds: 1, capSeconds: 300), 4);
      expect(exponentialBackoffSeconds(attempt: 8, baseSeconds: 1, capSeconds: 300), 128);
      expect(exponentialBackoffSeconds(attempt: 9, baseSeconds: 1, capSeconds: 300), 256);
      expect(exponentialBackoffSeconds(attempt: 10, baseSeconds: 1, capSeconds: 300), 300);
    });
  });
}
