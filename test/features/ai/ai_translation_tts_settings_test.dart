import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_translation_settings.dart';
import 'package:openhand/features/ai/model/ai_tts_settings.dart';

void main() {
  group('AiTranslationSettings.fromJson', () {
    test('parses JSON text and loose provider settings', () {
      final settings = AiTranslationSettings.fromJson('''
        {
          "enabled": "yes",
          "source_language": " EN ",
          "target_language": " zh-cn ",
          "timeout_seconds": "1",
          "max_text_characters": "999999",
          "provider_priority": "google,bing,google",
          "providers": {
            "youdao": {
              "enabled": "true",
              "endpoint": 123,
              "app_id": " app ",
              "api_key": " key ",
              "extra": {"x": 1}
            }
          }
        }
      ''');

      expect(settings.enabled, isTrue);
      expect(settings.sourceLanguage, 'en');
      expect(settings.targetLanguage, 'zh-CN');
      expect(settings.timeoutSeconds, AiTranslationSettings.minTimeoutSeconds);
      expect(
        settings.maxTextCharacters,
        AiTranslationSettings.maxMaxTextCharacters,
      );
      expect(settings.providerPriority.take(2), <AiTranslationProvider>[
        AiTranslationProvider.google,
        AiTranslationProvider.bing,
      ]);

      final youdao = settings.provider(AiTranslationProvider.youdao);
      expect(youdao.enabled, isTrue);
      expect(youdao.endpoint, '123');
      expect(youdao.appId, 'app');
      expect(youdao.apiKey, 'key');
      expect(youdao.extra, <String, Object?>{'x': 1});
    });

    test('falls back to defaults for non-object input', () {
      final settings = AiTranslationSettings.fromJson('[]');
      final defaults = AiTranslationSettings.defaults();

      expect(settings.enabled, defaults.enabled);
      expect(settings.sourceLanguage, defaults.sourceLanguage);
      expect(settings.providerPriority, defaults.providerPriority);
    });
  });

  group('AiTtsSettings.fromJson', () {
    test('parses loose map values and JSON text provider settings', () {
      final settings = AiTtsSettings.fromJson(<Object?, Object?>{
        'enabled': 'on',
        'timeout_seconds': '1',
        'max_text_characters': '999999',
        'provider_priority': 'ai,system,ai',
        'providers': <Object?, Object?>{
          'ai': '''
            {
              "enabled": "yes",
              "voice": 123,
              "language": " en ",
              "speed": "999",
              "volume": "-1",
              "pitch": "-99",
              "endpoint": " https://tts.example.com ",
              "model_config_id": 456,
              "extra": {"format": "wav"}
            }
          ''',
        },
      });

      expect(settings.enabled, isTrue);
      expect(settings.timeoutSeconds, AiTtsSettings.minTimeoutSeconds);
      expect(settings.maxTextCharacters, AiTtsSettings.maxMaxTextCharacters);
      expect(settings.providerPriority.take(2), <AiTtsProvider>[
        AiTtsProvider.ai,
        AiTtsProvider.system,
      ]);

      final ai = settings.provider(AiTtsProvider.ai);
      expect(ai.enabled, isTrue);
      expect(ai.voice, '123');
      expect(ai.language, 'en');
      expect(ai.speed, 200);
      expect(ai.volume, 0);
      expect(ai.pitch, -20);
      expect(ai.endpoint, 'https://tts.example.com');
      expect(ai.modelConfigId, '456');
      expect(ai.extra, <String, Object?>{'format': 'wav'});
    });

    test('falls back to defaults for non-object input', () {
      final settings = AiTtsSettings.fromJson('[]');
      final defaults = AiTtsSettings.defaults();

      expect(settings.enabled, defaults.enabled);
      expect(settings.timeoutSeconds, defaults.timeoutSeconds);
      expect(settings.providerPriority, defaults.providerPriority);
    });
  });
}
