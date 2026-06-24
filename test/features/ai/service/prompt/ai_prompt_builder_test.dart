import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  group('AiPromptBuilder cache-friendly history assembly', () {
    test('keeps consecutive continuation-looking user messages', () {
      final now = DateTime.utc(2026, 6, 24, 12);
      final session = _session(<AiSessionMessage>[
        AiSessionMessage.user(id: 'u1', content: '继续', createdAt: now),
        AiSessionMessage.user(
          id: 'u2',
          content: '继续吧',
          createdAt: now.add(const Duration(minutes: 1)),
        ),
        AiSessionMessage.user(
          id: 'u3',
          content: '继续处理',
          createdAt: now.add(const Duration(minutes: 2)),
        ),
      ]);

      final result = const AiPromptBuilder().buildSessionPrompt(
        templateBundle: _templateBundle,
        session: session,
        model: _model,
        runtimeContext: _runtimeContext,
        memoryEntries: const [],
        sessionMessages: session.messages,
        latestUserMessageId: 'u3',
      );

      final userTurns = result.messages
          .where((turn) => turn.role == AiChatRole.user)
          .map((turn) => turn.content)
          .toList(growable: false);

      expect(userTurns, containsAll(<String>['继续', '继续吧', '继续处理']));
      expect(userTurns.length, 3);
    });

    test('bounds long historical assistant messages', () {
      final now = DateTime.utc(2026, 6, 24, 12);
      final longAssistantReply = List<String>.filled(
        260,
        'assistant detail',
      ).join('\n');
      final session = _session(<AiSessionMessage>[
        AiSessionMessage.user(id: 'u1', content: 'start', createdAt: now),
        AiSessionMessage.assistant(
          id: 'a1',
          content: longAssistantReply,
          createdAt: now.add(const Duration(minutes: 1)),
        ),
        AiSessionMessage.user(
          id: 'u2',
          content: 'next',
          createdAt: now.add(const Duration(minutes: 2)),
        ),
      ]);

      final result = const AiPromptBuilder().buildSessionPrompt(
        templateBundle: _templateBundle,
        session: session,
        model: _model,
        runtimeContext: _runtimeContext,
        memoryEntries: const [],
        sessionMessages: session.messages,
        latestUserMessageId: 'u2',
      );

      final assistantTurn = result.messages.firstWhere(
        (turn) => turn.role == AiChatRole.assistant,
      );

      expect(
        assistantTurn.content,
        contains('[assistant_message_middle_omitted:'),
      );
      expect(assistantTurn.content.length, lessThan(longAssistantReply.length));
    });
  });
}

const AiPromptTemplateBundle _templateBundle = AiPromptTemplateBundle(
  template: AiThreadTemplate(
    id: AiPromptTemplatePolicies.defaultTemplateId,
    name: 'Default',
    iconName: 'auto_awesome_rounded',
    description: '',
    internalVersion: 'test',
    promptAssetDirectory: AiPromptTemplatePolicies.defaultPromptAssetDirectory,
  ),
  systemInstructions: 'System instructions.',
  developerInstructions: 'Developer instructions.',
  compressionSummaryInstructions: 'Compression instructions.',
);

const AiModelConfig _model = AiModelConfig(
  id: 'model',
  baseUrl: 'https://example.test',
  authScheme: AiAuthScheme.bearer,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

const AiSessionRuntimeContext _runtimeContext = AiSessionRuntimeContext(
  localeTag: 'zh-Hans',
  appVersion: 'test',
  appBuildNumber: '1',
  settingsFilePath: '',
  skillsStoragePath: '',
  mcpServersFilePath: '',
  userMemoryFilePath: '',
  compressionThresholdChars: 100000,
  memoryEnabled: false,
  memoryEntries: [],
  platformName: 'test',
  workingDirectory: '/tmp/openhand-test',
  timeZoneName: 'UTC',
);

AiSession _session(List<AiSessionMessage> messages) {
  final now = DateTime.utc(2026, 6, 24, 12);
  return AiSession(
    id: 'session',
    title: 'Test Session',
    templateId: AiPromptTemplatePolicies.defaultTemplateId,
    templateName: 'Default',
    templateIconName: 'auto_awesome_rounded',
    templateInternalVersion: 'test',
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'zh-Hans',
      platform: 'test',
      appVersion: 'test',
      appBuildNumber: '1',
      applicationDirectory: '/tmp/openhand',
      homeDirectory: '/tmp',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      sessionsDirectoryPath: '/tmp/openhand/sessions',
      compressionThresholdChars: 100000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const [],
  );
}
