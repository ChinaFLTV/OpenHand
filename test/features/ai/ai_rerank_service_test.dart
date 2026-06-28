import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

void main() {
  test('DashScope qwen3 rerank uses compatible reranks endpoint', () async {
    final transport = _RecordingTransport(
      responseBody: jsonEncode(<String, Object?>{
        'output': <String, Object?>{
          'results': <Object?>[
            <String, Object?>{'index': 1, 'relevance_score': 0.91},
            <String, Object?>{'index': 0, 'relevance_score': 0.12},
          ],
        },
      }),
    );
    final service = AiRerankService(transport: transport);

    final result = await service.rerank(
      model: const AiModelConfig(
        id: 'dashscope',
        baseUrl: 'https://dashscope.aliyuncs.com',
        authScheme: AiAuthScheme.bearer,
        token: 'test-token',
        modelId: 'qwen3-rerank',
        protocolType: AiProtocolType.qwen,
      ),
      query: 'vector database',
      documents: const <Object>['alpha', 'beta'],
      topN: 2,
      returnDocuments: false,
    );

    expect(transport.uri?.path, '/compatible-mode/v1/reranks');
    expect(transport.body['model'], 'qwen3-rerank');
    expect(transport.body['top_n'], 2);
    expect(transport.body.containsKey('return_documents'), isFalse);
    expect(result.items.map((item) => item.index), <int>[1, 0]);
    expect(result.items.first.score, 0.91);
  });

  test('Voyage rerank uses top_k and parses data array', () async {
    final transport = _RecordingTransport(
      responseBody: jsonEncode(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{'index': 0, 'score': 0.77},
        ],
      }),
    );
    final service = AiRerankService(transport: transport);

    final result = await service.rerank(
      model: const AiModelConfig(
        id: 'voyage',
        baseUrl: 'https://api.voyageai.com',
        authScheme: AiAuthScheme.bearer,
        token: 'test-token',
        modelId: 'rerank-2.5',
        protocolType: AiProtocolType.openai,
      ),
      query: 'rag',
      documents: const <Object>['doc'],
      topN: 1,
    );

    expect(transport.uri?.path, '/v1/rerank');
    expect(transport.body['top_k'], 1);
    expect(transport.body.containsKey('top_n'), isFalse);
    expect(transport.body['truncation'], true);
    expect(result.items.single.index, 0);
    expect(result.items.single.document, 'doc');
  });

  test('Cohere rerank omits unsupported return_documents flag', () async {
    final transport = _RecordingTransport(
      responseBody: jsonEncode(<String, Object?>{
        'results': <Object?>[
          <String, Object?>{'index': 0, 'relevance_score': 0.5},
        ],
      }),
    );
    final service = AiRerankService(transport: transport);

    await service.rerank(
      model: const AiModelConfig(
        id: 'cohere',
        baseUrl: 'https://api.cohere.com',
        authScheme: AiAuthScheme.bearer,
        token: 'test-token',
        modelId: 'rerank-v3.5',
        protocolType: AiProtocolType.openai,
      ),
      query: 'query',
      documents: const <Object>['doc'],
      topN: 1,
      returnDocuments: true,
      maxTokensPerDoc: 1024,
    );

    expect(transport.uri?.path, '/v2/rerank');
    expect(transport.body['top_n'], 1);
    expect(transport.body['max_tokens_per_doc'], 1024);
    expect(transport.body.containsKey('return_documents'), isFalse);
  });

  test(
    'Spark rerank uses versioned base path and compatible body fields',
    () async {
      final transport = _RecordingTransport(
        responseBody: jsonEncode(<String, Object?>{
          'results': <Object?>[
            <String, Object?>{'index': 0, 'score': 0.88},
          ],
        }),
      );
      final service = AiRerankService(transport: transport);

      final result = await service.rerank(
        model: const AiModelConfig(
          id: 'spark',
          baseUrl: 'https://maas-api.cn-huabei-1.xf-yun.com/v2',
          authScheme: AiAuthScheme.bearer,
          token: 'test-token',
          modelId: 'spark-rerank',
          protocolType: AiProtocolType.openai,
        ),
        query: 'query',
        documents: const <Object>['doc'],
        topN: 1,
        returnDocuments: true,
        maxTokensPerDoc: 1024,
        truncation: true,
        instruction: 'prefer exact matches',
      );

      expect(transport.uri?.path, '/v2/rerank');
      expect(transport.body['model'], 'spark-rerank');
      expect(transport.body['top_n'], 1);
      expect(transport.body['return_documents'], isTrue);
      expect(transport.body['max_tokens_per_doc'], 1024);
      expect(transport.body['truncation'], isTrue);
      expect(transport.body['instruct'], 'prefer exact matches');
      expect(result.items.single.score, 0.88);
    },
  );

  test('rerank response skips non-finite score values', () async {
    final transport = _RecordingTransport(
      responseBody:
          '{"results":[{"index":"0","relevance_score":"NaN"},{"index":"1","relevance_score":"0.8"}]}',
    );
    final service = AiRerankService(transport: transport);

    final result = await service.rerank(
      model: const AiModelConfig(
        id: 'cohere',
        baseUrl: 'https://api.cohere.com',
        authScheme: AiAuthScheme.bearer,
        token: 'test-token',
        modelId: 'rerank-v3.5',
        protocolType: AiProtocolType.openai,
      ),
      query: 'query',
      documents: const <Object>['bad', 'good'],
      topN: 2,
    );

    expect(result.items, hasLength(1));
    expect(result.items.single.index, 1);
    expect(result.items.single.score, 0.8);
  });
}

class _RecordingTransport extends AiTransportClient {
  _RecordingTransport({required this.responseBody})
    : super(client: _NoopClient());

  final String responseBody;
  Uri? uri;
  Map<String, Object?> body = const <String, Object?>{};

  @override
  Future<http.Response> sendJson({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required Duration timeout,
  }) async {
    this.uri = uri;
    this.body = body;
    return http.Response(responseBody, 200);
  }

  @override
  void dispose() {}
}

class _NoopClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError('network is disabled for this test');
  }
}
