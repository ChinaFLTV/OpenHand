import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/safe_subprocess.dart';

void main() {
  test('二进制超时会回收进程组中的子孙进程', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;

    final directory = await Directory.systemTemp.createTemp(
      'openhand_subprocess_test_',
    );
    final marker = File(
      '${directory.path}${Platform.pathSeparator}unexpected-output',
    );
    addTearDown(() => directory.delete(recursive: true));

    final result = await runBinaryProcessWithTimeout(
      '/bin/sh',
      const <String>[
        '-c',
        '(sleep 0.5; printf late > "\$OPENHAND_MARKER") & wait',
      ],
      environment: <String, String>{'OPENHAND_MARKER': marker.path},
      timeout: const Duration(milliseconds: 80),
      startInNewProcessGroup: true,
      tag: 'safe_subprocess_test',
    );

    expect(result, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(await marker.exists(), isFalse);
  });

  test('系统打开器看门狗会回收超时启动器', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;

    final existingPids = trackedChildPidsSnapshot().toSet();
    final started = await runDetachedSystemOpen(
      '/bin/sleep',
      const <String>['10'],
      watchdog: const Duration(milliseconds: 20),
      tag: 'safe_subprocess_test',
    );

    expect(started, isTrue);
    final launcherPids = trackedChildPidsSnapshot()
        .where((pid) => !existingPids.contains(pid))
        .toSet();
    expect(launcherPids, hasLength(1));

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(trackedChildPidsSnapshot().where(launcherPids.contains), isEmpty);
  });

  test('全局清理会及时通知第五个已跟踪进程', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;

    final directory = await Directory.systemTemp.createTemp(
      'openhand_tracked_children_test_',
    );
    final marker = File(
      '${directory.path}${Platform.pathSeparator}received-term',
    );
    addTearDown(() async {
      await killAllTrackedChildren(gracefulTimeout: Duration.zero);
      await directory.delete(recursive: true);
    });

    for (var index = 0; index < 4; index += 1) {
      final blocker = await startTrackedProcess('/bin/sh', const <String>[
        '-c',
        'trap "" TERM; printf ready; sleep 10',
      ]);
      await blocker.stdout.first.timeout(const Duration(seconds: 1));
    }
    final observer = await startTrackedProcess(
      '/bin/sh',
      const <String>[
        '-c',
        'trap \'printf received > "\$OPENHAND_TERM_MARKER"; exit 0\' TERM; '
            'printf ready; while :; do :; done',
      ],
      environment: <String, String>{'OPENHAND_TERM_MARKER': marker.path},
    );
    await observer.stdout.first.timeout(const Duration(seconds: 1));
    expect(trackedChildPidsSnapshot(), contains(observer.pid));

    final cleanup = killAllTrackedChildren(
      gracefulTimeout: const Duration(seconds: 1),
    );
    expect(
      await _waitForFile(marker, const Duration(milliseconds: 500)),
      isTrue,
    );
    await cleanup;
  });

  test('全局清理会摘除已强杀进程组的登记', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;

    final process = await startTrackedProcessInNewGroup(
      '/bin/sh',
      const <String>['-c', 'trap "" TERM; printf ready; while :; do :; done'],
    );
    addTearDown(() => killAllTrackedChildren(gracefulTimeout: Duration.zero));
    await process.stdout.first.timeout(const Duration(seconds: 1));
    expect(trackedChildPidsSnapshot(), contains(process.pid));

    await killAllTrackedChildren(gracefulTimeout: Duration.zero);

    expect(trackedChildPidsSnapshot(), isNot(contains(process.pid)));
  });
}

Future<bool> _waitForFile(File file, Duration timeout) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    if (await file.exists()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return file.exists();
}
