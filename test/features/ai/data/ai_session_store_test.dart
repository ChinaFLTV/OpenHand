import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AiSessionStore plan allowed prompts', () {
    Directory? tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'openhand_session_store_test_',
      );
      if (DatabaseService.isInitialized) {
        await DatabaseService.instance.close();
      }
      await DatabaseService.initialize(
        databasePath: p.join(tempDir!.path, 'openhand.db'),
        useNoIsolateFactory: true,
      );
    });

    tearDown(() async {
      if (DatabaseService.isInitialized) {
        await DatabaseService.instance.close();
      }
      final dir = tempDir;
      tempDir = null;
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('persists pending plan and history allowed prompts', () async {
      final now = DateTime.utc(2026, 6, 19, 8);
      final store = AiSessionStore(
        sessionsDirectoryPath: p.join(tempDir!.path, 'sessions'),
      );
      final session = AiSession(
        id: 'session-1',
        title: 'Plan session',
        templateId: 'programming_expert',
        templateName: '编程专家',
        templateIconName: 'code_rounded',
        templateInternalVersion: 'test',
        createdAt: now,
        updatedAt: now,
        messages: const <AiSessionMessage>[],
        environment: _testEnvironment(tempDir!.path),
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
        awaitingPlanApproval: true,
        pendingPlan: '1. Patch\n2. Verify',
        pendingPlanAllowedPrompts: const <AiSessionPlanAllowedPrompt>[
          AiSessionPlanAllowedPrompt(
            tool: 'Bash',
            prompt: 'run targeted tests',
          ),
          AiSessionPlanAllowedPrompt(tool: 'Bash', prompt: 'build web assets'),
        ],
        planHistory: <AiSessionPlanRecord>[
          AiSessionPlanRecord(
            id: 'plan-1',
            createdAt: now,
            updatedAt: now,
            status: AiSessionPlanStatus.pendingApproval,
            plan: '1. Patch\n2. Verify',
            allowedPrompts: const <AiSessionPlanAllowedPrompt>[
              AiSessionPlanAllowedPrompt(
                tool: 'Bash',
                prompt: 'run targeted tests',
              ),
            ],
          ),
        ],
      );

      await store.save(session);

      final loaded = await store.loadSession('session-1');
      expect(loaded, isNotNull);
      expect(loaded!.pendingPlanAllowedPrompts, hasLength(2));
      expect(loaded.pendingPlanAllowedPrompts.first.tool, 'Bash');
      expect(
        loaded.pendingPlanAllowedPrompts.first.prompt,
        'run targeted tests',
      );
      expect(loaded.pendingPlanAllowedPrompts.last.prompt, 'build web assets');
      expect(loaded.planHistory.single.allowedPrompts, hasLength(1));
      expect(
        loaded.planHistory.single.allowedPrompts.single.prompt,
        'run targeted tests',
      );
    });
  });
}

AiSessionEnvironment _testEnvironment(String rootPath) {
  return AiSessionEnvironment(
    localeTag: 'zh-CN',
    platform: 'macOS',
    appVersion: 'test',
    appBuildNumber: '1',
    applicationDirectory: rootPath,
    homeDirectory: rootPath,
    settingsFilePath: p.join(rootPath, 'settings.json'),
    skillsStoragePath: p.join(rootPath, 'skills'),
    mcpServersFilePath: p.join(rootPath, 'mcp.json'),
    userMemoryFilePath: p.join(rootPath, 'memory.json'),
    sessionsDirectoryPath: p.join(rootPath, 'sessions'),
    compressionThresholdChars: 1000,
  );
}
