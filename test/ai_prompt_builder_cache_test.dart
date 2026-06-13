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
  test('conversation history keeps consumed tool results cache-stable', () {
    final fixture = _PromptCacheFixture();
    final prompt = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: fixture.bundle,
      session: fixture.session,
      model: fixture.model,
      runtimeContext: fixture.runtimeContext,
      memoryEntries: const [],
      sessionMessages: fixture.session.messages,
      latestUserMessageId: 'u2',
    );

    final toolTurns = prompt.messages
        .where((turn) => turn.role == AiChatRole.tool)
        .toList(growable: false);

    expect(toolTurns, hasLength(1));
    expect(toolTurns.single.content, contains(fixture.rawToolResult));
    expect(toolTurns.single.content, isNot(contains('[tool_result_summary]')));
  });

  test('compression prompt still summarizes oversized tool results', () {
    final fixture = _PromptCacheFixture();
    final compressionPrompt = const AiPromptBuilder().buildCompressionPrompt(
      templateBundle: fixture.bundle,
      template: fixture.template,
      session: fixture.session,
      runtimeContext: fixture.runtimeContext,
      messagesToCompress: fixture.session.messages.take(4).toList(),
      previousCompressionPoint: null,
    );

    final payload = compressionPrompt
        .singleWhere((turn) => turn.role == AiChatRole.user)
        .content;

    expect(payload, contains('[tool_result_summary] Bash'));
    expect(payload, isNot(contains(fixture.rawToolResult)));
  });

  test(
    'explicit micro-compression still clears oldest consumed tool results',
    () {
      final fixture = _PromptCacheFixture(
        microCompressionEnabled: true,
        consumedToolResultCount: 6,
      );
      final prompt = const AiPromptBuilder().buildSessionPrompt(
        templateBundle: fixture.bundle,
        session: fixture.session,
        model: fixture.model,
        runtimeContext: fixture.runtimeContext,
        memoryEntries: const [],
        sessionMessages: fixture.session.messages,
        latestUserMessageId: 'u2',
      );

      final toolTurns = prompt.messages
          .where((turn) => turn.role == AiChatRole.tool)
          .toList(growable: false);

      expect(toolTurns, hasLength(6));
      expect(
        toolTurns.first.content,
        contains('[old_tool_result_cleared] Bash'),
      );
      expect(
        toolTurns.first.content,
        isNot(contains(fixture.rawToolResultFor(0))),
      );
      expect(toolTurns.last.content, contains(fixture.rawToolResultFor(5)));
    },
  );
}

class _PromptCacheFixture {
  _PromptCacheFixture({
    this.microCompressionEnabled = false,
    this.consumedToolResultCount = 1,
  });

  final bool microCompressionEnabled;
  final int consumedToolResultCount;

  final DateTime now = DateTime.utc(2026, 6, 13, 10);

  String rawToolResultFor(int index) =>
      'BEGIN-$index-${List<String>.filled(300, 'x').join()}-END';

  late final String rawToolResult = rawToolResultFor(0);

  late final AiThreadTemplate template = const AiThreadTemplate(
    id: 'default',
    name: 'Default Assistant',
    iconName: 'auto_awesome_rounded',
    description: 'test',
    internalVersion: 'test',
    promptAssetDirectory: 'assets/prompts/default',
  );

  late final AiPromptTemplateBundle bundle = AiPromptTemplateBundle(
    template: template,
    systemInstructions: 'System instructions.',
    developerInstructions: 'Developer instructions.',
    compressionSummaryInstructions: 'Compression instructions.',
  );

  late final AiModelConfig model = const AiModelConfig(
    id: 'model',
    baseUrl: 'https://example.test',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'deepseek-v4-flash',
    protocolType: AiProtocolType.deepseek,
  );

  late final AiSessionRuntimeContext runtimeContext = AiSessionRuntimeContext(
    localeTag: 'zh-Hans',
    appVersion: 'test',
    appBuildNumber: '1',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.md',
    compressionThresholdChars: 12000,
    toolResultCompressionThresholdChars: 100,
    toolResultCompressionHeadTailWindowChars: 12,
    microCompressionEnabled: microCompressionEnabled,
    memoryEnabled: false,
    memoryEntries: [],
    platformName: 'macos',
    workingDirectory: '/tmp/openhand',
    timeZoneName: 'CST',
  );

  late final AiSession session = AiSession(
    id: 's1',
    title: 'cache test',
    templateId: template.id,
    templateName: template.name,
    templateIconName: template.iconName,
    templateInternalVersion: template.internalVersion,
    createdAt: now,
    updatedAt: now,
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
      userMemoryFilePath: '/tmp/memory.md',
      sessionsDirectoryPath: '/tmp/sessions',
      compressionThresholdChars: 12000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const [],
    messages: _messages(),
  );

  List<AiSessionMessage> _messages() {
    final messages = <AiSessionMessage>[
      AiSessionMessage.user(id: 'u1', content: 'first', createdAt: now),
    ];
    for (var i = 0; i < consumedToolResultCount; i++) {
      messages
        ..add(
          AiSessionMessage.toolCall(
            id: 'tc$i',
            content: 'Tool call: Bash',
            createdAt: now.add(Duration(seconds: 1 + i * 3)),
            metadata: <String, Object?>{
              'tool_calls': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'call_$i',
                  'name': 'Bash',
                  'arguments': '{"command":"printf test"}',
                },
              ],
            },
          ),
        )
        ..add(
          AiSessionMessage.toolResult(
            id: 'tr$i',
            content: rawToolResultFor(i),
            createdAt: now.add(Duration(seconds: 2 + i * 3)),
            metadata: <String, Object?>{
              'tool_call_id': 'call_$i',
              'tool_name': 'Bash',
              'status': 'success',
            },
          ),
        )
        ..add(
          AiSessionMessage.assistant(
            id: 'a$i',
            content: 'consumed tool result $i',
            createdAt: now.add(Duration(seconds: 3 + i * 3)),
          ),
        );
    }
    messages.add(
      AiSessionMessage.user(
        id: 'u2',
        content: 'follow up',
        createdAt: now.add(Duration(seconds: 1 + consumedToolResultCount * 3)),
      ),
    );
    return messages;
  }
}
