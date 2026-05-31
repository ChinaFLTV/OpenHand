import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_operation_routing.dart';
import 'package:openhand/features/ai/model/ai_realtime_config.dart';
import 'package:openhand/features/ai/service/operations/ai_files_service.dart';
import 'package:openhand/features/ai/service/operations/ai_fine_tunes_service.dart';
import 'package:openhand/features/ai/service/operations/ai_realtime_service.dart';
import 'package:openhand/features/ai/service/operations/ai_responses_service.dart';
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

AiModelConfig _config() {
  return const AiModelConfig(
    id: 'provider-1',
    baseUrl: 'https://relay.example.com/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'sk-test',
    modelId: 'gpt-4.1-mini',
    protocolType: AiProtocolType.openai,
  );
}

void main() {
  test('responses service parses output text and reasoning', () async {
    final service = AiResponsesService(
      transport: AiTransportClient(
        client: _FakeHttpClient((request) async {
          return _jsonResponse(200, <String, Object?>{
            'output': <Object?>[
              <String, Object?>{
                'content': <Object?>[
                  <String, Object?>{'type': 'output_text', 'text': 'hello'},
                  <String, Object?>{'type': 'reasoning', 'text': 'think'},
                ],
              },
            ],
            'usage': <String, Object?>{
              'prompt_tokens': 10,
              'completion_tokens': 5,
              'total_tokens': 15,
            },
          });
        }),
      ),
    );

    final result = await service.createResponse(model: _config(), input: 'hi');

    expect(result.text, 'hello');
    expect(result.reasoning, 'think');
    expect(result.usage?.totalTokens, 15);
  });

  test('realtime service describes session using routed model and transport', () {
    final service = AiRealtimeService();
    final descriptor = service.describeSession(
      _config().copyWith(
        realtime: const AiRealtimeConfig(transport: 'websocket'),
        operationRouting: const AiOperationRouting(realtimeModelId: 'gpt-realtime'),
      ),
    );

    expect(descriptor.url, 'https://relay.example.com/v1/realtime');
    expect(descriptor.transport, 'websocket');
    expect(descriptor.modelId, 'gpt-realtime');
  });

  test('files service lists files from /v1/files', () async {
    final service = AiFilesService(
      transport: AiTransportClient(
        client: _FakeHttpClient((request) async {
          return _jsonResponse(200, <String, Object?>{
            'data': <Object?>[
              <String, Object?>{'id': 'file_1'},
            ],
          });
        }),
      ),
    );

    final items = await service.listFiles(model: _config());

    expect(items.single.id, 'file_1');
  });

  test('fine tunes service lists jobs from /v1/fine-tunes', () async {
    final service = AiFineTunesService(
      transport: AiTransportClient(
        client: _FakeHttpClient((request) async {
          return _jsonResponse(200, <String, Object?>{
            'data': <Object?>[
              <String, Object?>{'id': 'ft_1'},
            ],
          });
        }),
      ),
    );

    final items = await service.listJobs(model: _config());

    expect(items.single.id, 'ft_1');
  });
}
