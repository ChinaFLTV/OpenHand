import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/safe_subprocess.dart';

void main() {
  test('stdin bytes are delivered and EOF is closed', () async {
    if (Platform.isWindows) return;

    Process? startedProcess;
    var startCallbackCount = 0;
    final result = await runProcessWithTimeout(
      '/bin/sh',
      const <String>['-c', r'IFS= read -r value; printf "<%s>" "$value"'],
      stdinBytes: utf8.encode('hello\n'),
      timeout: const Duration(seconds: 2),
      onProcessStarted: (process) {
        startCallbackCount += 1;
        startedProcess = process;
      },
    );

    expect(result, isNotNull);
    expect(result!.exitCode, 0);
    expect(result.stdout, '<hello>');
    expect(startCallbackCount, 1);
    expect(startedProcess?.pid, result.pid);
  });

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

  test(
    'normal parent exit still terminates descendants holding pipes',
    () async {
      if (Platform.isWindows) return;

      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_process_pipe_test_',
      );
      final pidFile = File('${tempDirectory.path}/child.pid');
      int? childPid;
      try {
        final stopwatch = Stopwatch()..start();
        final result = await runProcessWithTimeout(
          '/bin/sh',
          const <String>[
            '-c',
            r'sleep 30 & child=$!; echo "$child" > "$CHILD_PID_FILE"; exit 0',
          ],
          environment: <String, String>{'CHILD_PID_FILE': pidFile.path},
          timeout: const Duration(seconds: 5),
          gracefulShutdownMs: 30,
        );
        stopwatch.stop();

        expect(result, isNotNull);
        expect(result!.exitCode, 0);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
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
    },
  );

  test('line logging bounds a stream without newline delimiters', () async {
    if (Platform.isWindows) return;

    final lines = <String>[];
    final result = await runTrackedProcessWithLineLogging(
      '/bin/sh',
      const <String>['-c', "head -c 2097152 /dev/zero | tr '\\0' x"],
      timeout: const Duration(seconds: 5),
      maxCapturedLinesPerStream: 1,
      maxLineCharacters: 128,
      onStdoutLine: lines.add,
    );

    expect(result.exitCode, 0);
    expect(result.timedOut, isFalse);
    expect(lines, hasLength(1));
    expect(lines.single, endsWith('…'));
    expect(lines.single.length, lessThanOrEqualTo(129));
    expect(result.stdout, lines.single);
  });

  test('line logging cleans descendants after parent exits', () async {
    if (Platform.isWindows) return;

    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_line_process_pipe_test_',
    );
    final pidFile = File('${tempDirectory.path}/child.pid');
    int? childPid;
    try {
      final result = await runTrackedProcessWithLineLogging(
        '/bin/sh',
        const <String>[
          '-c',
          r'sleep 30 & child=$!; echo "$child" > "$CHILD_PID_FILE"; exit 0',
        ],
        environment: <String, String>{'CHILD_PID_FILE': pidFile.path},
        timeout: const Duration(seconds: 5),
        gracefulTerminationTimeout: const Duration(milliseconds: 30),
      );

      expect(result.exitCode, 0);
      expect(result.timedOut, isFalse);
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
