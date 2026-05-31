import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_endpoint_override.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/runtime/ai_endpoint_router.dart';

void main() {
  test('router resolves default responses endpoint', () {
    const config = AiModelConfig(
      id: 'provider-1',
      baseUrl: 'https://relay.example.com/v1',
      authScheme: AiAuthScheme.bearer,
      token: 'sk-test',
      modelId: 'gpt-4.1-mini',
      protocolType: AiProtocolType.openai,
    );
    const router = AiEndpointRouter();

    final resolved = router.resolve(config, AiApiFamily.responses);

    expect(resolved.url, 'https://relay.example.com/v1/responses');
    expect(resolved.method, 'POST');
    expect(resolved.transport, 'json');
  });

  test('router respects path override', () {
    const config = AiModelConfig(
      id: 'provider-1',
      baseUrl: 'https://relay.example.com/v1',
      authScheme: AiAuthScheme.bearer,
      token: 'sk-test',
      modelId: 'gpt-4.1-mini',
      protocolType: AiProtocolType.openai,
      endpointOverrides: {
        AiApiFamily.embeddings: AiEndpointOverride(
          path: 'api/embeddings',
          method: 'POST',
        ),
      },
    );
    const router = AiEndpointRouter();

    final resolved = router.resolve(config, AiApiFamily.embeddings);

    expect(resolved.url, 'https://relay.example.com/v1/api/embeddings');
    expect(resolved.method, 'POST');
  });
}
