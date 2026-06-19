import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_sections.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  group('AiPromptBuilder compression prompt', () {
    test('preserves effective permission and plan gate state', () {
      final now = DateTime.utc(2026, 6, 19, 8);
      final session = AiSession(
        id: 'session-1',
        title: 'Planning session',
        templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
        templateName: '编程专家',
        templateIconName: 'code_rounded',
        templateInternalVersion: 'test',
        createdAt: now,
        updatedAt: now,
        messages: <AiSessionMessage>[
          AiSessionMessage.user(
            id: 'u1',
            content: 'Plan the change',
            createdAt: now,
          ),
        ],
        environment: _testEnvironment,
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
        todoItems: const <AiSessionTodoItem>[
          AiSessionTodoItem(
            id: '1',
            content: 'Inspect code',
            status: 'in_progress',
          ),
        ],
        mode: AiSessionMode.plan,
        pendingPlan: '1. Inspect\n2. Change\n3. Verify',
        fullAccessPermission: true,
      );

      final turns = const AiPromptBuilder().buildCompressionPrompt(
        templateBundle: _testBundle,
        template: _testTemplate,
        session: session,
        runtimeContext: _testRuntimeContext,
        messagesToCompress: session.messages,
        previousCompressionPoint: null,
      );

      final payload = _compressionPayload(turns.last.content);
      final sessionState = payload['session_state'] as Map<String, Object?>;
      expect(sessionState['mode'], 'plan');
      expect(sessionState['full_access_permission'], isTrue);
      expect(sessionState['write_command_confirmation_enabled'], isTrue);
      expect(sessionState['write_command_confirmation_required'], isFalse);

      final planMode = sessionState['plan_mode'] as Map<String, Object?>;
      expect(planMode['has_incomplete_todo'], isTrue);
      expect(planMode['exit_plan_mode_available'], isTrue);
      expect(
        planMode['planning_tool_names'],
        containsAll(<String>['Lsp', 'CodebaseSearch']),
      );
      expect(
        planMode['tool_gate_reason'],
        'plan_mode_planning_with_exit_allowed',
      );
    });

    test('preserves write confirmation decision in compressed transcript', () {
      final now = DateTime.utc(2026, 6, 19, 8);
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'u1',
          content: 'Run the write command',
          createdAt: now,
        ),
        AiSessionMessage.toolResult(
          id: 't1',
          content:
              'status: rejected\n'
              'write_confirmation_decision: dismissed\n'
              'write_confirmation_dismissed: true',
          createdAt: now.add(const Duration(seconds: 1)),
          metadata: const <String, Object?>{
            'tool_name': 'Bash',
            'tool_execution_status': 'rejected',
            'tool_execution_is_write_command': true,
            'file_mutation_kind': 'bash_write',
            'tool_execution_working_directory': '/tmp/project',
            'tool_execution_write_analysis_reason': 'mutating command touch',
            'tool_execution_result':
                'status: rejected\n'
                'write_confirmation_decision: dismissed\n'
                'write_confirmation_dismissed: true',
            'write_confirmation_decision': 'dismissed',
            'write_confirmation_dismissed': true,
          },
        ),
      ];
      final session = AiSession(
        id: 'session-1',
        title: 'Write confirmation session',
        templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
        templateName: '编程专家',
        templateIconName: 'code_rounded',
        templateInternalVersion: 'test',
        createdAt: now,
        updatedAt: now,
        messages: messages,
        environment: _testEnvironment,
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
      );

      final turns = const AiPromptBuilder().buildCompressionPrompt(
        templateBundle: _testBundle,
        template: _testTemplate,
        session: session,
        runtimeContext: _testRuntimeContext,
        messagesToCompress: messages,
        previousCompressionPoint: null,
      );

      final content = turns.last.content;
      expect(content, contains('[write_result] Bash'));
      expect(content, contains('status: rejected'));
      expect(content, contains('write_confirmation_decision: dismissed'));
      expect(content, contains('write_confirmation_dismissed: true'));
      expect(content, contains('mutation: bash_write'));
      expect(content, contains('reason: mutating command touch'));
    });

    test(
      'surfaces write confirmation decision in post-compact focus context',
      () {
        final now = DateTime.utc(2026, 6, 19, 8);
        final messages = <AiSessionMessage>[
          AiSessionMessage.toolResult(
            id: 't1',
            content:
                'status: rejected\n'
                'write_confirmation_decision: dismissed\n'
                'write_confirmation_dismissed: true',
            createdAt: now,
            metadata: const <String, Object?>{
              'tool_name': 'Bash',
              'status': 'rejected',
              'command': 'touch /tmp/openhand-focus-test',
              'tool_execution_is_write_command': true,
              'write_confirmation_decision': 'dismissed',
              'write_confirmation_dismissed': true,
            },
          ),
          AiSessionMessage.compressionPoint(
            id: 'c1',
            content: 'Checkpoint after rejected write confirmation.',
            createdAt: now.add(const Duration(seconds: 1)),
            metadata: const <String, Object?>{},
          ),
          AiSessionMessage.user(
            id: 'u1',
            content: 'What happened before compaction?',
            createdAt: now.add(const Duration(seconds: 2)),
          ),
        ];
        final session = AiSession(
          id: 'session-1',
          title: 'Focus context session',
          templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
          templateName: '编程专家',
          templateIconName: 'code_rounded',
          templateInternalVersion: 'test',
          createdAt: now,
          updatedAt: now,
          messages: messages,
          environment: _testEnvironment,
          statistics: const AiSessionStatistics.initial(),
          recentErrors: const <AiSessionErrorRecord>[],
        );

        final result = const AiPromptBuilder().buildSessionPrompt(
          templateBundle: _testBundle,
          session: session,
          model: _testModel,
          runtimeContext: _testRuntimeContext,
          memoryEntries: const <Never>[],
          sessionMessages: messages,
          latestUserMessageId: 'u1',
        );
        final focusContext = result.messages
            .map((turn) => turn.content)
            .firstWhere(
              (content) =>
                  content.startsWith(AiPromptSectionHeaders.focusContext),
            );

        expect(focusContext, contains('Bash · status=rejected'));
        expect(focusContext, contains('write_confirmation=dismissed'));
        expect(focusContext, contains('cmd=touch /tmp/openhand-focus-test'));
      },
    );
  });
}

