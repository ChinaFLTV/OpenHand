import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  const router = AiEndpointRouter();

  AiModelConfig config({
    required String baseUrl,
    bool autoCompleteBaseUrl = true,
    Map<AiApiFamily, AiEndpointOverride> endpointOverrides =
        const <AiApiFamily, AiEndpointOverride>{},
  }) {
    return AiModelConfig(
      id: 'provider',
      baseUrl: baseUrl,
      autoCompleteBaseUrl: autoCompleteBaseUrl,
      authScheme: AiAuthScheme.bearer,
      token: 'token',
      modelId: 'model',
      protocolType: AiProtocolType.openai,
      endpointOverrides: endpointOverrides,
    );
  }

  group('AiEndpointRouter Base URL completion', () {
    test('keeps legacy v1 completion enabled by default', () {
      final endpoint = router.resolve(
        config(baseUrl: 'https://maas-api.cn-huabei-1.xf-yun.com/v2'),
        AiApiFamily.chatCompletions,
      );

      expect(
        endpoint.url,
        'https://maas-api.cn-huabei-1.xf-yun.com/v2/v1/chat/completions',
      );
    });

    test('uses exact Base URL when completion is disabled', () {
      final endpoint = router.resolve(
        config(
          baseUrl: 'https://maas-api.cn-huabei-1.xf-yun.com/v2',
          autoCompleteBaseUrl: false,
        ),
        AiApiFamily.chatCompletions,
      );

      expect(
        endpoint.url,
        'https://maas-api.cn-huabei-1.xf-yun.com/v2/chat/completions',
      );
    });

    test('deduplicates an already completed same-version Base URL', () {
      final endpoint = router.resolve(
        config(baseUrl: 'https://api.example.com/v1'),
        AiApiFamily.models,
        method: 'GET',
      );

      expect(endpoint.url, 'https://api.example.com/v1/models');
    });

    test('does not rewrite explicit endpoint override paths', () {
      final endpoint = router.resolve(
        config(
          baseUrl: 'https://api.example.com/v2',
          autoCompleteBaseUrl: false,
          endpointOverrides: const <AiApiFamily, AiEndpointOverride>{
            AiApiFamily.chatCompletions: AiEndpointOverride(
              path: 'v1/custom/chat',
            ),
          },
        ),
        AiApiFamily.chatCompletions,
      );

      expect(endpoint.url, 'https://api.example.com/v2/v1/custom/chat');
    });

    test('persists auto-completion preference', () {
      final restored = AiModelConfig.fromJson(
        config(
          baseUrl: 'https://api.example.com/v2',
          autoCompleteBaseUrl: false,
        ).toJson(),
      );

      expect(restored.autoCompleteBaseUrl, isFalse);
    });
  });
}
