import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_api_dialect.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';

void main() {
  group('AiChatService', () {
    test(
      'streams custom OpenAI-compatible text-only turns through chat completions',
      () async {
        final requestedUrls = <Uri>[];
        final client = MockClient((request) async {
          requestedUrls.add(request.url);
          if (request.url.path.endsWith('/responses')) {
            return http.Response('responses endpoint missing', 404);
          }

          expect(request.url.path, '/v1/chat/completions');
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['stream'], isTrue);
          expect(body['tools'], isNull);

          return http.Response.bytes(
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"可以"},"finish_reason":null}]}\n\n'
              'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
              'data: [DONE]\n\n',
            ),
            200,
            headers: const <String, String>{
              'content-type': 'text/event-stream',
            },
          );
        });
        final service = AiChatService(client: client);
        addTearDown(service.dispose);

        final response = await service.sendMessageStream(
          model: _customOpenAiCompatibleModel(),
          messages: const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.user, content: '你爱我吗？'),
          ],
          timeout: const Duration(seconds: 5),
          streamIdleTimeout: const Duration(seconds: 5),
        );

        final events = await response.events.toList();
        final result = await response.result;

        expect(events.map((event) => event.textDelta).whereType<String>(), [
          '可以',
        ]);
        expect(result.reply, '可以');
        expect(requestedUrls, hasLength(1));
        expect(requestedUrls.single.path, '/v1/chat/completions');
      },
    );

    test('keeps responses routing for native OpenAI providers', () async {
      final requestedUrls = <Uri>[];
      final client = MockClient((request) async {
        requestedUrls.add(request.url);
        expect(request.url.path, '/v1/responses');
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['stream'], isTrue);
        expect(body['input'], contains('user: ping'));

        return http.Response(
          'data: {"type":"response.output_text.delta","delta":"OK"}\n\n'
          'data: {"type":"response.completed","response":{"output":[{"content":[{"type":"output_text","text":"OK"}]}]}}\n\n',
          200,
          headers: const <String, String>{'content-type': 'text/event-stream'},
        );
      });
      final service = AiChatService(client: client);
      addTearDown(service.dispose);

      final response = await service.sendMessageStream(
        model: _nativeOpenAiModel(),
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'ping'),
        ],
        timeout: const Duration(seconds: 5),
        streamIdleTimeout: const Duration(seconds: 5),
      );

      final result = await response.result;

      expect(result.reply, 'OK');
      expect(requestedUrls, hasLength(1));
      expect(requestedUrls.single.path, '/v1/responses');
    });

    test(
      'falls back to chat completions when responses streaming is missing',
      () async {
        final requestedUrls = <Uri>[];
        final client = MockClient((request) async {
          requestedUrls.add(request.url);
          if (request.url.path.endsWith('/responses')) {
            return http.Response('not found', 404);
          }
          expect(request.url.path, '/v1/chat/completions');
          return http.Response(
            'data: {"choices":[{"delta":{"content":"fallback"},"finish_reason":null}]}\n\n'
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
            'data: [DONE]\n\n',
            200,
            headers: const <String, String>{
              'content-type': 'text/event-stream',
            },
          );
        });
        final service = AiChatService(client: client);
        addTearDown(service.dispose);

        final response = await service.sendMessageStream(
          model: _nativeOpenAiModel(),
          messages: const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.user, content: 'ping'),
          ],
          timeout: const Duration(seconds: 5),
          streamIdleTimeout: const Duration(seconds: 5),
        );

        final result = await response.result;

        expect(result.reply, 'fallback');
        expect(requestedUrls.map((url) => url.path), [
          '/v1/responses',
          '/v1/chat/completions',
        ]);
      },
    );
  });
}

AiModelConfig _customOpenAiCompatibleModel() {
  return const AiModelConfig(
    id: 'custom-openai-compatible',
    baseUrl: 'https://relay.example/v1',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'deepseek-v4-flash',
    protocolType: AiProtocolType.openai,
  );
}

AiModelConfig _nativeOpenAiModel() {
  return const AiModelConfig(
    id: 'openai',
    baseUrl: 'https://api.openai.com/v1',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'gpt-4.1-mini',
    protocolType: AiProtocolType.openai,
    providerKind: AiProviderKind.openai,
  );
}
