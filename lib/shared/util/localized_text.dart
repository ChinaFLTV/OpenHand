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
      return fr ?? _openHandInlineCatalogText('fr', en) ?? en;
    case 'de':
      return de ?? _openHandInlineCatalogText('de', en) ?? en;
    case 'ja':
      return ja ?? _openHandInlineCatalogText('ja', en) ?? en;
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

String? _openHandInlineCatalogText(String languageCode, String en) {
  return _openHandInlineTextCatalog[en.trim()]?[languageCode];
}

const Map<String, Map<String, String>>
_openHandInlineTextCatalog = <String, Map<String, String>>{
  'Add': <String, String>{'fr': 'Ajouter', 'de': 'Hinzufügen', 'ja': '追加'},
  'Add field': <String, String>{
    'fr': 'Ajouter un champ',
    'de': 'Feld hinzufügen',
    'ja': 'フィールドを追加',
  },
  'Cancel': <String, String>{'fr': 'Annuler', 'de': 'Abbrechen', 'ja': 'キャンセル'},
  'Confirm': <String, String>{
    'fr': 'Confirmer',
    'de': 'Bestätigen',
    'ja': '確認',
  },
  'Delete': <String, String>{'fr': 'Supprimer', 'de': 'Löschen', 'ja': '削除'},
  'Edit': <String, String>{'fr': 'Modifier', 'de': 'Bearbeiten', 'ja': '編集'},
  'Submit': <String, String>{'fr': 'Envoyer', 'de': 'Senden', 'ja': '送信'},
  'Complete': <String, String>{
    'fr': 'Terminer',
    'de': 'Abschließen',
    'ja': '完了',
  },
  'Events': <String, String>{
    'fr': 'Événements',
    'de': 'Ereignisse',
    'ja': 'イベント',
  },
  'Requests': <String, String>{
    'fr': 'Requêtes',
    'de': 'Anfragen',
    'ja': 'リクエスト',
  },
  'Pending': <String, String>{
    'fr': 'En attente',
    'de': 'Ausstehend',
    'ja': '保留中',
  },
  'Resolved': <String, String>{'fr': 'Résolu', 'de': 'Erledigt', 'ja': '処理済み'},
  'High risk': <String, String>{
    'fr': 'Risque élevé',
    'de': 'Hohes Risiko',
    'ja': '高リスク',
  },
  'Workers': <String, String>{'fr': 'Workers', 'de': 'Worker', 'ja': 'Worker'},
  'Idle / busy': <String, String>{
    'fr': 'Libre / occupé',
    'de': 'Frei / beschäftigt',
    'ja': 'アイドル / ビジー',
  },
  'Queued': <String, String>{'fr': 'En file', 'de': 'Wartend', 'ja': 'キュー'},
  'Running': <String, String>{'fr': 'En cours', 'de': 'Läuft', 'ja': '実行中'},
  'Blocked': <String, String>{'fr': 'Bloqué', 'de': 'Blockiert', 'ja': 'ブロック中'},
  'Utilization': <String, String>{
    'fr': 'Utilisation',
    'de': 'Auslastung',
    'ja': '使用率',
  },
  'Tasks': <String, String>{'fr': 'Tâches', 'de': 'Aufgaben', 'ja': 'タスク'},
  'Active': <String, String>{'fr': 'Actif', 'de': 'Aktiv', 'ja': 'アクティブ'},
  'Completed': <String, String>{
    'fr': 'Terminé',
    'de': 'Abgeschlossen',
    'ja': '完了',
  },
  'Avg. progress': <String, String>{
    'fr': 'Progression moy.',
    'de': 'Durchschn. Fortschritt',
    'ja': '平均進捗',
  },
  'Tracking': <String, String>{'fr': 'Suivi', 'de': 'Verfolgung', 'ja': '追跡中'},
  'At risk': <String, String>{
    'fr': 'À risque',
    'de': 'Gefährdet',
    'ja': 'リスクあり',
  },
  'Done': <String, String>{'fr': 'Terminé', 'de': 'Erledigt', 'ja': '完了'},
  'Pressure': <String, String>{'fr': 'Pression', 'de': 'Druck', 'ja': '負荷'},
  'Token left': <String, String>{
    'fr': 'Tokens restants',
    'de': 'Tokens übrig',
    'ja': '残りトークン',
  },
  'Storage left': <String, String>{
    'fr': 'Stockage restant',
    'de': 'Speicher übrig',
    'ja': '残り容量',
  },
  'Token budget': <String, String>{
    'fr': 'Budget de tokens',
    'de': 'Token-Budget',
    'ja': 'トークン予算',
  },
  'Persisted storage': <String, String>{
    'fr': 'Stockage persistant',
    'de': 'Persistenter Speicher',
    'ja': '永続化ストレージ',
  },
  'High': <String, String>{'fr': 'Élevé', 'de': 'Hoch', 'ja': '高'},
  'Watch': <String, String>{'fr': 'Surveiller', 'de': 'Beobachten', 'ja': '注意'},
  'Normal': <String, String>{'fr': 'Normal', 'de': 'Normal', 'ja': '正常'},
  'Status': <String, String>{'fr': 'Statut', 'de': 'Status', 'ja': 'ステータス'},
  'Progress': <String, String>{
    'fr': 'Progression',
    'de': 'Fortschritt',
    'ja': '進捗',
  },
  'Next': <String, String>{'fr': 'Suivant', 'de': 'Weiter', 'ja': '次'},
  'Title': <String, String>{'fr': 'Titre', 'de': 'Titel', 'ja': 'タイトル'},
  'Created': <String, String>{'fr': 'Créé', 'de': 'Erstellt', 'ja': '作成'},
  'Updated': <String, String>{
    'fr': 'Mis à jour',
    'de': 'Aktualisiert',
    'ja': '更新',
  },
  'Handoff': <String, String>{
    'fr': 'Transmission',
    'de': 'Übergabe',
    'ja': '引き継ぎ',
  },
  'Recommended tool': <String, String>{
    'fr': 'Outil recommandé',
    'de': 'Empfohlenes Tool',
    'ja': '推奨ツール',
  },
  'Assigned worker': <String, String>{
    'fr': 'Worker attribué',
    'de': 'Zugewiesener Worker',
    'ja': '割り当て Worker',
  },
  'Key': <String, String>{'fr': 'Clé', 'de': 'Schlüssel', 'ja': 'キー'},
  'Value': <String, String>{'fr': 'Valeur', 'de': 'Wert', 'ja': '値'},
};
