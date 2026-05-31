import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_endpoint_override.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/operations/ai_completions_service.dart';
import 'package:openhand/features/ai/service/operations/ai_embeddings_service.dart';
import 'package:openhand/features/ai/service/operations/ai_moderations_service.dart';
import 'package:openhand/features/ai/service/operations/ai_rerank_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}

http.StreamedResponse _jsonResponse(int statusCode, Object body) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

AiModelConfig _baseConfig({Map<AiApiFamily, AiEndpointOverride>? overrides}) {
  return AiModelConfig(
    id: 'provider-1',
    baseUrl: 'https://relay.example.com/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'sk-test',
    modelId: 'gpt-4.1-mini',
    protocolType: AiProtocolType.openai,
    endpointOverrides: overrides ?? const <AiApiFamily, AiEndpointOverride>{},
  );
}

void main() {
  test('completions service hits /v1/completions', () async {
    late String requestUrl;
    late Map<String, Object?> requestBody;
    final transport = AiTransportClient(
      client: _FakeHttpClient((request) async {
        requestUrl = request.url.toString();
        requestBody = jsonDecode(await request.finalize().bytesToString())
            as Map<String, Object?>;
        return _jsonResponse(200, <String, Object?>{
          'choices': <Object?>[
            <String, Object?>{'text': 'done'},
          ],
        });
      }),
    );
    final service = AiCompletionsService(transport: transport);

    final result = await service.complete(
      model: _baseConfig(),
      prompt: 'hello',
    );

    expect(requestUrl, 'https://relay.example.com/v1/completions');
    expect(requestBody['prompt'], 'hello');
    expect(result.text, 'done');
  });

  test('embeddings service honors endpoint override', () async {
    late String requestUrl;
    final transport = AiTransportClient(
      client: _FakeHttpClient((request) async {
        requestUrl = request.url.toString();
        return _jsonResponse(200, <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'embedding': <double>[0.1, 0.2]},
          ],
        });
      }),
    );
    final service = AiEmbeddingsService(transport: transport);

    final result = await service.createEmbeddings(
      model: _baseConfig(
        overrides: <AiApiFamily, AiEndpointOverride>{
          AiApiFamily.embeddings: const AiEndpointOverride(
            path: 'api/embeddings',
          ),
        },
      ),
      input: const <String>['hello'],
    );

    expect(requestUrl, 'https://relay.example.com/v1/api/embeddings');
    expect(result.vectors.single, <double>[0.1, 0.2]);
  });

  test('moderations service hits /v1/moderations', () async {
    late String requestUrl;
    final transport = AiTransportClient(
      client: _FakeHttpClient((request) async {
        requestUrl = request.url.toString();
        return _jsonResponse(200, <String, Object?>{
          'results': <Object?>[],
        });
      }),
    );
    final service = AiModerationsService(transport: transport);

    await service.moderate(model: _baseConfig(), input: 'hello');

    expect(requestUrl, 'https://relay.example.com/v1/moderations');
  });

  test('rerank service parses result scores', () async {
    final transport = AiTransportClient(
      client: _FakeHttpClient((request) async {
        return _jsonResponse(200, <String, Object?>{
          'results': <Object?>[
            <String, Object?>{'index': 1, 'relevance_score': 0.93},
          ],
        });
      }),
    );
    final service = AiRerankService(transport: transport);

    final result = await service.rerank(
      model: _baseConfig(),
      query: 'hello',
      documents: const <String>['a', 'b'],
    );

    expect(result.items.single.index, 1);
    expect(result.items.single.score, 0.93);
  });
}
