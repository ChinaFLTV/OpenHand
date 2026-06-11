import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/model/ai_api_dialect.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  group('AiPromptBuilder history cache normalization', () {
    const builder = AiPromptBuilder();

    test('openai-compatible history keeps only leading system turns', () {
      final result = builder.buildSessionPrompt(
        templateBundle: _templateBundle(),
        session: _session(),
        model: _model(apiDialect: AiApiDialect.openAiCompat),
        runtimeContext: _runtimeContext(),
        memoryEntries: const [],
        sessionMessages: _conversationMessages(),
        latestUserMessageId: 'user-2',
      );

      final firstNonSystemIndex = result.messages.indexWhere(
        (item) => item.role != AiChatRole.system,
      );
      expect(firstNonSystemIndex, greaterThan(0));
      final tailHasSystem = result.messages
          .skip(firstNonSystemIndex)
          .any((item) => item.role == AiChatRole.system);
      expect(
        tailHasSystem,
        isFalse,
        reason:
            'OpenAI-compatible auto prefix cache should not see mid-history system turns.',
      );

      final normalizedHistory = result.messages
          .where((item) => item.role != AiChatRole.system)
          .map((item) => item.content)
          .join('\n');
      expect(
        normalizedHistory,
        contains('[system_reminder] Read truncated a large file preview'),
      );
      expect(normalizedHistory, contains('[status] status: completed'));
      expect(
        normalizedHistory,
        contains('[file_mutation_summary] touched /tmp/demo.txt'),
      );
    });

    test('anthropic-native history preserves system artifacts', () {
      final result = builder.buildSessionPrompt(
        templateBundle: _templateBundle(),
        session: _session(),
        model: _model(apiDialect: AiApiDialect.anthropicNative),
        runtimeContext: _runtimeContext(),
        memoryEntries: const [],
        sessionMessages: _conversationMessages(),
        latestUserMessageId: 'user-2',
      );

      final firstNonSystemIndex = result.messages.indexWhere(
        (item) => item.role != AiChatRole.system,
      );
      expect(firstNonSystemIndex, greaterThan(0));
      final tailHasSystem = result.messages
          .skip(firstNonSystemIndex)
          .any((item) => item.role == AiChatRole.system);
      expect(
        tailHasSystem,
        isTrue,
        reason:
            'Anthropic-native prompts still rely on explicit mid-history system artifacts.',
      );
    });
  });
}

AiPromptTemplateBundle _templateBundle() {
  return const AiPromptTemplateBundle(
    template: AiThreadTemplate(
      id: 'programming_expert',
      name: '编程专家',
      iconName: 'code_rounded',
      description: 'test',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/programming_expert',
    ),
    systemInstructions: 'System instructions',
    developerInstructions: 'Developer instructions',
    compressionSummaryInstructions: 'Compression instructions',
  );
}

AiModelConfig _model({required AiApiDialect apiDialect}) {
  return AiModelConfig(
    id: 'test-model',
    baseUrl: 'https://example.com',
    authScheme: AiAuthScheme.bearer,
    token: 'token',
    modelId: 'deepseek-v4-flash',
    protocolType: AiProtocolType.deepseek,
    apiDialect: apiDialect,
  );
}

AiSession _session() {
  final now = DateTime.utc(2026, 6, 11, 12);
  return AiSession(
    id: 'session-1',
    title: 'Cache Test',
    templateId: 'programming_expert',
    templateName: '编程专家',
    templateIconName: 'code_rounded',
    templateInternalVersion: '1.0.0',
    createdAt: now,
    updatedAt: now,
    messages: const [],
    environment: const AiSessionEnvironment(
      localeTag: 'zh-CN',
      platform: 'macos',
      appVersion: '1.0.0',
      appBuildNumber: '1',
      applicationDirectory: '/app',
      homeDirectory: '/Users/test',
      settingsFilePath: '/settings.json',
      skillsStoragePath: '/skills',
      mcpServersFilePath: '/mcp.json',
      userMemoryFilePath: '/memory.json',
      sessionsDirectoryPath: '/sessions',
      compressionThresholdChars: 12000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const [],
  );
}

AiSessionRuntimeContext _runtimeContext() {
  return const AiSessionRuntimeContext(
    localeTag: 'zh-CN',
    appVersion: '1.0.0',
    appBuildNumber: '1',
    settingsFilePath: '/settings.json',
    skillsStoragePath: '/skills',
    mcpServersFilePath: '/mcp.json',
    userMemoryFilePath: '/memory.json',
    compressionThresholdChars: 12000,
    memoryEnabled: false,
    memoryEntries: [],
    platformName: 'macos',
    workingDirectory: '/workspace',
    timeZoneName: 'Asia/Shanghai',
  );
}

List<AiSessionMessage> _conversationMessages() {
  final t0 = DateTime.utc(2026, 6, 11, 12);
  return <AiSessionMessage>[
    AiSessionMessage.user(
      id: 'user-1',
      content: '请帮我看一下脚本是否安全。',
      createdAt: t0,
    ),
    AiSessionMessage.toolCall(
      id: 'tool-call-1',
      content: '**Read**',
      createdAt: t0.add(const Duration(seconds: 1)),
      metadata: const <String, Object?>{
        'tool_call_id': 'call-1',
        'tool_calls': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'call-1',
            'name': 'Read',
            'arguments': '{"file_path":"/tmp/demo.txt"}',
          },
        ],
      },
    ),
    AiSessionMessage.toolResult(
      id: 'tool-result-1',
      content: '1\tline one\n2\tline two\n3\tline three',
      createdAt: t0.add(const Duration(seconds: 2)),
      metadata: const <String, Object?>{
        'tool_call_id': 'call-1',
        'tool_name': 'Read',
        'status': 'success',
        'read_file_path': '/tmp/demo.txt',
        'hook_system_reminders': <String>[
          'Read truncated a large file preview: /tmp/demo.txt',
        ],
      },
    ),
    AiSessionMessage.status(
      id: 'status-1',
      content: 'status: completed',
      createdAt: t0.add(const Duration(seconds: 3)),
    ),
    AiSessionMessage(
      id: 'mutation-1',
      kind: AiSessionMessageKind.fileMutationSummary,
      role: AiSessionMessageRole.system,
      content: 'touched /tmp/demo.txt',
      createdAt: t0.add(const Duration(seconds: 4)),
      characterCount: 'touched /tmp/demo.txt'.length,
    ),
    AiSessionMessage.user(
      id: 'user-2',
      content: '继续分析一下潜在风险。',
      createdAt: t0.add(const Duration(seconds: 5)),
    ),
  ];
}
