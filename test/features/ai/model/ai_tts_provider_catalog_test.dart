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
  });
}
