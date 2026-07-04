import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('catalog thinking budget enables thinking by default', () {
    final model = _model(
      protocolType: AiProtocolType.openai,
      modelId: 'gpt-5.4',
    );

    final profile = model.profileFor('gpt-5.4');
    expect(profile.maxThinkingLength, 128000);
    expect(profile.thinkingEnabled, isTrue);
    expect(model.resolvedSupportsThinking, isTrue);
    expect(model.resolvedThinkingEnabled, isTrue);
  });

  test('explicit default parameter can keep supported thinking disabled', () {
    final model = _model(
      protocolType: AiProtocolType.agnes,
      modelId: 'agnes-2.0-flash',
    );

    expect(model.resolvedSupportsThinking, isTrue);
    expect(model.resolvedThinkingEnabled, isFalse);
  });

  test('fallback catalogs mark Spark and LongCat thinking models', () {
    final spark = _model(
      protocolType: AiProtocolType.openai,
      modelId: 'spark-x1',
    );
    final longCat = _model(
      protocolType: AiProtocolType.longcat,
      modelId: 'longcat-flash',
    );

    expect(spark.resolvedThinkingEnabled, isTrue);
    expect(spark.profileFor('spark-x1').supportedParameters, [
      'enable_thinking',
    ]);
    expect(longCat.resolvedThinkingEnabled, isTrue);
    expect(longCat.profileFor('longcat-flash').maxThinkingLength, 32768);
  });

  test(
    'Qwen compatible requests use enable_thinking and honor overrides',
    () async {
      final adapter = AiProtocolRegistry.adapterFor(AiProtocolType.qwen);
      final enabledBody = await adapter.buildBody(
        _model(protocolType: AiProtocolType.qwen, modelId: 'qwen3-max'),
        _turns,
      );
      expect(enabledBody['enable_thinking'], isTrue);

      final disabledBody = await adapter.buildBody(
        _model(
          protocolType: AiProtocolType.qwen,
          modelId: 'qwen3-max',
          profile: const AiModelProfile(thinkingEnabled: false),
        ),
        _turns,
      );
      expect(disabledBody['enable_thinking'], isFalse);
    },
  );

  test('OpenRouter reasoning models use reasoning markers', () async {
    final adapter = AiProtocolRegistry.adapterFor(AiProtocolType.openai);
    final body = await adapter.buildBody(
      _model(
        protocolType: AiProtocolType.openai,
        modelId: 'openai/gpt-5.4',
        baseUrl: 'https://openrouter.ai/api',
      ),
      _turns,
    );

    expect(body['include_reasoning'], isTrue);
    expect(body['reasoning'], <String, Object?>{'enabled': true});
  });

  test('Gemini native requests emit thinkingConfig', () async {
    final adapter = AiProtocolRegistry.adapterFor(AiProtocolType.gemini);
    final body = await adapter.buildBody(
      _model(protocolType: AiProtocolType.gemini, modelId: 'gemini-2.5-pro'),
      _turns,
    );

    final generationConfig = body['generationConfig'] as Map<String, Object?>;
    expect(
      generationConfig['thinkingConfig'],
      containsPair('thinkingBudget', isPositive),
    );
    expect(
      generationConfig['thinkingConfig'],
      containsPair('includeThoughts', true),
    );
  });

  test('thinking retry helper strips only thinking request markers', () {
    final body = <String, Object?>{
      'model': 'qwen3-max',
      'enable_thinking': true,
      'messages': <Object?>[
        <String, Object?>{
          'role': 'assistant',
          'reasoning_content': 'keep this echo',
        },
      ],
      'generationConfig': <String, Object?>{
        'thinkingConfig': <String, Object?>{'thinkingBudget': 8192},
      },
    };

    expect(AiThinkingRequestPolicy.requestHasMarker(body: body), isTrue);
    final stripped = AiThinkingRequestPolicy.withoutRequestMarkers(body);
    expect(stripped.containsKey('enable_thinking'), isFalse);
    final messages = stripped['messages'] as List<Object?>;
    expect(
      messages.single,
      containsPair('reasoning_content', 'keep this echo'),
    );
    final generationConfig =
        stripped['generationConfig'] as Map<String, Object?>;
    expect(generationConfig.containsKey('thinkingConfig'), isFalse);
  });
}

const List<AiChatTurn> _turns = <AiChatTurn>[
  AiChatTurn(role: AiChatRole.user, content: 'hello'),
];

AiModelConfig _model({
  required AiProtocolType protocolType,
  required String modelId,
  String baseUrl = 'https://example.com/v1',
  AiModelProfile? profile,
}) {
  return AiModelConfig(
    id: 'test',
    baseUrl: baseUrl,
    authScheme: AiAuthScheme.bearer,
    token: 'token',
    modelId: modelId,
    protocolType: protocolType,
    modelProfiles: profile == null
        ? const <String, AiModelProfile>{}
        : <String, AiModelProfile>{modelId: profile},
  );
}
