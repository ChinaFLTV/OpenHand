import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_translation_settings.dart';

void main() {
  group('AiTranslationSettings', () {
    test('fromJson clamps numeric bounds and normalizes languages', () {
      final settings = AiTranslationSettings.fromJson(<String, Object?>{
        'enabled': 'true',
        'source_language': ' EN ',
        'target_language': 'auto',
        'timeout_seconds': 0,
        'max_text_characters': 999999,
      });

      expect(settings.enabled, isTrue);
      expect(settings.sourceLanguage, 'en');
      expect(
        settings.targetLanguage,
        AiTranslationSettings.defaultTargetLanguage,
      );
      expect(settings.timeoutSeconds, AiTranslationSettings.minTimeoutSeconds);
      expect(
        settings.maxTextCharacters,
        AiTranslationSettings.maxMaxTextCharacters,
      );
    });

    test('fromJson falls back malformed numeric values', () {
      final settings = AiTranslationSettings.fromJson(<String, Object?>{
        'timeout_seconds': 'bad',
        'max_text_characters': 'bad',
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

    test('copyWith and toJson normalize unsafe numeric values', () {
      const settings = AiTranslationSettings(
        enabled: false,
        sourceLanguage: 'bad',
        targetLanguage: 'bad',
        timeoutSeconds: -1,
        maxTextCharacters: 1,
        providers: <AiTranslationProvider, AiTranslationProviderSettings>{},
        providerPriority: <AiTranslationProvider>[],
      );

      final normalizedCurrent = settings.copyWith();
      final normalizedReplacement = settings.copyWith(
        timeoutSeconds: 999999,
        maxTextCharacters: 999999,
      );
      final json = settings.toJson();

      expect(
        normalizedCurrent.timeoutSeconds,
        AiTranslationSettings.minTimeoutSeconds,
      );
      expect(
        normalizedCurrent.maxTextCharacters,
        AiTranslationSettings.minMaxTextCharacters,
      );
      expect(
        normalizedReplacement.timeoutSeconds,
        AiTranslationSettings.maxTimeoutSeconds,
      );
      expect(
        normalizedReplacement.maxTextCharacters,
        AiTranslationSettings.maxMaxTextCharacters,
      );
      expect(json['timeout_seconds'], AiTranslationSettings.minTimeoutSeconds);
      expect(
        json['max_text_characters'],
        AiTranslationSettings.minMaxTextCharacters,
      );
    });
  });
}
