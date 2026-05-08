import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';

void main() {
  group('AiPromptBuilder DSML instructions', () {
    test('do not forbid exact TodoWrite when TodoWrite is listed', () {
      final prompt = const AiPromptBuilder().buildSessionPrompt(
        templateBundle: _bundle,
        session: _session,
        model: _model,
        runtimeContext: _runtimeContext,
        memoryEntries: const [],
        sessionMessages: _session.messages,
        latestUserMessageId: _latestUserMessage.id,
        availableTools: const <AiToolDefinition>[_todoWriteDefinition],
        useDsmlToolCalls: true,
      );

      final catalog = prompt.messages
          .singleWhere((turn) => turn.content.startsWith('# [2] Tool Catalog'))
          .content;

      expect(catalog, contains('<DSML:function_calls>'));
      expect(catalog, contains('string="false"'));
      expect(catalog, contains('Use `TodoWrite` only when that exact name'));
      expect(catalog, isNot(contains('do NOT invent names like `TodoWrite`')));
      expect(catalog, contains('`##TOOL_CALL##` markers'));
    });
  });
}

final DateTime _now = DateTime.utc(2026);

final AiSessionMessage _latestUserMessage = AiSessionMessage.user(
  id: 'u1',
  content: '请整理一个三步计划',
  createdAt: _now,
);

final AiSession _session = AiSession(
  id: 's1',
  title: 'Prompt Builder Test',
  templateId: 'default',
  templateName: 'Default Assistant',
  templateIconName: 'auto_awesome_rounded',
  templateInternalVersion: 'test',
  createdAt: _now,
  updatedAt: _now,
  messages: <AiSessionMessage>[_latestUserMessage],
  environment: const AiSessionEnvironment(
    localeTag: 'zh-Hans',
    platform: 'macos',
    appVersion: 'test',
    appBuildNumber: '1',
    applicationDirectory: '/tmp/openhand',
    homeDirectory: '/tmp',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.json',
    sessionsDirectoryPath: '/tmp/sessions',
    compressionThresholdChars: 100000,
  ),
  statistics: const AiSessionStatistics.initial(),
  recentErrors: const [],
);

const AiSessionRuntimeContext _runtimeContext = AiSessionRuntimeContext(
  localeTag: 'zh-Hans',
  appVersion: 'test',
  appBuildNumber: '1',
  settingsFilePath: '/tmp/settings.json',
  skillsStoragePath: '/tmp/skills',
  mcpServersFilePath: '/tmp/mcp.json',
  userMemoryFilePath: '/tmp/memory.json',
  compressionThresholdChars: 100000,
  memoryEnabled: true,
  memoryEntries: [],
  workingDirectory: '/tmp/openhand',
  platformName: 'macos',
  todayLocalDate: '2026-01-01',
  timeZoneName: 'UTC',
);

const AiModelConfig _model = AiModelConfig(
  id: 'm1',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

const AiPromptTemplateBundle _bundle = AiPromptTemplateBundle(
  template: AiThreadTemplate(
    id: 'default',
    name: 'Default Assistant',
    iconName: 'auto_awesome_rounded',
    description: 'test',
    internalVersion: 'test',
    promptAssetDirectory: 'assets/prompts/default',
  ),
  systemInstructions: 'System instructions.',
  developerInstructions: 'Developer instructions.',
  compressionSummaryInstructions: 'Compression instructions.',
);

const AiToolDefinition _todoWriteDefinition = AiToolDefinition(
  name: 'TodoWrite',
  description: 'Create or update the structured todo list.',
  parameters: <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'todos': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'object'},
      },
    },
    'required': <String>['todos'],
  },
);
