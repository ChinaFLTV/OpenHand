import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

void main() {
  test('Doubao translation ignores non-finite response codes', () async {
    final client = _StaticResponseClient(
      '{"code":1e999,"data":{"translation_list":[{"translation":"你好"}]}}',
    );
    final service = AiTranslationService(client: client);
    final provider =
        AiTranslationProviderSettings.defaults(
          AiTranslationProvider.doubao,
        ).copyWith(
          enabled: true,
          endpoint: 'https://example.test/translate',
          apiKey: 'test-key',
        );
    final settings = AiTranslationSettings.defaults()
        .copyWith(
          enabled: true,
          sourceLanguage: 'en',
          targetLanguage: 'zh-CN',
          providerPriority: const <AiTranslationProvider>[
            AiTranslationProvider.doubao,
          ],
          providers: <AiTranslationProvider, AiTranslationProviderSettings>{
            AiTranslationProvider.doubao: provider,
          },
        )
        .normalized();

    final result = await service.translate(
      text: 'hello',
      settings: settings,
      availableModels: const <AiModelConfig>[],
    );

    expect(result.text, '你好');
    expect(result.provider, AiTranslationProvider.doubao);
    expect(client.postedBody, contains('"text_list":["hello"]'));
    service.dispose();
  });

  test('embeddings ignore non-finite response dimension hints', () async {
    final transport = _RecordingTransport(
      responseBody: jsonEncode(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'embedding': <num>[1, 2, 3],
          },
        ],
      }),
    );
    final service = AiEmbeddingsService(transport: transport);

    final result = await service.createEmbedding(
      model: const AiModelConfig(
        id: 'embeddings',
        baseUrl: 'https://api.example.test',
        authScheme: AiAuthScheme.bearer,
        token: 'test-token',
        modelId: 'text-embedding-test',
        protocolType: AiProtocolType.openai,
        modelProfiles: <String, AiModelProfile>{
          'text-embedding-test': AiModelProfile(
            defaultParameters: <String, Object?>{'dimensions': double.infinity},
          ),
        },
      ),
      input: 'hello',
    );

    expect(transport.body['dimensions'], double.infinity);
    expect(result.vectors.single, <double>[1, 2, 3]);
    service.dispose();
  });
}

class _StaticResponseClient extends http.BaseClient {
  _StaticResponseClient(this.responseBody);

  final String responseBody;
  String postedBody = '';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      postedBody = request.body;
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(responseBody)),
      200,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }
}

class _RecordingTransport extends AiTransportClient {
  _RecordingTransport({required this.responseBody})
    : super(client: _NoopClient());

  final String responseBody;
  Map<String, Object?> body = const <String, Object?>{};

  @override
  Future<http.Response> sendJson({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required Duration timeout,
  }) async {
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
