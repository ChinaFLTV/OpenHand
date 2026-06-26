import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

void main() {
  group('AiEmbeddingsService', () {
    test('sends OpenAI-compatible embedding requests', () async {
      final client = _RecordingHttpClient(
        responseBody: <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'embedding': <num>[1, 2],
            },
            <String, Object?>{
              'embedding': <num>[3, 4],
            },
          ],
        },
      );
      final service = AiEmbeddingsService(
        transport: AiTransportClient(client: client),
      );

      final result = await service.createEmbeddings(
        model: _model(
          protocol: AiProtocolType.openai,
          baseUrl: 'https://api.openai.com',
          modelId: 'text-embedding-3-small',
        ),
        input: const <String>['alpha', 'beta'],
        dimensions: 512,
        encodingFormat: 'float',
        user: 'u-1',
      );

      expect(client.requests, hasLength(1));
      expect(client.requests.single.url.path, '/v1/embeddings');
      expect(client.bodies.single, <String, Object?>{
        'model': 'text-embedding-3-small',
        'input': <String>['alpha', 'beta'],
        'dimensions': 512,
        'encoding_format': 'float',
        'user': 'u-1',
      });
      expect(result.vectors, <List<double>>[
        <double>[1, 2],
        <double>[3, 4],
      ]);
    });

    test('sends Gemini batch embedding requests and parses values', () async {
      final client = _RecordingHttpClient(
        responseBody: <String, Object?>{
          'embeddings': <Object?>[
            <String, Object?>{
              'values': <num>[0.1, 0.2],
            },
            <String, Object?>{
              'values': <num>[0.3, 0.4],
            },
          ],
        },
      );
      final service = AiEmbeddingsService(
        transport: AiTransportClient(client: client),
      );

      final result = await service.createEmbeddings(
        model: _model(
          protocol: AiProtocolType.gemini,
          baseUrl: 'https://generativelanguage.googleapis.com',
          modelId: 'gemini-embedding-001',
          authScheme: AiAuthScheme.apiKey,
        ),
        input: const <String>['alpha', 'beta'],
        dimensions: 768,
      );

      expect(
        client.requests.single.url.path,
        '/v1beta/models/gemini-embedding-001:batchEmbedContents',
      );
      expect(client.requests.single.headers['x-goog-api-key'], 'test-token');
      final body = client.bodies.single;
      final requests = body['requests'] as List<Object?>;
      expect(requests, hasLength(2));
      expect(requests.first, <String, Object?>{
        'model': 'models/gemini-embedding-001',
        'content': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': 'alpha'},
          ],
        },
        'outputDimensionality': 768,
      });
      expect(result.vectors, <List<double>>[
        <double>[0.1, 0.2],
        <double>[0.3, 0.4],
      ]);
    });

    test('maps Mistral custom dimensions to output_dimension', () async {
      final client = _RecordingHttpClient(
        responseBody: <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'embedding': <num>[1, 2, 3],
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
          name: 'Mistral',
          baseUrl: 'https://api.mistral.ai/v1',
          modelId: 'mistral-embed',
        ),
        input: const <String>['alpha'],
        dimensions: 256,
      );

      expect(client.bodies.single['output_dimension'], 256);
      expect(client.bodies.single.containsKey('dimensions'), isFalse);
    });

    test('returns an empty result without network for empty batches', () async {
      final client = _RecordingHttpClient(
        responseBody: const <String, Object?>{},
      );
      final service = AiEmbeddingsService(
        transport: AiTransportClient(client: client),
      );

      final result = await service.createEmbeddings(
        model: _model(
          protocol: AiProtocolType.openai,
          baseUrl: 'https://api.openai.com',
          modelId: 'text-embedding-3-small',
        ),
        input: const <String>[],
      );

      expect(client.requests, isEmpty);
      expect(result.vectors, isEmpty);
      expect(result.payload['data'], isEmpty);
    });

    test('sends DashScope multimodal embedding requests', () async {
      final client = _RecordingHttpClient(
        responseBody: <String, Object?>{
          'output': <String, Object?>{
            'embeddings': <Object?>[
              <String, Object?>{
                'embedding': <num>[0.5, 0.6],
              },
            ],
          },
        },
      );
      final service = AiEmbeddingsService(
        transport: AiTransportClient(client: client),
      );

      final result = await service.createEmbeddings(
        model: _model(
          protocol: AiProtocolType.qwen,
          baseUrl: 'https://dashscope.aliyuncs.com',
          modelId: 'qwen3-vl-embedding',
        ),
        input: const <String>['find a similar image'],
        dimensions: 1024,
      );

      expect(
        client.requests.single.url.path,
        '/api/v1/services/embeddings/multimodal-embedding/multimodal-embedding',
      );
      expect(client.bodies.single, <String, Object?>{
        'model': 'qwen3-vl-embedding',
        'input': <String, Object?>{
          'contents': <Object?>[
            <String, Object?>{'text': 'find a similar image'},
          ],
        },
        'parameters': <String, Object?>{
          'enable_fusion': true,
          'dimension': 1024,
        },
      });
      expect(result.vectors, <List<double>>[
        <double>[0.5, 0.6],
      ]);
    });

    test('rejects multiple DashScope fused multimodal inputs', () async {
      final client = _RecordingHttpClient(
        responseBody: const <String, Object?>{},
      );
      final service = AiEmbeddingsService(
        transport: AiTransportClient(client: client),
      );

      await expectLater(
        service.createEmbeddings(
          model: _model(
            protocol: AiProtocolType.qwen,
            baseUrl: 'https://dashscope.aliyuncs.com',
            modelId: 'qwen3-vl-embedding',
          ),
          input: const <String>['first', 'second'],
        ),
        throwsArgumentError,
      );
      expect(client.requests, isEmpty);
    });
  });

  group('AiModelCatalog embedding profiles', () {
    test('marks only official embedding model ids as embedding-capable', () {
      final openAi = AiModelCatalog.lookup(
        'text-embedding-3-large',
        AiProtocolType.openai,
      );
      final qwen = AiModelCatalog.lookup(
        'text-embedding-v4',
        AiProtocolType.qwen,
      );
      final glm = AiModelCatalog.lookup('embedding-3', AiProtocolType.glm);
      final claude = AiModelCatalog.lookup(
        'claude-sonnet-4',
        AiProtocolType.claude,
      );

      expect(openAi?.supportsEmbeddings, isTrue);
      expect(openAi?.embeddingDimensions, 3072);
      expect(qwen?.supportsEmbeddings, isTrue);
      expect(qwen?.embeddingDimensions, 1024);
      expect(qwen?.embeddingBatchSize, 10);
      expect(glm?.supportsEmbeddings, isTrue);
      expect(glm?.embeddingDimensions, 1024);
      expect(claude?.supportsEmbeddings ?? false, isFalse);
    });

    test(
      'preserves catalog embedding booleans when user overrides other fields',
      () {
        final model =
            _model(
              protocol: AiProtocolType.gemini,
              baseUrl: 'https://generativelanguage.googleapis.com',
              modelId: 'gemini-embedding-001',
            ).copyWith(
              modelProfiles: const <String, AiModelProfile>{
                'gemini-embedding-001': AiModelProfile(
                  displayName: 'Custom name',
                ),
              },
            );

        final profile = model.profileFor('gemini-embedding-001');

        expect(profile.supportsEmbeddings, isTrue);
        expect(profile.embeddingSupportsCustomDimensions, isTrue);
        expect(profile.embeddingRequiresSpecialBody, isTrue);
      },
    );
  });
}

AiModelConfig _model({
  required AiProtocolType protocol,
  required String baseUrl,
  required String modelId,
  String name = '',
  AiAuthScheme authScheme = AiAuthScheme.bearer,
}) {
  return AiModelConfig(
    id: 'test',
    name: name,
    baseUrl: baseUrl,
    authScheme: authScheme,
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
