import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/media/ai_image_generation_service.dart';

void main() {
  group('音频生成服务', () {
    test('GMI MiniMax Music 使用官方队列接口并解析轮询结果', () async {
      Map<String, Object?>? submittedBody;
      var statusRequestCount = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          expect(
            request.url.toString(),
            'https://console.gmicloud.ai/api/v1/ie/requestqueue/apikey/requests',
          );
          expect(request.headers['authorization'], 'Bearer test-token');
          submittedBody = (jsonDecode(request.body) as Map)
              .cast<String, Object?>();
          return http.Response(
            jsonEncode(<String, Object?>{
              'request_id': 'request-1',
              'model': 'minimax-music-3.0',
              'status': 'success',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.host == 'console.gmicloud.ai') {
          statusRequestCount += 1;
          expect(
            request.url.path,
            '/api/v1/ie/requestqueue/apikey/requests/request-1',
          );
          return http.Response(
            jsonEncode(<String, Object?>{
              'request_id': 'request-1',
              'status': 'success',
              'outcome': <String, Object?>{
                'audio_url': 'https://media.example/generated.wav',
                'medias': <Object?>[
                  <String, Object?>{
                    'url': 'https://media.example/generated.wav',
                    'type': 'audio',
                    'format': 'mp3',
                  },
                ],
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.host == 'media.example') {
          return http.Response.bytes(
            const <int>[0x49, 0x44, 0x33, 0x04, 0x00, 0x00],
            200,
            headers: const <String, String>{'content-type': 'audio/wav'},
          );
        }
        fail('收到未预期的请求：${request.method} ${request.url}');
      });
      final service = AiImageGenerationService(client: client);
      addTearDown(service.dispose);

      final result = await service.generateAudio(
        model: const AiModelConfig(
          id: 'gmi',
          name: 'GMI',
          baseUrl: 'https://api.gmi-serving.com',
          authScheme: AiAuthScheme.bearer,
          token: 'test-token',
          modelId: 'minimax-music-3.0',
          protocolType: AiProtocolType.openai,
        ),
        prompt: '中国古风，悠扬笛声与古筝，宁静舒展',
        options: const AiCreationOptions(
          outputFormat: 'wav',
          sampleRate: 44100,
          bitrate: 256000,
          omitVoice: true,
        ),
        timeout: const Duration(seconds: 10),
      );

      expect(statusRequestCount, 1);
      expect(result.requestUrl, contains('console.gmicloud.ai'));
      expect(result.markdown, contains('.wav'));
      expect(submittedBody?['model'], 'minimax-music-3.0');
      final payload = (submittedBody?['payload'] as Map)
          .cast<String, Object?>();
      expect(payload, <String, Object?>{
        'lyrics': '[Inst]',
        'prompt': '中国古风，悠扬笛声与古筝，宁静舒展',
        'sample_rate': 44100,
        'bitrate': 256000,
        'format': 'wav',
      });
      expect(submittedBody, isNot(contains('voice')));
    });

    test('选择不指定音色后 OpenAI 请求不补默认音色', () async {
      Map<String, Object?>? submittedBody;
      final client = MockClient((request) async {
        submittedBody = (jsonDecode(request.body) as Map)
            .cast<String, Object?>();
        return http.Response.bytes(
          const <int>[0x49, 0x44, 0x33, 0x04, 0x00, 0x00],
          200,
          headers: const <String, String>{'content-type': 'audio/mpeg'},
        );
      });
      final service = AiImageGenerationService(client: client);
      addTearDown(service.dispose);

      await service.generateAudio(
        model: const AiModelConfig(
          id: 'openai',
          baseUrl: 'https://api.example.com',
          authScheme: AiAuthScheme.bearer,
          token: 'test-token',
          modelId: 'tts-1',
          protocolType: AiProtocolType.openai,
        ),
        prompt: '测试文本',
        options: const AiCreationOptions(omitVoice: true),
      );

      expect(submittedBody, isNot(contains('voice')));
      expect(submittedBody?['model'], 'tts-1');
      expect(submittedBody?['input'], '测试文本');
    });

    test('不指定音色状态可持久化', () {
      const options = AiCreationOptions(voice: 'alloy', omitVoice: true);
      final restored = AiCreationOptions.fromMetadata(options.toMetadata());

      expect(options.toMetadata(), isNot(contains('voice')));
      expect(restored.omitVoice, isTrue);
      expect(restored.voice, isNull);
    });
  });

  group('Agnes 视频生成服务', () {
    test('文生视频忽略模型臆造的模式与样式参数', () async {
      Map<String, Object?>? submittedBody;
      final client = MockClient((request) async {
        submittedBody = (jsonDecode(request.body) as Map)
            .cast<String, Object?>();
        return http.Response.bytes(
          const <int>[0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70],
          200,
          headers: const <String, String>{'content-type': 'video/mp4'},
        );
      });
      final service = AiImageGenerationService(client: client);
      addTearDown(service.dispose);

      final result = await service.generateVideo(
        model: _agnesVideoModel,
        prompt: '黑洞漫步的科幻电影视频',
        options: const AiCreationOptions(
          aspectRatio: '16:9',
          durationSeconds: 10,
          quality: 'high',
          style: 'cinematic',
          promptEnhance: true,
          resolution: '1920x1080',
          numFrames: 240,
          mode: 'text',
        ),
      );

      expect(result.requestUrl, 'https://api.example.com/v1/videos');
      expect(submittedBody?['model'], 'agnes-video-v2.0');
      expect(submittedBody?['width'], 1280);
      expect(submittedBody?['height'], 720);
      expect(submittedBody?['num_frames'], 241);
      expect(submittedBody?['frame_rate'], 24);
      expect(submittedBody, isNot(contains('mode')));
      expect(submittedBody, isNot(contains('style')));
      expect(submittedBody, isNot(contains('quality')));
    });

    test('多参考图固定使用关键帧模式', () async {
      Map<String, Object?>? submittedBody;
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_agnes_video_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final firstImage = File('${tempDirectory.path}/first.jpg');
      final lastImage = File('${tempDirectory.path}/last.jpg');
      await firstImage.writeAsBytes(const <int>[0xff, 0xd8, 0xff, 0xd9]);
      await lastImage.writeAsBytes(const <int>[0xff, 0xd8, 0xff, 0xd9]);
      final client = MockClient((request) async {
        submittedBody = (jsonDecode(request.body) as Map)
            .cast<String, Object?>();
        return http.Response.bytes(
          const <int>[0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70],
          200,
          headers: const <String, String>{'content-type': 'video/mp4'},
        );
      });
      final service = AiImageGenerationService(client: client);
      addTearDown(service.dispose);

      await service.generateVideo(
        model: _agnesVideoModel,
        prompt: '在首尾画面间生成平滑运镜',
        options: const AiCreationOptions(style: 'cinematic', mode: 'text'),
        referenceImages: <AiChatContentPart>[
          AiChatContentPart.imageFile(
            filePath: firstImage.path,
            mimeType: 'image/jpeg',
          ),
          AiChatContentPart.imageFile(
            filePath: lastImage.path,
            mimeType: 'image/jpeg',
          ),
        ],
      );

      expect(submittedBody, isNot(contains('mode')));
      final extraBody = (submittedBody?['extra_body'] as Map)
          .cast<String, Object?>();
      expect(extraBody['mode'], 'keyframes');
      expect(extraBody['image'], isA<List<Object?>>());
      expect(extraBody['image'] as List<Object?>, hasLength(2));
    });
  });
}

const _agnesVideoModel = AiModelConfig(
  id: 'agnes',
  baseUrl: 'https://api.example.com',
  authScheme: AiAuthScheme.bearer,
  token: 'test-token',
  modelId: 'agnes-video-v2.0',
  protocolType: AiProtocolType.agnes,
);
