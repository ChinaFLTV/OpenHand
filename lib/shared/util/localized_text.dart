import 'package:flutter/widgets.dart';

/// Single source of truth for in-widget, locale-based text selection.
///
/// Historically each feature library defined its own private `_localizedText`
/// helper with subtly different locale checks (`== 'zh'`, `startsWith('zh')`,
/// `.toLowerCase() == 'zh'`). Those diverged on variants such as `zh-Hans`,
/// `zh_CN` or upper-cased tags. This module unifies the check so every surface
/// resolves Chinese locales identically.

/// Whether the active locale should render Chinese copy.
///
/// Matches any Chinese variant (`zh`, `zh_CN`, `zh-Hans`, `ZH`, ...) by doing a
/// case-insensitive prefix match on the language subtag.
bool openHandIsChineseLocale(BuildContext context) {
  final languageCode = Localizations.localeOf(context).languageCode;
  return languageCode.toLowerCase().startsWith('zh');
}

/// Returns text for the active OpenHand locale with conservative fallback.
///
/// Prefer generated [AppLocalizations] for user-facing app copy. This helper is
/// for compact shared widgets and legacy surfaces that still accept inline copy.
String openHandLocalizedText(
  BuildContext context, {
  required String zh,
  required String en,
  String? zhHans,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  return openHandLocalizedTextForLocale(
    Localizations.localeOf(context),
    zh: zh,
    en: en,
    zhHans: zhHans,
    zhHant: zhHant,
    fr: fr,
    de: de,
    ja: ja,
  );
}

/// Returns text for an explicit locale.
///
/// Use this from services/controllers that must produce user-visible copy
/// without a [BuildContext], such as desktop notifications.
String openHandLocalizedTextForLocale(
  Locale locale, {
  required String zh,
  required String en,
  String? zhHans,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  final languageCode = locale.languageCode.toLowerCase();
  final scriptCode = locale.scriptCode?.toLowerCase();
  switch (languageCode) {
    case 'zh':
      if (scriptCode == 'hant') return zhHant ?? zh;
      return zhHans ?? zh;
    case 'fr':
      return fr ?? en;
    case 'de':
      return de ?? en;
    case 'ja':
      return ja ?? en;
    default:
      return en;
  }
}

/// Returns text for a platform locale name such as `zh_CN`, `zh-Hant`, or `fr`.
String openHandLocalizedTextForLocaleName(
  String localeName, {
  required String zh,
  required String en,
  String? zhHans,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  return openHandLocalizedTextForLocale(
    _openHandLocaleFromName(localeName),
    zh: zh,
    en: en,
    zhHans: zhHans,
    zhHant: zhHant,
    fr: fr,
    de: de,
    ja: ja,
  );
}

Locale _openHandLocaleFromName(String localeName) {
  final normalized = localeName.trim().replaceAll('_', '-');
  if (normalized.isEmpty) {
    return const Locale('en');
  }
  final parts = normalized.split('-').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return const Locale('en');
  }
  final languageCode = parts.first.toLowerCase();
  String? scriptCode;
  String? countryCode;
  for (final part in parts.skip(1)) {
    if (part.length == 4 && scriptCode == null) {
      scriptCode = part[0].toUpperCase() + part.substring(1).toLowerCase();
    } else {
      countryCode ??= part.toUpperCase();
    }
  }
  return Locale.fromSubtags(
    languageCode: languageCode,
    scriptCode: scriptCode,
    countryCode: countryCode,
  );
}
