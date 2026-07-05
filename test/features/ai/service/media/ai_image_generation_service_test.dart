import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/media/ai_image_generation_service.dart';

void main() {
  group('AiImageGenerationService video body', () {
    test('keeps explicit video size ahead of ratio-derived fallback', () async {
      final service = _videoServiceExpectingBody((body) {
        expect(body['model'], 'wan-test');
        expect(body['input'], <String, Object?>{'prompt': 'make a clip'});
        final parameters = _parametersFrom(body);
        expect(parameters['size'], '640x480');
      });

      final result = await service.generateVideo(
        model: _qwenVideoModel(),
        prompt: 'make a clip',
        options: const AiCreationOptions(
          size: '640x480',
          aspectRatio: '16:9',
          resolution: '1080p',
        ),
        timeout: const Duration(seconds: 1),
      );

      expect(result.markdown, contains('https://example.com/video.mp4'));
    });

    test('derives video size from aspect ratio and resolution', () async {
      final service = _videoServiceExpectingBody((body) {
        final parameters = _parametersFrom(body);
        expect(parameters['size'], '1920x1080');
      });

      await service.generateVideo(
        model: _qwenVideoModel(),
        prompt: 'make a clip',
        options: const AiCreationOptions(
          aspectRatio: '16:9',
          resolution: '1080p',
        ),
        timeout: const Duration(seconds: 1),
      );
    });
  });
}

AiImageGenerationService _videoServiceExpectingBody(
  void Function(Map<String, Object?> body) inspect,
) {
  final service = AiImageGenerationService(
    client: MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse('https://example.com/v1/videos/generations'),
      );
      expect(request.headers['content-type'], 'application/json');
      inspect(jsonDecode(request.body) as Map<String, Object?>);
      return http.Response(
        jsonEncode(<String, Object?>{
          'output': <String, Object?>{
            'video_url': 'https://example.com/video.mp4',
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }),
  );
  addTearDown(service.dispose);
  return service;
}

Map<String, Object?> _parametersFrom(Map<String, Object?> body) {
  return Map<String, Object?>.from(body['parameters']! as Map);
}

AiModelConfig _qwenVideoModel() {
  return const AiModelConfig(
    id: 'qwen-video-test',
    baseUrl: 'https://example.com',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'wan-test',
    protocolType: AiProtocolType.qwen,
  );
}
