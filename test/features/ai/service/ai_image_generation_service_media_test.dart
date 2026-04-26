import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/ai_image_generation_service.dart';

void main() {
  group('AiImageGenerationService media generation', () {
    const qwenVideoModel = AiModelConfig(
      id: 'qwen-video',
      baseUrl: 'https://dashscope.invalid/compatible-mode/v1/chat/completions',
      authScheme: AiAuthScheme.bearer,
      token: 'mock-token',
      modelId: 'wan2.2-t2v-plus',
      protocolType: AiProtocolType.qwen,
    );

    const openAiAudioModel = AiModelConfig(
      id: 'openai-audio',
      baseUrl: 'https://api.openai.invalid/v1/responses',
      authScheme: AiAuthScheme.bearer,
      token: 'mock-token',
      modelId: 'gpt-4o-mini-tts',
      protocolType: AiProtocolType.openai,
    );

    test('keeps dedicated video/audio support limited to capable protocols', () {
      for (final protocol in const <AiProtocolType>[
        AiProtocolType.openai,
        AiProtocolType.qwen,
        AiProtocolType.glm,
        AiProtocolType.seed,
        AiProtocolType.minimax,
      ]) {
        expect(
          AiImageGenerationService.supportsVideoGeneration(protocol),
          isTrue,
          reason:
              '${protocol.storageValue} should use media generation endpoints',
        );
      }
      for (final protocol in const <AiProtocolType>[
        AiProtocolType.openai,
        AiProtocolType.qwen,
        AiProtocolType.glm,
        AiProtocolType.seed,
        AiProtocolType.stepfun,
        AiProtocolType.minimax,
        AiProtocolType.hunyuan,
      ]) {
        expect(
          AiImageGenerationService.supportsAudioGeneration(protocol),
          isTrue,
          reason:
              '${protocol.storageValue} should use audio generation endpoints',
        );
      }

      for (final protocol in const <AiProtocolType>[
        AiProtocolType.claude,
        AiProtocolType.gemini,
        AiProtocolType.deepseek,
        AiProtocolType.kimi,
        AiProtocolType.grok,
        AiProtocolType.longcat,
        AiProtocolType.joycode,
        AiProtocolType.meta,
        AiProtocolType.mimo,
        AiProtocolType.ollama,
        AiProtocolType.vllm,
        AiProtocolType.sglang,
        // Wenxin/StepFun lack OpenAI-compatible video endpoints; ensure they
        // are not silently routed to `/v1/videos/generations`.
        AiProtocolType.stepfun,
        AiProtocolType.wenxin,
        // Hunyuan video uses TC3-HMAC signed RPC, not OpenAI-compat.
        AiProtocolType.hunyuan,
      ]) {
        expect(
          AiImageGenerationService.supportsVideoGeneration(protocol),
          isFalse,
          reason:
              '${protocol.storageValue} should not be diverted to video endpoints',
        );
      }
      for (final protocol in const <AiProtocolType>[
        AiProtocolType.claude,
        AiProtocolType.gemini,
        AiProtocolType.deepseek,
        AiProtocolType.kimi,
        AiProtocolType.grok,
        AiProtocolType.longcat,
        AiProtocolType.joycode,
        AiProtocolType.meta,
        AiProtocolType.mimo,
        AiProtocolType.ollama,
        AiProtocolType.vllm,
        AiProtocolType.sglang,
        AiProtocolType.wenxin,
      ]) {
        expect(
          AiImageGenerationService.supportsAudioGeneration(protocol),
          isFalse,
          reason:
              '${protocol.storageValue} should not be diverted to audio endpoints',
        );
      }
    });

    test(
      'uses model profiles and catalog entries before protocol fallback',
      () {
        const qwenOmniChat = AiModelConfig(
          id: 'qwen-omni',
          baseUrl: 'https://dashscope.invalid/compatible-mode/v1',
          authScheme: AiAuthScheme.bearer,
          token: 'mock-token',
          modelId: 'qwen3-omni-flash',
          protocolType: AiProtocolType.qwen,
        );
        const customVideoModel = AiModelConfig(
          id: 'custom-qwen-video',
          baseUrl: 'https://dashscope.invalid/compatible-mode/v1',
          authScheme: AiAuthScheme.bearer,
          token: 'mock-token',
          modelId: 'custom-video-generator',
          protocolType: AiProtocolType.qwen,
        );
        const userProfiledAudioModel = AiModelConfig(
          id: 'profiled-audio',
          baseUrl: 'https://mock.invalid/v1',
          authScheme: AiAuthScheme.bearer,
          token: 'mock-token',
          modelId: 'internal-audio-model',
          protocolType: AiProtocolType.minimax,
          modelProfiles: <String, AiModelProfile>{
            'internal-audio-model': AiModelProfile(
              capabilities: <AiModelCapability>{
                AiModelCapability.audioGeneration,
              },
            ),
          },
        );

        expect(
          AiImageGenerationService.supportsVideoGenerationForModel(
            qwenVideoModel,
          ),
          isTrue,
        );
        expect(
          AiImageGenerationService.supportsVideoGenerationForModel(
            qwenOmniChat,
          ),
          isFalse,
          reason: 'known Qwen Omni chat models should stay on chat endpoints',
        );
        expect(
          AiImageGenerationService.supportsVideoGenerationForModel(
            customVideoModel,
          ),
          isTrue,
          reason: 'unknown compatible models can still be manually configured',
        );
        expect(
          AiImageGenerationService.supportsVideoGenerationForModel(
            userProfiledAudioModel,
          ),
          isFalse,
        );
        expect(
          AiImageGenerationService.supportsAudioGenerationForModel(
            userProfiledAudioModel,
          ),
          isTrue,
        );
      },
    );

    test('routes Qwen video creation through DashScope-shaped body', () async {
      late Uri requestUrl;
      late Map<String, Object?> requestBody;
      late Map<String, String> requestHeaders;
      final service = AiImageGenerationService(
        client: MockClient((request) async {
          requestUrl = request.url;
          requestBody = jsonDecode(request.body) as Map<String, Object?>;
          requestHeaders = request.headers;
          expect(request.headers['authorization'], 'Bearer mock-token');
          expect(request.headers['accept'], contains('video/*'));
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'url': 'https://cdn.example.invalid/generated/clip.mp4',
                  'revised_prompt': 'city sunrise clip',
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final result = await service.generateVideo(
        model: qwenVideoModel,
        prompt: ' city sunrise ',
        options: const AiCreationOptions(
          aspectRatio: '16:9',
          durationSeconds: 6,
          count: 2,
          quality: 'hd',
        ),
      );

      expect(
        requestUrl.toString(),
        'https://dashscope.invalid/compatible-mode/v1/videos/generations',
      );
      expect(requestBody['model'], 'wan2.2-t2v-plus');
      // DashScope native shape: prompt is nested under `input`.
      expect(requestBody['input'], <String, Object?>{'prompt': 'city sunrise'});
      final parameters = requestBody['parameters'] as Map<String, Object?>;
      expect(parameters['size'], '1280x720');
      expect(parameters['duration'], 6);
      // Async header is required for DashScope to queue the job.
      expect(requestHeaders['x-dashscope-async'], 'enable');
      // No legacy OpenAI fields leak into the DashScope body.
      expect(requestBody.containsKey('n'), isFalse);
      expect(requestBody.containsKey('response_format'), isFalse);
      expect(result.markdown, contains('[city sunrise clip]'));
      expect(result.markdown, contains('clip.mp4'));
    });

    test('routes OpenAI Sora video to /v1/videos with seconds+size', () async {
      late Uri requestUrl;
      late Map<String, Object?> requestBody;
      final service = AiImageGenerationService(
        client: MockClient((request) async {
          requestUrl = request.url;
          requestBody = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'data': [
                {'url': 'https://cdn.example.invalid/sora/out.mp4'},
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      const soraModel = AiModelConfig(
        id: 'openai-sora',
        baseUrl: 'https://api.openai.invalid/v1/chat/completions',
        authScheme: AiAuthScheme.bearer,
        token: 'mock-token',
        modelId: 'sora-2',
        protocolType: AiProtocolType.openai,
        modelProfiles: <String, AiModelProfile>{
          'sora-2': AiModelProfile(
            capabilities: <AiModelCapability>{
              AiModelCapability.videoGeneration,
            },
          ),
        },
      );

      await service.generateVideo(
        model: soraModel,
        prompt: 'a robot dancing',
        options: const AiCreationOptions(
          aspectRatio: '9:16',
          durationSeconds: 8,
        ),
      );

      expect(requestUrl.toString(), 'https://api.openai.invalid/v1/videos');
      expect(requestBody, <String, Object?>{
        'model': 'sora-2',
        'prompt': 'a robot dancing',
        'size': '720x1280',
        'seconds': 8,
      });
    });

    test('routes MiniMax video to /v1/video_generation flat body', () async {
      late Uri requestUrl;
      late Map<String, Object?> requestBody;
      final service = AiImageGenerationService(
        client: MockClient((request) async {
          requestUrl = request.url;
          requestBody = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'data': [
                {'url': 'https://cdn.example.invalid/mm/out.mp4'},
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      const miniMaxModel = AiModelConfig(
        id: 'minimax-video',
        baseUrl: 'https://api.minimax.invalid/v1/chat/completions',
        authScheme: AiAuthScheme.bearer,
        token: 'mock-token',
        modelId: 'video-01',
        protocolType: AiProtocolType.minimax,
        modelProfiles: <String, AiModelProfile>{
          'video-01': AiModelProfile(
            capabilities: <AiModelCapability>{
              AiModelCapability.videoGeneration,
            },
          ),
        },
      );

      await service.generateVideo(
        model: miniMaxModel,
        prompt: 'sunset over the sea',
      );

      expect(
        requestUrl.toString(),
        'https://api.minimax.invalid/v1/video_generation',
      );
      expect(requestBody, <String, Object?>{
        'model': 'video-01',
        'prompt': 'sunset over the sea',
        'prompt_optimizer': true,
      });
    });

    test('polls relative video task URLs with provider auth headers', () async {
      final requestedUrls = <String>[];
      final service = AiImageGenerationService(
        client: MockClient((request) async {
          requestedUrls.add(request.url.toString());
          expect(request.headers['authorization'], 'Bearer mock-token');
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'id': 'task-123',
                'status': 'queued',
                'status_url': '/compatible-mode/v1/tasks/task-123',
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          expect(request.method, 'GET');
          expect(request.headers['accept'], 'application/json');
          return http.Response(
            jsonEncode({
              'status': 'succeeded',
              'result': {
                'video_url': 'https://cdn.example.invalid/tasks/task-123.mp4',
              },
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final result = await service.generateVideo(
        model: qwenVideoModel,
        prompt: 'task video',
        timeout: const Duration(seconds: 3),
      );

      expect(requestedUrls, <String>[
        'https://dashscope.invalid/compatible-mode/v1/videos/generations',
        'https://dashscope.invalid/compatible-mode/v1/tasks/task-123',
      ]);
      expect(result.markdown, contains('task-123.mp4'));
    });

    test(
      'persists binary audio responses as playable markdown links',
      () async {
        late Uri requestUrl;
        late Map<String, Object?> requestBody;
        final service = AiImageGenerationService(
          client: MockClient((request) async {
            requestUrl = request.url;
            requestBody = jsonDecode(request.body) as Map<String, Object?>;
            expect(request.headers['accept'], contains('audio/*'));
            return http.Response.bytes(
              const <int>[1, 2, 3, 4, 5],
              200,
              headers: const {'content-type': 'audio/mpeg'},
            );
          }),
        );

        final result = await service.generateAudio(
          model: openAiAudioModel,
          prompt: 'narration',
          options: const AiCreationOptions(style: 'verse'),
        );

        expect(
          requestUrl.toString(),
          'https://api.openai.invalid/v1/audio/speech',
        );
        expect(requestBody['model'], 'gpt-4o-mini-tts');
        expect(requestBody['input'], 'narration');
        expect(requestBody['voice'], 'verse');
        expect(result.markdown, contains('narration'));
        expect(result.markdown, contains('.mp3)'));

        final match = RegExp(r'\(([^)]+\.mp3)\)').firstMatch(result.markdown);
        expect(match, isNotNull);
        final file = File(match!.group(1)!);
        expect(file.existsSync(), isTrue);
        addTearDown(() {
          if (file.existsSync()) file.deleteSync();
        });
      },
    );

    test(
      'rejects unsupported video protocols before opening the network',
      () async {
        var calledNetwork = false;
        final service = AiImageGenerationService(
          client: MockClient((request) async {
            calledNetwork = true;
            return http.Response('', 500);
          }),
        );

        await expectLater(
          service.generateVideo(
            model: const AiModelConfig(
              id: 'claude',
              baseUrl: 'https://api.anthropic.invalid/v1/messages',
              authScheme: AiAuthScheme.bearer,
              token: 'mock-token',
              modelId: 'claude-sonnet-4',
              protocolType: AiProtocolType.claude,
            ),
            prompt: 'make a video',
          ),
          throwsA(isA<AiMediaGenerationException>()),
        );
        expect(calledNetwork, isFalse);
      },
    );
  });
}
