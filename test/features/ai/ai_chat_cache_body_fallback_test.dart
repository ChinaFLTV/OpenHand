import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test(
    'stream retries without cache body affinity when gateway rejects it',
    () async {
      final requestBodies = <Map<String, Object?>>[];
      var callCount = 0;
      final client = MockClient((request) async {
        callCount += 1;
        requestBodies.add(
          Map<String, Object?>.from(jsonDecode(request.body) as Map),
        );
        if (callCount == 1) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'message': 'Unknown parameter: prompt_cache_key',
              },
            }),
            400,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response(
          [
            'data: {"choices":[{"delta":{"content":"OK"},"finish_reason":null}]}',
            '',
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":8,"prompt_tokens_details":{"cached_tokens":6},"completion_tokens":1,"total_tokens":9}}',
            '',
            'data: [DONE]',
            '',
          ].join('\n'),
          200,
          headers: const <String, String>{'content-type': 'text/event-stream'},
        );
      });
      final service = AiChatService(client: client);

      final stream = await service.sendMessageStream(
        model: const AiModelConfig(
          id: 'model-1',
          baseUrl: 'http://127.0.0.1:3000',
          authScheme: AiAuthScheme.bearer,
          token: 'token',
          modelId: 'grok-composer-2.5-fast',
          protocolType: AiProtocolType.openai,
        ),
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.system, content: 'Stable system prompt.'),
          AiChatTurn(role: AiChatRole.user, content: 'Hello'),
        ],
        inputCacheConfig: const AiInputCacheRuntimeConfig(
          enabled: true,
          mode: 'allMessages',
          updateInterval: 10,
          breakpointCount: 4,
          cacheAffinityId: 'session-1',
        ),
      );

      final events = await stream.events.toList();
      final result = await stream.result;

      expect(callCount, 2);
      expect(
        requestBodies.first[AiPromptCacheAffinity
            .openAiPromptCacheKeyBodyField],
        'session-1',
      );
      expect(
        requestBodies.last.containsKey(
          AiPromptCacheAffinity.openAiPromptCacheKeyBodyField,
        ),
        isFalse,
      );
      expect(events.where((event) => event.textDelta == 'OK'), isNotEmpty);
      expect(result.reply, 'OK');
      expect(result.usage?.cacheReadTokens, 6);
    },
  );

  test(
    'stream keeps non-cache gateway errors on the original failure',
    () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount += 1;
        return http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{'message': 'Bad request: unrelated'},
          }),
          400,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final service = AiChatService(client: client);

      await expectLater(
        service.sendMessageStream(
          model: const AiModelConfig(
            id: 'model-1',
            baseUrl: 'http://127.0.0.1:3000',
            authScheme: AiAuthScheme.bearer,
            token: 'token',
            modelId: 'grok-composer-2.5-fast',
            protocolType: AiProtocolType.openai,
          ),
          messages: const <AiChatTurn>[
            AiChatTurn(
              role: AiChatRole.system,
              content: 'Stable system prompt.',
            ),
            AiChatTurn(role: AiChatRole.user, content: 'Hello'),
          ],
          inputCacheConfig: const AiInputCacheRuntimeConfig(
            enabled: true,
            mode: 'allMessages',
            updateInterval: 10,
            breakpointCount: 4,
            cacheAffinityId: 'session-1',
          ),
        ),
        throwsA(
          isA<AiChatException>().having(
            (error) => error.message,
            'message',
            contains('Bad request: unrelated'),
          ),
        ),
      );
      expect(callCount, 1);
    },
  );

  test(
    'stream does not retry cache errors when request has no body marker',
    () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount += 1;
        return http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'message': 'Unknown parameter: prompt_cache_key',
            },
          }),
          400,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final service = AiChatService(client: client);

      await expectLater(
        service.sendMessageStream(
          model: const AiModelConfig(
            id: 'model-1',
            baseUrl: 'https://api.x.ai',
            authScheme: AiAuthScheme.bearer,
            token: 'token',
            modelId: 'grok-composer-2.5-fast',
            protocolType: AiProtocolType.grok,
          ),
          messages: const <AiChatTurn>[
            AiChatTurn(
              role: AiChatRole.system,
              content: 'Stable system prompt.',
            ),
            AiChatTurn(role: AiChatRole.user, content: 'Hello'),
          ],
          inputCacheConfig: const AiInputCacheRuntimeConfig(
            enabled: true,
            mode: 'allMessages',
            updateInterval: 10,
            breakpointCount: 4,
            cacheAffinityId: 'session-1',
          ),
        ),
        throwsA(isA<AiChatException>()),
      );
      expect(callCount, 1);
    },
  );
}
