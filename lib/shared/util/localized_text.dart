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
  final locale = Localizations.localeOf(context);
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
