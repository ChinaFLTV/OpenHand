import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_catalog.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';

void main() {
  group('AiModelCatalog media-capable lookups', () {
    void expectCapability(
      String modelId,
      AiProtocolType protocol,
      AiModelCapability capability,
    ) {
      final profile = AiModelCatalog.lookup(modelId, protocol);
      expect(
        profile,
        isNotNull,
        reason: '$modelId should resolve under ${protocol.storageValue}',
      );
      expect(
        profile!.capabilities,
        contains(capability),
        reason: '$modelId should advertise ${capability.name}',
      );
    }

    test('OpenAI Sora 2 maps to video generation', () {
      expectCapability(
        'sora-2',
        AiProtocolType.openai,
        AiModelCapability.videoGeneration,
      );
    });

    test('Qwen wan 2.2 maps to video generation', () {
      expectCapability(
        'wan2.2-t2v-plus',
        AiProtocolType.qwen,
        AiModelCapability.videoGeneration,
      );
    });

    test('Qwen cosyvoice / qwen3-tts map to audio generation', () {
      expectCapability(
        'cosyvoice-v2',
        AiProtocolType.qwen,
        AiModelCapability.audioGeneration,
      );
      expectCapability(
        'qwen3-tts-mini-realtime',
        AiProtocolType.qwen,
        AiModelCapability.audioGeneration,
      );
    });

    test('GLM CogVideoX and CogTTS map to media generation', () {
      expectCapability(
        'cogvideox',
        AiProtocolType.glm,
        AiModelCapability.videoGeneration,
      );
      expectCapability(
        'cogtts',
        AiProtocolType.glm,
        AiModelCapability.audioGeneration,
      );
    });

    test('MiniMax video-01 and t2a / speech maps to media generation', () {
      expectCapability(
        'video-01',
        AiProtocolType.minimax,
        AiModelCapability.videoGeneration,
      );
      expectCapability(
        't2a-async-v2',
        AiProtocolType.minimax,
        AiModelCapability.audioGeneration,
      );
      expectCapability(
        'speech-02-hd',
        AiProtocolType.minimax,
        AiModelCapability.audioGeneration,
      );
    });
  });
}
