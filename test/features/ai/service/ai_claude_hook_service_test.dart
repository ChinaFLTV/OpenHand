import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_claude_hook_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('parses SessionStart additionalContext as a system reminder', () async {
    final root = await Directory.systemTemp.createTemp('openhand_hook_test_');
    try {
      final home = Directory(p.join(root.path, 'home'))
        ..createSync(recursive: true);
      final workspace = Directory(p.join(root.path, 'workspace'))
        ..createSync(recursive: true);
      final claudeDir = Directory(p.join(workspace.path, '.claude'))
        ..createSync(recursive: true);
      final script = File(p.join(root.path, 'session_start_hook.sh'))
        ..writeAsStringSync('''#!/bin/sh
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Loaded workspace policy."}}'
''');
      await Process.run('chmod', <String>['+x', script.path]);
      final settings = File(p.join(claudeDir.path, 'settings.json'));
      settings.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'hooks': <String, Object?>{
            'SessionStart': <Object?>[
              <String, Object?>{
                'matcher': 'startup',
                'hooks': <Object?>[
                  <String, Object?>{
                    'type': 'command',
                    'command': _shellQuote(script.path),
                  },
                ],
              },
            ],
          },
        }),
      );

      final service = AiClaudeHookService(
        applicationDirectoryPath: () => workspace.path,
        homeDirectoryPath: () => home.path,
      );
      final result = await service.runHooks(
        eventName: 'SessionStart',
        sessionId: 'session-1',
        matcherValue: 'startup',
        cwd: workspace.path,
        payload: const <String, Object?>{'source': 'startup'},
      );

      expect(result.executedHookCount, 1);
      expect(result.systemReminders, contains('Loaded workspace policy.'));
    } finally {
      await root.delete(recursive: true);
    }
  });
}

String _shellQuote(String value) {
  return "'${value.replaceAll("'", "'\\''")}'";
}
