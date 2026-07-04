import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/async_concurrency.dart';

void main() {
  group('forEachIndexWithConcurrencyLimit', () {
    test(
      'stops waiting between items when shouldContinue turns false',
      () async {
        var keepGoing = true;
        final visited = <int>[];

        final work = forEachIndexWithConcurrencyLimit(
          itemCount: 3,
          maxConcurrency: 1,
          shouldContinue: () => keepGoing,
          delayBetweenItems: const Duration(days: 1),
          task: (index) async {
            visited.add(index);
            keepGoing = false;
          },
        );

        await expectLater(
          work.timeout(const Duration(milliseconds: 500)),
          completes,
        );
        expect(visited, <int>[0]);
      },
    );
  });

  group('runOrderedWithConcurrencyLimit', () {
    test('preserves result order with bounded workers', () async {
      final results = await runOrderedWithConcurrencyLimit<int>(
        itemCount: 4,
        maxConcurrency: 2,
        task: (index) async => index * 10,
      );

      expect(results, <int>[0, 10, 20, 30]);
    });
  });
}
