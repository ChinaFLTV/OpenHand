import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

/// 组件内按语言选择文本的唯一入口。

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

/// 公共“删除”标签，避免各界面重复维护同一组多语言文本。
String openHandDeleteLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '删除',
    zhHant: '刪除',
    en: 'Delete',
    fr: 'Supprimer',
    de: 'Löschen',
    ja: '削除',
  );
}

/// 公共“保存”标签，避免各界面重复维护同一组多语言文本。
String openHandSaveLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '保存',
    zhHant: '儲存',
    en: 'Save',
    fr: 'Enregistrer',
    de: 'Speichern',
    ja: '保存',
  );
}

/// 界面实际提供文本的语言集合，与 [openHandLocalizedTextForLocale] 的分支一致。
const Set<String> _openHandSupportedLanguageCodes = <String>{
  'zh',
  'en',
  'fr',
  'de',
  'ja',
};

/// 把任意语言标签收敛为界面确实支持的语言。
///
/// 宿主系统语言可能是应用未提供的语种（如 `es`），直接拿去查本地化表会抛错；
/// 未识别的语种统一回退到英文，中文则只保留简繁书写方向。
Locale openHandSupportedUiLocale(Locale locale) {
  final languageCode = locale.languageCode.toLowerCase();
  if (!_openHandSupportedLanguageCodes.contains(languageCode)) {
    return const Locale('en');
  }
  if (languageCode != 'zh') return Locale(languageCode);
  return locale.scriptCode?.toLowerCase() == 'hant'
      ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
      : const Locale('zh');
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

// 跨模块通用文案

String openHandAddLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '添加',
    zhHant: '新增',
    en: 'Add',
    fr: 'Ajouter',
    de: 'Hinzufügen',
    ja: '追加',
  );
}

String openHandBrowserLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '浏览器',
    zhHant: '瀏覽器',
    en: 'Browser',
    fr: 'Navigateur',
    de: 'Browser',
    ja: 'ブラウザ',
  );
}

String openHandClearLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '清空',
    zhHant: '清空',
    en: 'Clear',
    fr: 'Effacer',
    de: 'Leeren',
    ja: 'クリア',
  );
}

String openHandCopiedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已复制',
    zhHant: '已複製',
    en: 'Copied',
    fr: 'Copié',
    de: 'Kopiert',
    ja: 'コピーしました',
  );
}

String openHandCopyLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '复制',
    zhHant: '複製',
    en: 'Copy',
    fr: 'Copier',
    de: 'Kopieren',
    ja: 'コピー',
  );
}

String openHandErrorLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '错误',
    zhHant: '錯誤',
    en: 'Error',
    fr: 'Erreur',
    de: 'Fehler',
    ja: 'エラー',
  );
}

String openHandFailedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '失败',
    zhHant: '失敗',
    en: 'Failed',
    fr: 'Échec',
    de: 'Fehlgeschlagen',
    ja: '失敗',
  );
}

String openHandInstallLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '安装',
    zhHant: '安裝',
    en: 'Install',
    fr: 'Installer',
    de: 'Installieren',
    ja: 'インストール',
  );
}

String openHandInstructionsLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '指令', en: 'Instructions');
}

String openHandKnowledgeBaseLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '知识库',
    zhHant: '知識庫',
    en: 'Knowledge Base',
    fr: 'Base de connaissances',
    de: 'Wissensdatenbank',
    ja: 'ナレッジベース',
  );
}

String openHandModelLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '模型',
    zhHant: '模型',
    en: 'Model',
    fr: 'Modèle',
    de: 'Modell',
    ja: 'モデル',
  );
}

String openHandOutputLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '输出',
    zhHant: '輸出',
    en: 'Output',
    fr: 'Sortie',
    de: 'Ausgabe',
    ja: '出力',
  );
}

String openHandPreviewLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '预览',
    zhHant: '預覽',
    en: 'Preview',
    fr: 'Aperçu',
    de: 'Vorschau',
    ja: 'プレビュー',
  );
}

String openHandRefreshLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '刷新',
    zhHant: '重新整理',
    en: 'Refresh',
    fr: 'Actualiser',
    de: 'Aktualisieren',
    ja: '更新',
  );
}

String openHandResetLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '重置', en: 'Reset');
}

String openHandRunningLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '运行中',
    zhHant: '執行中',
    en: 'Running',
    fr: 'En cours',
    de: 'Läuft',
    ja: '実行中',
  );
}

String openHandSaveFailedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '保存失败',
    zhHant: '儲存失敗',
    en: 'Save failed',
    fr: 'Échec de l’enregistrement',
    de: 'Speichern fehlgeschlagen',
    ja: '保存に失敗しました',
  );
}

String openHandStartLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '启动',
    zhHant: '啟動',
    en: 'Start',
    fr: 'Démarrer',
    de: 'Starten',
    ja: '起動',
  );
}

String openHandStatusLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '状态',
    zhHant: '狀態',
    en: 'Status',
    fr: 'État',
    de: 'Status',
    ja: 'ステータス',
  );
}

String openHandStoppedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已停止',
    zhHant: '已停止',
    en: 'Stopped',
    fr: 'Arrêté',
    de: 'Gestoppt',
    ja: '停止済み',
  );
}

String openHandTemplateLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '模板',
    zhHant: '範本',
    en: 'Template',
    fr: 'Modèle',
    de: 'Vorlage',
    ja: 'テンプレート',
  );
}

String openHandUpdatedLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '更新时间', en: 'Updated');
}

String openHandActiveLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '进行中', en: 'Active');
}

String openHandAgentLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '智能体',
    zhHant: '智能體',
    en: 'Agent',
    fr: 'Agent',
    de: 'Agent',
    ja: 'エージェント',
  );
}

String openHandAllLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '全部',
    zhHant: '全部',
    en: 'All',
    fr: 'Tout',
    de: 'Alle',
    ja: 'すべて',
  );
}

String openHandClearSearchLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '清空搜索',
    zhHant: '清空搜尋',
    en: 'Clear search',
    fr: 'Effacer la recherche',
    de: 'Suche leeren',
    ja: '検索をクリア',
  );
}

String openHandCodeBlockLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '代码块',
    zhHant: '程式碼區塊',
    en: 'Code block',
    fr: 'Bloc de code',
    de: 'Codeblock',
    ja: 'コードブロック',
  );
}

String openHandCollapseLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '收起',
    zhHant: '收起',
    en: 'Collapse',
    fr: 'Réduire',
    de: 'Einklappen',
    ja: '折りたたむ',
  );
}

String openHandConfirmLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '确认', en: 'Confirm');
}

String openHandCreatedLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '创建时间', en: 'Created');
}

String openHandDetailsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '详情',
    zhHant: '詳情',
    en: 'Details',
    fr: 'Détails',
    de: 'Details',
    ja: '詳細',
  );
}

String openHandDisabledLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '未启用',
    zhHant: '未啟用',
    en: 'Disabled',
    fr: 'Désactivé',
    de: 'Deaktiviert',
    ja: '無効',
  );
}

String openHandEnabledLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已启用',
    zhHant: '已啟用',
    en: 'Enabled',
    fr: 'Activé',
    de: 'Aktiviert',
    ja: '有効',
  );
}

String openHandEnvironmentLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '环境信息', en: 'Environment');
}

String openHandErrorsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '错误',
    zhHant: '錯誤',
    en: 'Errors',
    fr: 'Erreurs',
    de: 'Fehler',
    ja: 'エラー',
  );
}

String openHandExportJsonLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '导出 JSON',
    zhHant: '匯出 JSON',
    en: 'Export JSON',
    fr: 'Exporter JSON',
    de: 'JSON exportieren',
    ja: 'JSON をエクスポート',
  );
}

String openHandHeading1Label(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '一级标题',
    zhHant: '一級標題',
    en: 'Heading 1',
    fr: 'Titre 1',
    de: 'Überschrift 1',
    ja: '見出し 1',
  );
}

String openHandHeading2Label(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '二级标题',
    zhHant: '二級標題',
    en: 'Heading 2',
    fr: 'Titre 2',
    de: 'Überschrift 2',
    ja: '見出し 2',
  );
}

String openHandHeading3Label(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '三级标题',
    zhHant: '三級標題',
    en: 'Heading 3',
    fr: 'Titre 3',
    de: 'Überschrift 3',
    ja: '見出し 3',
  );
}

String openHandInstalledLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已安装',
    zhHant: '已安裝',
    en: 'Installed',
    fr: 'Installé',
    de: 'Installiert',
    ja: 'インストール済み',
  );
}

String openHandKeywordsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '关键字',
    zhHant: '關鍵字',
    en: 'Keywords',
    fr: 'Mots-clés',
    de: 'Schlüsselwörter',
    ja: 'キーワード',
  );
}

String openHandKnowledgeLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '知识库',
    zhHant: '知識庫',
    en: 'Knowledge',
    fr: 'Connaissance',
    de: 'Wissen',
    ja: 'ナレッジ',
  );
}

String openHandMemoryLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '记忆',
    zhHant: '記憶',
    en: 'Memory',
    fr: 'Mémoire',
    de: 'Speicher',
    ja: 'メモリ',
  );
}

String openHandModeLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '模式',
    zhHant: '模式',
    en: 'Mode',
    fr: 'Mode',
    de: 'Modus',
    ja: 'モード',
  );
}

String openHandModelIdLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '模型 ID',
    zhHant: '模型 ID',
    en: 'Model ID',
    fr: 'ID du modèle',
    de: 'Modell-ID',
    ja: 'モデル ID',
  );
}

String openHandMoreActionsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '更多操作',
    zhHant: '更多操作',
    en: 'More actions',
    fr: 'Plus d’actions',
    de: 'Weitere Aktionen',
    ja: 'その他の操作',
  );
}

String openHandNetworkLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '网络',
    zhHant: '網路',
    en: 'Network',
    fr: 'Réseau',
    de: 'Netzwerk',
    ja: 'ネットワーク',
  );
}

String openHandNoLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '否',
    zhHant: '否',
    en: 'No',
    fr: 'Non',
    de: 'Nein',
    ja: 'いいえ',
  );
}

String openHandNotConfiguredLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '未配置',
    zhHant: '未設定',
    en: 'Not configured',
    fr: 'Non configuré',
    de: 'Nicht konfiguriert',
    ja: '未設定',
  );
}

String openHandObjectiveLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '逆向目标',
    zhHant: '逆向目標',
    en: 'Objective',
    fr: 'Objectif',
    de: 'Ziel',
    ja: '目的',
  );
}

String openHandOkLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '确定',
    zhHant: '確定',
    en: 'OK',
    fr: 'OK',
    de: 'OK',
    ja: 'OK',
  );
}

String openHandOverviewLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '概览',
    zhHant: '概覽',
    en: 'Overview',
    fr: 'Vue d’ensemble',
    de: 'Übersicht',
    ja: '概要',
  );
}

String openHandPathCopiedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '路径已复制。',
    zhHant: '路徑已複製。',
    en: 'Path copied.',
    fr: 'Chemin copié.',
    de: 'Pfad kopiert.',
    ja: 'パスをコピーしました。',
  );
}

String openHandPathLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '路径',
    zhHant: '路徑',
    en: 'Path',
    fr: 'Chemin',
    de: 'Pfad',
    ja: 'パス',
  );
}

String openHandRequestsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '请求数',
    zhHant: '請求數',
    en: 'Requests',
    fr: 'Requêtes',
    de: 'Anfragen',
    ja: 'リクエスト数',
  );
}

String openHandRetryLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '重新加载', en: 'Retry');
}

String openHandRunLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '执行',
    zhHant: '執行',
    en: 'Run',
    fr: 'Exécuter',
    de: 'Ausführen',
    ja: '実行',
  );
}

String openHandSandboxLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '沙盒', en: 'Sandbox');
}

String openHandSearchLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '搜索',
    zhHant: '搜尋',
    en: 'Search',
    fr: 'Rechercher',
    de: 'Suchen',
    ja: '検索',
  );
}

String openHandSourceLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '来源',
    zhHant: '來源',
    en: 'Source',
    fr: 'Source',
    de: 'Quelle',
    ja: 'ソース',
  );
}

String openHandSpeedLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '语速', en: 'Speed');
}

String openHandStructuredLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '结构化', en: 'Structured');
}

String openHandTaskLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '任务描述',
    zhHant: '任務描述',
    en: 'Task',
    fr: 'Tâche',
    de: 'Aufgabe',
    ja: 'タスク',
  );
}

String openHandTodayLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '今天', en: 'Today');
}

String openHandTokenBudgetLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'Token 预算',
    en: 'Token budget',
    fr: 'Budget de tokens',
    de: 'Token-Budget',
    ja: 'トークン予算',
  );
}

String openHandToolLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '工具',
    zhHant: '工具',
    en: 'Tool',
    fr: 'Outil',
    de: 'Werkzeug',
    ja: 'ツール',
  );
}

String openHandTypeLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '类型',
    zhHant: '類型',
    en: 'Type',
    fr: 'Type',
    de: 'Typ',
    ja: '種類',
  );
}

String openHandUnknownLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '未知',
    zhHant: '未知',
    en: 'Unknown',
    fr: 'Inconnu',
    de: 'Unbekannt',
    ja: '不明',
  );
}

String openHandUpdateLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '更新',
    zhHant: '更新',
    en: 'Update',
    fr: 'Mettre à jour',
    de: 'Aktualisieren',
    ja: '更新',
  );
}

String openHandVoiceLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '音色/发音人', en: 'Voice');
}

String openHandVolumeLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '音量', en: 'Volume');
}

String openHandWarningLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '警告',
    zhHant: '警告',
    en: 'Warning',
    fr: 'Avertissement',
    de: 'Warnung',
    ja: '警告',
  );
}

String openHandWorkspaceLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '工作区', en: 'Workspace');
}

String openHandYesLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '是',
    zhHant: '是',
    en: 'Yes',
    fr: 'Oui',
    de: 'Ja',
    ja: 'はい',
  );
}

String openHandProtocolLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '协议',
    zhHant: '通訊協定',
    en: 'Protocol',
    fr: 'Protocole',
    de: 'Protokoll',
    ja: 'プロトコル',
  );
}

String openHandCompletedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已完成',
    zhHant: '已完成',
    en: 'Completed',
    fr: 'Terminé',
    de: 'Abgeschlossen',
    ja: '完了',
  );
}

String openHandAgentsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '智能体',
    zhHant: '智能體',
    en: 'Agents',
    fr: 'Agents',
    de: 'Agenten',
    ja: 'エージェント',
  );
}

String openHandApiModelLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'API 模型',
    zhHant: 'API 模型',
    en: 'API Model',
    fr: 'Modèle API',
    de: 'API-Modell',
    ja: 'API モデル',
  );
}

String openHandAutoLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '自动',
    zhHant: '自動',
    en: 'Auto',
    fr: 'Auto',
    de: 'Auto',
    ja: '自動',
  );
}

String openHandAwaitingApprovalLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '等待批准',
    zhHant: '等待批准',
    en: 'Awaiting Approval',
    fr: 'En attente',
    de: 'Wartet auf Freigabe',
    ja: '承認待ち',
  );
}

String openHandBackLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '返回',
    zhHant: '返回',
    en: 'Back',
    fr: 'Retour',
    de: 'Zurück',
    ja: '戻る',
  );
}

String openHandCacheLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '缓存',
    zhHant: '快取',
    en: 'Cache',
    fr: 'Cache',
    de: 'Cache',
    ja: 'キャッシュ',
  );
}

String openHandCancelledLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已取消',
    zhHant: '已取消',
    en: 'Cancelled',
    fr: 'Annulé',
    de: 'Abgebrochen',
    ja: 'キャンセル',
  );
}

String openHandContinueLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '继续',
    zhHant: '繼續',
    en: 'Continue',
    fr: 'Continuer',
    de: 'Fortfahren',
    ja: '続行',
  );
}

String openHandCopyIdLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '复制 ID',
    zhHant: '複製 ID',
    en: 'Copy ID',
    fr: 'Copier l’ID',
    de: 'ID kopieren',
    ja: 'ID をコピー',
  );
}

String openHandCreatedAtLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '创建时间',
    zhHant: '建立時間',
    en: 'Created At',
    fr: 'Créé le',
    de: 'Erstellt am',
    ja: '作成日時',
  );
}

String openHandCustomLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '自定义',
    zhHant: '自訂',
    en: 'Custom',
    fr: 'Personnalisé',
    de: 'Benutzerdefiniert',
    ja: 'カスタム',
  );
}

String openHandDefaultAccessLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '默认权限',
    zhHant: '預設權限',
    en: 'Default Access',
    fr: 'Accès par défaut',
    de: 'Standardzugriff',
    ja: 'デフォルト権限',
  );
}

String openHandDeviceLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '设备',
    zhHant: '裝置',
    en: 'Device',
    fr: 'Appareil',
    de: 'Gerät',
    ja: 'デバイス',
  );
}

String openHandDismissLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '关闭',
    zhHant: '關閉',
    en: 'Dismiss',
    fr: 'Fermer',
    de: 'Schließen',
    ja: '閉じる',
  );
}

String openHandDoneLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已完成',
    zhHant: '已完成',
    en: 'Done',
    fr: 'Terminé',
    de: 'Fertig',
    ja: '完了',
  );
}

String openHandDurationLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '耗时',
    zhHant: '耗時',
    en: 'Duration',
    fr: 'Durée',
    de: 'Dauer',
    ja: '所要時間',
  );
}

String openHandEvidenceLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '证据',
    en: 'Evidence',
    fr: 'Preuve',
    de: 'Nachweis',
    ja: '根拠',
  );
}

String openHandExpandLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '展开',
    zhHant: '展開',
    en: 'Expand',
    fr: 'Déplier',
    de: 'Aufklappen',
    ja: '展開',
  );
}

String openHandExportCsvLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '导出 CSV',
    zhHant: '匯出 CSV',
    en: 'Export CSV',
    fr: 'Exporter CSV',
    de: 'CSV exportieren',
    ja: 'CSV をエクスポート',
  );
}

String openHandFullAccessLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '完全访问权限',
    zhHant: '完整存取權限',
    en: 'Full Access',
    fr: 'Accès complet',
    de: 'Vollzugriff',
    ja: 'フルアクセス権限',
  );
}

String openHandGenerateAiTitleLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '获取 AI 摘要标题',
    zhHant: '取得 AI 摘要標題',
    en: 'Generate AI Title',
    fr: 'Générer le titre IA',
    de: 'KI-Titel erstellen',
    ja: 'AI 要約タイトルを生成',
  );
}

String openHandTrajectoryLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '轨迹',
    zhHant: '軌跡',
    en: 'Trajectory',
    fr: 'Trajectoire',
    de: 'Verlauf',
    ja: '軌跡',
  );
}

String openHandImportLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '导入',
    zhHant: '匯入',
    en: 'Import',
    fr: 'Importer',
    de: 'Importieren',
    ja: 'インポート',
  );
}

String openHandMatchModeLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '匹配模式',
    zhHant: '匹配模式',
    en: 'Match Mode',
    fr: 'Mode de correspondance',
    de: 'Übereinstimmungsmodus',
    ja: '一致モード',
  );
}

String openHandNameLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '名称',
    zhHant: '名稱',
    en: 'Name',
    fr: 'Nom',
    de: 'Name',
    ja: '名前',
  );
}

String openHandNotCheckedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '未检测',
    zhHant: '未檢測',
    en: 'Not checked',
    fr: 'Non vérifié',
    de: 'Nicht geprüft',
    ja: '未チェック',
  );
}

String openHandNoteLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '备注',
    zhHant: '備註',
    en: 'Note',
    fr: 'Note',
    de: 'Notiz',
    ja: 'メモ',
  );
}

String openHandNotesLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '备注',
    zhHant: '備註',
    en: 'Notes',
    fr: 'Notes',
    de: 'Notizen',
    ja: 'メモ',
  );
}

String openHandOffLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '关闭',
    zhHant: '關閉',
    en: 'Off',
    fr: 'Inactif',
    de: 'Aus',
    ja: 'オフ',
  );
}

String openHandOnLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '开启',
    zhHant: '開啟',
    en: 'On',
    fr: 'Actif',
    de: 'Ein',
    ja: 'オン',
  );
}

String openHandOtherLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '其他',
    zhHant: '其他',
    en: 'Other',
    fr: 'Autres',
    de: 'Andere',
    ja: 'その他',
  );
}

String openHandPlainTextLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '纯文本',
    zhHant: '純文字',
    en: 'Plain text',
    fr: 'Texte brut',
    de: 'Nur Text',
    ja: 'プレーンテキスト',
  );
}

String openHandPluginsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '插件',
    zhHant: '外掛',
    en: 'Plugins',
    fr: 'Plugins',
    de: 'Plugins',
    ja: 'プラグイン',
  );
}

String openHandProxyLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '代理',
    zhHant: '代理',
    en: 'Proxy',
    fr: 'Proxy',
    de: 'Proxy',
    ja: 'プロキシ',
  );
}

String openHandRegenerateLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '重新生成',
    zhHant: '重新生成',
    en: 'Regenerate',
    fr: 'Régénérer',
    de: 'Neu generieren',
    ja: '再生成',
  );
}

String openHandResponseLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '响应',
    zhHant: '回應',
    en: 'Response',
    fr: 'Réponse',
    de: 'Antwort',
    ja: 'レスポンス',
  );
}

String openHandRestartLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '重启',
    zhHant: '重啟',
    en: 'Restart',
    fr: 'Redémarrer',
    de: 'Neustarten',
    ja: '再起動',
  );
}

String openHandSendingLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '发送中',
    zhHant: '傳送中',
    en: 'Sending',
    fr: 'Envoi',
    de: 'Wird gesendet',
    ja: '送信中',
  );
}

String openHandSessionIdLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '会话 ID',
    zhHant: '會話 ID',
    en: 'Session ID',
    fr: 'ID de session',
    de: 'Sitzungs-ID',
    ja: 'セッション ID',
  );
}

String openHandSessionLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '会话',
    zhHant: '會話',
    en: 'Session',
    fr: 'Session',
    de: 'Sitzung',
    ja: 'セッション',
  );
}

String openHandSkillMarketLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '技能市场',
    zhHant: '技能市場',
    en: 'Skill Market',
    fr: 'Marché des compétences',
    de: 'Skill-Markt',
    ja: 'スキルマーケット',
  );
}

String openHandStartingLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '启动中',
    zhHant: '啟動中',
    en: 'Starting',
    fr: 'Démarrage',
    de: 'Startet',
    ja: '起動中',
  );
}

String openHandStopLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '停止',
    zhHant: '停止',
    en: 'Stop',
    fr: 'Arrêter',
    de: 'Stoppen',
    ja: '停止',
  );
}

String openHandSuccessLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '成功',
    zhHant: '成功',
    en: 'Success',
    fr: 'Succès',
    de: 'Erfolg',
    ja: '成功',
  );
}

String openHandTargetUrlLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '目标 URL',
    zhHant: '目標 URL',
    en: 'Target URL',
    fr: 'URL cible',
    de: 'Ziel-URL',
    ja: '対象 URL',
  );
}

String openHandTextLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '文本',
    zhHant: '文字',
    en: 'Text',
    fr: 'Texte',
    de: 'Text',
    ja: 'テキスト',
  );
}

String openHandTimedOutLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '超时',
    zhHant: '逾時',
    en: 'Timed out',
    fr: 'Expiré',
    de: 'Zeitüberschreitung',
    ja: 'タイムアウト',
  );
}

String openHandTitleLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '标题',
    zhHant: '標題',
    en: 'Title',
    fr: 'Titre',
    de: 'Titel',
    ja: 'タイトル',
  );
}

String openHandToolResultLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '工具结果',
    zhHant: '工具結果',
    en: 'Tool Result',
    fr: 'Résultat outil',
    de: 'Tool-Ergebnis',
    ja: 'ツール結果',
  );
}

String openHandTotalTimeLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '总耗时',
    zhHant: '總耗時',
    en: 'Total time',
    fr: 'Temps total',
    de: 'Gesamtzeit',
    ja: '合計時間',
  );
}

String openHandTranslateLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '翻译',
    zhHant: '翻譯',
    en: 'Translate',
    fr: 'Traduire',
    de: 'Übersetzen',
    ja: '翻訳',
  );
}

String openHandTriggerActionsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '触发动作',
    zhHant: '觸發動作',
    en: 'Trigger Actions',
    fr: 'Actions déclencheuses',
    de: 'Auslöseaktionen',
    ja: 'トリガー操作',
  );
}

String openHandUninstallLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '卸载',
    zhHant: '解除安裝',
    en: 'Uninstall',
    fr: 'Désinstaller',
    de: 'Deinstallieren',
    ja: 'アンインストール',
  );
}

String openHandUpdatedAtLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '更新时间',
    zhHant: '更新時間',
    en: 'Updated At',
    fr: 'Mis à jour le',
    de: 'Aktualisiert am',
    ja: '更新日時',
  );
}

String openHandWorkingDirectoryLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '工作目录',
    zhHant: '工作目錄',
    en: 'Working Directory',
    fr: 'Répertoire de travail',
    de: 'Arbeitsverzeichnis',
    ja: '作業ディレクトリ',
  );
}
