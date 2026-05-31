import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/model_registry/ai_model_scanner.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}

class _FakeScanner extends AiModelScanner {
  _FakeScanner(this._result) : super(httpClient: _FakeHttpClient((request) async {
    throw UnimplementedError('scanner HTTP should not be used when scan is overridden');
  }));

  final AiModelScanResult _result;
  AiModelConfig? lastConfig;
  Duration? lastTimeout;

  @override
  Future<AiModelScanResult> scan(
    AiModelConfig config, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    lastConfig = config;
    lastTimeout = timeout;
    return _result;
  }
}

http.StreamedResponse _jsonResponse(int statusCode, Object body) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

AiModelConfig _openAiConfig() {
  return const AiModelConfig(
    id: 'provider-1',
    name: 'Relay',
    baseUrl: 'https://relay.example.com/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'sk-test',
    modelId: 'gpt-4o-mini',
    protocolType: AiProtocolType.openai,
    maxTokens: 2048,
    temperature: 0.9,
  );
}

void main() {
  test('testModel sends a minimal non-stream chat probe without max_tokens or temperature', () async {
    late Map<String, Object?> requestBody;
    late String requestUrl;
    final service = AiChatService(
      client: _FakeHttpClient((request) async {
        requestUrl = request.url.toString();
        requestBody = jsonDecode(await request.finalize().bytesToString())
            as Map<String, Object?>;
        return _jsonResponse(200, <String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{'content': 'OK'},
            },
          ],
        });
      }),
    );

    final reply = await service.testModel(_openAiConfig());

    expect(reply, 'OK');
    expect(requestUrl, 'https://relay.example.com/v1/chat/completions');
    expect(requestBody['model'], 'gpt-4o-mini');
    expect(requestBody.containsKey('max_tokens'), isFalse);
    expect(requestBody.containsKey('temperature'), isFalse);
    expect(requestBody.containsKey('stream'), isFalse);
  });

  test('testModel appends scan-based diagnosis for openai-compatible probe failures', () async {
    final scanner = _FakeScanner(
      const AiModelScanResult(modelIds: <String>['gpt-4o-mini']),
    );
    final service = AiChatService(
      client: _FakeHttpClient((request) async {
        return _jsonResponse(503, <String, Object?>{'error': 'upstream overloaded'});
      }),
      modelScanner: scanner,
    );

    await expectLater(
      service.testModel(_openAiConfig()),
      throwsA(
        isA<AiChatException>()
            .having((e) => e.message, 'message', contains('503'))
            .having((e) => e.message, 'message', contains('请求地址 / URL: https://relay.example.com/v1/chat/completions'))
            .having((e) => e.message, 'message', contains('模型列表接口可达')),
      ),
    );
    expect(scanner.lastConfig, isNotNull);
    expect(scanner.lastTimeout, const Duration(seconds: 12));
  });

  test('testModel recognizes relay-side model availability failures', () async {
    final scanner = _FakeScanner(
      const AiModelScanResult(modelIds: <String>[]),
    );
    final service = AiChatService(
      client: _FakeHttpClient((request) async {
        return _jsonResponse(503, <String, Object?>{
          'error': '分组 default 下模型 gpt-5-nano 无可用渠道（distributor）',
        });
      }),
      modelScanner: scanner,
    );

    await expectLater(
      service.testModel(_openAiConfig().copyWith(modelId: 'gpt-5-nano')),
      throwsA(
        isA<AiChatException>()
            .having((e) => e.message, 'message', contains('模型在当前中转不可用'))
            .having((e) => e.message, 'message', contains('模型分组/渠道可用性问题'))
            .having((e) => e.message, 'message', contains('无可用渠道')),
      ),
    );
  });
}
