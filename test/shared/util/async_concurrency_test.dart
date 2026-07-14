import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/async_concurrency.dart';

void main() {
  test('bounded subscription cancellation completes normally', () async {
    var cancelled = false;
    final controller = StreamController<void>(
      onCancel: () {
        cancelled = true;
      },
    );
    final subscription = controller.stream.listen((_) {});

    final completed = await cancelStreamSubscriptionBounded<void>(subscription);

    expect(completed, isTrue);
    expect(cancelled, isTrue);
    await controller.close();
  });

  test('bounded subscription cancellation contains cleanup errors', () async {
    Object? capturedError;
    final controller = StreamController<void>(
      onCancel: () => throw StateError('cancel failed'),
    );
    final subscription = controller.stream.listen((_) {});

    final completed = await cancelStreamSubscriptionBounded<void>(
      subscription,
      onError: (error, _) => capturedError = error,
    );

    expect(completed, isFalse);
    expect(capturedError, isA<StateError>());
    await controller.close();
  });

  test('bounded subscription cancellation cannot block shutdown', () async {
    final releaseCancellation = Completer<void>();
    final controller = StreamController<void>(
      onCancel: () => releaseCancellation.future,
    );
    final subscription = controller.stream.listen((_) {});

    final completed = await cancelStreamSubscriptionBounded<void>(
      subscription,
      timeout: const Duration(milliseconds: 20),
    );

    expect(completed, isFalse);
    releaseCancellation.complete();
    await controller.close();
  });

  test('cancelling a missing subscription is idempotent', () async {
    expect(await cancelStreamSubscriptionBounded<void>(null), isTrue);
  });
}
