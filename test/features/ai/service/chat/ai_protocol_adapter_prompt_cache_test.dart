import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
