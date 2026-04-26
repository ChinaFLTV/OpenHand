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
        AiProtocolType.minimax,
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
        // Seed/StepFun/Hunyuan TTS use bespoke signed RPCs, not
        // `/v1/audio/speech`. Keep them off the default audio matrix.
        AiProtocolType.seed,
        AiProtocolType.stepfun,
        AiProtocolType.hunyuan,
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

    test(
      'polls GLM CogVideoX async-result endpoint until video URL is ready',
      () async {
        final calls = <String>[];
        var pollCount = 0;
        final service = AiImageGenerationService(
          client: MockClient((request) async {
            calls.add('${request.method} ${request.url}');
            if (request.method == 'POST') {
              return http.Response(
                jsonEncode({
                  'id': 'cogvideo-task-1',
                  'request_id': 'req-1',
                  'task_status': 'PROCESSING',
                }),
                200,
                headers: const {'content-type': 'application/json'},
              );
            }
            pollCount += 1;
            if (pollCount == 1) {
              return http.Response(
                jsonEncode({
                  'id': 'cogvideo-task-1',
                  'task_status': 'PROCESSING',
                }),
                200,
                headers: const {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({
                'id': 'cogvideo-task-1',
                'task_status': 'SUCCESS',
                'video_result': [
                  {
                    'url': 'https://cdn.bigmodel.invalid/cogvideo/out.mp4',
                    'cover_image_url':
                        'https://cdn.bigmodel.invalid/cogvideo/cover.png',
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        );
        const glmVideoModel = AiModelConfig(
          id: 'glm-video',
          baseUrl: 'https://open.bigmodel.invalid/api/paas/v4/chat/completions',
          authScheme: AiAuthScheme.bearer,
          token: 'mock-token',
          modelId: 'cogvideox-2',
          protocolType: AiProtocolType.glm,
          modelProfiles: <String, AiModelProfile>{
            'cogvideox-2': AiModelProfile(
              capabilities: <AiModelCapability>{
                AiModelCapability.videoGeneration,
              },
            ),
          },
        );

        final result = await service.generateVideo(
          model: glmVideoModel,
          prompt: 'rain on rooftops',
          timeout: const Duration(seconds: 30),
        );

        // First call: POST to /videos/generations.
        expect(
          calls.first,
          'POST https://open.bigmodel.invalid/api/paas/v4/videos/generations',
        );
        // Polling calls go to /async-result/{id}, not /videos/generations/{id}.
        expect(
          calls
              .skip(1)
              .every(
                (call) =>
                    call.contains('/api/paas/v4/async-result/cogvideo-task-1'),
              ),
          isTrue,
          reason: 'GLM polling must rewrite the path to async-result',
        );
        expect(result.markdown, contains('cogvideo/out.mp4'));
      },
    );

    test('chains MiniMax video task → query → /files/retrieve', () async {
      final calls = <String>[];
      final service = AiImageGenerationService(
        client: MockClient((request) async {
          calls.add('${request.method} ${request.url}');
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'task_id': 'mm-task-9',
                'base_resp': {'status_code': 0, 'status_msg': 'success'},
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/query/video_generation')) {
            // Surface task_id through query string and respond with success.
            expect(request.url.queryParameters['task_id'], 'mm-task-9');
            return http.Response(
              jsonEncode({
                'task_id': 'mm-task-9',
                'status': 'Success',
                'file_id': 'file-42',
                'base_resp': {'status_code': 0, 'status_msg': 'success'},
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          // /files/retrieve?file_id=file-42
          expect(request.url.path.endsWith('/files/retrieve'), isTrue);
          expect(request.url.queryParameters['file_id'], 'file-42');
          return http.Response(
            jsonEncode({
              'file': {
                'file_id': 'file-42',
                'download_url': 'https://cdn.minimax.invalid/files/file-42.mp4',
              },
              'base_resp': {'status_code': 0, 'status_msg': 'success'},
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      const miniMaxModel = AiModelConfig(
        id: 'minimax-video-async',
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

      final result = await service.generateVideo(
        model: miniMaxModel,
        prompt: 'flying koi',
        timeout: const Duration(seconds: 30),
      );

      expect(calls.length, 3);
      expect(calls[0], 'POST https://api.minimax.invalid/v1/video_generation');
      expect(
        calls[1],
        'GET https://api.minimax.invalid/v1/query/video_generation?task_id=mm-task-9',
      );
      expect(
        calls[2],
        'GET https://api.minimax.invalid/v1/files/retrieve?file_id=file-42',
      );
      expect(result.markdown, contains('files/file-42.mp4'));
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

    test('uses DashScope native shape for Qwen TTS audio body', () async {
      late Uri requestUrl;
      late Map<String, Object?> requestBody;
      final service = AiImageGenerationService(
        client: MockClient((request) async {
          requestUrl = request.url;
          requestBody = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response.bytes(
            const <int>[1, 2, 3],
            200,
            headers: const {'content-type': 'audio/mpeg'},
          );
        }),
      );
      const qwenTts = AiModelConfig(
        id: 'qwen-tts',
        baseUrl:
            'https://dashscope.invalid/compatible-mode/v1/chat/completions',
        authScheme: AiAuthScheme.bearer,
        token: 'mock-token',
        modelId: 'cosyvoice-v2',
        protocolType: AiProtocolType.qwen,
        modelProfiles: <String, AiModelProfile>{
          'cosyvoice-v2': AiModelProfile(
            capabilities: <AiModelCapability>{
              AiModelCapability.audioGeneration,
            },
          ),
        },
      );

      final result = await service.generateAudio(
        model: qwenTts,
        prompt: '你好世界',
        options: const AiCreationOptions(style: 'longxiaochun'),
      );

      expect(
        requestUrl.toString(),
        'https://dashscope.invalid/compatible-mode/v1/audio/speech',
      );
      expect(requestBody['model'], 'cosyvoice-v2');
      expect(requestBody['input'], <String, Object?>{'text': '你好世界'});
      expect(requestBody['parameters'], <String, Object?>{
        'voice': 'longxiaochun',
        'format': 'mp3',
      });
      expect(requestBody.containsKey('voice'), isFalse);
      expect(result.markdown, contains('.mp3)'));

      final match = RegExp(r'\(([^)]+\.mp3)\)').firstMatch(result.markdown);
      expect(match, isNotNull);
      final file = File(match!.group(1)!);
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
    });

    test('uses MiniMax T2A v2 nested body for audio generation', () async {
      late Uri requestUrl;
      late Map<String, Object?> requestBody;
      final service = AiImageGenerationService(
        client: MockClient((request) async {
          requestUrl = request.url;
          requestBody = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response.bytes(
            const <int>[1, 2, 3],
            200,
            headers: const {'content-type': 'audio/mpeg'},
          );
        }),
      );
      const miniMaxTts = AiModelConfig(
        id: 'minimax-tts',
        baseUrl: 'https://api.minimax.invalid/v1/chat/completions',
        authScheme: AiAuthScheme.bearer,
        token: 'mock-token',
        modelId: 'speech-02-hd',
        protocolType: AiProtocolType.minimax,
        modelProfiles: <String, AiModelProfile>{
          'speech-02-hd': AiModelProfile(
            capabilities: <AiModelCapability>{
              AiModelCapability.audioGeneration,
            },
          ),
        },
      );

      final result = await service.generateAudio(
        model: miniMaxTts,
        prompt: 'hello world',
        options: const AiCreationOptions(style: 'male-qn-jingying'),
      );

      expect(requestUrl.toString(), 'https://api.minimax.invalid/v1/t2a_v2');
      expect(requestBody['model'], 'speech-02-hd');
      expect(requestBody['text'], 'hello world');
      final voiceSetting = requestBody['voice_setting'] as Map<String, Object?>;
      expect(voiceSetting['voice_id'], 'male-qn-jingying');
      expect(voiceSetting['speed'], 1.0);
      final audioSetting = requestBody['audio_setting'] as Map<String, Object?>;
      expect(audioSetting['format'], 'mp3');
      expect(requestBody.containsKey('input'), isFalse);
      expect(requestBody.containsKey('voice'), isFalse);
      expect(result.markdown, contains('.mp3)'));

      final match = RegExp(r'\(([^)]+\.mp3)\)').firstMatch(result.markdown);
      expect(match, isNotNull);
      final file = File(match!.group(1)!);
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
    });

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
