import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_tts_provider_catalog.dart';

void main() {
  group('AiTtsProviderCatalogs', () {
    test('uses StepFun 2.5 voices instead of OpenAI presets', () {
      final voices = AiTtsProviderCatalogs.voiceOptionsForAiModel(
        protocol: AiProtocolType.stepfun,
        modelId: 'stepaudio-2.5-tts',
      );
      final values = voices.map((option) => option.value).toList();

      expect(values, contains('cixingnansheng'));
      expect(values, contains('lively-girl'));
      expect(values, contains('shuangkuainansheng'));
      expect(values, isNot(contains('alloy')));
      expect(values, isNot(contains('mengwa')));
      expect(values.length, values.toSet().length);

      final brightMale = voices.firstWhere(
        (option) => option.value == 'shuangkuainansheng',
      );
      expect(brightMale.label, isNot(brightMale.value));
      expect(brightMale.label, '爽快男声');
    });

    test('normalizes StepFun voices and response formats', () {
      expect(
        AiTtsProviderCatalogs.normalizeVoiceForAiModel(
          voice: 'verse',
          protocol: AiProtocolType.stepfun,
          modelId: 'stepaudio-2.5-tts',
        ),
        AiTtsProviderCatalogs.stepFunDefaultVoice,
      );
      expect(
        AiTtsProviderCatalogs.normalizeVoiceForAiModel(
          voice: 'lively-girl',
          protocol: AiProtocolType.stepfun,
          modelId: 'stepaudio-2.5-tts',
        ),
        'lively-girl',
      );
      expect(
        AiTtsProviderCatalogs.normalizeVoiceForAiModel(
          voice: 'mengwa',
          protocol: AiProtocolType.stepfun,
          modelId: 'stepaudio-2.5-tts',
        ),
        AiTtsProviderCatalogs.stepFunDefaultVoice,
      );
      expect(
        AiTtsProviderCatalogs.normalizeStepFunResponseFormat('WAV'),
        'wav',
      );
      expect(
        AiTtsProviderCatalogs.normalizeStepFunResponseFormat('aac'),
        'mp3',
      );
    });

    test('keeps OpenAI-compatible voice behavior for non StepFun models', () {
      final voices = AiTtsProviderCatalogs.voiceOptionsForAiModel(
        protocol: AiProtocolType.openai,
        modelId: 'gpt-4o-mini-tts',
      );
      final values = voices.map((option) => option.value).toList();

      expect(values, contains('alloy'));
      expect(values, contains('cedar'));
      expect(values, contains('marin'));
      expect(values, isNot(contains('cixingnansheng')));
      expect(
        AiTtsProviderCatalogs.normalizeVoiceForAiModel(
          voice: '',
          protocol: AiProtocolType.openai,
          modelId: 'gpt-4o-mini-tts',
        ),
        AiTtsProviderCatalogs.openAiDefaultVoice,
      );
      expect(
        AiTtsProviderCatalogs.normalizeVoiceForAiModel(
          voice: 'nova',
          protocol: AiProtocolType.openai,
          modelId: 'gpt-4o-mini-tts',
        ),
        'nova',
      );
    });

    test('uses Qwen voice catalogs by TTS model family', () {
      final qwen3Voices = AiTtsProviderCatalogs.voiceOptionsForAiModel(
        protocol: AiProtocolType.qwen,
        modelId: 'qwen3-tts-flash',
      );
      final qwen3Values = qwen3Voices.map((option) => option.value).toList();

      expect(qwen3Values, contains('Cherry'));
      expect(qwen3Values, contains('Kiki'));
      expect(qwen3Values, isNot(contains('alloy')));

      final legacyVoices = AiTtsProviderCatalogs.voiceOptionsForAiModel(
        protocol: AiProtocolType.qwen,
        modelId: 'qwen-tts-latest',
      );
      final legacyValues = legacyVoices.map((option) => option.value).toList();

      expect(legacyValues, contains('Cherry'));
      expect(legacyValues, contains('Dylan'));
      expect(legacyValues, isNot(contains('Kiki')));
      expect(
        AiTtsProviderCatalogs.normalizeVoiceForAiModel(
          voice: 'alloy',
          protocol: AiProtocolType.qwen,
          modelId: 'qwen3-tts-flash',
        ),
        AiTtsProviderCatalogs.qwenDefaultVoice,
      );
    });

    test('routes non OpenAI TTS providers to provider-specific voices', () {
      final minimaxVoices = AiTtsProviderCatalogs.voiceOptionsForAiModel(
        protocol: AiProtocolType.minimax,
        modelId: 'speech-02-hd',
      );
      expect(
        minimaxVoices.map((option) => option.value),
        contains(AiTtsProviderCatalogs.minimaxDefaultVoice),
      );
      expect(
        AiTtsProviderCatalogs.defaultVoiceForAiModel(
          protocol: AiProtocolType.minimax,
          modelId: 'speech-02-hd',
        ),
        AiTtsProviderCatalogs.minimaxDefaultVoice,
      );

      final seedVoices = AiTtsProviderCatalogs.voiceOptionsForAiModel(
        protocol: AiProtocolType.seed,
        modelId: 'seed-tts-2.0-standard',
      );
      expect(
        seedVoices.map((option) => option.value),
        contains(AiTtsProviderCatalogs.doubaoDefaultVoice),
      );

      final mimoPresetVoices = AiTtsProviderCatalogs.voiceOptionsForAiModel(
        protocol: AiProtocolType.mimo,
        modelId: 'mimo-v2.5-tts',
      );
      expect(
        mimoPresetVoices.map((option) => option.value),
        contains(AiTtsProviderCatalogs.mimoDefaultVoice),
      );

      final mimoCloneVoices = AiTtsProviderCatalogs.voiceOptionsForAiModel(
        protocol: AiProtocolType.mimo,
        modelId: 'mimo-v2.5-tts-voiceclone',
      );
      expect(mimoCloneVoices, isEmpty);
    });
  });
}
