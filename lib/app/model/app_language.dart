import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

enum AppLanguage {
  simplifiedChinese,
  traditionalChinese,
  english,
  french,
  german,
  japanese,
}

final List<Locale> supportedAppLocales = AppLanguage.values
    .map((language) => language.locale)
    .toList(growable: false);

extension AppLanguageX on AppLanguage {
  Locale get locale {
    return switch (this) {
      AppLanguage.simplifiedChinese => const Locale('zh'),
      AppLanguage.traditionalChinese => const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
      ),
      AppLanguage.english => const Locale('en'),
      AppLanguage.french => const Locale('fr'),
      AppLanguage.german => const Locale('de'),
      AppLanguage.japanese => const Locale('ja'),
    };
  }

  String get storageValue {
    return switch (this) {
      AppLanguage.simplifiedChinese => 'zh_Hans',
      AppLanguage.traditionalChinese => 'zh_Hant',
      AppLanguage.english => 'en',
      AppLanguage.french => 'fr',
      AppLanguage.german => 'de',
      AppLanguage.japanese => 'ja',
    };
  }

  String label(AppLocalizations l10n) {
    return switch (this) {
      AppLanguage.simplifiedChinese => l10n.languageSimplifiedChinese,
      AppLanguage.traditionalChinese => l10n.languageTraditionalChinese,
      AppLanguage.english => l10n.languageEnglish,
      AppLanguage.french => l10n.languageFrench,
      AppLanguage.german => l10n.languageGerman,
      AppLanguage.japanese => l10n.languageJapanese,
    };
  }
}

AppLanguage appLanguageFromStorage(String? value) {
  for (final language in AppLanguage.values) {
    if (language.storageValue == value) {
      return language;
    }
  }
  return AppLanguage.simplifiedChinese;
}
