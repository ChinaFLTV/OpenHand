import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';

void main() {
  group('AiSession plan allowed prompts', () {
    test('round-trips pending plan and plan history prompts through json', () {
      final now = DateTime.utc(2026, 6, 19, 8);
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
        environment: _testEnvironment,
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
        awaitingPlanApproval: true,
        pendingPlan: '1. Patch\n2. Verify',
        pendingPlanAllowedPrompts: const <AiSessionPlanAllowedPrompt>[
          AiSessionPlanAllowedPrompt(
            tool: 'Bash',
            prompt: 'run targeted tests',
          ),
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

      final decoded = AiSession.fromJson(session.toJson());

      expect(decoded.pendingPlanAllowedPrompts, hasLength(1));
      expect(decoded.pendingPlanAllowedPrompts.single.tool, 'Bash');
      expect(
        decoded.pendingPlanAllowedPrompts.single.prompt,
        'run targeted tests',
      );
      expect(decoded.planHistory.single.allowedPrompts, hasLength(1));
      expect(
        decoded.planHistory.single.allowedPrompts.single.prompt,
        'run targeted tests',
      );
    });
  });

  group('AiSessionTodoState', () {
    test('normalizes status strings before comparison', () {
      expect(AiSessionTodoState.isCompletedStatus(' Completed '), isTrue);
      expect(AiSessionTodoState.isIncompleteStatus(' pending '), isTrue);
      expect(AiSessionTodoState.isFailureStatus(' FAILED '), isTrue);
    });

    test('treats empty lists as not all completed', () {
      expect(
        AiSessionTodoState.hasIncomplete(const <AiSessionTodoItem>[]),
        isFalse,
      );
      expect(
        AiSessionTodoState.allCompleted(const <AiSessionTodoItem>[]),
        isFalse,
      );
      expect(
        AiSessionTodoState.hasFailure(const <AiSessionTodoItem>[]),
        isFalse,
      );
    });

    test('summarizes active and completed todo lists', () {
      const todos = <AiSessionTodoItem>[
        AiSessionTodoItem(id: '1', content: 'Inspect', status: 'completed'),
        AiSessionTodoItem(id: '2', content: 'Patch', status: 'in_progress'),
      ];

      expect(AiSessionTodoState.hasIncomplete(todos), isTrue);
      expect(AiSessionTodoState.allCompleted(todos), isFalse);
      expect(AiSessionTodoState.hasFailure(todos), isFalse);
    });

    test('keeps legacy failed statuses grouped as failures', () {
      const todos = <AiSessionTodoItem>[
        AiSessionTodoItem(id: '1', content: 'Retry build', status: 'blocked'),
        AiSessionTodoItem(
          id: '2',
          content: 'Run smoke test',
          status: 'cancelled',
        ),
      ];

      expect(AiSessionTodoState.hasIncomplete(todos), isTrue);
      expect(AiSessionTodoState.allCompleted(todos), isFalse);
      expect(AiSessionTodoState.hasFailure(todos), isTrue);
    });
  });
}

const AiSessionEnvironment _testEnvironment = AiSessionEnvironment(
  localeTag: 'zh-CN',
  platform: 'macOS',
  appVersion: 'test',
  appBuildNumber: '1',
  applicationDirectory: '/tmp/openhand',
  homeDirectory: '/tmp',
  settingsFilePath: '/tmp/settings.json',
  skillsStoragePath: '/tmp/skills',
  mcpServersFilePath: '/tmp/mcp.json',
  userMemoryFilePath: '/tmp/memory.json',
  sessionsDirectoryPath: '/tmp/sessions',
  compressionThresholdChars: 1000,
);
