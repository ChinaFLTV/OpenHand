import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/app_runtime_cleanup_registry.dart';

void main() {
  test('cleanups run once in reverse registration order', () async {
    final calls = <String>[];
    final registry = AppRuntimeCleanupRegistry();
    registry.register('database', () => calls.add('database'));
    registry.register('controller', () async {
      await Future<void>.delayed(Duration.zero);
      calls.add('controller');
    });
    registry.register('listener', () => calls.add('listener'));

    final first = registry.dispose();
    final second = registry.dispose();
    await Future.wait<void>(<Future<void>>[first, second]);

    expect(calls, <String>['listener', 'controller', 'database']);
  });

  test('a failed cleanup does not skip remaining resources', () async {
    final calls = <String>[];
    final errors = <String>[];
    final registry = AppRuntimeCleanupRegistry(
      onError: (name, _, _) => errors.add(name),
    );
    registry.register('last', () => calls.add('last'));
    registry.register('broken', () => throw StateError('failed'));
    registry.register('first', () => calls.add('first'));

    await registry.dispose();

    expect(calls, <String>['first', 'last']);
    expect(errors, <String>['broken']);
  });
}
