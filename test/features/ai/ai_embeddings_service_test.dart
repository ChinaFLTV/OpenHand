import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

void main() {
  group('AiEmbeddingsService embedding parameters', () {
    test('sends declared OpenAI user parameter', () async {
      final client = _RecordingHttpClient(
        responseBody: <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'embedding': <num>[1, 2],
            },
          ],
        },
      );
      final service = AiEmbeddingsService(
        transport: AiTransportClient(client: client),
      );

      await service.createEmbeddings(
        model: _model(
          protocol: AiProtocolType.openai,
          baseUrl: 'https://api.openai.com',
          modelId: 'text-embedding-3-small',
        ),
        input: const <String>['alpha'],
        user: 'u-1',
      );

      expect(client.bodies.single, containsPair('user', 'u-1'));
    });

    test('filters undeclared compatible user parameter', () async {
      final client = _RecordingHttpClient(
        responseBody: <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'embedding': <num>[1, 2],
            },
          ],
        },
      );
      final service = AiEmbeddingsService(
        transport: AiTransportClient(client: client),
      );

      await service.createEmbeddings(
        model:
            _model(
              protocol: AiProtocolType.ollama,
              baseUrl: 'http://localhost:11434/v1',
              modelId: 'local-basic-embed',
            ).copyWith(
              modelProfiles: const <String, AiModelProfile>{
                'local-basic-embed': AiModelProfile(
                  capabilities: <AiModelCapability>{
                    AiModelCapability.embeddingGeneration,
                  },
                  supportedParameters: <String>['input', 'model'],
                ),
              },
            ),
        input: const <String>['alpha'],
        user: 'should-not-leak',
      );

      expect(client.bodies.single, <String, Object?>{
        'model': 'local-basic-embed',
        'input': <String>['alpha'],
      });
    });

    test('sends Bedrock Titan native text embedding payload', () async {
      final client = _RecordingHttpClient(
        responseBody: <String, Object?>{
          'embedding': <num>[0.1, 0.2, 0.3],
        },
      );
      final service = AiEmbeddingsService(
        transport: AiTransportClient(client: client),
      );

      final result = await service.createEmbeddings(
        model: _model(
          protocol: AiProtocolType.openai,
          baseUrl: 'https://bedrock-runtime.us-east-1.amazonaws.com',
          modelId: 'amazon.titan-embed-text-v2:0',
        ),
        input: const <String>['alpha'],
        dimensions: 512,
      );

      expect(client.requests.single.url.pathSegments, <String>[
        'model',
        'amazon.titan-embed-text-v2:0',
        'invoke',
      ]);
      expect(client.bodies.single, <String, Object?>{
        'inputText': 'alpha',
        'dimensions': 512,
        'normalize': true,
        'embeddingTypes': <String>['float'],
      });
      expect(result.vectors.single, <double>[0.1, 0.2, 0.3]);
    });
  });

  group('AiModelCatalog embedding profiles', () {
    test('captures DashScope embedding dimension and batch limits', () {
      final text = AiModelCatalog.lookup(
        'text-embedding-v4',
        AiProtocolType.qwen,
      );
      final multimodal = AiModelCatalog.lookup(
        'qwen3-vl-embedding',
        AiProtocolType.qwen,
      );

      expect(text?.embeddingMinDimensions, 64);
      expect(text?.embeddingMaxDimensions, 2048);
      expect(text?.embeddingMaxInputsPerBatch, 10);
      expect(text?.embeddingMaxTokensPerBatch, 8192);

      expect(multimodal?.embeddingMinDimensions, 256);
      expect(multimodal?.embeddingMaxDimensions, 2560);
      expect(multimodal?.embeddingMaxInputsPerBatch, 1);
      expect(multimodal?.embeddingMaxTokensPerBatch, 32000);
    });

    test('captures Gemini Embedding 2 batch token limit', () {
      final profile = AiModelCatalog.lookup(
        'gemini-embedding-2',
        AiProtocolType.gemini,
      );

      expect(profile?.embeddingMaxTokensPerBatch, 8192);
      expect(profile?.embeddingMaxDimensions, 3072);
      expect(profile?.supportsEmbeddings, isTrue);
    });
  });
}

AiModelConfig _model({
  required AiProtocolType protocol,
  required String baseUrl,
  required String modelId,
}) {
  return AiModelConfig(
    id: 'test',
    name: 'test',
    baseUrl: baseUrl,
    authScheme: AiAuthScheme.bearer,
    token: 'test-token',
    modelId: modelId,
    protocolType: protocol,
    apiDialect: inferAiApiDialect(protocol),
    providerKind: inferAiProviderKind(protocol),
  );
}

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient({required this.responseBody});

  final Map<String, Object?> responseBody;
  final List<http.Request> requests = <http.Request>[];
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final httpRequest = request as http.Request;
    requests.add(httpRequest);
    bodies.add(jsonDecode(httpRequest.body) as Map<String, Object?>);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(responseBody))),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}
