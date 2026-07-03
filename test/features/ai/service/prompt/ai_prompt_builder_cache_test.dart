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
  test('tool catalog order is stable when normalized names collide', () {
    final dashTool = _tool('Read-File', 'Dash variant.');
    final underscoreTool = _tool('Read_File', 'Underscore variant.');

    final first = _buildPrompt(<AiToolDefinition>[dashTool, underscoreTool]);
    final second = _buildPrompt(<AiToolDefinition>[underscoreTool, dashTool]);
    final firstCatalog = _toolCatalogText(first);
    final secondCatalog = _toolCatalogText(second);

    expect(firstCatalog, secondCatalog);
    expect(
      first.metadata['stable_prefix_hash'],
      second.metadata['stable_prefix_hash'],
    );
    expect(
      firstCatalog.indexOf('- Read-File:'),
      lessThan(firstCatalog.indexOf('- Read_File:')),
    );
  });
}

AiPromptBuildResult _buildPrompt(List<AiToolDefinition> tools) {
  final now = DateTime.utc(2026);
  final userMessage = AiSessionMessage.user(
    id: 'user-1',
    content: '测试工具目录排序',
    createdAt: now,
  );
  final session = AiSession(
    id: 'session-1',
    title: 'cache test',
    templateId: AiPromptTemplatePolicies.defaultTemplateId,
    templateName: 'Default',
    templateIconName: 'auto_awesome_rounded',
    templateInternalVersion: 'test',
    createdAt: now,
    updatedAt: now,
    messages: <AiSessionMessage>[userMessage],
    environment: _environment(),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
  );
  return const AiPromptBuilder().buildSessionPrompt(
    templateBundle: _templateBundle(),
    session: session,
    model: _model(),
    runtimeContext: _runtimeContext(),
    memoryEntries: const [],
    sessionMessages: session.messages,
    latestUserMessageId: userMessage.id,
    availableTools: tools,
    displayCatalogOverride: tools,
  );
}

AiToolDefinition _tool(String name, String description) {
  return AiToolDefinition(
    name: name,
    description: description,
    parameters: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  );
}

String _toolCatalogText(AiPromptBuildResult result) {
  return result.messages
      .firstWhere(
        (turn) =>
            turn.role == AiChatRole.system &&
            turn.content.startsWith(AiPromptSectionHeaders.toolCatalog),
      )
      .content;
}

AiPromptTemplateBundle _templateBundle() {
  return const AiPromptTemplateBundle(
    template: AiThreadTemplate(
      id: AiPromptTemplatePolicies.defaultTemplateId,
      name: 'Default',
      iconName: 'auto_awesome_rounded',
      description: 'Default test template',
      internalVersion: 'test',
      promptAssetDirectory:
          AiPromptTemplatePolicies.defaultPromptAssetDirectory,
    ),
    systemInstructions: 'System',
    developerInstructions: 'Developer',
    compressionSummaryInstructions: 'Compression',
  );
}

AiSessionRuntimeContext _runtimeContext() {
  return const AiSessionRuntimeContext(
    localeTag: 'zh-Hans',
    appVersion: 'test',
    appBuildNumber: '1',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.json',
    compressionThresholdChars: 100000,
    memoryEnabled: false,
    memoryEntries: [],
    platformName: 'test',
    workingDirectory: '/tmp/openhand-test',
    timeZoneName: 'UTC',
  );
}

AiSessionEnvironment _environment() {
  return const AiSessionEnvironment(
    localeTag: 'zh-Hans',
    platform: 'test',
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
  );
}

AiModelConfig _model() {
  return const AiModelConfig(
    id: 'model-1',
    baseUrl: 'https://example.invalid',
    authScheme: AiAuthScheme.bearer,
    token: 'token',
    modelId: 'test-model',
    protocolType: AiProtocolType.openai,
    maxTokens: 1024,
  );
}
