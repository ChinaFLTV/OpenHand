import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/ai/service/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';

void main() {
  test('compression prompt uses concise no-tools identity', () {
    const template = AiThreadTemplate(
      id: 'machine_expert',
      name: '机器专家',
      iconName: 'build_circle_rounded',
      description: 'terminal workflow',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/machine_expert',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'FULL SYSTEM INSTRUCTIONS SHOULD NOT BE INCLUDED',
      developerInstructions: 'developer instructions',
      compressionSummaryInstructions: 'KEEP TERMINAL BINDING STATE',
    );
    final now = DateTime.utc(2026, 5, 3);
    final session = _session(
      template: template,
      now: now,
      messages: <AiSessionMessage>[
        AiSessionMessage.user(id: 'm1', content: '继续排查远端终端问题', createdAt: now),
      ],
    );

    final prompt = const AiPromptBuilder().buildCompressionPrompt(
      templateBundle: bundle,
      template: template,
      session: session,
      runtimeContext: _runtimeContext(),
      messagesToCompress: session.messages,
      previousCompressionPoint: null,
    );

    expect(prompt.first.content, contains('TEXT ONLY'));
    expect(prompt.first.content, contains('Do not call tools'));
    expect(
      prompt.first.content,
      isNot(contains('FULL SYSTEM INSTRUCTIONS SHOULD NOT BE INCLUDED')),
    );
    expect(prompt[1].content, contains('KEEP TERMINAL BINDING STATE'));
    expect(prompt.last.content, contains('继续排查远端终端问题'));
  });

  test('micro compact clears older consumed tool results', () {
    const template = AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description: 'default',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'system',
      developerInstructions: 'developer',
      compressionSummaryInstructions: 'compression',
    );
    final now = DateTime.utc(2026, 5, 3);
    final history = <AiSessionMessage>[
      AiSessionMessage.user(id: 'u1', content: 'run tools', createdAt: now),
      for (var i = 0; i < 7; i++) ...<AiSessionMessage>[
        _toolCall('tc$i', 'call$i', now),
        _toolResult('tr$i', 'call$i', 'raw result $i', now),
      ],
      AiSessionMessage.assistant(
        id: 'a1',
        content: 'consumed tool outputs',
        createdAt: now,
      ),
    ];
    final latest = AiSessionMessage.user(
      id: 'latest',
      content: 'continue',
      createdAt: now,
    );
    final messages = <AiSessionMessage>[...history, latest];
    final session = _session(template: template, now: now, messages: messages);

    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: messages,
      latestUserMessageId: latest.id,
    );
    final promptText = result.messages.map((turn) => turn.content).join('\n');

    expect(
      RegExp(r'\[old_tool_result_cleared\]').allMatches(promptText).length,
      2,
    );
    expect(promptText, isNot(contains('raw result 0')));
    expect(promptText, isNot(contains('raw result 1')));
    expect(promptText, contains('raw result 2'));
    expect(promptText, contains('raw result 6'));
  });

  test('records context budget metadata for prompt builds', () {
    const template = AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description: 'default',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'system',
      developerInstructions: 'developer',
      compressionSummaryInstructions: 'compression',
    );
    final now = DateTime.utc(2026, 5, 3);
    final latest = AiSessionMessage.user(
      id: 'latest',
      content: 'hello',
      createdAt: now,
    );
    final session = _session(template: template, now: now, messages: [latest]);

    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model(maxContextTokens: 1000),
      runtimeContext: _runtimeContext(),
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: [latest],
      latestUserMessageId: latest.id,
    );

    expect(
      result.metadata['current_prompt_character_count'],
      result.promptCharacterCount,
    );
    expect(
      result.metadata['context_budget_estimated_prompt_tokens'],
      isA<int>().having((value) => value, 'value', greaterThan(0)),
    );
    expect(result.metadata['context_budget_model_max_tokens'], 1000);
    expect(result.metadata['context_budget_summary_reserve_tokens'], 500);
    expect(result.metadata['context_budget_effective_window_tokens'], 500);
    expect(
      result.metadata['context_budget_auto_compact_threshold_tokens'],
      450,
    );
    expect(result.metadata['context_budget_status'], isNot('unknown'));
    expect(result.metadata['context_budget_usage_percent'], isA<int>());
    expect(result.metadata['context_budget_percent_left'], isA<int>());
  });
}

AiSessionMessage _toolCall(String id, String callId, DateTime now) {
  return AiSessionMessage.toolCall(
    id: id,
    content: 'Tool call $callId',
    createdAt: now,
    metadata: <String, Object?>{
      'tool_calls': <Map<String, Object?>>[
        <String, Object?>{
          'id': callId,
          'name': 'Bash',
          'arguments': '{"cmd":"echo $callId"}',
        },
      ],
    },
  );
}

AiSessionMessage _toolResult(
  String id,
  String callId,
  String content,
  DateTime now,
) {
  return AiSessionMessage.toolResult(
    id: id,
    content: content,
    createdAt: now,
    metadata: <String, Object?>{
      'tool_call_id': callId,
      'tool_name': 'Bash',
      'status': 'success',
    },
  );
}

AiModelConfig _model({int? maxContextTokens}) {
  return AiModelConfig(
    id: 'model',
    baseUrl: 'https://example.test/v1',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'test-model',
    protocolType: AiProtocolType.openai,
    maxContextTokens: maxContextTokens,
  );
}

AiSession _session({
  required AiThreadTemplate template,
  required DateTime now,
  required List<AiSessionMessage> messages,
}) {
  return AiSession(
    id: 'session-1',
    title: 'Compression Test',
    templateId: template.id,
    templateName: template.name,
    templateIconName: template.iconName,
    templateInternalVersion: template.internalVersion,
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'zh-Hans',
      platform: 'macos',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '/tmp/openhand',
      homeDirectory: '/tmp',
      settingsFilePath: '/tmp/settings.json',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.md',
      sessionsDirectoryPath: '/tmp/sessions',
      compressionThresholdChars: 12000,
    ),
    statistics: AiSessionStatistics.fromMessages(
      messages,
      totalPromptCharacters: 0,
      promptBuildCount: 0,
      compressionRunCount: 0,
      totalUsage: const AiTokenUsage(),
      lastPromptSystemMessageCount: 0,
      lastPromptHistoryMessageCount: 0,
    ),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}

AiSessionRuntimeContext _runtimeContext() {
  return const AiSessionRuntimeContext(
    localeTag: 'zh-Hans',
    appVersion: '0.1.0',
    appBuildNumber: '1',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.md',
    compressionThresholdChars: 12000,
    memoryEnabled: true,
    memoryEntries: <UserMemoryEntry>[],
  );
}
