import '../../l10n/app_localizations.dart';
import '../util/localized_text.dart';

abstract final class StructuredErrorText {
  static const List<String> _legacyAnchors = <String>[
    '原因 / Why:',
    '建议 / Try:',
    '服务端原文 / Server says:',
    '原始错误 / Raw:',
  ];

  static AppLocalizations get _l10n =>
      lookupAppLocalizations(openHandSupportedUiLocale(openHandAmbientLocale));

  static String pick({
    required String zh,
    required String en,
    String? zhHans,
    String? zhHant,
    String? fr,
    String? de,
    String? ja,
  }) {
    return openHandAmbientText(
      zh: zh,
      en: en,
      zhHans: zhHans,
      zhHant: zhHant,
      fr: fr,
      de: de,
      ja: ja,
    );
  }

  static String whyLabel() => _l10n.structuredErrorWhy;

  static String tryLabel() => _l10n.structuredErrorTry;

  static String serverSaysLabel() => _l10n.structuredErrorServerSays;

  static String rawLabel() => _l10n.structuredErrorRaw;

  static bool isStructured(String raw) {
    if (raw.isEmpty) return false;
    return raw.contains(whyLabel()) ||
        raw.contains(tryLabel()) ||
        raw.contains(serverSaysLabel()) ||
        raw.contains(rawLabel()) ||
        _legacyAnchors.any(raw.contains);
  }

  static String format({
    required String title,
    required String reason,
    required String try_,
    String? raw,
    String? server,
  }) {
    final buf = StringBuffer()
      ..writeln(title)
      ..writeln(whyLabel())
      ..writeln(reason)
      ..writeln(tryLabel())
      ..write(try_);
    final serverText = server?.trim();
    if (serverText != null && serverText.isNotEmpty) {
      buf
        ..writeln()
        ..write('${serverSaysLabel()} $serverText');
    }
    final rawText = raw?.trim();
    if (rawText != null && rawText.isNotEmpty) {
      buf
        ..writeln()
        ..write('${rawLabel()} $rawText');
    }
    return buf.toString();
  }
}
