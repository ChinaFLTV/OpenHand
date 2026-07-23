import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/app_runtime_cleanup_registry.dart';

void main() {
  test('总时限耗尽后不再启动剩余清理', () async {
    var blockingCleanupStarted = false;
    var skippedCleanupStarted = false;
    final errors = <Object>[];
    final registry =
        AppRuntimeCleanupRegistry(
            cleanupTimeout: const Duration(seconds: 1),
            totalTimeout: const Duration(milliseconds: 10),
            onError: (ignoredName, error, ignoredStackTrace) =>
                errors.add(error),
          )
          ..register('应跳过的清理', () {
            skippedCleanupStarted = true;
          })
          ..register('阻塞清理', () {
            blockingCleanupStarted = true;
            sleep(const Duration(milliseconds: 30));
          });

    await registry.dispose();

    expect(blockingCleanupStarted, isTrue);
    expect(skippedCleanupStarted, isFalse);
    expect(errors.whereType<TimeoutException>(), hasLength(1));
  });
}
