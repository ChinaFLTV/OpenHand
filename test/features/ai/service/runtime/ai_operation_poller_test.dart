import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/runtime/ai_operation_poller.dart';

void main() {
  group('AiOperationPoller', () {
    test('rejects non-positive timeout without invoking tick', () async {
      var tickCount = 0;
      const poller = AiOperationPoller();

      await expectLater(
        poller.pollUntil<int>(
          tick: () async {
            tickCount += 1;
            return 1;
          },
          isTerminal: (_) => true,
          timeout: Duration.zero,
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(tickCount, 0);
    });

    test('bounds a hanging tick by the remaining polling budget', () async {
      const poller = AiOperationPoller();

      await expectLater(
        poller.pollUntil<int>(
          tick: () => Completer<int?>().future,
          isTerminal: (_) => true,
          timeout: const Duration(milliseconds: 20),
          initialDelay: Duration.zero,
          maxDelay: Duration.zero,
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('keeps polling until a terminal value is returned', () async {
      var tickCount = 0;
      const poller = AiOperationPoller();

      final result = await poller.pollUntil<int>(
        tick: () async {
          tickCount += 1;
          return tickCount < 2 ? null : 7;
        },
        isTerminal: (value) => value == 7,
        timeout: const Duration(seconds: 1),
        initialDelay: Duration.zero,
        maxDelay: Duration.zero,
      );

      expect(result, 7);
      expect(tickCount, 2);
    });
  });
}
