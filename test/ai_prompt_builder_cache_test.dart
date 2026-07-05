import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('conversation prompt keeps consumed tool summaries cache-stable', () {
    final messages = _toolLoopMessages();
    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: _templateBundle,
      session: _session(messages),
      model: _model,
      runtimeContext: _runtimeContext(),
      memoryEntries: const [],
      sessionMessages: messages,
      latestUserMessageId: 'user-2',
    );

    final promptText = _promptText(result.messages);
    expect(promptText, contains('[tool_result_summary] AgentTaskTrack'));
    expect(promptText, isNot(contains('[old_tool_result_cleared]')));
  });

  test(
    'compression prompt micro-compacts old tool results only when enabled',
    () {
      final messages = _toolLoopMessages().take(10).toList(growable: false);
      final session = _session(messages);
      const builder = AiPromptBuilder();

      final enabledText = _promptText(
        builder.buildCompressionPrompt(
          templateBundle: _templateBundle,
          template: _template,
          session: session,
          runtimeContext: _runtimeContext(),
          messagesToCompress: messages,
          previousCompressionPoint: null,
        ),
      );
      final disabledText = _promptText(
        builder.buildCompressionPrompt(
          templateBundle: _templateBundle,
          template: _template,
          session: session,
          runtimeContext: _runtimeContext(microCompressionEnabled: false),
          messagesToCompress: messages,
          previousCompressionPoint: null,
        ),
      );

      expect(enabledText, contains('[old_tool_result_cleared] AgentTaskTrack'));
      expect(disabledText, isNot(contains('[old_tool_result_cleared]')));
      expect(disabledText, contains('[tool_result_summary] AgentTaskTrack'));
    },
  );
}

const _template = AiThreadTemplate(
  id: 'default',
  name: 'Default',
  iconName: AiThreadTemplateIcons.autoAwesomeRounded,
  description: 'Default test template',
  internalVersion: 'test',
  promptAssetDirectory: 'assets/prompts/default',
);

const _templateBundle = AiPromptTemplateBundle(
  template: _template,
  systemInstructions: 'You are OpenHand.',
  developerInstructions: 'Follow the user request.',
  compressionSummaryInstructions: 'Summarize the selected messages.',
);

const _model = AiModelConfig(
  id: 'test-provider',
  baseUrl: 'https://example.invalid/v1',
  authScheme: AiAuthScheme.bearer,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

AiSessionRuntimeContext _runtimeContext({bool microCompressionEnabled = true}) {
  return AiSessionRuntimeContext(
    localeTag: 'en',
    appVersion: 'test',
    appBuildNumber: '1',
    settingsFilePath: '',
    skillsStoragePath: '',
    mcpServersFilePath: '',
    userMemoryFilePath: '',
    compressionThresholdChars: 12000,
    toolResultCompressionThresholdChars: 200,
    microCompressionEnabled: microCompressionEnabled,
    memoryEnabled: false,
    memoryEntries: const [],
    templateId: 'default',
    workingDirectory: '/workspace',
    platformName: 'test',
    timeZoneName: 'UTC',
  );
}

AiSession _session(List<AiSessionMessage> messages) {
  final now = DateTime.utc(2026, 7, 5);
  return AiSession(
    id: 'session-1',
    title: 'Cache test',
    templateId: _template.id,
    templateName: _template.name,
    templateIconName: _template.iconName,
    templateInternalVersion: _template.internalVersion,
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'en',
      platform: 'test',
      appVersion: 'test',
      appBuildNumber: '1',
      applicationDirectory: '',
      homeDirectory: '',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      sessionsDirectoryPath: '',
      compressionThresholdChars: 12000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const [],
  );
}

List<AiSessionMessage> _toolLoopMessages() {
  final startedAt = DateTime.utc(2026, 7, 5, 1);
  return <AiSessionMessage>[
    AiSessionMessage.user(
      id: 'user-1',
      content: 'Use tools and continue.',
      createdAt: startedAt,
    ),
    ..._toolExchange(1, startedAt.add(const Duration(minutes: 1))),
    AiSessionMessage.assistant(
      id: 'assistant-1',
      content: 'First tool result consumed.',
      createdAt: startedAt.add(const Duration(minutes: 2)),
    ),
    ..._toolExchange(2, startedAt.add(const Duration(minutes: 3))),
    AiSessionMessage.assistant(
      id: 'assistant-2',
      content: 'Second tool result consumed.',
      createdAt: startedAt.add(const Duration(minutes: 4)),
    ),
    ..._toolExchange(3, startedAt.add(const Duration(minutes: 5))),
    AiSessionMessage.assistant(
      id: 'assistant-3',
      content: 'Third tool result consumed.',
      createdAt: startedAt.add(const Duration(minutes: 6)),
    ),
    AiSessionMessage.user(
      id: 'user-2',
      content: 'Continue.',
      createdAt: startedAt.add(const Duration(minutes: 7)),
    ),
  ];
}

List<AiSessionMessage> _toolExchange(int index, DateTime createdAt) {
  final callId = 'call-$index';
  return <AiSessionMessage>[
    AiSessionMessage.toolCall(
      id: 'tool-call-$index',
      content: '',
      createdAt: createdAt,
      metadata: <String, Object?>{
        'tool_call_id': callId,
        'tool_calls': <Map<String, Object?>>[
          <String, Object?>{
            'id': callId,
            'name': 'AgentTaskTrack',
            'arguments': '{"purpose":"inspect cache stability $index"}',
          },
        ],
      },
    ),
    AiSessionMessage.toolResult(
      id: 'tool-result-$index',
      content: _longToolResult(index),
      createdAt: createdAt.add(const Duration(seconds: 1)),
      metadata: <String, Object?>{
        'tool_call_id': callId,
        'tool_name': 'AgentTaskTrack',
        'status': 'success',
        'purpose': 'inspect cache stability $index',
      },
    ),
  ];
}

String _longToolResult(int index) {
  return List<String>.generate(
    30,
    (line) => 'result-$index line-$line /workspace/file_$index.dart:$line',
  ).join('\n');
}

String _promptText(Iterable<AiChatTurn> turns) {
  return turns.map((turn) => '${turn.roleName}\n${turn.content}').join('\n');
}
