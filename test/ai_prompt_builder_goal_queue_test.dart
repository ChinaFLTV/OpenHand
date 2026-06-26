import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_goal.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  test('queued chat interruption omits paused goal user turn from prompt', () {
    final now = DateTime.utc(2026, 6, 26, 3, 50);
    final goal = AiSessionGoalRecord(
      id: 'goal-1',
      objective: '目标问题',
      status: AiSessionGoalStatus.paused,
      createdAt: now,
      updatedAt: now,
      pausedAt: now,
      evaluatorProviderConfigId: 'provider',
      evaluatorModelId: 'evaluator',
      evaluatorModelLabel: 'Evaluator',
      statusReason: aiSessionGoalPausedForQueueStatusReason,
    );
    final goalMessage = AiSessionMessage.user(
      id: 'user-goal',
      content: '目标问题',
      createdAt: now,
      metadata: const <String, Object?>{
        aiSessionMessageSenderOriginJsonKey:
            aiSessionMessageSenderOriginExplicitUser,
        aiSessionGoalIdMetadataKey: 'goal-1',
        aiSessionGoalObjectiveMetadataKey: true,
      },
    );
    final queuedMessage = AiSessionMessage.user(
      id: 'user-queued',
      content: '普通插队问题',
      createdAt: now.add(const Duration(seconds: 1)),
      metadata: const <String, Object?>{
        aiSessionMessageSenderOriginJsonKey:
            aiSessionMessageSenderOriginExplicitUser,
      },
    );
    final session = _session(
      now: now,
      messages: <AiSessionMessage>[goalMessage, queuedMessage],
      metadata: AiSessionGoalState(current: goal).toMetadataPatch(),
    );

    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: _templateBundle,
      session: session,
      model: _model,
      runtimeContext: _runtimeContext,
      memoryEntries: const <Never>[],
      sessionMessages: session.activeConversationMessagesForPrompt,
      latestUserMessageId: queuedMessage.id,
    );

    final userTurns = result.messages
        .where((turn) => turn.role == AiChatRole.user)
        .map((turn) => turn.content)
        .toList(growable: false);
    expect(userTurns, contains('普通插队问题'));
    expect(userTurns, isNot(contains('目标问题')));
    expect(
      result.messages
          .where((turn) => turn.role == AiChatRole.system)
          .map((turn) => turn.content)
          .join('\n'),
      contains('A goal is paused for queued user messages.'),
    );
  });
}

AiSession _session({
  required DateTime now,
  required List<AiSessionMessage> messages,
  required Map<String, Object?> metadata,
}) {
  return AiSession(
    id: 'session-1',
    title: 'Session',
    templateId: 'default',
    templateName: 'Default Assistant',
    templateIconName: AiThreadTemplateIcons.autoAwesomeRounded,
    templateInternalVersion: 'test',
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: _environment,
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
    metadata: metadata,
  );
}

const _template = AiThreadTemplate(
  id: 'default',
  name: 'Default Assistant',
  iconName: AiThreadTemplateIcons.autoAwesomeRounded,
  description: 'Default test template',
  internalVersion: 'test',
  promptAssetDirectory: 'test',
);

const _templateBundle = AiPromptTemplateBundle(
  template: _template,
  systemInstructions: 'System instructions.',
  developerInstructions: 'Developer instructions.',
  compressionSummaryInstructions: '',
);

const _model = AiModelConfig(
  id: 'provider',
  baseUrl: 'https://example.invalid',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'model',
  protocolType: AiProtocolType.openai,
);

const _environment = AiSessionEnvironment(
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

const _runtimeContext = AiSessionRuntimeContext(
  localeTag: 'zh-Hans',
  appVersion: 'test',
  appBuildNumber: '1',
  settingsFilePath: '/tmp/settings.json',
  skillsStoragePath: '/tmp/skills',
  mcpServersFilePath: '/tmp/mcp.json',
  userMemoryFilePath: '/tmp/memory.json',
  compressionThresholdChars: 100000,
  memoryEnabled: false,
  memoryEntries: <Never>[],
  platformName: 'test',
  workingDirectory: '/tmp/openhand',
  timeZoneName: 'CST',
);
