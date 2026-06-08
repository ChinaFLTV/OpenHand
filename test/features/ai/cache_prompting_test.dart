import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';

void main() {
  group('Claude prompt cache', () {
    test('adds stable-prefix and tail message breakpoints', () async {
      const adapter = ClaudeProtocolAdapter();
      const model = AiModelConfig(
        id: 'claude-test',
        baseUrl: 'https://api.anthropic.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'claude-test',
        protocolType: AiProtocolType.claude,
      );
      final turns = <AiChatTurn>[
        const AiChatTurn(role: AiChatRole.system, content: 'stable system'),
        for (var i = 0; i < 16; i++)
          AiChatTurn(
            role: i.isEven ? AiChatRole.user : AiChatRole.assistant,
            content: 'message $i',
          ),
      ];

      final body = await adapter.buildBody(
        model,
        turns,
        tools: const <AiToolDefinition>[
          AiToolDefinition(
            name: 'Read',
            description: 'Read a file.',
            parameters: <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{},
            },
          ),
        ],
        inputCacheConfig: const AiInputCacheRuntimeConfig(
          enabled: true,
          mode: 'allMessages',
          updateInterval: 10,
          breakpointCount: 4,
        ),
      );

      final systemBlocks = body['system'] as List<dynamic>;
      expect((systemBlocks.first as Map)['cache_control'], isNotNull);
      final tools = body['tools'] as List<dynamic>;
      expect((tools.last as Map)['cache_control'], isNotNull);

      final messages = body['messages'] as List<dynamic>;
      expect(_messageHasCacheControl(messages.first as Map), isTrue);
      expect(_messageHasCacheControl(messages.last as Map), isTrue);
    });

    test('flags enabled cache with missing request markers as drift', () {
      final now = DateTime.utc(2026, 6, 9, 12);
      final session = _sessionWithMessages(<AiSessionMessage>[
        AiSessionMessage.user(
          id: 'u1',
          content: '继续',
          createdAt: now,
          metadata: const <String, Object?>{
            'prompt_metadata': <String, Object?>{
              'cache_enabled': true,
              'idle_gap_seconds': 10,
              'stable_prefix_hash': 'abc',
              'previous_stable_prefix_hash': 'abc',
              'tool_catalog_hash': 'tools',
              'previous_tool_catalog_hash': 'tools',
            },
            'request_cache_control_marker_count': 0,
          },
        ),
        AiSessionMessage.assistant(
          id: 'a1',
          content: '继续推进。',
          createdAt: now.add(const Duration(seconds: 1)),
          usage: const AiTokenUsage(promptTokens: 50000, cacheReadTokens: 114),
        ),
      ]);

      final trend = SessionCacheHitTrend.fromSession(
        session,
        claudeStyle: true,
      );

      expect(trend.points, hasLength(1));
      expect(trend.points.first.prefixDriftSuspected, isTrue);
    });
  });
}

bool _messageHasCacheControl(Map<dynamic, dynamic> message) {
  final content = message['content'];
  if (content is List) {
    return content.whereType<Map>().any(
      (block) => block['cache_control'] != null,
    );
  }
  return message['cache_control'] != null;
}

AiSession _sessionWithMessages(List<AiSessionMessage> messages) {
  final now = DateTime.utc(2026, 6, 9, 12);
  return AiSession(
    id: 's1',
    title: 'cache test',
    templateId: 'default',
    templateName: 'Default',
    templateIconName: 'auto',
    templateInternalVersion: '1',
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'zh',
      platform: 'macos',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '/tmp',
      homeDirectory: '/tmp',
      settingsFilePath: '/tmp/settings.json',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.json',
      sessionsDirectoryPath: '/tmp/sessions',
      compressionThresholdChars: 0,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}
