import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('creation options ignore non-finite numeric metadata', () {
    final options = AiCreationOptions.fromMetadata(<String, Object?>{
      'duration_seconds': double.infinity,
      'count': '3',
      'speed': 'NaN',
      'sample_rate': '24000',
      'volume': '0.8',
    });

    expect(options.durationSeconds, isNull);
    expect(options.count, 3);
    expect(options.speed, isNull);
    expect(options.sampleRate, 24000);
    expect(options.volume, 0.8);
  });

  test('translation settings fall back for non-finite numeric values', () {
    final settings = AiTranslationSettings.fromJson(<String, Object?>{
      'timeout_seconds': double.infinity,
      'max_text_characters': 'NaN',
    });

    expect(
      settings.timeoutSeconds,
      AiTranslationSettings.defaultTimeoutSeconds,
    );
    expect(
      settings.maxTextCharacters,
      AiTranslationSettings.defaultMaxTextCharacters,
    );
  });

  test('tts settings fall back for non-finite numeric values', () {
    final settings = AiTtsSettings.fromJson(<String, Object?>{
      'timeout_seconds': double.infinity,
      'max_text_characters': 'Infinity',
    });

    expect(settings.timeoutSeconds, AiTtsSettings.defaultTimeoutSeconds);
    expect(settings.maxTextCharacters, AiTtsSettings.defaultMaxTextCharacters);
  });
}
