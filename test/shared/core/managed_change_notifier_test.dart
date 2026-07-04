import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/core/managed_change_notifier.dart';

void main() {
  test('enqueueOperation runs operations serially', () async {
    final notifier = _TestNotifier();
    final firstGate = Completer<int>();
    final order = <String>[];

    final first = notifier.run(() async {
      order.add('first-start');
      return firstGate.future;
    });
    final second = notifier.run(() async {
      order.add('second-start');
      return 2;
    });

    await Future<void>.delayed(Duration.zero);
    expect(order, <String>['first-start']);

    firstGate.complete(1);

    expect(await first, 1);
    expect(await second, 2);
    expect(order, <String>['first-start', 'second-start']);
  });

  test('queued operation fails without running after dispose', () async {
    final notifier = _TestNotifier();
    final gate = Completer<int>();
    var queuedRan = false;

    final first = notifier.run(() => gate.future);
    final queued = notifier.run(() async {
      queuedRan = true;
      return 2;
    });

    final queuedExpectation = expectLater(queued, throwsStateError);
    notifier.dispose();
    gate.complete(1);

    await expectLater(first, throwsStateError);
    await queuedExpectation;
    expect(queuedRan, isFalse);
  });

  test('in-flight operation reports dispose instead of success', () async {
    final notifier = _TestNotifier();
    final gate = Completer<int>();
    final pending = notifier.run(() => gate.future);

    final pendingExpectation = expectLater(pending, throwsStateError);
    notifier.dispose();
    gate.complete(1);

    await pendingExpectation;
  });
}

class _TestNotifier extends ManagedChangeNotifier {
  Future<T> run<T>(Future<T> Function() operation) {
    return enqueueOperation(operation);
  }
}
