import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AiClaudeHookService', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('openhand-hook-test-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('matches newline-separated tool aliases independently', () async {
      final claudeDir = Directory(p.join(tempDir.path, '.claude'))
        ..createSync();
      File(p.join(claudeDir.path, 'settings.json')).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'hooks': <String, Object?>{
            'PreToolUse': <Object?>[
              <String, Object?>{
                'matcher': r'^Lsp$',
                'hooks': <Object?>[
                  <String, Object?>{
                    'type': 'command',
                    'command':
                        'printf \'{"additionalContext":"legacy lsp hook"}\'',
                  },
                ],
              },
            ],
          },
        }),
      );
      final service = AiClaudeHookService(
        applicationDirectoryPath: () => tempDir.path,
        homeDirectoryPath: () => tempDir.path,
      );

      final result = await service.runHooks(
        eventName: 'PreToolUse',
        sessionId: 'hook-test',
        matcherValue: 'LSP\nLsp',
        cwd: tempDir.path,
        payload: const <String, Object?>{'tool_name': 'LSP'},
      );

      expect(result.executedHookCount, 1);
      expect(result.systemReminders, contains('legacy lsp hook'));
    });
  });
}
