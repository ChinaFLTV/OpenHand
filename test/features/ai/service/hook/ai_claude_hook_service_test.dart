import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';

void main() {
  test('JSON block decision stops remaining Claude hooks', () async {
    if (Platform.isWindows) return;

    final workspace = await Directory.systemTemp.createTemp(
      'openhand_claude_hook_block_test_',
    );
    final home = await Directory.systemTemp.createTemp(
      'openhand_claude_hook_home_',
    );
    final secondMarker = File('${workspace.path}/second-ran');
    try {
      await _writeHooks(workspace, 'PreToolUse', <String>[
        "printf '%s' '{\"decision\":\"block\",\"reason\":\"Denied by hook\"}'",
        'printf ran > ${_shellQuote(secondMarker.path)}',
      ]);
      final service = _service(workspace, home);

      final result = await service.runHooks(
        eventName: 'PreToolUse',
        sessionId: 'block-session',
        payload: const <String, Object?>{},
        cwd: workspace.path,
      );

      expect(result.blocked, isTrue);
      expect(result.blockReason, 'Denied by hook');
      expect(result.executedHookCount, 1);
      expect(await secondMarker.exists(), isFalse);
    } finally {
      await workspace.delete(recursive: true);
      await home.delete(recursive: true);
    }
  });

  test('Claude hook receives valid Unicode JSON through stdin', () async {
    if (Platform.isWindows) return;

    final workspace = await Directory.systemTemp.createTemp(
      'openhand_claude_hook_stdin_test_',
    );
    final home = await Directory.systemTemp.createTemp(
      'openhand_claude_hook_home_',
    );
    final capturedFile = File('${workspace.path}/stdin.json');
    try {
      await _writeHooks(workspace, 'SessionStart', <String>[
        'cat > ${_shellQuote(capturedFile.path)}; '
            "printf '%s' '{\"additionalContext\":\"hook ok\"}'",
      ]);
      final service = _service(workspace, home);

      final result = await service.runHooks(
        eventName: 'SessionStart',
        sessionId: 'unicode-session',
        payload: const <String, Object?>{'message': '你好 👋'},
        cwd: workspace.path,
      );

      final decoded = jsonDecode(await capturedFile.readAsString()) as Map;
      expect(decoded['hook_event_name'], 'SessionStart');
      expect(decoded['hookEventName'], 'SessionStart');
      expect(decoded['session_id'], 'unicode-session');
      expect(decoded['sessionId'], 'unicode-session');
      expect(decoded['message'], '你好 👋');
      expect(result.systemReminders, contains('hook ok'));
    } finally {
      await workspace.delete(recursive: true);
      await home.delete(recursive: true);
    }
  });

  test('Claude hook timeout terminates inherited descendant pipes', () async {
    if (Platform.isWindows) return;

    final workspace = await Directory.systemTemp.createTemp(
      'openhand_claude_hook_timeout_test_',
    );
    final home = await Directory.systemTemp.createTemp(
      'openhand_claude_hook_home_',
    );
    final pidFile = File('${workspace.path}/child.pid');
    int? childPid;
    try {
      await _writeHooks(workspace, 'Stop', <String>[
        'sleep 30 & child=\$!; echo "\$child" > '
            '${_shellQuote(pidFile.path)}; wait',
      ]);
      final service = _service(
        workspace,
        home,
        timeout: const Duration(milliseconds: 300),
      );

      final result = await service.runHooks(
        eventName: 'Stop',
        sessionId: 'timeout-session',
        payload: const <String, Object?>{},
        cwd: workspace.path,
      );

      expect(
        result.systemReminders,
        contains('Hook command timed out and was terminated.'),
      );
      childPid = await _readPid(pidFile);
      await _expectProcessStopped(childPid);
    } finally {
      _forceKill(childPid);
      await workspace.delete(recursive: true);
      await home.delete(recursive: true);
    }
  });
}

AiClaudeHookService _service(
  Directory workspace,
  Directory home, {
  Duration timeout = const Duration(seconds: 3),
}) {
  return AiClaudeHookService(
    applicationDirectoryPath: () => workspace.path,
    homeDirectoryPath: () => home.path,
    commandTimeout: timeout,
    configPresenceCacheTtl: Duration.zero,
  );
}

Future<void> _writeHooks(
  Directory workspace,
  String eventName,
  List<String> commands,
) async {
  final directory = Directory('${workspace.path}/.claude');
  await directory.create(recursive: true);
  await File('${directory.path}/settings.json').writeAsString(
    jsonEncode(<String, Object?>{
      'hooks': <String, Object?>{
        eventName: <Object?>[
          <String, Object?>{
            'matcher': '',
            'hooks': commands
                .map(
                  (command) => <String, Object?>{
                    'type': 'command',
                    'command': command,
                  },
                )
                .toList(growable: false),
          },
        ],
      },
    }),
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
