import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_endpoint_override.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/runtime/ai_endpoint_router.dart';

void main() {
  group('AiEndpointRouter', () {
    test('falls back to default method and transport for blank input', () {
      final endpoint = const AiEndpointRouter().resolve(
        _config(),
        AiApiFamily.chatCompletions,
        method: '  ',
        transport: '  ',
      );

      expect(endpoint.method, 'POST');
      expect(endpoint.transport, 'json');
      expect(Uri.parse(endpoint.url).path, '/v1/chat/completions');
    });

    test('ignores blank override path and keeps default endpoint path', () {
      final endpoint = const AiEndpointRouter().resolve(
        _config(
          endpointOverrides: const <AiApiFamily, AiEndpointOverride>{
            AiApiFamily.embeddings: AiEndpointOverride(path: '  '),
          },
        ),
        AiApiFamily.embeddings,
      );

      expect(Uri.parse(endpoint.url).path, '/v1/embeddings');
    });

    test('trims explicit override url and merges query defaults', () {
      final endpoint = const AiEndpointRouter().resolve(
        _config(
          endpointOverrides: const <AiApiFamily, AiEndpointOverride>{
            AiApiFamily.files: AiEndpointOverride(
              url: ' https://upload.example.test/v1/files?mode=fast ',
              queryDefaults: <String, String>{'mode': 'default', 'ttl': '30'},
            ),
          },
        ),
        AiApiFamily.files,
      );

      final uri = Uri.parse(endpoint.url);
      expect(uri.origin, 'https://upload.example.test');
      expect(uri.path, '/v1/files');
      expect(uri.queryParameters, <String, String>{
        'mode': 'fast',
        'ttl': '30',
      });
    });
  });
}

AiModelConfig _config({
  Map<AiApiFamily, AiEndpointOverride> endpointOverrides =
      const <AiApiFamily, AiEndpointOverride>{},
}) {
  return AiModelConfig(
    id: 'provider-1',
    baseUrl: 'https://api.example.test/v1',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'gpt-4o-mini',
    protocolType: AiProtocolType.openai,
    endpointOverrides: endpointOverrides,
  );
}
