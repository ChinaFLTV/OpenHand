import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/ai_chat_service.dart';

void main() {
  test('AiChatService testModel sends a minimal availability probe', () async {
    Uri? requestUri;
    Map<String, String>? requestHeaders;
    Map<String, Object?>? requestBody;
    final service = AiChatService(
      client: MockClient((request) async {
        requestUri = request.url;
        requestHeaders = request.headers;
        requestBody = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'OK'},
              },
            ],
          }),
          200,
        );
      }),
    );
    final model = AiModelConfig(
      id: 'model-1',
      baseUrl: 'https://api.example.com/',
      authScheme: AiAuthScheme.bearer,
      token: 'secret-token',
      modelId: 'gpt-test',
      protocolType: AiProtocolType.openai,
    );

    addTearDown(service.dispose);

    final reply = await service.testModel(model);

    expect(reply, 'OK');
    expect(
      requestUri.toString(),
      'https://api.example.com/v1/chat/completions',
    );
    expect(
      requestHeaders,
      containsPair('authorization', 'Bearer secret-token'),
    );
    expect(requestBody, isNotNull);
    expect(requestBody!['model'], 'gpt-test');
    expect(requestBody!['messages'], [
      {
        'role': 'user',
        'content': 'Reply with OK only if this model configuration works.',
      },
    ]);
  });

  test(
    'AiChatService testModel surfaces transport failures as AiChatException',
    () async {
      final service = AiChatService(
        client: MockClient((request) async {
          throw http.ClientException('network unavailable');
        }),
      );
      final model = AiModelConfig(
        id: 'model-1',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      addTearDown(service.dispose);

      expect(
        () => service.testModel(model),
        throwsA(
          isA<AiChatException>().having(
            (error) => error.message,
            'message',
            'network unavailable',
          ),
        ),
      );
    },
  );
}
