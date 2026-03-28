import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/ai_chat_service.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';

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
    'AiChatService sendMessage returns reply text with usage metadata',
    () async {
      final service = AiChatService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Ready'},
                },
              ],
              'usage': {
                'prompt_tokens': 12,
                'completion_tokens': 4,
                'total_tokens': 16,
              },
            }),
            200,
          );
        }),
      );
      const model = AiModelConfig(
        id: 'model-1',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      addTearDown(service.dispose);

      final completion = await service.sendMessage(
        model: model,
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'Hello'),
        ],
      );

      expect(completion.reply, 'Ready');
      expect(completion.usage?.promptTokens, 12);
      expect(completion.usage?.completionTokens, 4);
      expect(completion.usage?.totalTokens, 16);
    },
  );

  test(
    'AiChatService sendMessage accepts integer-like usage values from compatible providers',
    () async {
      final service = AiChatService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Ready'},
                },
              ],
              'usage': {
                'prompt_tokens': '12',
                'completion_tokens': 4.0,
                'total_tokens': '16.0',
              },
            }),
            200,
          );
        }),
      );
      const model = AiModelConfig(
        id: 'model-compatible-usage',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      addTearDown(service.dispose);

      final completion = await service.sendMessage(
        model: model,
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'Hello'),
        ],
      );

      expect(completion.usage?.promptTokens, 12);
      expect(completion.usage?.completionTokens, 4);
      expect(completion.usage?.totalTokens, 16);
    },
  );

  test(
    'AiChatService sendMessage recovers DSML tool calls when the provider returns tool markup in content',
    () async {
      final service = AiChatService(
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content':
                          '<｜DSML｜function_calls><｜DSML｜invoke name="TodoWrite"><｜DSML｜parameter name="todos" string="false">[{"id":"1","content":"Create the HTML page","status":"in_progress"}]</｜DSML｜parameter></｜DSML｜invoke></｜DSML｜function_calls>',
                    },
                  },
                ],
              }),
            ),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      );
      const model = AiModelConfig(
        id: 'model-dsml',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      addTearDown(service.dispose);

      final completion = await service.sendMessage(
        model: model,
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'Hello'),
        ],
      );

      expect(completion.reply, isEmpty);
      expect(completion.toolCalls, hasLength(1));
      expect(completion.toolCalls.single.name, 'TodoWrite');
      expect(
        completion.toolCalls.single.arguments,
        '{"todos":[{"id":"1","content":"Create the HTML page","status":"in_progress"}]}',
      );
    },
  );

  test(
    'AiChatService encodes OpenAI-compatible image attachments as content parts',
    () async {
      Map<String, Object?>? requestBody;
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-ai-chat-image-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final imageFile = File('${tempDirectory.path}/sample.png');
      final sourceImage = img.Image(width: 4, height: 3);
      await imageFile.writeAsBytes(img.encodePng(sourceImage), flush: true);
      final service = AiChatService(
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Ready'},
                },
              ],
            }),
            200,
          );
        }),
      );
      const model = AiModelConfig(
        id: 'model-image',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-4o-mini',
        protocolType: AiProtocolType.openai,
      );

      addTearDown(service.dispose);

      await service.sendMessage(
        model: model,
        messages: <AiChatTurn>[
          AiChatTurn(
            role: AiChatRole.user,
            content: 'Describe the attachment',
            parts: <AiChatContentPart>[
              AiChatContentPart.imageFile(
                filePath: imageFile.path,
                mimeType: 'image/png',
              ),
            ],
          ),
        ],
      );

      final messages = requestBody?['messages'] as List<dynamic>?;
      expect(messages, isNotNull);
      final firstMessage = messages!.first as Map<String, Object?>;
      final content = firstMessage['content'] as List<dynamic>;
      expect(content, hasLength(2));
      expect(content.first, <String, Object?>{
        'type': 'text',
        'text': 'Describe the attachment',
      });
      final imagePart = content.last as Map<String, Object?>;
      final imageUrl = imagePart['image_url'] as Map<String, Object?>;
      expect(imagePart['type'], 'image_url');
      expect('${imageUrl['url']}', startsWith('data:image/png;base64,'));
    },
  );

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

  test(
    'AiChatService sendMessageStream completes when SSE emits DONE without closing upstream connection',
    () async {
      final responseController = StreamController<List<int>>();
      final service = AiChatService(
        client: _StreamingMockClient(responseController),
      );
      const model = AiModelConfig(
        id: 'model-stream',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      addTearDown(() async {
        await responseController.close();
        service.dispose();
      });

      final response = await service.sendMessageStream(
        model: model,
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'Hello'),
        ],
      );
      final eventsFuture = response.events.toList();

      responseController.add(
        utf8.encode(
          'data: {"choices":[{"delta":{"content":"Ready"}}]}\n\n'
          'data: [DONE]\n\n',
        ),
      );

      final result = await response.result.timeout(const Duration(seconds: 1));
      final events = await eventsFuture.timeout(const Duration(seconds: 1));

      expect(result.reply, 'Ready');
      expect(events, hasLength(1));
      expect(events.single.type, AiChatStreamEventType.textDelta);
      expect(events.single.textDelta, 'Ready');
    },
  );

  test(
    'AiChatService sendMessageStream keeps distinct tool calls when SSE indexes are string values',
    () async {
      final responseController = StreamController<List<int>>();
      final service = AiChatService(
        client: _StreamingMockClient(responseController),
      );
      const model = AiModelConfig(
        id: 'model-stream-tools',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      addTearDown(() async {
        await responseController.close();
        service.dispose();
      });

      final response = await service.sendMessageStream(
        model: model,
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'Hello'),
        ],
      );
      final eventsFuture = response.events.toList();

      responseController.add(
        utf8.encode(
          'data: {"usage":{"prompt_tokens":"6","completion_tokens":"2","total_tokens":"8"},"choices":[{"delta":{"tool_calls":[{"index":"0","id":"tool-call-0","function":{"name":"bash","arguments":"{\\"cmd\\":\\"pwd\\"}"}},{"index":"1","id":"tool-call-1","function":{"name":"bash","arguments":"{\\"cmd\\":\\"ls\\"}"}}]}}]}\n\n'
          'data: [DONE]\n\n',
        ),
      );

      final result = await response.result.timeout(const Duration(seconds: 1));
      final events = await eventsFuture.timeout(const Duration(seconds: 1));

      expect(result.toolCalls, hasLength(2));
      expect(result.toolCalls.first.id, 'tool-call-0');
      expect(result.toolCalls.last.id, 'tool-call-1');
      expect(result.usage?.totalTokens, 8);
      expect(
        events.where((event) => event.type == AiChatStreamEventType.usage),
        hasLength(1),
      );
      expect(
        events.where(
          (event) => event.type == AiChatStreamEventType.toolCallDelta,
        ),
        hasLength(2),
      );
    },
  );

  test(
    'AiChatService sendMessageStream ignores trailing SSE blocks after DONE in the same chunk',
    () async {
      final responseController = StreamController<List<int>>();
      final service = AiChatService(
        client: _StreamingMockClient(responseController),
      );
      const model = AiModelConfig(
        id: 'model-stream-done-guard',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      addTearDown(() async {
        await responseController.close();
        service.dispose();
      });

      final response = await service.sendMessageStream(
        model: model,
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'Hello'),
        ],
      );
      final eventsFuture = response.events.toList();

      responseController.add(
        utf8.encode(
          'data: {"choices":[{"delta":{"content":"Ready"}}]}\n\n'
          'data: [DONE]\n\n'
          'data: {"choices":[{"delta":{"content":"Late"}}]}\n\n',
        ),
      );

      final result = await response.result.timeout(const Duration(seconds: 1));
      final events = await eventsFuture.timeout(const Duration(seconds: 1));

      expect(result.reply, 'Ready');
      expect(events, hasLength(1));
      expect(events.single.textDelta, 'Ready');
    },
  );

  test(
    'AiChatService sendMessageStream recovers DSML tool calls from streamed text content',
    () async {
      final responseController = StreamController<List<int>>();
      final service = AiChatService(
        client: _StreamingMockClient(responseController),
      );
      const model = AiModelConfig(
        id: 'model-stream-dsml',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      addTearDown(() async {
        await responseController.close();
        service.dispose();
      });

      final response = await service.sendMessageStream(
        model: model,
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'Hello'),
        ],
      );

      responseController.add(
        utf8.encode(
          'data: {"choices":[{"delta":{"content":"<｜DSML｜function_calls><｜DSML｜invoke name=\\"TodoWrite\\"><｜DSML｜parameter name=\\"todos\\" string=\\"false\\">[{\\"id\\":\\"1\\",\\"content\\":\\"Patch the timeline\\",\\"status\\":\\"in_progress\\"}]</｜DSML｜parameter></｜DSML｜invoke></｜DSML｜function_calls>"}}]}\n\n'
          'data: [DONE]\n\n',
        ),
      );

      final result = await response.result.timeout(const Duration(seconds: 1));

      expect(result.reply, isEmpty);
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'TodoWrite');
      expect(
        result.toolCalls.single.arguments,
        '{"todos":[{"id":"1","content":"Patch the timeline","status":"in_progress"}]}',
      );
    },
  );

  test(
    'AiChatService synthetic stream cancellation ignores late completion safely',
    () async {
      final service = AiChatService(
        client: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response(
            jsonEncode({
              'content': [
                {'text': 'Late reply'},
              ],
              'usage': {
                'input_tokens': 3,
                'output_tokens': 2,
                'total_tokens': 5,
              },
            }),
            200,
          );
        }),
      );
      const model = AiModelConfig(
        id: 'model-claude',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'claude-test',
        protocolType: AiProtocolType.claude,
      );

      addTearDown(service.dispose);

      final response = await service.sendMessageStream(
        model: model,
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'Hello'),
        ],
      );
      final eventsFuture = response.events.toList();

      await response.cancel!.call();
      final result = await response.result;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(result.wasCancelled, isTrue);
      expect(result.reply, isEmpty);
      expect(await eventsFuture, isEmpty);
    },
  );
}

class _StreamingMockClient extends http.BaseClient {
  _StreamingMockClient(this._responseStream);

  final StreamController<List<int>> _responseStream;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(_responseStream.stream, 200);
  }
}
