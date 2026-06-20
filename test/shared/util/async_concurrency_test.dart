import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/async_concurrency.dart';

void main() {
  group('async concurrency helpers', () {
    test(
      'preserves result order while capping oversized concurrency',
      () async {
        var running = 0;
        var peak = 0;

        final results = await runOrderedWithConcurrencyLimit<int>(
          itemCount: kOpenHandMaxAsyncConcurrency + 8,
          maxConcurrency: 100000,
          task: (index) async {
            running += 1;
            peak = peak < running ? running : peak;
            await Future<void>.delayed(const Duration(milliseconds: 1));
            running -= 1;
            return -index;
          },
        );

        expect(results, List<int>.generate(results.length, (index) => -index));
        expect(peak, lessThanOrEqualTo(kOpenHandMaxAsyncConcurrency));
      },
    );

    test('treats non-positive concurrency as a single worker', () async {
      var running = 0;
      var peak = 0;

      await forEachIndexWithConcurrencyLimit(
        itemCount: 5,
        maxConcurrency: 0,
        task: (index) async {
          running += 1;
          peak = peak < running ? running : peak;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          running -= 1;
        },
      );

      expect(peak, 1);
    });

    test('does not schedule work for empty or negative item counts', () async {
      var calls = 0;

      final results = await runOrderedWithConcurrencyLimit<int>(
        itemCount: -1,
        maxConcurrency: 4,
        task: (index) async {
          calls += 1;
          return index;
        },
      );

      await forEachIndexWithConcurrencyLimit(
        itemCount: 0,
        maxConcurrency: 4,
        task: (index) async {
          calls += 1;
        },
      );

      expect(results, isEmpty);
      expect(calls, 0);
    });
  });
}
