import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_api_dialect.dart';
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_endpoint_override.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_operation_routing.dart';
import 'package:openhand/features/ai/model/ai_realtime_config.dart';

void main() {
  test('ai model config json roundtrip preserves advanced provider fields', () {
    const original = AiModelConfig(
      id: 'provider-1',
      name: 'Relay',
      baseUrl: 'https://relay.example.com/v1',
      authScheme: AiAuthScheme.bearer,
      token: 'sk-test',
      modelId: 'gpt-4.1-mini',
      protocolType: AiProtocolType.openai,
      providerKind: AiProviderKind.openai,
      endpointOverrides: {
        AiApiFamily.responses: AiEndpointOverride(path: 'v1/responses'),
      },
      operationRouting: AiOperationRouting(
        responsesModelId: 'gpt-4.1',
        embeddingModelId: 'text-embedding-3-large',
        defaultVoice: 'alloy',
      ),
      capabilityOverrides: {
        AiApiFamily.realtime: 'experimental',
      },
      operationExtras: <String, Object?>{
        'responses': <String, Object?>{'reasoning': 'medium'},
      },
      realtime: AiRealtimeConfig(
        transport: 'websocket',
        voice: 'alloy',
        inputFormat: 'pcm16',
        outputFormat: 'pcm16',
        sampleRate: 24000,
      ),
    );

    final decoded = AiModelConfig.fromJson(original.toJson());

    expect(decoded.apiDialect, AiApiDialect.openAiCompat);
    expect(decoded.providerKind, AiProviderKind.openai);
    expect(decoded.endpointOverrides.containsKey(AiApiFamily.responses), isTrue);
    expect(decoded.operationRouting.responsesModelId, 'gpt-4.1');
    expect(decoded.capabilityStatusFor(AiApiFamily.realtime), 'experimental');
    expect(decoded.realtime.transport, 'websocket');
    expect(decoded.resolveOperationModelId(AiApiFamily.embeddings), 'text-embedding-3-large');
  });

  test('legacy config infers api dialect and provider kind from protocol type', () {
    final decoded = AiModelConfig.fromJson(<String, Object?>{
      'id': 'provider-1',
      'base_url': 'https://api.anthropic.com/v1',
      'auth_scheme': 'bearer',
      'token': 'sk-test',
      'model_id': 'claude-sonnet-4-5',
      'protocol_type': 'claude',
    });

    expect(decoded.apiDialect, AiApiDialect.anthropicNative);
    expect(decoded.providerKind, AiProviderKind.claude);
  });
}
