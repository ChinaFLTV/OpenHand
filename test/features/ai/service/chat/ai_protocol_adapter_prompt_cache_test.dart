import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';

void main() {
  const stableSystem = '# [0] Stable System\n\ncacheable template prefix';
  const dynamicTail = '# [3d] Dynamic Session State\n\n{"todos":1}';
  const cacheConfig = AiInputCacheRuntimeConfig(
    enabled: true,
    mode: 'allMessages',
    updateInterval: 10,
    breakpointCount: 4,
  );

  test('OpenAI compat normalizes post-user runtime system turns', () async {
    final body = await const OpenAiProtocolAdapter(AiProtocolType.openai)
        .buildBody(_model(AiProtocolType.openai), const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.system, content: stableSystem),
          AiChatTurn(role: AiChatRole.user, content: '第一轮之后的用户输入'),
          AiChatTurn(role: AiChatRole.system, content: dynamicTail),
        ], inputCacheConfig: cacheConfig);

    final messages = (body['messages'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(messages.map((item) => item['role']).toList(), <String>[
      'system',
      'user',
      'user',
    ]);
    expect(jsonEncode(messages.first), contains('cacheable template prefix'));
    expect(
      jsonEncode(messages.first).contains('Dynamic Session State'),
      isFalse,
    );
    final encodedMessages = jsonEncode(messages.skip(1).toList());
    expect(encodedMessages, contains('第一轮之后的用户输入'));
    expect(encodedMessages, contains('Dynamic Session State'));
    expect(encodedMessages, contains('<openhand_runtime_context>'));
  });

  test('OpenAI compat preserves tool-exchange system reminders', () async {
    final body = await const OpenAiProtocolAdapter(AiProtocolType.openai)
        .buildBody(_model(AiProtocolType.openai), const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.system, content: stableSystem),
          AiChatTurn(role: AiChatRole.user, content: '先读状态'),
          AiChatTurn(
            role: AiChatRole.assistant,
            content: '调用工具',
            toolCalls: <AiToolCall>[
              AiToolCall(id: 'call_1', name: 'Read', arguments: '{"path":"a"}'),
            ],
          ),
          AiChatTurn(
            role: AiChatRole.system,
            content: '# System Reminder\n\n工具结果前的运行态提示',
          ),
          AiChatTurn(
            role: AiChatRole.tool,
            toolCallId: 'call_1',
            content: '工具结果',
          ),
        ], inputCacheConfig: cacheConfig);

    final messages = (body['messages'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(messages.map((item) => item['role']).toList(), <String>[
      'system',
      'user',
      'assistant',
      'tool',
    ]);
    expect(
      jsonEncode(messages.skip(1).toList()).contains('"role":"system"'),
      isFalse,
    );
    final toolMessage = messages.last;
    expect(toolMessage['content'], contains('工具结果'));
    expect(toolMessage['content'], contains('[system_reminder]'));
    expect(toolMessage['content'], contains('工具结果前的运行态提示'));
  });

  test(
    'Claude keeps post-user runtime context out of top-level system',
    () async {
      final body = await const ClaudeProtocolAdapter()
          .buildBody(_model(AiProtocolType.claude), const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.system, content: stableSystem),
            AiChatTurn(role: AiChatRole.user, content: '第一轮之后的用户输入'),
            AiChatTurn(role: AiChatRole.system, content: dynamicTail),
          ], inputCacheConfig: cacheConfig);

      final encodedSystem = jsonEncode(body['system']);
      expect(encodedSystem, contains('cacheable template prefix'));
      expect(encodedSystem.contains('Dynamic Session State'), isFalse);

      final messages = body['messages'] as List<Object?>;
      expect(messages, hasLength(1));
      final encodedMessages = jsonEncode(messages);
      expect(encodedMessages, contains('第一轮之后的用户输入'));
      expect(encodedMessages, contains('Dynamic Session State'));
      expect(encodedMessages, contains('<openhand_runtime_context>'));
    },
  );

  test(
    'Gemini keeps post-user runtime context out of systemInstruction',
    () async {
      final body = await const GeminiProtocolAdapter()
          .buildBody(_model(AiProtocolType.gemini), const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.system, content: stableSystem),
            AiChatTurn(role: AiChatRole.user, content: '第一轮之后的用户输入'),
            AiChatTurn(role: AiChatRole.system, content: dynamicTail),
          ], inputCacheConfig: cacheConfig);

      final encodedSystem = jsonEncode(body['systemInstruction']);
      expect(encodedSystem, contains('cacheable template prefix'));
      expect(encodedSystem.contains('Dynamic Session State'), isFalse);

      final contents = body['contents'] as List<Object?>;
      expect(contents, hasLength(1));
      final encodedContents = jsonEncode(contents);
      expect(encodedContents, contains('第一轮之后的用户输入'));
      expect(encodedContents, contains('Dynamic Session State'));
      expect(encodedContents, contains('<openhand_runtime_context>'));
    },
  );

  test('protocol tool schemas are canonicalized for cache stability', () async {
    final adapters = <AiProtocolAdapter>[
      const OpenAiProtocolAdapter(AiProtocolType.openai),
      const ClaudeProtocolAdapter(),
      const GeminiProtocolAdapter(),
    ];
    for (final adapter in adapters) {
      final first = await adapter.buildBody(
        _model(adapter.protocolType),
        const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.system, content: stableSystem),
          AiChatTurn(role: AiChatRole.user, content: '测试工具 schema 排序'),
        ],
        tools: <AiToolDefinition>[
          _schemaTool(
            properties: <String, Object?>{
              'alpha': const <String, Object?>{'type': 'string'},
              'zeta': const <String, Object?>{
                'description': 'Tail field',
                'type': 'string',
              },
            },
            required: const <String>['zeta', 'alpha'],
          ),
        ],
      );
      final second = await adapter.buildBody(
        _model(adapter.protocolType),
        const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.system, content: stableSystem),
          AiChatTurn(role: AiChatRole.user, content: '测试工具 schema 排序'),
        ],
        tools: <AiToolDefinition>[
          _schemaTool(
            properties: <String, Object?>{
              'zeta': const <String, Object?>{
                'type': 'string',
                'description': 'Tail field',
              },
              'alpha': const <String, Object?>{'type': 'string'},
            },
            required: const <String>['alpha', 'zeta'],
          ),
        ],
      );

      expect(
        jsonEncode(first),
        jsonEncode(second),
        reason: adapter.protocolType.storageValue,
      );
    }
  });

  test('operation extras are canonicalized before request encoding', () async {
    const adapter = OpenAiProtocolAdapter(AiProtocolType.openai);
    const messages = <AiChatTurn>[
      AiChatTurn(role: AiChatRole.system, content: stableSystem),
      AiChatTurn(role: AiChatRole.user, content: '测试额外请求参数排序'),
    ];
    final first = await adapter.buildChatRequest(
      model: _model(AiProtocolType.openai).copyWith(
        operationExtras: <String, Object?>{
          'global': <String, Object?>{
            'top_z': <String, Object?>{'zeta': 2, 'alpha': 1},
            'query': <String, Object?>{'z': '9', 'a': '1'},
            'headers': <String, Object?>{'X-Z': '9', 'X-A': '1'},
            'body': <String, Object?>{
              'extra_z': <String, Object?>{'zeta': 2, 'alpha': 1},
              'extra_a': <Object?>[
                <String, Object?>{'zeta': 2, 'alpha': 1},
              ],
            },
          },
          AiApiFamily.chatCompletions.storageValue: <String, Object?>{
            'top_a': <String, Object?>{'zeta': 2, 'alpha': 1},
          },
        },
      ),
      messages: messages,
    );
    final second = await adapter.buildChatRequest(
      model: _model(AiProtocolType.openai).copyWith(
        operationExtras: <String, Object?>{
          AiApiFamily.chatCompletions.storageValue: <String, Object?>{
            'top_a': <String, Object?>{'alpha': 1, 'zeta': 2},
          },
          'global': <String, Object?>{
            'body': <String, Object?>{
              'extra_a': <Object?>[
                <String, Object?>{'alpha': 1, 'zeta': 2},
              ],
              'extra_z': <String, Object?>{'alpha': 1, 'zeta': 2},
            },
            'headers': <String, Object?>{'X-A': '1', 'X-Z': '9'},
            'query': <String, Object?>{'a': '1', 'z': '9'},
            'top_z': <String, Object?>{'alpha': 1, 'zeta': 2},
          },
        },
      ),
      messages: messages,
    );

    expect(first.url, second.url);
    expect(jsonEncode(first.headers), jsonEncode(second.headers));
    expect(jsonEncode(first.body), jsonEncode(second.body));
    expect(first.body.keys.last, 'messages');
    expect(jsonEncode(first.body['extra_z']), '{"alpha":1,"zeta":2}');
  });
}

AiModelConfig _model(AiProtocolType protocolType) {
  return AiModelConfig(
    id: 'test-${protocolType.storageValue}',
    baseUrl: switch (protocolType) {
      AiProtocolType.claude => 'https://api.anthropic.com',
      AiProtocolType.gemini => 'https://generativelanguage.googleapis.com',
      _ => 'https://example.invalid',
    },
    authScheme: AiAuthScheme.bearer,
    token: 'test-token',
    modelId: switch (protocolType) {
      AiProtocolType.claude => 'claude-test',
      AiProtocolType.gemini => 'gemini-test',
      _ => 'model-test',
    },
    protocolType: protocolType,
    maxTokens: 1024,
  );
}

AiToolDefinition _schemaTool({
  required Map<String, Object?> properties,
  required List<String> required,
}) {
  return AiToolDefinition(
    name: 'SchemaProbe',
    description: 'Schema order probe.',
    parameters: <String, Object?>{
      'type': 'object',
      'required': required,
      'properties': properties,
    },
  );
}
