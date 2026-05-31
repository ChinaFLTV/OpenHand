import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/model_registry/ai_model_scanner.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}

http.StreamedResponse _jsonResponse(
  int statusCode,
  Object body,
) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

AiModelConfig _openAiConfig(String baseUrl) {
  return AiModelConfig(
    id: 'provider-1',
    baseUrl: baseUrl,
    authScheme: AiAuthScheme.bearer,
    token: 'sk-test',
    modelId: 'gpt-4o-mini',
    protocolType: AiProtocolType.openai,
  );
}

void main() {
  test('openai-compatible scan prefers /v1/models for bare host base URLs', () async {
    final requestedUrls = <String>[];
    final scanner = AiModelScanner(
      httpClient: _FakeHttpClient((request) async {
        requestedUrls.add(request.url.toString());
        if (request.url.toString() == 'https://relay.example.com/v1/models') {
          return _jsonResponse(200, <String, Object?>{
            'data': <Object?>[
              <String, Object?>{'id': 'gpt-4o-mini'},
            ],
          });
        }
        return _jsonResponse(404, <String, Object?>{'error': 'not found'});
      }),
    );

    final result = await scanner.scan(_openAiConfig('https://relay.example.com'));

    expect(result.isSuccess, isTrue);
    expect(result.modelIds, <String>['gpt-4o-mini']);
    expect(
      requestedUrls,
      contains('https://relay.example.com/v1/models'),
    );
    expect(
      requestedUrls.where((url) => url == 'https://relay.example.com/models'),
      isEmpty,
    );
  });

  test('openai-compatible scan keeps /v1/models when base URL already ends with /v1', () async {
    final requestedUrls = <String>[];
    final scanner = AiModelScanner(
      httpClient: _FakeHttpClient((request) async {
        requestedUrls.add(request.url.toString());
        return _jsonResponse(200, <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'id': 'gpt-4o-mini'},
          ],
        });
      }),
    );

    final result = await scanner.scan(_openAiConfig('https://relay.example.com/v1'));

    expect(result.isSuccess, isTrue);
    expect(requestedUrls, <String>['https://relay.example.com/v1/models']);
  });

  test('openai-compatible scan derives /v1/models from full chat endpoint URLs', () async {
    final requestedUrls = <String>[];
    final scanner = AiModelScanner(
      httpClient: _FakeHttpClient((request) async {
        requestedUrls.add(request.url.toString());
        return _jsonResponse(200, <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'id': 'gpt-4o-mini'},
          ],
        });
      }),
    );

    final result = await scanner.scan(
      _openAiConfig('https://relay.example.com/v1/chat/completions'),
    );

    expect(result.isSuccess, isTrue);
    expect(requestedUrls, <String>['https://relay.example.com/v1/models']);
  });

  test('openai-compatible scan returns auth errors immediately', () async {
    final requestedUrls = <String>[];
    final scanner = AiModelScanner(
      httpClient: _FakeHttpClient((request) async {
        requestedUrls.add(request.url.toString());
        return _jsonResponse(401, <String, Object?>{'error': 'invalid key'});
      }),
    );

    final result = await scanner.scan(_openAiConfig('https://relay.example.com'));

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('401'));
    expect(requestedUrls, <String>['https://relay.example.com/v1/models']);
  });
}
