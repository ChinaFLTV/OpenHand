import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/hook_config.dart';
import 'package:openhand/features/hooks/service/hooks_executor.dart';

void main() {
  test('exit code two blocks remaining hooks', () async {
    if (Platform.isWindows) return;

    final workspace = await Directory.systemTemp.createTemp(
      'openhand_hook_block_test_',
    );
    final secondMarker = File('${workspace.path}/second-ran');
    try {
      final executor = _executor(<HookEntry>[
        _hook(id: 'block', script: "printf 'blocked by policy'; exit 2"),
        _hook(
          id: 'second',
          script: "printf ran > ${_shellQuote(secondMarker.path)}",
        ),
      ]);

      final result = await executor.executeEvent(
        event: HookEvent.sessionStart,
        sessionId: 'block-test',
      );

      expect(result.blocked, isTrue);
      expect(result.blockReason, 'blocked by policy');
      expect(result.executedCount, 1);
      expect(result.hookResults.single.status, 'blocked');
      expect(await secondMarker.exists(), isFalse);
    } finally {
      await workspace.delete(recursive: true);
    }
  });

  test('long output has a bounded preview and captured file', () async {
    if (Platform.isWindows) return;

    String? outputPath;
    try {
      final executor = _executor(<HookEntry>[
        _hook(id: 'output', script: "head -c 5000 /dev/zero | tr '\\0' x"),
      ]);

      final result = await executor.executeEvent(
        event: HookEvent.sessionStart,
        sessionId: 'output-test',
      );
      final hookResult = result.hookResults.single;
      outputPath = hookResult.stdoutFile;

      expect(hookResult.status, 'success');
      expect(hookResult.stdout, endsWith('...[truncated]'));
      expect(hookResult.stdout.length, lessThan(4100));
      expect(outputPath, isNotNull);
      expect((await File(outputPath!).readAsString()).length, 5000);
    } finally {
      if (outputPath != null) {
        final file = File(outputPath);
        if (await file.exists()) await file.delete();
      }
    }
  });

  test('timeout terminates hook descendants that inherit pipes', () async {
    if (Platform.isWindows) return;

    final workspace = await Directory.systemTemp.createTemp(
      'openhand_hook_timeout_test_',
    );
    final pidFile = File('${workspace.path}/child.pid');
    int? childPid;
    try {
      final executor = _executor(<HookEntry>[
        _hook(
          id: 'timeout',
          timeoutSeconds: 1,
          script:
              'sleep 30 & child=\$!; echo "\$child" > '
              '${_shellQuote(pidFile.path)}; wait',
        ),
      ]);

      final result = await executor.executeEvent(
        event: HookEvent.sessionStart,
        sessionId: 'timeout-test',
      );

      expect(result.timedOutCount, 1);
      expect(result.hookResults.single.status, 'timed_out');
      childPid = await _readPid(pidFile);
      await _expectProcessStopped(childPid);
    } finally {
      _forceKill(childPid);
      await workspace.delete(recursive: true);
    }
  });

  test('oversized payload remains valid bounded JSON on stdin', () async {
    if (Platform.isWindows) return;

    final workspace = await Directory.systemTemp.createTemp(
      'openhand_hook_context_test_',
    );
    final capturedFile = File('${workspace.path}/context.json');
    try {
      final executor = _executor(<HookEntry>[
        _hook(id: 'context', script: 'cat > ${_shellQuote(capturedFile.path)}'),
      ]);

      final result = await executor.executeEvent(
        event: HookEvent.sessionStart,
        sessionId: 'context-test',
        payload: <String, Object?>{'large': '界' * 300000},
      );

      expect(result.successCount, 1);
      final decoded = jsonDecode(await capturedFile.readAsString()) as Map;
      expect(decoded['_openhand_context_truncated'], isTrue);
      expect(decoded['_openhand_original_utf8_bytes'], greaterThan(512 * 1024));
      expect(decoded['session_id'], 'context-test');
    } finally {
      await workspace.delete(recursive: true);
    }
  });
}

HooksExecutor _executor(List<HookEntry> hooks) {
  return HooksExecutor.forTesting(
    enabledHooksForEvent: (event) => hooks
        .where((hook) => hook.event == event && hook.enabled && hook.hasScript)
        .toList(growable: false),
  );
}

HookEntry _hook({
  required String id,
  required String script,
  int timeoutSeconds = 5,
}) {
  return HookEntry(
    id: id,
    event: HookEvent.sessionStart,
    label: id,
    scriptContent: script,
    timeoutSeconds: timeoutSeconds,
  );
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

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
