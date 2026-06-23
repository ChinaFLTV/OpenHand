import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

void main() {
  group('StepFun protocol coverage', () {
    test('parses OpenAI-compatible tool calls', () {
      final adapter = AiProtocolRegistry.adapterFor(AiProtocolType.stepfun);
      final calls = adapter.parseToolCalls(
        jsonEncode(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'tool_calls': <Object?>[
                  <String, Object?>{
                    'id': 'call_1',
                    'type': 'function',
                    'function': <String, Object?>{
                      'name': 'lookup_weather',
                      'arguments': <String, Object?>{'city': '上海'},
                    },
                  },
                ],
              },
            },
          ],
        }),
      );

      expect(calls, hasLength(1));
      expect(calls.single.id, 'call_1');
      expect(calls.single.name, 'lookup_weather');
      expect(jsonDecode(calls.single.arguments), <String, Object?>{
        'city': '上海',
      });
    });

    test('recognises Step 3.7 Flash as a multimodal model', () {
      final profile = AiModelCatalog.lookup(
        'step-3.7-flash',
        AiProtocolType.stepfun,
      );

      expect(profile, isNotNull);
      expect(profile!.supportsAttachments, isTrue);
      expect(profile.supportedModalities, contains(AiModelModality.image));
      expect(profile.supportedModalities, contains(AiModelModality.video));
    });

    test(
      'uses StepFun default voice for stepaudio TTS in OpenAI mode',
      () async {
        final client = _RecordingClient(
          http.Response.bytes(
            Uint8List.fromList(<int>[0x49, 0x44, 0x33, 0x04]),
            200,
            headers: const <String, String>{'content-type': 'audio/mpeg'},
          ),
        );
        final service = AiImageGenerationService(client: client);
        final model = _modelConfig(
          protocolType: AiProtocolType.openai,
          modelId: 'gpt-4o',
          operationRouting: const AiOperationRouting(
            speechModelId: 'stepaudio-2.5-tts',
          ),
        );

        await service.generateAudio(
          model: model,
          prompt: '智能阶跃，十倍每一个人的可能',
          options: const AiCreationOptions(
            outputFormat: 'aac',
            sampleRate: 44100,
            bitrate: 128000,
            pitch: 2,
          ),
        );

        final body =
            jsonDecode(client.lastRequest!.body) as Map<String, Object?>;
        expect(
          client.lastRequest!.url.toString(),
          endsWith('/v1/audio/speech'),
        );
        expect(body['model'], 'stepaudio-2.5-tts');
        expect(body['voice'], 'cixingnansheng');
        expect(body['response_format'], 'mp3');
        expect(body.containsKey('sample_rate'), isFalse);
        expect(body.containsKey('bitrate'), isFalse);
        expect(body.containsKey('pitch'), isFalse);
      },
    );

    test(
      'normalizes legacy alloy voice in direct StepFun speech calls',
      () async {
        final client = _RecordingClient(
          http.Response.bytes(
            Uint8List.fromList(<int>[0x49, 0x44, 0x33, 0x04]),
            200,
            headers: const <String, String>{'content-type': 'audio/mpeg'},
          ),
        );
        final service = AiAudioIoService(
          transport: AiTransportClient(client: client),
        );
        final model = _modelConfig(
          protocolType: AiProtocolType.stepfun,
          modelId: 'stepaudio-2.5-tts',
          operationRouting: const AiOperationRouting(defaultVoice: 'alloy'),
        );

        await service.createSpeech(
          model: model,
          input: '智能阶跃，十倍每一个人的可能',
          responseFormat: 'aac',
          speed: '3.0',
        );

        final body =
            jsonDecode(client.lastRequest!.body) as Map<String, Object?>;
        expect(body['voice'], 'cixingnansheng');
        expect(body['response_format'], 'mp3');
        expect(body['speed'], 2.0);
      },
    );
  });
}

AiModelConfig _modelConfig({
  required AiProtocolType protocolType,
  required String modelId,
  AiOperationRouting operationRouting = const AiOperationRouting(),
}) {
  return AiModelConfig(
    id: 'stepfun-test',
    baseUrl: 'https://api.stepfun.com/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'token',
    modelId: modelId,
    protocolType: protocolType,
    operationRouting: operationRouting,
  );
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.response);

  final http.Response response;
  http.Request? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      lastRequest = request;
    }
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[response.bodyBytes]),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
