import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/app_runtime_cleanup_registry.dart';

void main() {
  test('运行时资源按注册逆序释放且重复调用共享同一流程', () async {
    final released = <String>[];
    final registry =
        AppRuntimeCleanupRegistry(
            cleanupTimeout: const Duration(milliseconds: 100),
            totalTimeout: const Duration(seconds: 1),
            onError: (name, error, stack) {
              fail('释放 $name 时不应失败：$error');
            },
          )
          ..register('第一项', () => released.add('第一项'))
          ..register('第二项', () => released.add('第二项'));

    await Future.wait<void>(<Future<void>>[
      registry.dispose(),
      registry.dispose(),
    ]);

    expect(released, <String>['第二项', '第一项']);
    expect(() => registry.register('过晚注册', () {}), throwsStateError);
  });

  test('单项卡住时按总预算继续触发后续释放', () async {
    final started = <String>[];
    final errors = <String>[];
    final registry =
        AppRuntimeCleanupRegistry(
            cleanupTimeout: const Duration(seconds: 1),
            totalTimeout: const Duration(milliseconds: 90),
            onError: (name, error, stack) => errors.add(name),
          )
          ..register('最终释放', () => started.add('最终释放'))
          ..register('卡住一', () {
            started.add('卡住一');
            return Completer<void>().future;
          })
          ..register('卡住二', () {
            started.add('卡住二');
            return Completer<void>().future;
          });

    final stopwatch = Stopwatch()..start();
    await registry.dispose();
    stopwatch.stop();

    expect(started, <String>['卡住二', '卡住一', '最终释放']);
    expect(errors, containsAll(<String>['卡住二', '卡住一']));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('拒绝非正数释放时限', () {
    expect(
      () => AppRuntimeCleanupRegistry(cleanupTimeout: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => AppRuntimeCleanupRegistry(totalTimeout: Duration.zero),
      throwsArgumentError,
    );
  });
}
