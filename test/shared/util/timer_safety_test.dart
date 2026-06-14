import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/timer_safety.dart';

void main() {
  group('startNonOverlappingPeriodicTimer', () {
    test(
      'does not start a second callback after timeout while first is alive',
      () async {
        final errors = <Object>[];
        var started = 0;
        late Timer timer;

        timer = startNonOverlappingPeriodicTimer(
          const Duration(milliseconds: 5),
          (_) {
            started += 1;
            return Completer<void>().future;
          },
          min: const Duration(milliseconds: 1),
          callbackTimeout: const Duration(milliseconds: 15),
          cancelOnCallbackTimeout: false,
          onError: (error, _) => errors.add(error),
        );

        await Future<void>.delayed(const Duration(milliseconds: 60));
        timer.cancel();

        expect(started, 1);
        expect(errors.whereType<TimeoutException>(), hasLength(1));
      },
    );
  });
}
