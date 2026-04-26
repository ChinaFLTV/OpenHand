import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/self_learning_dispatcher.dart';

void main() {
  group('selectSelfLearningModel', () {
    const chatModel = AiModelConfig(
      id: 'chat-provider',
      baseUrl: 'https://mock.invalid/v1',
      authScheme: AiAuthScheme.bearer,
      token: 'token',
      modelId: 'grok-3',
      protocolType: AiProtocolType.grok,
    );

    const videoModel = AiModelConfig(
      id: 'video-provider',
      baseUrl: 'https://mock.invalid/v1',
      authScheme: AiAuthScheme.bearer,
      token: 'token',
      modelId: 'grok-imagine-video',
      protocolType: AiProtocolType.grok,
    );

    test(
      'skips last-used media generation model and uses selected chat model',
      () {
        final selection = selectSelfLearningModel(
          models: const <AiModelConfig>[videoModel, chatModel],
          selectedModel: chatModel,
          preferredProviderConfigId: videoModel.id,
        );

        expect(selection.model?.id, chatModel.id);
        expect(selection.source, 'selected');
        expect(selection.skippedPreferredModelId, videoModel.modelId);
        expect(selection.skippedPreferredProviderId, videoModel.id);
      },
    );

    test(
      'uses first available chat model when selected model is also media-only',
      () {
        final selection = selectSelfLearningModel(
          models: const <AiModelConfig>[videoModel, chatModel],
          selectedModel: videoModel,
          preferredProviderConfigId: videoModel.id,
        );

        expect(selection.model?.id, chatModel.id);
        expect(selection.source, 'first_available');
      },
    );

    test(
      'rejects explicit media-generation profile when no text model exists',
      () {
        const profiledAudioModel = AiModelConfig(
          id: 'audio-provider',
          baseUrl: 'https://mock.invalid/v1',
          authScheme: AiAuthScheme.bearer,
          token: 'token',
          modelId: 'custom-audio-maker',
          protocolType: AiProtocolType.openai,
          modelProfiles: <String, AiModelProfile>{
            'custom-audio-maker': AiModelProfile(
              capabilities: <AiModelCapability>{
                AiModelCapability.audioGeneration,
              },
            ),
          },
        );

        final selection = selectSelfLearningModel(
          models: const <AiModelConfig>[profiledAudioModel],
          selectedModel: profiledAudioModel,
          preferredProviderConfigId: profiledAudioModel.id,
        );

        expect(selection.model, isNull);
        expect(selection.source, 'none');
        expect(selection.skippedPreferredModelId, profiledAudioModel.modelId);
      },
    );

    test(
      'filters newly added media-only model IDs even without catalog hit',
      () {
        // These IDs intentionally use shapes that may not yet be in the
        // catalog – the heuristic fallback in
        // `_looksLikeDedicatedMediaGenerationModel` must still skip them so
        // self-learning never tries to use a media-only model for chat.
        const candidates = <String>[
          'sora-2',
          'wan2.2-t2v-plus',
          'cosyvoice-v2',
          'qwen3-tts-mini-realtime',
          'cogvideox',
          'cogtts',
          'cogsound-v1',
          't2a-async-v2',
          'video-01',
          'speech-02-hd',
          'flux.1-schnell',
          'imagen-4',
          'midjourney-v7',
          'ideogram-3',
          'kling-v2',
          'hailuo-02',
          'veo-3',
          'vidu-2',
          'seedream-4',
          'cogview-4',
          'stable-audio-2.5',
          'musicgen-medium',
        ];
        for (final id in candidates) {
          final media = AiModelConfig(
            id: 'media-$id',
            baseUrl: 'https://mock.invalid/v1',
            authScheme: AiAuthScheme.bearer,
            token: 'token',
            modelId: id,
            protocolType: AiProtocolType.openai,
          );
          final selection = selectSelfLearningModel(
            models: <AiModelConfig>[media],
            selectedModel: media,
            preferredProviderConfigId: media.id,
          );
          expect(
            selection.model,
            isNull,
            reason: '$id should be filtered as media-only',
          );
          expect(selection.source, 'none');
        }
      },
    );
  });
}
