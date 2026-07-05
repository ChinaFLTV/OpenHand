import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/async_concurrency.dart';

void main() {
  group('isCancelSignalCompleted', () {
    test('reports null and pending signals as not cancelled', () async {
      expect(await isCancelSignalCompleted(null), isFalse);

      final cancel = Completer<void>();
      expect(await isCancelSignalCompleted(cancel.future), isFalse);
    });

    test('treats completed and failed signals as cancelled', () async {
      final completed = Completer<void>();
      final completedCheck = isCancelSignalCompleted(completed.future);
      completed.complete();
      expect(await completedCheck, isTrue);

      final failed = Completer<void>();
      final failedCheck = isCancelSignalCompleted(failed.future);
      failed.completeError(StateError('cancelled'));
      expect(await failedCheck, isTrue);
    });
  });

  group('delayUntilCancelled', () {
    test('returns true when cancellation wins the delay race', () async {
      final cancel = Completer<void>();
      final delayed = delayUntilCancelled(
        const Duration(milliseconds: 10),
        cancelSignal: cancel.future,
      );

      cancel.complete();

      expect(await delayed, isTrue);
    });

    test('returns false for zero delay without cancellation', () async {
      expect(await delayUntilCancelled(Duration.zero), isFalse);
    });
  });

  group('awaitWithCancelSignal', () {
    test('returns the future value when work completes first', () async {
      expect(await awaitWithCancelSignal(Future<int>.value(7)), 7);
    });

    test('returns null when cancellation completes first', () async {
      final work = Completer<int>();
      final cancel = Completer<void>();
      final result = awaitWithCancelSignal(
        work.future,
        cancelSignal: cancel.future,
      );

      cancel.complete();

      expect(await result, isNull);
      work.completeError(StateError('late failure'));
      await Future<void>.delayed(Duration.zero);
    });

    test('treats failed cancellation signals as cancelled', () async {
      final work = Completer<int>();
      final cancel = Completer<void>();
      final result = awaitWithCancelSignal(
        work.future,
        cancelSignal: cancel.future,
      );

      cancel.completeError(StateError('cancelled'));

      expect(await result, isNull);
      work.complete(1);
    });
  });
}
