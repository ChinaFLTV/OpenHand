import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

/// 组件内按语言选择文本的唯一入口。
///
/// 旧代码曾在各功能模块重复实现 `_localizedText`，且中文判断规则不一致。
/// 此处统一处理 `zh-Hans`、`zh_CN` 及大小写变体。

Locale? _ambientLocaleOverride;

/// 无 [BuildContext] 场景使用的界面语言。
///
/// 服务、控制器产生的用户可见文本（通知、异常消息、日志摘要）必须与界面语言
/// 一致。此值由设置控制器在语言变更时同步；同步之前回退到宿主平台语言。
Locale get openHandAmbientLocale =>
    _ambientLocaleOverride ?? PlatformDispatcher.instance.locale;

set openHandAmbientLocale(Locale locale) => _ambientLocaleOverride = locale;

/// 按 [openHandAmbientLocale] 返回文本，供没有 [BuildContext] 的调用方使用。
String openHandAmbientText({
  required String zh,
  required String en,
  String? zhHans,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  return openHandLocalizedTextForLocale(
    openHandAmbientLocale,
    zh: zh,
    en: en,
    zhHans: zhHans,
    zhHant: zhHant,
    fr: fr,
    de: de,
    ja: ja,
  );
}

/// 当前语言是否应显示中文文本。
bool openHandIsChineseLocale(BuildContext context) {
  final languageCode = Localizations.localeOf(context).languageCode;
  return languageCode.toLowerCase().startsWith('zh');
}

/// 按当前语言返回文本，并执行保守回退。
///
/// 正式界面文本优先使用生成的 AppLocalizations；此方法仅服务紧凑公共组件及
/// 仍使用内联文本的旧界面。
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

/// 已绑定语言的文本取值函数。
///
/// 与 [openHandLocalizedText] 参数一致，但省去每次调用重复传 `context`。
typedef OpenHandLocalizedTextResolver =
    String Function({
      required String zh,
      required String en,
      String? zhHans,
      String? zhHant,
      String? fr,
      String? de,
      String? ja,
    });

/// 绑定 [context] 当前语言，返回可复用的取值函数。
///
/// 供一个 `build` / 弹窗构建器内需要多次取文本的界面使用：语言只解析一次，
/// 后续调用不再重复走 `Localizations.localeOf`。
OpenHandLocalizedTextResolver openHandTextResolver(BuildContext context) {
  return openHandTextResolverForLocale(Localizations.localeOf(context));
}

/// 绑定显式 [locale]，返回可复用的取值函数。供没有 [BuildContext] 的场景使用。
OpenHandLocalizedTextResolver openHandTextResolverForLocale(Locale locale) {
  return ({
    required String zh,
    required String en,
    String? zhHans,
    String? zhHant,
    String? fr,
    String? de,
    String? ja,
  }) => openHandLocalizedTextForLocale(
    locale,
    zh: zh,
    en: en,
    zhHans: zhHans,
    zhHant: zhHant,
    fr: fr,
    de: de,
    ja: ja,
  );
}

/// 公共“取消”标签，避免各弹窗重复维护同一组多语言文本。
String openHandCancelLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '取消', en: 'Cancel');
}

/// 公共“关闭”标签，避免各弹窗重复维护同一组多语言文本。
String openHandCloseLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '关闭',
    zhHant: '關閉',
    en: 'Close',
    fr: 'Fermer',
    de: 'Schließen',
    ja: '閉じる',
  );
}

/// 按明确指定的语言返回文本。
///
/// 供没有 [BuildContext] 但必须生成用户可见文本的服务或控制器使用。
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

/// 按 `zh_CN`、`zh-Hant`、`fr` 等平台语言名称返回文本。
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
