import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_sections.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  group('AiPromptBuilder plan mode prompt', () {
    test('marks awaiting approval turns as no-tool turns', () {
      final now = DateTime.utc(2026, 6, 19, 8);
      final session = AiSession(
        id: 'session-1',
        title: 'Pending plan',
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
          AiSessionMessage.user(
            id: 'u2',
            content: 'Can you repeat the plan?',
            createdAt: now.add(const Duration(minutes: 1)),
          ),
        ],
        environment: _testEnvironment,
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
        todoItems: const <AiSessionTodoItem>[
          AiSessionTodoItem(
            id: '1',
            content: 'Inspect code',
            status: 'pending',
          ),
        ],
        mode: AiSessionMode.plan,
        awaitingPlanApproval: true,
        pendingPlan: '1. Inspect\n2. Change\n3. Verify',
      );

      final result = const AiPromptBuilder().buildSessionPrompt(
        templateBundle: _testBundle,
        session: session,
        model: _testModel,
        runtimeContext: _testRuntimeContext,
        memoryEntries: const <Never>[],
        sessionMessages: session.messages,
        latestUserMessageId: 'u2',
        displayCatalogOverride: const <AiToolDefinition>[_readTool],
      );

      expect(result.metadata['current_tool_count'], 0);
      expect(result.metadata['awaiting_plan_approval'], isTrue);
      expect(
        result.metadata['runtime_tool_gate_reason'],
        'awaiting_plan_approval',
      );

      final dynamicState = _jsonSection(
        result.messages,
        AiPromptSectionHeaders.dynamicSessionState,
      );
      final plan = Map<String, Object?>.from(dynamicState['plan'] as Map);
      expect(plan['awaiting_approval'], isTrue);
      expect(plan['available_tool_count'], 0);
      expect(plan['tool_gate_reason'], 'awaiting_plan_approval');

      final planReminder = result.messages
          .map((turn) => turn.content)
          .firstWhere(
            (content) =>
                content.startsWith(AiPromptSectionHeaders.planModeReminder),
          );
      expect(planReminder, contains('Do not call any tools in this turn'));
      expect(planReminder, contains('1. Inspect'));

      final toolCatalog = result.messages
          .map((turn) => turn.content)
          .firstWhere(
            (content) => content.startsWith(AiPromptSectionHeaders.toolCatalog),
          );
      expect(toolCatalog, contains('Read'));
    });
  });
}

Map<String, Object?> _jsonSection(List<AiChatTurn> messages, String header) {
  final content = messages
      .map((turn) => turn.content)
      .firstWhere((item) => item.startsWith(header));
  final match = RegExp(r'```json\n([\s\S]*?)\n```').firstMatch(content);
  expect(match, isNotNull);
  final decoded = jsonDecode(match!.group(1)!);
  return Map<String, Object?>.from(decoded as Map);
}

const AiToolDefinition _readTool = AiToolDefinition(
  name: 'Read',
  description: 'Read a file.',
  parameters: <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'file_path': <String, Object?>{'type': 'string'},
    },
    'required': <String>['file_path'],
    'additionalProperties': false,
  },
);

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

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
