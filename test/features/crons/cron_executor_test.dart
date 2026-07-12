import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/cron_config.dart';
import 'package:openhand/features/crons/service/cron_executor.dart';

void main() {
  test('cron output is bounded without stopping pipe drainage', () async {
    if (Platform.isWindows) return;

    final workspace = await Directory.systemTemp.createTemp(
      'openhand_cron_output_test_',
    );
    try {
      final record = await CronExecutor.execute(
        _entry(
          "head -c 20000 /dev/zero | tr '\\0' x",
          workingDirectory: workspace.path,
        ),
      );

      expect(record.status, 'success');
      expect(record.exitCode, 0);
      expect(record.stdout.length, 8000);
    } finally {
      await workspace.delete(recursive: true);
    }
  });

  test('cron timeout terminates the complete descendant tree', () async {
    if (Platform.isWindows) return;

    final workspace = await Directory.systemTemp.createTemp(
      'openhand_cron_timeout_test_',
    );
    final pidFile = File('${workspace.path}/child.pid');
    int? childPid;
    try {
      final stopwatch = Stopwatch()..start();
      final record = await CronExecutor.execute(
        _entry(
          r'sleep 30 & child=$!; echo "$child" > "$CHILD_PID_FILE"; wait',
          timeoutSeconds: 1,
          workingDirectory: workspace.path,
          environment: <String, String>{'CHILD_PID_FILE': pidFile.path},
        ),
      );
      stopwatch.stop();

      expect(record.status, 'timed_out');
      expect(record.exitCode, -1);
      expect(record.pid, greaterThan(0));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 4)));
      childPid = await _readPid(pidFile);
      await _expectProcessStopped(childPid);
    } finally {
      _forceKill(childPid);
      await workspace.delete(recursive: true);
    }
  });

  test('real negative signal exit is not reported as a timeout', () async {
    if (Platform.isWindows) return;

    final workspace = await Directory.systemTemp.createTemp(
      'openhand_cron_signal_test_',
    );
    try {
      final record = await CronExecutor.execute(
        _entry(r'kill -HUP $$', workingDirectory: workspace.path),
      );

      expect(record.status, 'failed');
      expect(record.exitCode, lessThan(0));
      expect(record.errorMessage, isNot(contains('Timed out')));
    } finally {
      await workspace.delete(recursive: true);
    }
  });

  test(
    'cron cancellation handles an already running descendant tree',
    () async {
      if (Platform.isWindows) return;

      final workspace = await Directory.systemTemp.createTemp(
        'openhand_cron_cancel_test_',
      );
      final pidFile = File('${workspace.path}/child.pid');
      int? childPid;
      try {
        final handle = CronExecutor.start(
          _entry(
            r'sleep 30 & child=$!; echo "$child" > "$CHILD_PID_FILE"; wait',
            timeoutSeconds: 10,
            workingDirectory: workspace.path,
            environment: <String, String>{'CHILD_PID_FILE': pidFile.path},
          ),
        );
        childPid = await _readPid(pidFile);
        handle.cancel();

        final record = await handle.result.timeout(const Duration(seconds: 4));
        expect(record.status, 'killed');
        expect(record.pid, isNotNull);
        await _expectProcessStopped(childPid);
      } finally {
        _forceKill(childPid);
        await workspace.delete(recursive: true);
      }
    },
  );
}

CronEntry _entry(
  String script, {
  int timeoutSeconds = 5,
  required String workingDirectory,
  Map<String, String> environment = const <String, String>{},
}) {
  return CronEntry(
    id: 'test-cron',
    name: 'Test cron',
    scriptContent: script,
    timeoutSeconds: timeoutSeconds,
    workingDirectory: workingDirectory,
    environment: environment,
    collectAppMetadata: false,
    collectHostMetadata: false,
  );
}

Future<int> _readPid(File file) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (await file.exists()) {
      final value = int.tryParse((await file.readAsString()).trim());
      if (value != null) return value;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Child pid was not written before the test deadline');
}

Future<void> _expectProcessStopped(int processId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    final probe = await Process.run('/bin/kill', <String>['-0', '$processId']);
    if (probe.exitCode != 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Descendant process $processId is still running');
}

void _forceKill(int? processId) {
  if (processId == null) return;
  try {
    Process.killPid(processId, ProcessSignal.sigkill);
  } catch (_) {
    // The expected path already terminated the child.
  }
}
