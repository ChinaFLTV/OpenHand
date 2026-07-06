import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_tts_settings.dart';

void main() {
  group('AiTtsSettings', () {
    test('fromJson clamps numeric bounds', () {
      final settings = AiTtsSettings.fromJson(<String, Object?>{
        'enabled': 'true',
        'timeout_seconds': 999999,
        'max_text_characters': 1,
      });

      expect(settings.enabled, isTrue);
      expect(settings.timeoutSeconds, AiTtsSettings.maxTimeoutSeconds);
      expect(settings.maxTextCharacters, AiTtsSettings.minMaxTextCharacters);
    });

    test('fromJson falls back malformed numeric values', () {
      final settings = AiTtsSettings.fromJson(<String, Object?>{
        'timeout_seconds': 'bad',
        'max_text_characters': 'bad',
      });

      expect(settings.timeoutSeconds, AiTtsSettings.defaultTimeoutSeconds);
      expect(
        settings.maxTextCharacters,
        AiTtsSettings.defaultMaxTextCharacters,
      );
    });

    test('copyWith and toJson normalize unsafe numeric values', () {
      const settings = AiTtsSettings(
        enabled: false,
        timeoutSeconds: 0,
        maxTextCharacters: 999999,
        providers: <AiTtsProvider, AiTtsProviderSettings>{},
        providerPriority: <AiTtsProvider>[],
      );

      final normalizedCurrent = settings.copyWith();
      final normalizedReplacement = settings.copyWith(
        timeoutSeconds: 999999,
        maxTextCharacters: 1,
      );
      final json = settings.toJson();

      expect(normalizedCurrent.timeoutSeconds, AiTtsSettings.minTimeoutSeconds);
      expect(
        normalizedCurrent.maxTextCharacters,
        AiTtsSettings.maxMaxTextCharacters,
      );
      expect(
        normalizedReplacement.timeoutSeconds,
        AiTtsSettings.maxTimeoutSeconds,
      );
      expect(
        normalizedReplacement.maxTextCharacters,
        AiTtsSettings.minMaxTextCharacters,
      );
      expect(json['timeout_seconds'], AiTtsSettings.minTimeoutSeconds);
      expect(json['max_text_characters'], AiTtsSettings.maxMaxTextCharacters);
    });
  });
}
