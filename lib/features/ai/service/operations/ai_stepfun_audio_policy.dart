import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_tts_provider_catalog.dart';

final class AiStepFunAudioPolicy {
  const AiStepFunAudioPolicy._();

  static const int maxSpeechInputRunes = 1000;

  static bool isStepFunSpeech({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    return AiTtsProviderCatalogs.usesStepFunSpeech(
      protocol: protocol,
      modelId: modelId,
    );
  }

  static bool isStepAudio25TtsModel(String modelId) {
    return AiTtsProviderCatalogs.isStepAudio25TtsModel(modelId);
  }

  static String? inputValidationError({
    required AiProtocolType protocol,
    required String modelId,
    required String input,
  }) {
    if (!isStepFunSpeech(protocol: protocol, modelId: modelId)) return null;
    if (input.runes.length <= maxSpeechInputRunes) return null;
    return 'StepFun TTS input exceeds $maxSpeechInputRunes characters.';
  }

  static String resolveVoice(String? raw) {
    return AiTtsProviderCatalogs.normalizeStepFunVoice(raw);
  }

  static String resolveResponseFormat(Object? raw) {
    return AiTtsProviderCatalogs.normalizeStepFunResponseFormat(raw);
  }

  static int? resolveSampleRate(Object? raw) {
    final value = optionalIntFromValue(raw);
    if (value == null ||
        !AiTtsProviderCatalogs.stepFunSupportedSampleRates.contains(value)) {
      return null;
    }
    return value;
  }

  static double? resolveSpeed(Object? raw) => _boundedDouble(raw, 0.5, 2.0);

  static double? resolveVolume(Object? raw) => _boundedDouble(raw, 0.1, 2.0);

  static Map<String, Object?> normalizeSpeechBody({
    required Map<String, Object?> body,
    required AiProtocolType protocol,
    required String modelId,
  }) {
    if (!isStepFunSpeech(protocol: protocol, modelId: modelId)) return body;
    final normalized = Map<String, Object?>.from(body);
    normalized['voice'] = resolveVoice('${normalized['voice'] ?? ''}');
    normalized['response_format'] = resolveResponseFormat(
      normalized['response_format'],
    );

    final speed = resolveSpeed(normalized['speed']);
    if (speed == null) {
      normalized.remove('speed');
    } else {
      normalized['speed'] = speed;
    }

    final volume = resolveVolume(normalized['volume']);
    if (volume == null) {
      normalized.remove('volume');
    } else {
      normalized['volume'] = volume;
    }

    final sampleRate = resolveSampleRate(normalized['sample_rate']);
    if (sampleRate == null) {
      normalized.remove('sample_rate');
    } else {
      normalized['sample_rate'] = sampleRate;
    }

    normalized.remove('bitrate');
    normalized.remove('pitch');
    if (isStepAudio25TtsModel(modelId)) {
      normalized.remove('voice_label');
    }
    return normalized;
  }

  static double? _boundedDouble(Object? raw, double min, double max) {
    final value = optionalDoubleFromValue(raw);
    if (value == null) return null;
    return value.clamp(min, max);
  }
}
