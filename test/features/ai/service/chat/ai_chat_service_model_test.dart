import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/model_registry/ai_model_scanner.dart';
import 'package:openhand/features/ai/service/usage/ai_usage_tracker.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testDirectory;
  late DatabaseService database;

  setUpAll(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'openhand-model-test-',
    );
    database = await DatabaseService.initialize(
      databasePath: p.join(testDirectory.path, 'openhand.db'),
      useNoIsolateFactory: true,
    );
  });

  tearDownAll(() async {
    await AiUsageTracker.instance.flush();
    await database.close();
    await testDirectory.delete(recursive: true);
  });

  const responsesSuccessBody = <String, Object?>{
    'status': 'completed',
    'output_text': 'OK',
  };
  const chatSuccessBody = <String, Object?>{
    'choices': <Object?>[
      <String, Object?>{
        'message': <String, Object?>{'role': 'assistant', 'content': 'OK'},
        'finish_reason': 'stop',
      },
    ],
  };

  http.Response jsonResponse(Object body, int statusCode) {
    return http.Response(
      jsonEncode(body),
      statusCode,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }

  AiModelConfig model({String responsesStatus = 'auto'}) {
    return AiModelConfig(
      id: 'provider-1',
      name: '测试提供商',
      baseUrl: 'https://example.com/v1',
      authScheme: AiAuthScheme.bearer,
      token: 'secret',
      modelId: 'test-model',
      protocolType: AiProtocolType.openai,
      capabilityOverrides: <AiApiFamily, String>{
        AiApiFamily.responses: responsesStatus,
      },
    );
  }

  ({AiChatService service, AiModelScanner scanner}) serviceFor(
    MockClient client,
  ) {
    final scanner = AiModelScanner(httpClient: client);
    return (
      service: AiChatService(client: client, modelScanner: scanner),
      scanner: scanner,
    );
  }

  test('模型测试在 Responses 成功后直接返回并标记该接口', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return jsonResponse(responsesSuccessBody, 200);
    });
    final runtime = serviceFor(client);
    addTearDown(() {
      runtime.service.dispose();
      runtime.scanner.dispose();
      client.close();
    });

    final result = await runtime.service.testModel(model());

    expect(result.reply, 'OK');
    expect(result.chatApiFamily, AiApiFamily.responses);
    expect(paths, <String>['/v1/responses']);
  });

  test('模型测试在 Responses 翻译失败后继续测试 Chat Completions', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/responses')) {
        return jsonResponse(<String, Object?>{
          'message': 'input 翻译后为空（没有可用内容）。',
          'type': 'invalid_request_error',
          'code': 'responses_translation_error',
        }, 400);
      }
      return jsonResponse(chatSuccessBody, 200);
    });
    final runtime = serviceFor(client);
    addTearDown(() {
      runtime.service.dispose();
      runtime.scanner.dispose();
      client.close();
    });

    final result = await runtime.service.testModel(model());

    expect(result.reply, 'OK');
    expect(result.chatApiFamily, AiApiFamily.chatCompletions);
    expect(paths, <String>['/v1/responses', '/v1/chat/completions']);
  });

  test('普通会话把 Responses 翻译错误识别为兼容性失败并自动回退', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/responses')) {
        return jsonResponse(<String, Object?>{
          'message': 'input 翻译后为空（没有可用内容）。',
          'type': 'invalid_request_error',
          'code': 'responses_translation_error',
        }, 400);
      }
      return jsonResponse(chatSuccessBody, 200);
    });
    final runtime = serviceFor(client);
    addTearDown(() {
      runtime.service.dispose();
      runtime.scanner.dispose();
      client.close();
    });

    final result = await runtime.service.sendMessage(
      model: model(),
      messages: const <AiChatTurn>[
        AiChatTurn(role: AiChatRole.user, content: '你好'),
      ],
    );

    expect(result.reply, 'OK');
    expect(
      result.requestFallbacks,
      contains(aiChatRequestFallbackResponsesUnsupported),
    );
    expect(paths, <String>['/v1/responses', '/v1/chat/completions']);
  });

  test('持久化为 Chat Completions 后普通会话不再请求 Responses', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return jsonResponse(chatSuccessBody, 200);
    });
    final runtime = serviceFor(client);
    addTearDown(() {
      runtime.service.dispose();
      runtime.scanner.dispose();
      client.close();
    });
    final restoredModel = AiModelConfig.fromJson(
      model(responsesStatus: 'disabled').toJson(),
    );

    final result = await runtime.service.sendMessage(
      model: restoredModel,
      messages: const <AiChatTurn>[
        AiChatTurn(role: AiChatRole.user, content: '你好'),
      ],
    );

    expect(result.reply, 'OK');
    expect(paths, <String>['/v1/chat/completions']);
  });

  test('设置控制器只更新最新配置的已验证聊天接口并持久化', () async {
    final controller = await SettingsController.create();
    addTearDown(controller.dispose);
    expect(await controller.saveAiModel(model()), isTrue);

    expect(
      await controller.updateAiModelVerifiedChatApiFamily(
        'provider-1',
        AiApiFamily.chatCompletions,
      ),
      isTrue,
    );
    expect(
      controller.aiModels.single.capabilityStatusFor(AiApiFamily.responses),
      'disabled',
    );

    final restoredController = await SettingsController.create();
    addTearDown(restoredController.dispose);
    expect(
      restoredController.aiModels.single.capabilityStatusFor(
        AiApiFamily.responses,
      ),
      'disabled',
    );
  });

  test('两个聊天接口都失败时错误详情同时保留两边原因', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/responses')) {
        return jsonResponse(<String, Object?>{'error': 'Responses 不可用'}, 500);
      }
      if (request.url.path.endsWith('/chat/completions')) {
        return jsonResponse(<String, Object?>{
          'error': 'Chat Completions 不可用',
        }, 503);
      }
      return jsonResponse(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{'id': 'test-model'},
        ],
      }, 200);
    });
    final runtime = serviceFor(client);
    addTearDown(() {
      runtime.service.dispose();
      runtime.scanner.dispose();
      client.close();
    });

    await expectLater(
      runtime.service.testModel(model()),
      throwsA(
        isA<AiChatException>()
            .having((error) => error.message, '错误详情', contains('Responses 不可用'))
            .having(
              (error) => error.message,
              '错误详情',
              contains('Chat Completions 不可用'),
            ),
      ),
    );
  });
}
