import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/safe_subprocess.dart';

void main() {
  test('line-logging runner exposes the managed process handle', () async {
    final executable = Platform.isWindows ? 'cmd.exe' : '/bin/sh';
    final arguments = Platform.isWindows
        ? const <String>['/d', '/s', '/c', 'echo ready']
        : const <String>['-c', 'printf "ready\\n"'];
    Process? startedProcess;
    final lines = <String>[];

    final result = await runTrackedProcessWithLineLogging(
      executable,
      arguments,
      timeout: const Duration(seconds: 5),
      onProcessStarted: (process) => startedProcess = process,
      onStdoutLine: lines.add,
    );

    expect(startedProcess, isNotNull);
    expect(result.pid, startedProcess!.pid);
    expect(result.exitCode, 0);
    expect(result.timedOut, isFalse);
    expect(lines, contains('ready'));
  });

  test('exposed process handle can cancel a running command tree', () async {
    final executable = Platform.isWindows ? 'cmd.exe' : '/bin/sh';
    final arguments = Platform.isWindows
        ? const <String>['/d', '/s', '/c', 'ping -n 30 127.0.0.1 > nul']
        : const <String>['-c', 'sleep 30'];
    final stopped = Completer<void>();

    final result = await runTrackedProcessWithLineLogging(
      executable,
      arguments,
      timeout: const Duration(seconds: 10),
      onProcessStarted: (process) {
        unawaited(
          terminateTrackedProcessTree(
            process,
            gracefulTimeout: const Duration(milliseconds: 100),
          ).whenComplete(() {
            if (!stopped.isCompleted) stopped.complete();
          }),
        );
      },
    );
    await stopped.future.timeout(const Duration(seconds: 5));

    expect(result.timedOut, isFalse);
    expect(result.exitCode, isNot(0));
  });
}
