import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/operations/ai_responses_service.dart';
import 'package:openhand/features/ai/service/session_io/ai_token_usage_parser.dart';
import 'package:openhand/features/home/model/cache_hit_ratio.dart';

void main() {
  group('Responses-first OpenAI-compatible routing', () {
    test(
      'prefers Responses for plain text without duplicating final output',
      () async {
        final client = MockClient((request) async {
          expect(request.url.path, '/v1/responses');
          return _responsesStreamResponse(<Map<String, Object?>>[
            <String, Object?>{
              'type': 'response.output_text.delta',
              'delta': 'Hello',
            },
            <String, Object?>{
              'type': 'response.completed',
              'response': <String, Object?>{
                'status': 'completed',
                'output_text': 'Hello',
                'output': <Object?>[
                  <String, Object?>{
                    'type': 'message',
                    'content': <Object?>[
                      <String, Object?>{'type': 'output_text', 'text': 'Hello'},
                    ],
                  },
                ],
              },
            },
          ]);
        });
        final service = AiChatService(client: client);
        addTearDown(service.dispose);

        final response = await service.sendMessageStream(
          model: _model(),
          messages: const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.user, content: 'hi'),
          ],
        );
        await response.events.drain<void>();

        expect((await response.result).reply, 'Hello');
      },
    );

    test(
      'maps multimodal turns and tool exchanges to Responses input',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'openhand_responses_test_',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final image = File('${tempDir.path}/pixel.png');
        await image.writeAsBytes(const <int>[1, 2, 3, 4]);
        final service = AiResponsesService(
          client: MockClient((_) async => http.Response('{}', 200)),
        );
        addTearDown(service.dispose);

        final request = await service.buildChatRequest(
          model: _model(
            operationExtras: const <String, Object?>{
              'responses': <String, Object?>{
                'body': <String, Object?>{'gateway_hint': 'stable'},
              },
            },
          ),
          messages: <AiChatTurn>[
            const AiChatTurn(role: AiChatRole.system, content: 'Be concise.'),
            AiChatTurn(
              role: AiChatRole.user,
              content: 'Inspect this image.',
              parts: <AiChatContentPart>[
                AiChatContentPart.imageFile(
                  filePath: image.path,
                  mimeType: 'image/png',
                ),
              ],
            ),
            const AiChatTurn(
              role: AiChatRole.assistant,
              content: '',
              toolCalls: <AiToolCall>[
                AiToolCall(
                  id: 'call_1',
                  name: 'inspect_image',
                  arguments: '{"detail":"high"}',
                ),
              ],
            ),
            const AiChatTurn(
              role: AiChatRole.tool,
              content: '{"objects":2}',
              toolCallId: 'call_1',
            ),
          ],
          tools: const <AiToolDefinition>[
            AiToolDefinition(
              name: 'inspect_image',
              description: 'Inspect an image.',
              parameters: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{},
              },
            ),
          ],
          stream: true,
        );

        final input = request.body['input']! as List;
        final userMessage = input[1] as Map<String, Object?>;
        final userContent = userMessage['content']! as List;
        expect(userContent.first, <String, Object?>{
          'type': 'input_text',
          'text': 'Inspect this image.',
        });
        expect(
          (userContent.last as Map<String, Object?>)['image_url'],
          startsWith('data:image/png;base64,'),
        );
        expect(input[2], <String, Object?>{
          'type': 'function_call',
          'call_id': 'call_1',
          'name': 'inspect_image',
          'arguments': '{"detail":"high"}',
        });
        expect(input[3], <String, Object?>{
          'type': 'function_call_output',
          'call_id': 'call_1',
          'output': '{"objects":2}',
        });
        final tools = request.body['tools']! as List;
        expect(tools.single, <String, Object?>{
          'type': 'function',
          'name': 'inspect_image',
          'description': 'Inspect an image.',
          'parameters': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
          },
        });
        expect(request.body['tool_choice'], 'auto');
        expect(request.body['messages'], isNull);
        expect(request.body['gateway_hint'], 'stable');
        expect(request.body.keys.last, 'input');
      },
    );

    test('streams Responses tool calls and cache-aware usage', () async {
      late Map<String, Object?> requestBody;
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/responses');
        requestBody = jsonDecode(request.body) as Map<String, Object?>;
        return _responsesStreamResponse(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'response.output_item.added',
            'output_index': 0,
            'item': <String, Object?>{
              'type': 'function_call',
              'id': 'fc_1',
              'call_id': 'call_1',
              'name': 'get_weather',
              'arguments': '',
            },
          },
          <String, Object?>{
            'type': 'response.function_call_arguments.delta',
            'output_index': 0,
            'item_id': 'fc_1',
            'delta': '{"city":"北',
          },
          <String, Object?>{
            'type': 'response.function_call_arguments.delta',
            'output_index': 0,
            'item_id': 'fc_1',
            'delta': '京"}',
          },
          <String, Object?>{
            'type': 'response.completed',
            'response': <String, Object?>{
              'status': 'completed',
              'output': <Object?>[
                <String, Object?>{
                  'type': 'function_call',
                  'id': 'fc_1',
                  'call_id': 'call_1',
                  'name': 'get_weather',
                  'arguments': '{"city":"北京"}',
                },
              ],
              'usage': <String, Object?>{
                'input_tokens': 120,
                'output_tokens': 12,
                'total_tokens': 132,
                'input_tokens_details': <String, Object?>{'cached_tokens': 80},
                'output_tokens_details': <String, Object?>{
                  'reasoning_tokens': 4,
                },
              },
            },
          },
        ]);
      });
      final service = AiChatService(client: client);
      addTearDown(service.dispose);

      final response = await service.sendMessageStream(
        model: _model(),
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: '北京天气？'),
        ],
        tools: const <AiToolDefinition>[
          AiToolDefinition(
            name: 'get_weather',
            description: 'Get weather.',
            parameters: <String, Object?>{'type': 'object'},
          ),
        ],
        timeout: const Duration(seconds: 5),
        streamIdleTimeout: const Duration(seconds: 5),
      );
      final eventsFuture = response.events.toList();
      final result = await response.result;
      final events = await eventsFuture;

      expect(requestBody['tools'], isNotNull);
      expect(result.finishReason, 'tool_calls');
      expect(result.toolCalls.single.id, 'call_1');
      expect(result.toolCalls.single.name, 'get_weather');
      expect(result.toolCalls.single.arguments, '{"city":"北京"}');
      expect(result.usage?.promptTokens, 120);
      expect(result.usage?.completionTokens, 12);
      expect(result.usage?.cacheReadTokens, 80);
      expect(result.usage?.reasoningTokens, 4);
      expect(
        events.where(
          (event) => event.type == AiChatStreamEventType.toolCallDelta,
        ),
        isNotEmpty,
      );
    });

    test(
      'falls back once and remembers a missing Responses endpoint',
      () async {
        final paths = <String>[];
        final client = MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/responses')) {
            return http.Response(
              '{"error":{"message":"route not found"}}',
              404,
            );
          }
          return _chatStreamResponse('fallback');
        });
        final service = AiChatService(client: client);
        addTearDown(service.dispose);

        final first = await service.sendMessageStream(
          model: _model(),
          messages: const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.user, content: 'first'),
          ],
        );
        await first.events.drain<void>();
        final firstResult = await first.result;
        final second = await service.sendMessageStream(
          model: _model(),
          messages: const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.user, content: 'second'),
          ],
        );
        await second.events.drain<void>();
        final secondResult = await second.result;

        expect(paths, <String>[
          '/v1/responses',
          '/v1/chat/completions',
          '/v1/chat/completions',
        ]);
        expect(firstResult.reply, 'fallback');
        expect(
          firstResult.requestFallbacks,
          contains(aiChatRequestFallbackResponsesUnsupported),
        );
        expect(secondResult.reply, 'fallback');
      },
    );

    test(
      'does not hide authentication failures behind Chat fallback',
      () async {
        final paths = <String>[];
        final client = MockClient((request) async {
          paths.add(request.url.path);
          return http.Response('{"error":{"message":"invalid API key"}}', 401);
        });
        final service = AiChatService(client: client);
        addTearDown(service.dispose);

        await expectLater(
          service.sendMessageStream(
            model: _model(),
            messages: const <AiChatTurn>[
              AiChatTurn(role: AiChatRole.user, content: 'ping'),
            ],
          ),
          throwsA(isA<AiChatException>()),
        );
        expect(paths, <String>['/v1/responses']);
      },
    );

    test('honors an explicit Responses disabled capability', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return _chatStreamResponse('chat');
      });
      final service = AiChatService(client: client);
      addTearDown(service.dispose);

      final response = await service.sendMessageStream(
        model: _model(responsesStatus: 'disabled'),
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'ping'),
        ],
      );
      await response.events.drain<void>();
      expect((await response.result).reply, 'chat');
      expect(paths, <String>['/v1/chat/completions']);
    });

    test('materializes Responses image output as thread markdown', () async {
      final pngBase64 = base64Encode(const <int>[137, 80, 78, 71]);
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/responses');
        final requestBody = jsonDecode(request.body) as Map<String, Object?>;
        final requestTools = requestBody['tools']! as List;
        expect(
          requestTools.where(
            (tool) => tool is Map && tool['type'] == 'image_generation',
          ),
          hasLength(1),
        );
        expect(requestBody['tool_choice'], <String, Object?>{
          'type': 'image_generation',
        });
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'status': 'completed',
              'output': <Object?>[
                <String, Object?>{
                  'type': 'message',
                  'content': <Object?>[
                    <String, Object?>{'type': 'output_text', 'text': '完成'},
                  ],
                },
                <String, Object?>{
                  'type': 'image_generation_call',
                  'result': pngBase64,
                },
              ],
              'usage': <String, Object?>{
                'input_tokens': 10,
                'output_tokens': 4,
              },
            }),
          ),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final service = AiChatService(client: client);
      addTearDown(service.dispose);

      final result = await service.sendMessage(
        model: _model(),
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: '生成图片'),
        ],
        creationRequest: const AiCreationRequest(mode: AiCreationMode.image),
      );

      expect(result.reply, startsWith('完成'));
      final match = RegExp(r'!\[[^\]]+\]\(([^)]+)\)').firstMatch(result.reply);
      expect(match, isNotNull);
      final outputFile = File(match!.group(1)!);
      expect(await outputFile.exists(), isTrue);
      addTearDown(() async {
        if (await outputFile.exists()) await outputFile.delete();
      });
    });

    test(
      'falls back from Responses image tool to the dedicated image API',
      () async {
        final paths = <String>[];
        final pngBase64 = base64Encode(const <int>[137, 80, 78, 71]);
        final client = MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/responses')) {
            expect(
              (jsonDecode(request.body) as Map<String, Object?>)['stream'],
              isNull,
            );
            return http.Response(
              '{"error":{"message":"route not found"}}',
              404,
            );
          }
          expect(request.url.path, '/v1/images/generations');
          return http.Response(
            jsonEncode(<String, Object?>{
              'data': <Object?>[
                <String, Object?>{'b64_json': pngBase64},
              ],
            }),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        });
        final service = AiChatService(client: client);
        addTearDown(service.dispose);

        final response = await service.sendMessageStream(
          model: _model(),
          messages: const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.user, content: '生成一张图片'),
          ],
          creationRequest: const AiCreationRequest(mode: AiCreationMode.image),
        );
        await response.events.drain<void>();
        final result = await response.result;

        expect(paths, <String>['/v1/responses', '/v1/images/generations']);
        expect(
          result.requestFallbacks,
          contains(aiChatRequestFallbackResponsesUnsupported),
        );
        final match = RegExp(
          r'!\[[^\]]+\]\(([^)]+)\)',
        ).firstMatch(result.reply);
        expect(match, isNotNull);
        final outputFile = File(match!.group(1)!);
        addTearDown(() async {
          if (await outputFile.exists()) await outputFile.delete();
        });
      },
    );

    test(
      'keeps image-tool incompatibility isolated from plain text routing',
      () async {
        final requests = <({String path, Map<String, Object?> body})>[];
        final pngBase64 = base64Encode(const <int>[137, 80, 78, 71]);
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          requests.add((path: request.url.path, body: body));
          if (request.url.path.endsWith('/responses')) {
            final tools = body['tools'];
            final requestsImage =
                tools is List &&
                tools.any(
                  (tool) => tool is Map && tool['type'] == 'image_generation',
                );
            if (requestsImage) {
              return http.Response(
                '{"error":{"message":"unsupported image_generation tool"}}',
                400,
              );
            }
            return _responsesStreamResponse(<Map<String, Object?>>[
              <String, Object?>{
                'type': 'response.output_text.delta',
                'delta': 'text-via-responses',
              },
            ]);
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'data': <Object?>[
                <String, Object?>{'b64_json': pngBase64},
              ],
            }),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        });
        final service = AiChatService(client: client);
        addTearDown(service.dispose);

        final imageResponse = await service.sendMessageStream(
          model: _model(),
          messages: const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.user, content: '生成图片'),
          ],
          creationRequest: const AiCreationRequest(mode: AiCreationMode.image),
        );
        await imageResponse.events.drain<void>();
        final imageResult = await imageResponse.result;
        final imageMatch = RegExp(
          r'!\[[^\]]+\]\(([^)]+)\)',
        ).firstMatch(imageResult.reply);
        expect(imageMatch, isNotNull);
        final outputFile = File(imageMatch!.group(1)!);
        addTearDown(() async {
          if (await outputFile.exists()) await outputFile.delete();
        });

        final textResponse = await service.sendMessageStream(
          model: _model(),
          messages: const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.user, content: '继续文本对话'),
          ],
        );
        await textResponse.events.drain<void>();
        expect((await textResponse.result).reply, 'text-via-responses');
        expect(requests.map((request) => request.path), <String>[
          '/v1/responses',
          '/v1/images/generations',
          '/v1/responses',
        ]);
      },
    );

    test('does not let one missing model poison the whole endpoint', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/responses')) {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          if (body['model'] == 'model-1') {
            return http.Response(
              '{"error":{"message":"model model-1 not found"}}',
              404,
            );
          }
          return _responsesStreamResponse(<Map<String, Object?>>[
            <String, Object?>{
              'type': 'response.output_text.delta',
              'delta': 'second-model',
            },
          ]);
        }
        return _chatStreamResponse('first-model-fallback');
      });
      final service = AiChatService(client: client);
      addTearDown(service.dispose);

      final first = await service.sendMessageStream(
        model: _model(),
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'first'),
        ],
      );
      await first.events.drain<void>();
      expect((await first.result).reply, 'first-model-fallback');

      final second = await service.sendMessageStream(
        model: _model(modelId: 'model-2'),
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: 'second'),
        ],
      );
      await second.events.drain<void>();
      expect((await second.result).reply, 'second-model');
      expect(paths, <String>[
        '/v1/responses',
        '/v1/chat/completions',
        '/v1/responses',
      ]);
    });

    test(
      'keeps Responses camel-case cache telemetry usable by thread stats',
      () {
        final usage = AiTokenUsageParser.parseOpenAi(<String, Object?>{
          'inputTokens': 200,
          'outputTokens': 20,
          'totalTokens': 220,
          'inputTokensDetails': <String, Object?>{'cachedTokens': 150},
          'outputTokensDetails': <String, Object?>{'reasoningTokens': 8},
        });

        expect(usage?.promptTokens, 200);
        expect(usage?.cacheReadTokens, 150);
        expect(usage?.reasoningTokens, 8);
        expect(
          computeCacheHitRatio(
            promptTokens: usage!.promptTokens!,
            cacheReadTokens: usage.cacheReadTokens!,
            claudeStyle: false,
          ),
          0.75,
        );
      },
    );
  });
}

AiModelConfig _model({
  String modelId = 'model-1',
  String responsesStatus = 'auto',
  Map<String, Object?> operationExtras = const <String, Object?>{},
}) {
  return AiModelConfig(
    id: 'relay',
    baseUrl: 'https://relay.example/v1',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: modelId,
    protocolType: AiProtocolType.openai,
    capabilityOverrides: <AiApiFamily, String>{
      AiApiFamily.responses: responsesStatus,
    },
    operationExtras: operationExtras,
  );
}

http.Response _chatStreamResponse(String text) {
  return http.Response(
    'data: {"choices":[{"delta":{"content":"$text"},"finish_reason":null}]}\n\n'
    'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
    'data: [DONE]\n\n',
    200,
    headers: const <String, String>{'content-type': 'text/event-stream'},
  );
}

http.Response _responsesStreamResponse(List<Map<String, Object?>> events) {
  final body = events.map((event) => 'data: ${jsonEncode(event)}\n\n').join();
  return http.Response.bytes(
    utf8.encode(body),
    200,
    headers: const <String, String>{'content-type': 'text/event-stream'},
  );
}
