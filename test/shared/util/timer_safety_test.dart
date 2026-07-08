import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/timer_safety.dart';

void main() {
  test('non-overlapping timer releases gate after callback timeout', () async {
    final errors = <Object>[];
    final blockers = <Completer<void>>[];
    var calls = 0;

    final timer = startNonOverlappingPeriodicTimer(
      const Duration(milliseconds: 1),
      (_) {
        calls++;
        final blocker = Completer<void>();
        blockers.add(blocker);
        return blocker.future;
      },
      min: const Duration(milliseconds: 1),
      max: const Duration(milliseconds: 20),
      callbackTimeout: const Duration(milliseconds: 2),
      cancelOnCallbackTimeout: false,
      onError: (error, _) => errors.add(error),
    );
    addTearDown(timer.cancel);

    await _waitUntil(() => calls >= 2);
    timer.cancel();
    for (final blocker in blockers) {
      if (!blocker.isCompleted) blocker.complete();
    }

    expect(calls, greaterThanOrEqualTo(2));
    expect(errors.whereType<TimeoutException>(), isNotEmpty);
  });

  test('non-overlapping timer does not overlap healthy callbacks', () async {
    var calls = 0;
    var active = 0;
    var maxActive = 0;

    final timer = startNonOverlappingPeriodicTimer(
      const Duration(milliseconds: 1),
      (_) async {
        calls++;
        active++;
        if (active > maxActive) maxActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 6));
        active--;
      },
      min: const Duration(milliseconds: 1),
      max: const Duration(milliseconds: 20),
      callbackTimeout: const Duration(milliseconds: 80),
    );
    addTearDown(timer.cancel);

    await _waitUntil(() => calls >= 3);
    timer.cancel();
    await _waitUntil(() => active == 0);

    expect(calls, greaterThanOrEqualTo(3));
    expect(maxActive, 1);
  });
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(milliseconds: 300),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!predicate()) {
    if (stopwatch.elapsed >= timeout) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
