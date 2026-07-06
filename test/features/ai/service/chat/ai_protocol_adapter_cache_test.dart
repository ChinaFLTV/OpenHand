import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test(
    'OpenAI-compatible cache body keeps messages last and prefix-extending',
    () async {
      final adapter = AiProtocolRegistry.adapterFor(AiProtocolType.openai);
      const model = AiModelConfig(
        id: 'test-openai',
        baseUrl: 'https://api.openai.com',
        authScheme: AiAuthScheme.bearer,
        token: 'test-token',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
        providerKind: AiProviderKind.openai,
        temperature: 0.2,
      );
      const cacheConfig = AiInputCacheRuntimeConfig(
        enabled: true,
        mode: 'allMessages',
        updateInterval: 10,
        breakpointCount: 4,
        cacheAffinityId: 'session-1',
        promptCacheKey: 'stable-prefix-key',
      );
      final tools = <AiToolDefinition>[
        const AiToolDefinition(
          name: 'Read',
          description: 'Read a local file.',
          parameters: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'path': <String, Object?>{'type': 'string'},
            },
            'required': <String>['path'],
          },
        ),
      ];
      final first = await adapter.buildChatRequest(
        model: model,
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.system, content: 'Stable system prompt.'),
          AiChatTurn(role: AiChatRole.user, content: 'first question'),
        ],
        tools: tools,
        stream: true,
        inputCacheConfig: cacheConfig,
      );
      final second = await adapter.buildChatRequest(
        model: model,
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.system, content: 'Stable system prompt.'),
          AiChatTurn(role: AiChatRole.user, content: 'first question'),
          AiChatTurn(role: AiChatRole.assistant, content: 'first answer'),
          AiChatTurn(role: AiChatRole.user, content: 'second question'),
        ],
        tools: tools,
        stream: true,
        inputCacheConfig: cacheConfig,
      );

      final keys = first.body.keys.toList(growable: false);
      expect(keys.last, AiPromptCacheAffinity.messagesBodyField);
      expect(
        keys.indexOf(AiPromptCacheAffinity.openAiPromptCacheKeyBodyField),
        lessThan(keys.indexOf(AiPromptCacheAffinity.messagesBodyField)),
      );
      expect(
        keys.indexOf('tools'),
        lessThan(keys.indexOf(AiPromptCacheAffinity.messagesBodyField)),
      );
      expect(
        first.body[AiPromptCacheAffinity.openAiPromptCacheKeyBodyField],
        'stable-prefix-key',
      );
      expect(
        second.body[AiPromptCacheAffinity.openAiPromptCacheKeyBodyField],
        'stable-prefix-key',
      );

      final firstJson = jsonEncode(first.body);
      final secondJson = jsonEncode(second.body);
      final lcp = _longestCommonPrefixLength(firstJson, secondJson);
      expect(lcp, greaterThanOrEqualTo(firstJson.length - 4));
    },
  );
}

int _longestCommonPrefixLength(String left, String right) {
  final maxLength = math.min(left.length, right.length);
  var index = 0;
  while (index < maxLength &&
      left.codeUnitAt(index) == right.codeUnitAt(index)) {
    index += 1;
  }
  return index;
}
