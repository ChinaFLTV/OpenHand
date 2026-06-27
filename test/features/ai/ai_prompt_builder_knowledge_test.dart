import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/knowledge_base/index.dart';

void main() {
  group('AiPromptBuilder knowledge base context', () {
    test('appends knowledge context to the latest user turn', () {
      final now = DateTime.utc(2026, 6, 27);
      const knowledgeContext =
          '<OpenHandKnowledgeBaseContext>\n'
          '[KB-1]\n'
          'Title: Architecture Notes\n'
          'Content:\n'
          'Use Qdrant for local vector retrieval.\n'
          '</OpenHandKnowledgeBaseContext>';
      final latestUserMessage = AiSessionMessage.user(
        id: 'u1',
        content: 'How should the knowledge base retrieve local docs?',
        createdAt: now,
        metadata: const <String, Object?>{
          knowledgeBaseMessageMetadataKey: <String, Object?>{
            knowledgeBasePromptAppendMetadataKey: knowledgeContext,
          },
        },
      );

      final result = const AiPromptBuilder().buildConversationPrompt(
        templateBundle: _templateBundle,
        session: _session(now),
        model: _model,
        runtimeContext: _runtimeContext,
        memoryEntries: const [],
        historyMessages: const <AiSessionMessage>[],
        latestUserMessage: latestUserMessage,
      );

      final latestUserTurn = result.messages.lastWhere(
        (turn) => turn.role == AiChatRole.user,
      );
      expect(latestUserTurn.content, contains(latestUserMessage.content));
      expect(latestUserTurn.content, contains(knowledgeContext));
      expect(
        latestUserTurn.content.indexOf(latestUserMessage.content),
        lessThan(latestUserTurn.content.indexOf(knowledgeContext)),
      );
    });
  });
}

const AiThreadTemplate _template = AiThreadTemplate(
  id: AiPromptTemplatePolicies.defaultTemplateId,
  name: 'Default Assistant',
  iconName: AiThreadTemplateIcons.autoAwesomeRounded,
  description: 'Test template',
  internalVersion: 'test',
  promptAssetDirectory: AiPromptTemplatePolicies.defaultPromptAssetDirectory,
);

const AiPromptTemplateBundle _templateBundle = AiPromptTemplateBundle(
  template: _template,
  systemInstructions: 'You are OpenHand.',
  developerInstructions: '',
  compressionSummaryInstructions: '',
);

const AiModelConfig _model = AiModelConfig(
  id: 'provider',
  baseUrl: 'https://example.com/v1',
  authScheme: AiAuthScheme.bearer,
  token: 'token',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

const AiSessionRuntimeContext _runtimeContext = AiSessionRuntimeContext(
  localeTag: 'en-US',
  appVersion: 'test',
  appBuildNumber: '1',
  settingsFilePath: '/tmp/settings.json',
  skillsStoragePath: '/tmp/skills',
  mcpServersFilePath: '/tmp/mcp.json',
  userMemoryFilePath: '/tmp/memory.json',
  compressionThresholdChars: 200000,
  memoryEnabled: false,
  memoryEntries: [],
  templateId: AiPromptTemplatePolicies.defaultTemplateId,
);

AiSession _session(DateTime now) {
  return AiSession(
    id: 's1',
    title: 'Knowledge test',
    templateId: AiPromptTemplatePolicies.defaultTemplateId,
    templateName: 'Default Assistant',
    templateIconName: AiThreadTemplateIcons.autoAwesomeRounded,
    templateInternalVersion: 'test',
    createdAt: now,
    updatedAt: now,
    messages: const <AiSessionMessage>[],
    environment: const AiSessionEnvironment(
      localeTag: 'en-US',
      platform: 'test',
      appVersion: 'test',
      appBuildNumber: '1',
      applicationDirectory: '/tmp/app',
      homeDirectory: '/tmp',
      settingsFilePath: '/tmp/settings.json',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.json',
      sessionsDirectoryPath: '/tmp/sessions',
      compressionThresholdChars: 200000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}
