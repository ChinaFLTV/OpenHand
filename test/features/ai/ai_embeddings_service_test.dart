import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

    test(
      'decodes OpenAI-compatible base64 float embedding responses',
      () async {
        final client = _RecordingHttpClient(
          responseBody: <String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'embedding': _base64Float32(<double>[1.25, -2.5]),
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
          input: const <String>['alpha'],
          encodingFormat: 'base64',
        );

        expect(client.bodies.single, <String, Object?>{
          'model': 'text-embedding-3-small',
          'input': <String>['alpha'],
          'encoding_format': 'base64',
        });
        expect(result.vectors, hasLength(1));
        expect(result.vectors.single, hasLength(2));
        expect(result.vectors.single[0], closeTo(1.25, 0.000001));
        expect(result.vectors.single[1], closeTo(-2.5, 0.000001));
      },
    );

    test(
      'sends typed OpenAI-compatible embedding parameters when declared',
      () async {
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
            baseUrl: 'https://integrate.api.nvidia.com',
            modelId: 'nvidia/nv-embedqa-e5-v5',
          ),
          input: const <String>['alpha'],
          inputType: 'query',
          truncation: 'END',
        );

        expect(client.requests.single.url.path, '/v1/embeddings');
        expect(client.bodies.single, <String, Object?>{
          'model': 'nvidia/nv-embedqa-e5-v5',
          'input': <String>['alpha'],
          'input_type': 'query',
          'truncate': 'END',
        });
      },
    );

    test(
      'matches Cohere strategy with case-insensitive supported parameters',
      () async {
        final client = _RecordingHttpClient(
          responseBody: <String, Object?>{
            'embeddings': <String, Object?>{
              'float': <Object?>[
                <num>[0.1, 0.2],
              ],
            },
          },
        );
        final service = AiEmbeddingsService(
          transport: AiTransportClient(client: client),
        );

        final result = await service.createEmbeddings(
          model:
              _model(
                protocol: AiProtocolType.openai,
                baseUrl: 'https://gateway.example',
                modelId: 'custom-cohere-embed',
              ).copyWith(
                modelProfiles: const <String, AiModelProfile>{
                  'custom-cohere-embed': AiModelProfile(
                    supportedParameters: <String>['Texts', 'Input_Type'],
                    embeddingEndpointPath: 'v2/embed',
                    embeddingDefaultInputType: 'search_document',
                    embeddingDefaultEncodingFormat: 'float',
                  ),
                },
              ),
          input: const <String>['alpha'],
        );

        expect(client.requests.single.url.path, '/v2/embed');
        expect(client.bodies.single, <String, Object?>{
          'model': 'custom-cohere-embed',
          'texts': <String>['alpha'],
          'input_type': 'search_document',
          'embedding_types': <String>['float'],
        });
        expect(result.vectors, <List<double>>[
          <double>[0.1, 0.2],
        ]);
      },
    );

    test(
      'matches Jina strategy with case-insensitive supported parameters',
      () async {
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
                protocol: AiProtocolType.openai,
                baseUrl: 'https://gateway.example',
                modelId: 'custom-jina-embed',
              ).copyWith(
                modelProfiles: const <String, AiModelProfile>{
                  'custom-jina-embed': AiModelProfile(
                    supportedParameters: <String>['Embedding_Type', 'Task'],
                    embeddingDefaultTaskType: 'retrieval.passage',
                    embeddingDefaultEncodingFormat: 'float',
                    embeddingOutputsNormalized: true,
                  ),
                },
              ),
          input: const <String>['alpha'],
        );

        expect(client.bodies.single, <String, Object?>{
          'model': 'custom-jina-embed',
          'input': <String>['alpha'],
          'task': 'retrieval.passage',
          'embedding_type': 'float',
          'normalized': true,
        });
      },
    );

    test(
      'merges profile embedding defaults below explicit payload and extras',
      () async {
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
                protocol: AiProtocolType.openai,
                baseUrl: 'https://api.openai.com',
                modelId: 'text-embedding-3-small',
              ).copyWith(
                modelProfiles: const <String, AiModelProfile>{
                  'text-embedding-3-small': AiModelProfile(
                    defaultParameters: <String, Object?>{
                      'dimensions': 1024,
                      'encoding_format': 'base64',
                      'user': 'profile-user',
                      'provider_flag': true,
                    },
                  ),
                },
                operationExtras: const <String, Object?>{
                  'embeddings': <String, Object?>{
                    'body': <String, Object?>{
                      'user': 'extra-user',
                      'extra_flag': true,
                    },
                  },
                },
              ),
          input: const <String>['alpha'],
          dimensions: 512,
          encodingFormat: 'float',
        );

        expect(client.bodies.single, <String, Object?>{
          'model': 'text-embedding-3-small',
          'input': <String>['alpha'],
          'dimensions': 512,
          'encoding_format': 'float',
          'user': 'extra-user',
          'provider_flag': true,
          'extra_flag': true,
        });
      },
    );

    test('decodes Perplexity base64 int8 embedding responses', () async {
      final client = _RecordingHttpClient(
        responseBody: <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'embedding': base64Encode(<int>[255, 0, 1, 127, 128]),
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
          baseUrl: 'https://api.perplexity.ai',
          modelId: 'pplx-embed-v1-0.6b',
        ),
        input: const <String>['alpha'],
        dimensions: 512,
      );

      expect(client.requests.single.url.path, '/v1/embeddings');
      expect(client.bodies.single, <String, Object?>{
        'model': 'pplx-embed-v1-0.6b',
        'input': <String>['alpha'],
        'dimensions': 512,
        'encoding_format': 'base64_int8',
      });
      expect(result.vectors, <List<double>>[
        <double>[-1, 0, 1, 127, -128],
      ]);
    });

    test('decodes Perplexity base64 binary embedding responses', () async {
      final client = _RecordingHttpClient(
        responseBody: <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'embedding': base64Encode(<int>[
                0x05, // LSB-first bits: 1, 0, 1, 0, 0, 0, 0, 0
                0x80, // LSB-first bits: 0, 0, 0, 0, 0, 0, 0, 1
              ]),
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
          baseUrl: 'https://api.perplexity.ai',
          modelId: 'pplx-embed-v1-0.6b',
        ),
        input: const <String>['alpha'],
        dimensions: 10,
        encodingFormat: 'base64_binary',
      );

      expect(client.bodies.single, <String, Object?>{
        'model': 'pplx-embed-v1-0.6b',
        'input': <String>['alpha'],
        'dimensions': 10,
        'encoding_format': 'base64_binary',
      });
      expect(result.vectors, <List<double>>[
        <double>[1, 0, 1, 0, 0, 0, 0, 0, 0, 0],
      ]);
    });

    test('sends Perplexity contextualized embedding requests', () async {
      final client = _RecordingHttpClient(
        responseBody: <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'index': 0,
              'data': <Object?>[
                <String, Object?>{
                  'embedding': base64Encode(<int>[1, 2]),
                },
                <String, Object?>{
                  'embedding': base64Encode(<int>[3, 4]),
                },
              ],
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
          baseUrl: 'https://api.perplexity.ai',
          modelId: 'pplx-embed-context-v1-4b',
        ),
        input: const <String>['chunk one', 'chunk two'],
        dimensions: 256,
      );

      expect(client.requests.single.url.path, '/v1/embeddings/contextualized');
      expect(client.bodies.single, <String, Object?>{
        'model': 'pplx-embed-context-v1-4b',
        'input': <Object?>[
          <String>['chunk one', 'chunk two'],
        ],
        'dimensions': 256,
        'encoding_format': 'base64_int8',
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
        'taskType': 'RETRIEVAL_DOCUMENT',
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

    test(
      'sends Cohere embedding requests with input type and truncation',
      () async {
        final client = _RecordingHttpClient(
          responseBody: <String, Object?>{
            'embeddings': <String, Object?>{
              'float': <Object?>[
                <num>[0.1, 0.2],
                <num>[0.3, 0.4],
              ],
            },
          },
        );
        final service = AiEmbeddingsService(
          transport: AiTransportClient(client: client),
        );

        final result = await service.createEmbeddings(
          model: _model(
            protocol: AiProtocolType.openai,
            baseUrl: 'https://api.cohere.com/v2',
            modelId: 'embed-v4.0',
          ),
          input: const <String>['alpha', 'beta'],
          dimensions: 512,
        );

        expect(client.requests.single.url.path, '/v2/embed');
        expect(client.bodies.single, <String, Object?>{
          'model': 'embed-v4.0',
          'texts': <String>['alpha', 'beta'],
          'input_type': 'search_document',
          'embedding_types': <String>['float'],
          'output_dimension': 512,
          'truncate': 'END',
        });
        expect(result.vectors, <List<double>>[
          <double>[0.1, 0.2],
          <double>[0.3, 0.4],
        ]);
      },
    );

    test('does not send Cohere v4-only dimensions to v3 models', () async {
      final client = _RecordingHttpClient(
        responseBody: <String, Object?>{
          'embeddings': <String, Object?>{
            'float': <Object?>[
              <num>[0.1, 0.2],
            ],
          },
        },
      );
      final service = AiEmbeddingsService(
        transport: AiTransportClient(client: client),
      );

      await service.createEmbeddings(
        model: _model(
          protocol: AiProtocolType.openai,
          baseUrl: 'https://api.cohere.com/v2',
          modelId: 'embed-english-v3.0',
        ),
        input: const <String>['alpha'],
        dimensions: 384,
      );

      expect(client.requests.single.url.path, '/v2/embed');
      expect(client.bodies.single, <String, Object?>{
        'model': 'embed-english-v3.0',
        'texts': <String>['alpha'],
        'input_type': 'search_document',
        'embedding_types': <String>['float'],
        'truncate': 'END',
      });
      expect(client.bodies.single.containsKey('output_dimension'), isFalse);
    });

    test(
      'sends Voyage embedding requests with typed retrieval params',
      () async {
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
            baseUrl: 'https://api.voyageai.com/v1',
            modelId: 'voyage-3.5',
          ),
          input: const <String>['alpha'],
          dimensions: 512,
          inputType: 'query',
        );

        expect(client.bodies.single, <String, Object?>{
          'model': 'voyage-3.5',
          'input': <String>['alpha'],
          'input_type': 'query',
          'output_dimension': 512,
          'output_dtype': 'float',
          'truncation': true,
        });
      },
    );

    test('sends Jina embedding requests with retrieval task', () async {
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
          baseUrl: 'https://api.jina.ai/v1',
          modelId: 'jina-embeddings-v3',
        ),
        input: const <String>['alpha'],
        dimensions: 256,
        taskType: 'retrieval.query',
        truncation: 'true',
      );

      expect(client.bodies.single, <String, Object?>{
        'model': 'jina-embeddings-v3',
        'input': <String>['alpha'],
        'task': 'retrieval.query',
        'dimensions': 256,
        'embedding_type': 'float',
        'normalized': true,
        'truncate': true,
      });
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

    test(
      'deep merges nested profile defaults for provider parameters only',
      () async {
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

        await service.createEmbeddings(
          model:
              _model(
                protocol: AiProtocolType.qwen,
                baseUrl: 'https://dashscope.aliyuncs.com',
                modelId: 'qwen3-vl-embedding',
              ).copyWith(
                modelProfiles: const <String, AiModelProfile>{
                  'qwen3-vl-embedding': AiModelProfile(
                    defaultParameters: <String, Object?>{
                      'input': <String, Object?>{'stale': true},
                      'parameters': <String, Object?>{
                        'dimension': 512,
                        'text_type': 'query',
                      },
                    },
                  ),
                },
              ),
          input: const <String>['find a similar image'],
          dimensions: 1024,
        );

        expect(client.bodies.single, <String, Object?>{
          'model': 'qwen3-vl-embedding',
          'input': <String, Object?>{
            'contents': <Object?>[
              <String, Object?>{'text': 'find a similar image'},
            ],
          },
          'parameters': <String, Object?>{
            'dimension': 1024,
            'text_type': 'query',
            'enable_fusion': true,
          },
        });
      },
    );

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
      expect(glm?.embeddingDimensions, 2048);
      final jina = AiModelCatalog.lookup(
        'jina-embeddings-v3',
        AiProtocolType.openai,
      );
      expect(jina?.supportsEmbeddings, isTrue);
      expect(jina?.embeddingOutputsNormalized, isTrue);
      expect(jina?.embeddingDefaultQueryTaskType, 'retrieval.query');
      final bce = AiModelCatalog.lookup(
        'bce-embedding-base_v1',
        AiProtocolType.openai,
      );
      final jinaCode = AiModelCatalog.lookup(
        'jina-code-embeddings-1.5b',
        AiProtocolType.openai,
      );
      final jinaV2 = AiModelCatalog.lookup(
        'jina-embeddings-v2-base-en',
        AiProtocolType.openai,
      );
      expect(bce?.displayName, 'BCE Embedding');
      expect(bce?.embeddingDimensions, 768);
      expect(jinaCode?.displayName, 'Jina Code Embeddings 1.5B');
      expect(jinaCode?.embeddingDimensions, 1536);
      expect(jinaCode?.embeddingMaxInputTokens, 32768);
      expect(jinaCode?.embeddingSupportsTruncation, isTrue);
      expect(jinaV2?.displayName, 'Jina Embeddings v2');
      expect(jinaV2?.embeddingDimensions, 768);
      expect(jinaV2?.embeddingDefaultDocumentTaskType, 'retrieval.passage');
      expect(claude?.supportsEmbeddings ?? false, isFalse);
    });

    test(
      'keeps provider-specific text embedding profiles over compatible endpoints',
      () {
        final qwen = AiModelCatalog.lookup(
          'text-embedding-v4',
          AiProtocolType.openai,
        );
        final google = AiModelCatalog.lookup(
          'text-embedding-005',
          AiProtocolType.openai,
        );
        final googleMultilingual = AiModelCatalog.lookup(
          'text-multilingual-embedding-002',
          AiProtocolType.openai,
        );
        final openAi = AiModelCatalog.lookup(
          'text-embedding-3-large',
          AiProtocolType.openai,
        );
        final openAiViaQwenProtocol = AiModelCatalog.lookup(
          'text-embedding-3-large',
          AiProtocolType.qwen,
        );

        expect(qwen?.displayName, 'text-embedding-v4');
        expect(qwen?.embeddingDimensions, 1024);
        expect(qwen?.embeddingBatchSize, 10);
        expect(qwen?.embeddingEndpointPath, 'compatible-mode/v1/embeddings');

        expect(google?.displayName, 'text-embedding-005');
        expect(google?.embeddingDimensions, 768);
        expect(
          google?.embeddingSupportedTaskTypes,
          contains('RETRIEVAL_QUERY'),
        );
        expect(
          googleMultilingual?.displayName,
          'text-multilingual-embedding-002',
        );
        expect(googleMultilingual?.embeddingDimensions, 768);
        expect(googleMultilingual?.embeddingRequiresSpecialBody, isTrue);

        expect(openAi?.displayName, 'text-embedding-3-large');
        expect(openAi?.embeddingDimensions, 3072);
        expect(openAiViaQwenProtocol?.displayName, 'text-embedding-3-large');
        expect(openAiViaQwenProtocol?.embeddingDimensions, 3072);
      },
    );

    test(
      'captures provider variant embedding limits without broad fallbacks',
      () {
        final cohereLight = AiModelCatalog.lookup(
          'embed-english-light-v3.0',
          AiProtocolType.openai,
        );
        final cohereMultilingualLight = AiModelCatalog.lookup(
          'embed-multilingual-light-v3.0',
          AiProtocolType.openai,
        );
        final voyageLite = AiModelCatalog.lookup(
          'voyage-3.5-lite',
          AiProtocolType.openai,
        );
        final voyageLaw = AiModelCatalog.lookup(
          'voyage-law-2',
          AiProtocolType.openai,
        );
        final baidu = AiModelCatalog.lookup(
          'Embedding-V1',
          AiProtocolType.wenxin,
        );
        final baiduCompatible = AiModelCatalog.lookup(
          'Embedding-V1',
          AiProtocolType.openai,
        );
        final tao = AiModelCatalog.lookup('tao-8k', AiProtocolType.wenxin);
        final qwen3 = AiModelCatalog.lookup(
          'Qwen3-Embedding-4B',
          AiProtocolType.wenxin,
        );
        final doubao = AiModelCatalog.lookup(
          'doubao-embedding-text-240515',
          AiProtocolType.seed,
        );

        expect(cohereLight?.displayName, 'Cohere Embed English Light v3.0');
        expect(cohereLight?.embeddingDimensions, 384);
        expect(cohereLight?.embeddingEndpointPath, 'v2/embed');
        expect(cohereLight?.embeddingMaxInputsPerBatch, 96);
        expect(cohereLight?.embeddingDefaultEncodingFormat, 'float');
        expect(
          cohereLight?.supportedParameters,
          isNot(contains('output_dimension')),
        );
        expect(cohereMultilingualLight?.embeddingDimensions, 384);

        expect(voyageLite?.displayName, 'Voyage Embedding');
        expect(voyageLite?.embeddingDimensions, 1024);
        expect(voyageLite?.embeddingSupportsCustomDimensions, isTrue);
        expect(voyageLite?.embeddingMaxDimensions, 2048);
        expect(voyageLite?.embeddingMaxTokensPerBatch, 1000000);
        expect(voyageLite?.embeddingOutputDTypes, contains('int8'));
        expect(voyageLite?.embeddingOutputDTypes, contains('ubinary'));

        expect(voyageLaw?.displayName, 'Voyage Law 2');
        expect(voyageLaw?.embeddingMaxInputTokens, 16000);
        expect(voyageLaw?.embeddingMaxTokensPerBatch, 120000);
        expect(voyageLaw?.embeddingOutputDTypes, isEmpty);

        expect(baidu?.displayName, 'Embedding-V1');
        expect(baidu?.embeddingDimensions, 384);
        expect(baidu?.embeddingBatchSize, 16);
        expect(baiduCompatible?.displayName, 'Embedding-V1');
        expect(tao?.displayName, 'tao-8k');
        expect(tao?.embeddingBatchSize, 1);
        expect(qwen3?.displayName, 'Qwen3-Embedding');
        expect(qwen3?.embeddingDimensions, 2560);
        expect(qwen3?.embeddingSupportsCustomDimensions, isTrue);
        expect(doubao?.displayName, 'Doubao Embedding');
      },
    );

    test('recognizes common self-hosted embedding model profiles', () {
      final e5 = AiModelCatalog.lookup(
        'intfloat/multilingual-e5-large',
        AiProtocolType.openai,
      );
      final gteQwen = AiModelCatalog.lookup(
        'Alibaba-NLP/gte-Qwen2-7B-instruct',
        AiProtocolType.openai,
      );
      final bgeBase = AiModelCatalog.lookup(
        'BAAI/bge-base-zh-v1.5',
        AiProtocolType.openai,
      );
      final mixedbread = AiModelCatalog.lookup(
        'mixedbread-ai/mxbai-embed-large-v1',
        AiProtocolType.openai,
      );
      final snowflake = AiModelCatalog.lookup(
        'Snowflake/snowflake-arctic-embed-m-v2.0',
        AiProtocolType.openai,
      );
      final snowflakeEmbed2 = AiModelCatalog.lookup(
        'snowflake-arctic-embed2',
        AiProtocolType.openai,
      );
      final embeddingGemma = AiModelCatalog.lookup(
        'embeddinggemma',
        AiProtocolType.openai,
      );
      final graniteCompact = AiModelCatalog.lookup(
        'granite-embedding:30m',
        AiProtocolType.openai,
      );
      final graniteLarge = AiModelCatalog.lookup(
        'ibm/granite-embedding-278m-multilingual',
        AiProtocolType.openai,
      );
      final nomicV2 = AiModelCatalog.lookup(
        'nomic-embed-text-v2-moe',
        AiProtocolType.openai,
      );
      final paraphrase = AiModelCatalog.lookup(
        'paraphrase-multilingual',
        AiProtocolType.openai,
      );
      final miniLm = AiModelCatalog.lookup(
        'sentence-transformers/all-MiniLM-L6-v2',
        AiProtocolType.openai,
      );
      final miniLmL12 = AiModelCatalog.lookup(
        'sentence-transformers/all-MiniLM-L12-v2',
        AiProtocolType.openai,
      );
      final reranker = AiModelCatalog.lookup(
        'BAAI/bge-reranker-large',
        AiProtocolType.openai,
      );

      expect(e5?.displayName, 'intfloat multilingual-e5');
      expect(e5?.embeddingDimensions, 1024);
      expect(e5?.embeddingMaxInputTokens, 512);
      expect(e5?.embeddingDefaultQueryTaskType, 'query');
      expect(e5?.embeddingDefaultDocumentTaskType, 'passage');
      expect(e5?.embeddingQueryTextPrefix, 'query:');
      expect(e5?.embeddingDocumentTextPrefix, 'passage:');

      expect(gteQwen?.displayName, 'GTE Qwen2 Embedding');
      expect(gteQwen?.embeddingDimensions, 3584);
      expect(gteQwen?.embeddingMaxInputTokens, 32768);
      expect(gteQwen?.embeddingSupportsCustomDimensions, isTrue);

      expect(bgeBase?.displayName, 'BAAI bge-base-zh');
      expect(bgeBase?.embeddingDimensions, 768);
      expect(mixedbread?.displayName, 'mxbai-embed-large-v1');
      expect(mixedbread?.embeddingDimensions, 1024);
      expect(snowflake?.displayName, 'Snowflake Arctic Embed');
      expect(snowflake?.embeddingDimensions, 768);
      expect(snowflake?.embeddingMaxInputTokens, 8192);
      expect(snowflakeEmbed2?.displayName, 'Snowflake Arctic Embed');
      expect(snowflakeEmbed2?.embeddingDimensions, 1024);
      expect(snowflakeEmbed2?.embeddingMaxInputTokens, 8192);
      expect(embeddingGemma?.displayName, 'EmbeddingGemma');
      expect(embeddingGemma?.embeddingDimensions, 768);
      expect(embeddingGemma?.embeddingSupportsCustomDimensions, isTrue);
      expect(graniteCompact?.displayName, 'IBM Granite Embedding');
      expect(graniteCompact?.embeddingDimensions, 384);
      expect(graniteLarge?.displayName, 'IBM Granite Embedding');
      expect(graniteLarge?.embeddingDimensions, 768);
      expect(nomicV2?.displayName, 'Nomic Embed Text v2 MoE');
      expect(nomicV2?.embeddingMinDimensions, 256);
      expect(nomicV2?.embeddingMaxInputTokens, 512);
      expect(paraphrase?.displayName, 'paraphrase-multilingual');
      expect(paraphrase?.embeddingDimensions, 768);
      expect(miniLm?.displayName, 'all-MiniLM-L6-v2');
      expect(miniLm?.embeddingDimensions, 384);
      expect(miniLmL12?.displayName, 'all-MiniLM-L12-v2');
      expect(miniLmL12?.embeddingDimensions, 384);
      expect(reranker?.supportsEmbeddings ?? false, isFalse);
    });

    test('recognizes managed compatible embedding model profiles', () {
      final titan = AiModelCatalog.lookup(
        'amazon.titan-embed-text-v2:0',
        AiProtocolType.openai,
      );
      final titanImage = AiModelCatalog.lookup(
        'amazon.titan-embed-image-v1',
        AiProtocolType.openai,
      );
      final nvidia = AiModelCatalog.lookup(
        'nvidia/nv-embedqa-e5-v5',
        AiProtocolType.openai,
      );
      final mistral = AiModelCatalog.lookup(
        'mistral-embed',
        AiProtocolType.openai,
      );
      final solar = AiModelCatalog.lookup(
        'solar-embedding-1-large-query',
        AiProtocolType.openai,
      );
      final slate = AiModelCatalog.lookup(
        'ibm/slate-30m-english-rtrvr',
        AiProtocolType.openai,
      );
      final slate125 = AiModelCatalog.lookup(
        'ibm/slate-125m-english-rtrvr-v2',
        AiProtocolType.openai,
      );
      final perplexity = AiModelCatalog.lookup(
        'pplx-embed-v1-4b',
        AiProtocolType.openai,
      );
      final perplexityContext = AiModelCatalog.lookup(
        'pplx-embed-context-v1-0.6b',
        AiProtocolType.openai,
      );
      final fireworksQwen3 = AiModelCatalog.lookup(
        'accounts/fireworks/models/qwen3-embedding-8b',
        AiProtocolType.openai,
      );

      expect(titan?.displayName, 'Amazon Titan Text Embeddings V2');
      expect(titan?.embeddingDimensions, 1024);
      expect(titan?.embeddingSupportsCustomDimensions, isTrue);
      expect(titan?.embeddingMinDimensions, 256);
      expect(titan?.embeddingMaxDimensions, 1024);
      expect(titan?.embeddingOutputDTypes, contains('binary'));

      expect(titanImage?.isMultimodal, isTrue);
      expect(titanImage?.embeddingDimensions, 1024);

      expect(nvidia?.displayName, 'NVIDIA NV-EmbedQA E5');
      expect(nvidia?.embeddingDimensions, 1024);
      expect(nvidia?.embeddingInputTypes, contains('query'));
      expect(nvidia?.supportedParameters, contains('input_type'));
      expect(nvidia?.embeddingDefaultTruncation, 'END');
      expect(nvidia?.embeddingSupportsTruncation, isTrue);

      expect(mistral?.displayName, 'Mistral Embed');
      expect(mistral?.embeddingOutputDTypes, contains('ubinary'));
      expect(mistral?.embeddingMaxInputsPerBatch, 512);

      expect(solar?.displayName, 'Solar Embedding');
      expect(solar?.embeddingDimensions, 4096);
      expect(solar?.embeddingDefaultTaskType, 'query');
      expect(solar?.embeddingQueryModelId, 'solar-embedding-1-large-query');
      expect(
        solar?.embeddingDocumentModelId,
        'solar-embedding-1-large-passage',
      );
      expect(slate?.displayName, 'IBM Slate 30M Embedding');
      expect(slate?.embeddingDimensions, 384);
      expect(slate125?.displayName, 'IBM Slate 125M Embedding');
      expect(slate125?.embeddingDimensions, 384);

      expect(perplexity?.displayName, 'Perplexity Embed v1 4B');
      expect(perplexity?.embeddingDimensions, 2560);
      expect(perplexity?.embeddingMinDimensions, 128);
      expect(perplexity?.embeddingDefaultEncodingFormat, 'base64_int8');
      expect(perplexity?.embeddingOutputsNormalized, isFalse);
      expect(perplexity?.embeddingMaxInputsPerBatch, 512);

      expect(
        perplexityContext?.displayName,
        'Perplexity Contextual Embed v1 0.6B',
      );
      expect(
        perplexityContext?.embeddingEndpointPath,
        'v1/embeddings/contextualized',
      );
      expect(perplexityContext?.embeddingRequiresSpecialBody, isTrue);
      expect(perplexityContext?.embeddingMaxInputsPerBatch, 16000);

      expect(fireworksQwen3?.displayName, 'Qwen3 Embedding');
      expect(fireworksQwen3?.embeddingDimensions, 4096);
      expect(fireworksQwen3?.embeddingMinDimensions, 32);
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
        expect(profile.embeddingDimensions, 3072);
        expect(profile.embeddingBatchSize, 100);
        expect(profile.embeddingSupportsCustomDimensions, isTrue);
        expect(profile.embeddingRequiresSpecialBody, isTrue);
        expect(profile.embeddingDefaultQueryTaskType, 'RETRIEVAL_QUERY');
      },
    );

    test('round-trips extended embedding profile parameters', () {
      const profile = AiModelProfile(
        capabilities: <AiModelCapability>{
          AiModelCapability.embeddingGeneration,
        },
        supportedParameters: <String>['input', 'model', 'input_type'],
        embeddingInputTypes: <String>['document', 'query'],
        embeddingDefaultInputType: 'document',
        embeddingQueryModelId: 'embedding-query',
        embeddingDocumentModelId: 'embedding-document',
        embeddingQueryInputType: 'query',
        embeddingDocumentInputType: 'document',
        embeddingSupportedTaskTypes: <String>['retrieval.query'],
        embeddingDefaultTaskType: 'retrieval.passage',
        embeddingDefaultQueryTaskType: 'retrieval.query',
        embeddingDefaultDocumentTaskType: 'retrieval.passage',
        embeddingQueryTextPrefix: 'query:',
        embeddingDocumentTextPrefix: 'passage:',
        embeddingEncodingFormats: <String>['float'],
        embeddingDefaultEncodingFormat: 'float',
        embeddingOutputDTypes: <String>['float', 'int8'],
        embeddingDefaultOutputDType: 'float',
        embeddingDefaultTruncation: 'END',
        embeddingSimilarityMetric: 'cosine',
        embeddingOutputsNormalized: true,
      );

      final roundTripped = AiModelProfile.fromJson(profile.toJson());

      expect(roundTripped.supportedParameters, <String>[
        'input',
        'model',
        'input_type',
      ]);
      expect(roundTripped.embeddingDefaultInputType, 'document');
      expect(roundTripped.embeddingQueryModelId, 'embedding-query');
      expect(roundTripped.embeddingDocumentModelId, 'embedding-document');
      expect(roundTripped.embeddingQueryInputType, 'query');
      expect(roundTripped.embeddingDocumentInputType, 'document');
      expect(roundTripped.embeddingDefaultQueryTaskType, 'retrieval.query');
      expect(
        roundTripped.embeddingDefaultDocumentTaskType,
        'retrieval.passage',
      );
      expect(roundTripped.embeddingQueryTextPrefix, 'query:');
      expect(roundTripped.embeddingDocumentTextPrefix, 'passage:');
      expect(roundTripped.embeddingDefaultOutputDType, 'float');
      expect(roundTripped.embeddingDefaultTruncation, 'END');
      expect(roundTripped.embeddingOutputsNormalized, isTrue);
    });
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

String _base64Float32(List<double> values) {
  final data = ByteData(values.length * 4);
  for (var index = 0; index < values.length; index += 1) {
    data.setFloat32(index * 4, values[index], Endian.little);
  }
  return base64Encode(data.buffer.asUint8List());
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
