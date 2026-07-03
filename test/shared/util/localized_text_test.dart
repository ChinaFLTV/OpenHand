import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/localized_text.dart';

void main() {
  group('openHandLocalizedTextForLocaleName', () {
    test('resolves Chinese variants with script-aware fallbacks', () {
      expect(
        openHandLocalizedTextForLocaleName(
          'zh_CN',
          zh: '中文',
          en: 'English',
          zhHant: '繁中',
        ),
        '中文',
      );
      expect(
        openHandLocalizedTextForLocaleName(
          'zh-Hant-TW',
          zh: '中文',
          en: 'English',
          zhHant: '繁中',
        ),
        '繁中',
      );
    });

    test('resolves supported non-Chinese locales', () {
      expect(
        openHandLocalizedTextForLocaleName(
          'fr_FR',
          zh: '中文',
          en: 'English',
          fr: 'Français',
        ),
        'Français',
      );
      expect(
        openHandLocalizedTextForLocaleName(
          'de-DE',
          zh: '中文',
          en: 'English',
          de: 'Deutsch',
        ),
        'Deutsch',
      );
      expect(
        openHandLocalizedTextForLocaleName(
          'ja',
          zh: '中文',
          en: 'English',
          ja: '日本語',
        ),
        '日本語',
      );
    });

    test('falls back conservatively when a locale is unsupported', () {
      expect(
        openHandLocalizedTextForLocaleName(
          'es_ES',
          zh: '中文',
          en: 'English',
          fr: 'Français',
        ),
        'English',
      );
    });
  });
}
