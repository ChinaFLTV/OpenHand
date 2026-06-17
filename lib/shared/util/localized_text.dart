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

/// Returns [zh] for Chinese locales and [en] otherwise.
String openHandLocalizedText(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  return openHandIsChineseLocale(context) ? zh : en;
}
