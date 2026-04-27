import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';

AiSession _stubSession() {
  final now = DateTime.utc(2026, 4, 26);
  return AiSession(
    id: 'sess-test',
    title: 'Test',
    templateId: 'default',
    templateName: 'Default',
    templateIconName: 'auto_awesome_rounded',
    templateInternalVersion: '1.0.0',
    createdAt: now,
    updatedAt: now,
    messages: const [],
    environment: const AiSessionEnvironment(
      localeTag: 'en',
      platform: 'test',
      appVersion: '0.0.0',
      appBuildNumber: '0',
      applicationDirectory: '',
      homeDirectory: '',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      sessionsDirectoryPath: '',
      compressionThresholdChars: 0,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const [],
  );
}

AiSessionRuntimeContext _stubRuntimeContext() {
  return const AiSessionRuntimeContext(
    localeTag: 'en',
    appVersion: '0.0.0',
    appBuildNumber: '0',
    settingsFilePath: '',
    skillsStoragePath: '',
    mcpServersFilePath: '',
    userMemoryFilePath: '',
    compressionThresholdChars: 0,
    memoryEnabled: false,
    memoryEntries: [],
  );
}

AiPromptTemplateBundle _stubBundle() {
  return const AiPromptTemplateBundle(
    template: AiThreadTemplate(
      id: 'default',
      name: 'Default',
      iconName: 'auto_awesome_rounded',
      description: 'test',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    ),
    systemInstructions: 'system',
    developerInstructions: 'developer',
    compressionSummaryInstructions: 'compress',
  );
}

const _model = AiModelConfig(
  id: 'm-test',
  baseUrl: 'https://example.invalid',
  authScheme: AiAuthScheme.bearer,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

const _toolDef = AiToolDefinition(
  name: 'Bash',
  description: 'Execute a shell command.',
  parameters: <String, Object?>{},
);

void main() {
  const builder = AiPromptBuilder();
  final bundle = _stubBundle();
  final session = _stubSession();
  final ctx = _stubRuntimeContext();

  String catalogMessage(List<String> contents) {
    return contents.firstWhere((c) => c.startsWith('# [2] Tool Catalog'));
  }

  test('useDsmlToolCalls=true 注入 DSML 调用格式说明', () {
    final result = builder.buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model,
      runtimeContext: ctx,
      memoryEntries: const [],
      sessionMessages: const [],
      availableTools: const [_toolDef],
      useDsmlToolCalls: true,
    );
    final catalog = catalogMessage(
      result.messages.map((m) => m.content).toList(),
    );
    expect(catalog, contains('Tool Invocation Format (DSML)'));
    expect(catalog, contains('<DSML:function_calls>'));
    expect(catalog, contains('<DSML:invoke name='));
    expect(catalog, contains('<DSML:parameter name='));
    expect(catalog, contains('##TOOL_CALL##'),
        reason: '应明确禁止模型使用 ##TOOL_CALL## 信封等错误格式');
    expect(catalog, contains('Bash'));
  });

  test('useDsmlToolCalls=false 时不注入 DSML 说明', () {
    final result = builder.buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model,
      runtimeContext: ctx,
      memoryEntries: const [],
      sessionMessages: const [],
      availableTools: const [_toolDef],
    );
    final catalog = catalogMessage(
      result.messages.map((m) => m.content).toList(),
    );
    expect(catalog, isNot(contains('Tool Invocation Format (DSML)')));
    expect(catalog, isNot(contains('<DSML:function_calls>')));
    expect(catalog, contains('Bash'));
  });

  test('availableTools 为空时不注入 DSML 说明（即使 useDsmlToolCalls=true）', () {
    final result = builder.buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model,
      runtimeContext: ctx,
      memoryEntries: const [],
      sessionMessages: const [],
      useDsmlToolCalls: true,
    );
    final catalog = catalogMessage(
      result.messages.map((m) => m.content).toList(),
    );
    expect(catalog, isNot(contains('Tool Invocation Format (DSML)')));
  });
}
