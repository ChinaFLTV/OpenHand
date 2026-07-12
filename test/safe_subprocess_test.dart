import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/safe_subprocess.dart';

void main() {
  test('text subprocess capture remains bounded without line breaks', () async {
    if (Platform.isWindows) return;

    final result = await runProcessWithTimeout(
      '/bin/sh',
      const <String>['-c', "head -c 2097152 /dev/zero | tr '\\0' x"],
      timeout: const Duration(seconds: 5),
      maxStdoutBytes: 4096,
      maxStderrBytes: 1024,
    );

    expect(result, isNotNull);
    expect(result!.exitCode, 0);
    expect((result.stdout as String).length, 4096);
    expect(result.stderr, isEmpty);
  });

  test('timeout terminates a continuously writing process', () async {
    if (Platform.isWindows) return;

    final stopwatch = Stopwatch()..start();
    final result = await runProcessWithTimeout(
      '/bin/sh',
      const <String>['-c', 'while :; do printf x; done'],
      timeout: const Duration(milliseconds: 100),
      gracefulShutdownMs: 50,
      maxStdoutBytes: 1024,
      maxStderrBytes: 1024,
    );
    stopwatch.stop();

    expect(result, isNull);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('timeout terminates descendants that inherit process pipes', () async {
    if (Platform.isWindows) return;

    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_process_tree_test_',
    );
    final pidFile = File('${tempDirectory.path}/child.pid');
    int? childPid;
    try {
      final result = await runProcessWithTimeout(
        '/bin/sh',
        const <String>[
          '-c',
          r'sleep 30 & child=$!; echo "$child" > "$CHILD_PID_FILE"; wait',
        ],
        environment: <String, String>{'CHILD_PID_FILE': pidFile.path},
        timeout: const Duration(milliseconds: 300),
        gracefulShutdownMs: 30,
      );

      expect(result, isNull);
      childPid = int.tryParse((await pidFile.readAsString()).trim());
      expect(childPid, isNotNull);

      final deadline = DateTime.now().add(const Duration(seconds: 2));
      var alive = true;
      while (alive && DateTime.now().isBefore(deadline)) {
        final probe = await Process.run('/bin/kill', <String>[
          '-0',
          '$childPid',
        ]);
        alive = probe.exitCode == 0;
        if (alive) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      expect(alive, isFalse);
    } finally {
      if (childPid != null) {
        try {
          Process.killPid(childPid, ProcessSignal.sigkill);
        } catch (_) {
          // The expected path already terminated the child.
        }
      }
      await tempDirectory.delete(recursive: true);
    }
  });
}
