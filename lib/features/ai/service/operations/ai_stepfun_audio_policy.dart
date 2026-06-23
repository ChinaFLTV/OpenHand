import '../../model/ai_model_config.dart';

final class AiStepFunAudioPolicy {
  const AiStepFunAudioPolicy._();

  static const String defaultVoice = 'cixingnansheng';
  static const int maxSpeechInputRunes = 1000;

  static const Set<String> _supportedFormats = <String>{
    'wav',
    'mp3',
    'flac',
    'opus',
    'pcm',
  };

  static const Set<int> _supportedSampleRates = <int>{
    8000,
    16000,
    22050,
    24000,
    48000,
  };

  static const Set<String> _openAiPresetVoices = <String>{
    'alloy',
    'ash',
    'ballad',
    'cedar',
    'coral',
    'echo',
    'fable',
    'marin',
    'nova',
    'onyx',
    'sage',
    'shimmer',
    'verse',
  };

  static bool isStepFunSpeech({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    return protocol == AiProtocolType.stepfun || isStepFunTtsModel(modelId);
  }

  static bool isStepFunTtsModel(String modelId) {
    final normalized = modelId.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.startsWith('step-tts') ||
        (normalized.startsWith('stepaudio-') && normalized.contains('tts'));
  }

  static bool isStepAudio25TtsModel(String modelId) {
    return modelId.trim().toLowerCase().startsWith('stepaudio-2.5-tts');
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
    final voice = raw?.trim() ?? '';
    if (voice.isEmpty || _openAiPresetVoices.contains(voice.toLowerCase())) {
      return defaultVoice;
    }
    return voice;
  }

  static String resolveResponseFormat(Object? raw) {
    final format = '${raw ?? ''}'.trim().toLowerCase();
    if (_supportedFormats.contains(format)) return format;
    return 'mp3';
  }

  static int? resolveSampleRate(Object? raw) {
    final value = _intValue(raw);
    if (value == null || !_supportedSampleRates.contains(value)) return null;
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

  static int? _intValue(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}'.trim());
  }

  static double? _boundedDouble(Object? raw, double min, double max) {
    final value = _doubleValue(raw);
    if (value == null || value.isNaN || value.isInfinite) return null;
    return value.clamp(min, max).toDouble();
  }

  static double? _doubleValue(Object? raw) {
    if (raw is double) return raw;
    if (raw is int) return raw.toDouble();
    if (raw is num) return raw.toDouble();
    return double.tryParse('${raw ?? ''}'.trim());
  }
}
