import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/async_concurrency.dart';

void main() {
  group('cancelStreamSubscriptionBounded', () {
    test('treats an absent subscription as already cleaned up', () async {
      expect(await cancelStreamSubscriptionBounded<int>(null), isTrue);
    });

    test('cancels a normal subscription', () async {
      final controller = StreamController<int>();
      final subscription = controller.stream.listen((_) {});

      expect(await cancelStreamSubscriptionBounded<int>(subscription), isTrue);
      await controller.close();
    });

    test('returns after the cleanup budget when cancellation stalls', () async {
      final releaseCancellation = Completer<void>();
      final controller = StreamController<int>(
        onCancel: () => releaseCancellation.future,
      );
      final subscription = controller.stream.listen((_) {});
      Object? reportedError;

      final cancelled = await cancelStreamSubscriptionBounded<int>(
        subscription,
        timeout: const Duration(milliseconds: 10),
        onError: (error, _) => reportedError = error,
      );

      expect(cancelled, isFalse);
      expect(reportedError, isA<TimeoutException>());
      releaseCancellation.complete();
      await controller.close();
    });
  });
}
