import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/service/ai_claude_hook_service.dart';

void main() {
  test(
    'AiClaudeHookService truncates large hook stdout without returning the full payload',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final rootDirectory = await Directory.systemTemp.createTemp(
        'openhand-hook-service-large-output-',
      );
      addTearDown(() async {
        if (rootDirectory.existsSync()) {
          await rootDirectory.delete(recursive: true);
        }
      });
      final homeDirectory = Directory('${rootDirectory.path}/home')
        ..createSync(recursive: true);
      final workspaceDirectory = Directory('${rootDirectory.path}/workspace')
        ..createSync(recursive: true);
      final configFile = File(
        '${workspaceDirectory.path}/.claude/settings.json',
      );
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode(<String, Object?>{
          'hooks': <String, Object?>{
            'Notification': <Object?>[
              <String, Object?>{
                'matcher': '',
                'hooks': <Object?>[
                  <String, Object?>{
                    'type': 'command',
                    'command': 'python3 -c "print(\'x\' * 5000)"',
                  },
                ],
              },
            ],
          },
        }),
        flush: true,
      );
      final service = AiClaudeHookService(
        applicationDirectoryPath: () => workspaceDirectory.path,
        homeDirectoryPath: () => homeDirectory.path,
      );

      final result = await service.runHooks(
        eventName: 'Notification',
        sessionId: 'hook-large-output',
        payload: const <String, Object?>{
          'notification_type': 'permission_prompt',
        },
        cwd: workspaceDirectory.path,
      );

      expect(result.systemReminders, hasLength(1));
      expect(result.systemReminders.single, endsWith('...[truncated]'));
      expect(result.systemReminders.single.length, lessThanOrEqualTo(4015));
      expect(result.loadedConfigPaths, <String>[configFile.path]);
    },
  );

  test(
    'AiClaudeHookService only reports successfully parsed hook config paths',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final rootDirectory = await Directory.systemTemp.createTemp(
        'openhand-hook-service-config-paths-',
      );
      addTearDown(() async {
        if (rootDirectory.existsSync()) {
          await rootDirectory.delete(recursive: true);
        }
      });
      final homeDirectory = Directory('${rootDirectory.path}/home')
        ..createSync(recursive: true);
      final workspaceDirectory = Directory('${rootDirectory.path}/workspace')
        ..createSync(recursive: true);
      final invalidHomeConfig = File(
        '${homeDirectory.path}/.claude/settings.json',
      );
      await invalidHomeConfig.parent.create(recursive: true);
      await invalidHomeConfig.writeAsString('{invalid', flush: true);
      final validWorkspaceConfig = File(
        '${workspaceDirectory.path}/.claude/settings.json',
      );
      await validWorkspaceConfig.parent.create(recursive: true);
      await validWorkspaceConfig.writeAsString(
        jsonEncode(<String, Object?>{
          'hooks': <String, Object?>{
            'Notification': <Object?>[
              <String, Object?>{
                'matcher': '',
                'hooks': <Object?>[
                  <String, Object?>{
                    'type': 'command',
                    'command': 'printf "config ok"',
                  },
                ],
              },
            ],
          },
        }),
        flush: true,
      );
      final service = AiClaudeHookService(
        applicationDirectoryPath: () => workspaceDirectory.path,
        homeDirectoryPath: () => homeDirectory.path,
      );

      final result = await service.runHooks(
        eventName: 'Notification',
        sessionId: 'hook-config-paths',
        payload: const <String, Object?>{
          'notification_type': 'permission_prompt',
        },
        cwd: workspaceDirectory.path,
      );

      expect(result.systemReminders, <String>['config ok']);
      expect(result.loadedConfigPaths, <String>[validWorkspaceConfig.path]);
    },
  );
}
