import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test(
    'grok chat requests carry stable conversation affinity header',
    () async {
      const adapter = OpenAiProtocolAdapter(AiProtocolType.grok);
      final request = await adapter.buildChatRequest(
        model: _model(
          protocolType: AiProtocolType.grok,
          baseUrl: 'https://api.x.ai',
          modelId: 'grok-composer-2.5-fast',
        ),
        messages: _messages,
        stream: true,
        inputCacheConfig: _cacheConfig,
      );

      expect(
        request.headers[AiPromptCacheAffinity.grokConversationHeader],
        'session-1',
      );
      expect(request.body.containsKey('session_id'), isFalse);
    },
  );

  test(
    'grok-compatible custom gateways use composite cache affinity',
    () async {
      const adapter = OpenAiProtocolAdapter(AiProtocolType.openai);
      final request = await adapter.buildChatRequest(
        model: _model(
          protocolType: AiProtocolType.openai,
          baseUrl: 'http://127.0.0.1:3000',
          modelId: 'grok-composer-2.5-fast',
        ),
        messages: _messages,
        stream: true,
        inputCacheConfig: _cacheConfig,
      );

      expect(
        request.headers[AiPromptCacheAffinity.grokConversationHeader],
        'session-1',
      );
      expect(
        request.body[AiPromptCacheAffinity.openAiPromptCacheKeyBodyField],
        'session-1',
      );
      final bodyKeys = request.body.keys.toList(growable: false);
      expect(
        bodyKeys.indexOf(AiPromptCacheAffinity.openAiPromptCacheKeyBodyField),
        lessThan(bodyKeys.indexOf('messages')),
      );
    },
  );

  test(
    'grok-compatible gateways keep session header and stable body cache key separate',
    () async {
      const adapter = OpenAiProtocolAdapter(AiProtocolType.openai);
      final request = await adapter.buildChatRequest(
        model: _model(
          protocolType: AiProtocolType.openai,
          baseUrl: 'http://127.0.0.1:3000',
          modelId: 'grok-composer-2.5-fast',
        ),
        messages: _messages,
        stream: true,
        inputCacheConfig: _stablePromptCacheConfig,
      );

      expect(
        request.headers[AiPromptCacheAffinity.grokConversationHeader],
        'session-1',
      );
      expect(
        request.body[AiPromptCacheAffinity.openAiPromptCacheKeyBodyField],
        'stable-key-1',
      );
    },
  );

  test(
    'direct xai grok requests do not add openai cache body fields',
    () async {
      const adapter = OpenAiProtocolAdapter(AiProtocolType.grok);
      final request = await adapter.buildChatRequest(
        model: _model(
          protocolType: AiProtocolType.grok,
          baseUrl: 'https://api.x.ai',
          modelId: 'grok-composer-2.5-fast',
        ),
        messages: _messages,
        stream: true,
        inputCacheConfig: _cacheConfig,
      );

      expect(
        request.headers[AiPromptCacheAffinity.grokConversationHeader],
        'session-1',
      );
      expect(
        request.body.containsKey(
          AiPromptCacheAffinity.openAiPromptCacheKeyBodyField,
        ),
        isFalse,
      );
      expect(request.body.containsKey('session_id'), isFalse);
    },
  );

  test('openrouter requests use session affinity body and header', () async {
    const adapter = OpenAiProtocolAdapter(AiProtocolType.openai);
    final request = await adapter.buildChatRequest(
      model: _model(
        protocolType: AiProtocolType.openai,
        baseUrl: 'https://openrouter.ai/api/v1',
        modelId: 'x-ai/grok-4',
      ),
      messages: _messages,
      stream: true,
      inputCacheConfig: _cacheConfig,
    );

    expect(
      request.headers[AiPromptCacheAffinity.openRouterSessionHeader],
      'session-1',
    );
    expect(
      request.headers.containsKey(AiPromptCacheAffinity.grokConversationHeader),
      isFalse,
    );
    expect(
      request.body.containsKey(
        AiPromptCacheAffinity.openAiPromptCacheKeyBodyField,
      ),
      isFalse,
    );
    expect(
      request.body[AiPromptCacheAffinity.openRouterSessionBodyField],
      'session-1',
    );
    final bodyKeys = request.body.keys.toList(growable: false);
    expect(
      bodyKeys.indexOf(AiPromptCacheAffinity.openRouterSessionBodyField),
      lessThan(bodyKeys.indexOf('messages')),
    );
  });

  test(
    'openai-compatible requests use prompt cache key body affinity',
    () async {
      const adapter = OpenAiProtocolAdapter(AiProtocolType.openai);
      final request = await adapter.buildChatRequest(
        model: _model(
          protocolType: AiProtocolType.openai,
          baseUrl: 'https://api.openai.com',
          modelId: 'gpt-5.1',
        ),
        messages: _messages,
        stream: true,
        inputCacheConfig: _cacheConfig,
      );

      expect(
        request.body[AiPromptCacheAffinity.openAiPromptCacheKeyBodyField],
        'session-1',
      );
      final bodyKeys = request.body.keys.toList(growable: false);
      expect(
        bodyKeys.indexOf(AiPromptCacheAffinity.openAiPromptCacheKeyBodyField),
        lessThan(bodyKeys.indexOf('messages')),
      );
    },
  );

  test(
    'openai-compatible requests prefer stable prompt cache key over session id',
    () async {
      const adapter = OpenAiProtocolAdapter(AiProtocolType.openai);
      final request = await adapter.buildChatRequest(
        model: _model(
          protocolType: AiProtocolType.openai,
          baseUrl: 'https://api.openai.com',
          modelId: 'gpt-5.1',
        ),
        messages: _messages,
        stream: true,
        inputCacheConfig: _stablePromptCacheConfig,
      );

      expect(
        request.body[AiPromptCacheAffinity.openAiPromptCacheKeyBodyField],
        'stable-key-1',
      );
      expect(
        request.headers.containsKey(
          AiPromptCacheAffinity.grokConversationHeader,
        ),
        isFalse,
      );
    },
  );

  test(
    'cache affinity is omitted when input cache config is disabled',
    () async {
      const adapter = OpenAiProtocolAdapter(AiProtocolType.grok);
      final request = await adapter.buildChatRequest(
        model: _model(
          protocolType: AiProtocolType.grok,
          baseUrl: 'https://api.x.ai',
          modelId: 'grok-composer-2.5-fast',
        ),
        messages: _messages,
        stream: true,
        inputCacheConfig: AiInputCacheRuntimeConfig.disabled,
      );

      expect(
        request.headers.containsKey(
          AiPromptCacheAffinity.grokConversationHeader,
        ),
        isFalse,
      );
      expect(
        request.body.containsKey(
          AiPromptCacheAffinity.openAiPromptCacheKeyBodyField,
        ),
        isFalse,
      );
    },
  );
}

const List<AiChatTurn> _messages = <AiChatTurn>[
  AiChatTurn(role: AiChatRole.system, content: 'Stable system prompt.'),
  AiChatTurn(role: AiChatRole.user, content: 'Hello'),
];

const AiInputCacheRuntimeConfig _cacheConfig = AiInputCacheRuntimeConfig(
  enabled: true,
  mode: 'allMessages',
  updateInterval: 10,
  breakpointCount: 4,
  cacheAffinityId: 'session-1',
);

const AiInputCacheRuntimeConfig _stablePromptCacheConfig =
    AiInputCacheRuntimeConfig(
      enabled: true,
      mode: 'allMessages',
      updateInterval: 10,
      breakpointCount: 4,
      cacheAffinityId: 'session-1',
      promptCacheKey: 'stable-key-1',
    );

AiModelConfig _model({
  required AiProtocolType protocolType,
  required String baseUrl,
  required String modelId,
}) {
  return AiModelConfig(
    id: 'model-$modelId',
    baseUrl: baseUrl,
    authScheme: AiAuthScheme.bearer,
    token: 'token',
    modelId: modelId,
    protocolType: protocolType,
  );
}