Map<String, Object?> _compressionPayload(String content) {
  final match = RegExp(
    r'# Compression Task Payload\s+```json\n([\s\S]*?)\n```',
  ).firstMatch(content);
  expect(match, isNotNull);
  final decoded = jsonDecode(match!.group(1)!);
  return Map<String, Object?>.from(decoded as Map);
}

const AiThreadTemplate _testTemplate = AiThreadTemplate(
  id: AiPromptTemplatePolicies.programmingExpertTemplateId,
  name: '编程专家',
  iconName: 'code_rounded',
  description: 'test',
  internalVersion: 'test',
  promptAssetDirectory:
      AiPromptTemplatePolicies.programmingExpertPromptAssetDirectory,
);

const AiPromptTemplateBundle _testBundle = AiPromptTemplateBundle(
  template: _testTemplate,
  systemInstructions: 'system',
  developerInstructions: 'developer',
  compressionSummaryInstructions: 'compression',
);

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

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

const AiSessionRuntimeContext _testRuntimeContext = AiSessionRuntimeContext(
  localeTag: 'zh-CN',
  appVersion: 'test',
  appBuildNumber: '1',
  settingsFilePath: '/tmp/settings.json',
  skillsStoragePath: '/tmp/skills',
  mcpServersFilePath: '/tmp/mcp.json',
  userMemoryFilePath: '/tmp/memory.json',
  compressionThresholdChars: 1000,
  memoryEnabled: false,
  memoryEntries: <Never>[],
  workingDirectory: '/tmp/project',
  platformName: 'macOS',
  timeZoneName: 'Asia/Shanghai',
);
