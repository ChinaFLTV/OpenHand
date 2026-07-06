import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_tts_settings.dart';

void main() {
  group('AiTtsProviderSettings', () {
    test('fromJson clamps provider numeric values', () {
      final settings = AiTtsProviderSettings.fromJson(<String, Object?>{
        'speed': -1,
        'volume': 999,
        'pitch': -999,
      }, provider: AiTtsProvider.ai);

      expect(settings.speed, AiTtsProviderSettings.minSpeed);
      expect(settings.volume, AiTtsProviderSettings.maxVolume);
      expect(settings.pitch, AiTtsProviderSettings.minPitch);
    });

    test('copyWith and toJson normalize non-finite provider values', () {
      final defaults = AiTtsProviderSettings.defaults(AiTtsProvider.ai);
      final settings = AiTtsProviderSettings(
        provider: defaults.provider,
        enabled: defaults.enabled,
        voice: defaults.voice,
        language: defaults.language,
        speed: double.nan,
        volume: double.infinity,
        pitch: double.negativeInfinity,
        endpoint: defaults.endpoint,
        appId: defaults.appId,
        apiKey: defaults.apiKey,
        apiSecret: defaults.apiSecret,
        accessToken: defaults.accessToken,
        region: defaults.region,
        modelConfigId: defaults.modelConfigId,
        modelId: defaults.modelId,
        extra: defaults.extra,
      );

      final normalized = settings.copyWith();
      final json = settings.toJson();

      expect(normalized.speed, defaults.speed);
      expect(normalized.volume, AiTtsProviderSettings.maxVolume);
      expect(normalized.pitch, AiTtsProviderSettings.minPitch);
      expect(json['speed'], defaults.speed);
      expect(json['volume'], AiTtsProviderSettings.maxVolume);
      expect(json['pitch'], AiTtsProviderSettings.minPitch);
    });
  });

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
