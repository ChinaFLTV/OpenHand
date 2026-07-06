import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/memory/index.dart';

void main() {
  test('cache anchor follows the actual leading request prefix', () {
    final first = _buildPromptWithTools(<AiToolDefinition>[
      _tool('Read', 'Read a file.'),
    ]);
    final second = _buildPromptWithTools(<AiToolDefinition>[
      _tool('Write', 'Write a file.'),
    ]);

    expect(first.metadata['stable_prefix_hash'], isNotEmpty);
    expect(
      first.metadata['stable_prefix_hash'],
      second.metadata['stable_prefix_hash'],
    );
    expect(
      first.metadata['tool_catalog_hash'],
      isNot(second.metadata['tool_catalog_hash']),
    );
    expect(
      first.metadata['cache_anchor_hash'],
      isNot(second.metadata['cache_anchor_hash']),
    );
    expect(
      first.metadata['stable_cache_key'],
      isNot(second.metadata['stable_cache_key']),
    );
  });
}

AiPromptBuildResult _buildPromptWithTools(List<AiToolDefinition> tools) {
  final now = DateTime.utc(2026, 7, 6);
  final template = AiPromptTemplateRepository().resolveTemplate(
    AiPromptTemplatePolicies.defaultTemplateId,
  );
  final latestUser = AiSessionMessage.user(
    id: 'user-1',
    content: 'hello',
    createdAt: now,
  );
  final session = AiSession(
    id: 'session-1',
    title: 'test',
    templateId: template.id,
    templateName: template.name,
    templateIconName: template.iconName,
    templateInternalVersion: template.internalVersion,
    createdAt: now,
    updatedAt: now,
    messages: <AiSessionMessage>[latestUser],
    environment: AiSessionEnvironment(
      localeTag: 'zh',
      platform: 'macOS',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '/tmp',
      homeDirectory: '/tmp',
      settingsFilePath: 'db://settings',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.json',
      sessionsDirectoryPath: '/tmp/sessions',
      compressionThresholdChars: 0,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
    fullAccessPermission: true,
  );

  return const AiPromptBuilder().buildConversationPrompt(
    templateBundle: AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'System instructions.',
      developerInstructions: 'Developer instructions.',
      compressionSummaryInstructions: 'No compressed conversation summary yet.',
    ),
    session: session,
    model: const AiModelConfig(
      id: 'model-1',
      baseUrl: 'https://gateway.example.com',
      authScheme: AiAuthScheme.bearer,
      token: 'token',
      modelId: 'gpt-test',
      protocolType: AiProtocolType.openai,
    ),
    runtimeContext: AiSessionRuntimeContext(
      localeTag: 'zh',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      settingsFilePath: 'db://settings',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.json',
      compressionThresholdChars: 0,
      memoryEnabled: false,
      memoryEntries: const <UserMemoryEntry>[],
      templateId: template.id,
      platformName: 'macos',
      workingDirectory: '/tmp/project',
      timeZoneName: 'CST',
      writeCommandConfirmationEnabled: false,
    ),
    memoryEntries: const <UserMemoryEntry>[],
    historyMessages: const <AiSessionMessage>[],
    latestUserMessage: latestUser,
    availableTools: tools,
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
