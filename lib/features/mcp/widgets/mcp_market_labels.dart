import 'package:flutter/widgets.dart';

import '../../../shared/util/localized_text.dart';
import '../../../shared/util/text_normalization.dart';
import '../model/mcp_market.dart';

typedef _McpMarketCopy = ({
  String zh,
  String zhHant,
  String en,
  String fr,
  String de,
  String ja,
});

final RegExp _cjkPattern = RegExp(r'[\u3400-\u9FFF\uF900-\uFAFF]');

String _copy(BuildContext context, _McpMarketCopy text) {
  return openHandLocalizedText(
    context,
    zh: text.zh,
    zhHant: text.zhHant,
    en: text.en,
    fr: text.fr,
    de: text.de,
    ja: text.ja,
  );
}

String mcpMarketSummary(BuildContext context, McpMarketServer server) {
  final zh = server.summaryZh.trim().isNotEmpty
      ? server.summaryZh.trim()
      : server.summary.trim();
  final latinCandidates = <String>[
    server.summary.trim(),
    server.summaryZh.trim(),
  ];
  final latin = latinCandidates.firstWhere(
    (text) => text.isNotEmpty && !_cjkPattern.hasMatch(text),
    orElse: () => '',
  );
  final language = Localizations.localeOf(context).languageCode.toLowerCase();
  if (language == 'zh' || language == 'ja') {
    return zh;
  }
  return latin.isNotEmpty ? latin : zh;
}

String mcpMarketCategoryLabel(BuildContext context, String key) {
  final normalized = key.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }
  final hit = _categories[normalized];
  if (hit != null) {
    return _copy(context, hit);
  }
  if (Localizations.localeOf(context).languageCode.toLowerCase() == 'en' &&
      !_cjkPattern.hasMatch(key) &&
      kLabelKeySeparatorPattern.hasMatch(normalized)) {
    return humanizeLabelKey(normalized);
  }
  return key.trim();
}

String mcpMarketTypeLabel(BuildContext context) {
  return _copy(context, (
    zh: 'MCP 服务',
    zhHant: 'MCP 服務',
    en: 'MCP service',
    fr: 'Service MCP',
    de: 'MCP-Dienst',
    ja: 'MCPサービス',
  ));
}

String mcpMarketUnavailableLabel(BuildContext context) {
  return _copy(context, (
    zh: '暂不可添加',
    zhHant: '暫不可新增',
    en: 'Unavailable',
    fr: 'Indisponible',
    de: 'Nicht verfügbar',
    ja: '追加できません',
  ));
}

String mcpMarketDownloadsLabel(BuildContext context) {
  return _copy(context, (
    zh: '下载',
    zhHant: '下載',
    en: 'Downloads',
    fr: 'Téléchargements',
    de: 'Downloads',
    ja: 'ダウンロード',
  ));
}

String mcpMarketInstallsLabel(BuildContext context) {
  return _copy(context, (
    zh: '安装',
    zhHant: '安裝',
    en: 'Installs',
    fr: 'Installations',
    de: 'Installationen',
    ja: 'インストール',
  ));
}

const Map<String, _McpMarketCopy> _categories = <String, _McpMarketCopy>{
  '腾讯产品mcp': (
    zh: '腾讯产品 MCP',
    zhHant: '騰訊產品 MCP',
    en: 'Tencent MCP',
    fr: 'MCP Tencent',
    de: 'Tencent-MCP',
    ja: 'テンセント MCP',
  ),
  '搜索与信息检索': (
    zh: '搜索与信息检索',
    zhHant: '搜尋與資訊檢索',
    en: 'Search & retrieval',
    fr: 'Recherche et information',
    de: 'Suche & Abruf',
    ja: '検索と情報取得',
  ),
  '开发者工具': (
    zh: '开发者工具',
    zhHant: '開發者工具',
    en: 'Developer tools',
    fr: 'Outils développeur',
    de: 'Entwicklertools',
    ja: '開発者ツール',
  ),
  '文档工具': (
    zh: '文档工具',
    zhHant: '文件工具',
    en: 'Document tools',
    fr: 'Outils documentaires',
    de: 'Dokumentwerkzeuge',
    ja: 'ドキュメントツール',
  ),
  '支付与交易': (
    zh: '支付与交易',
    zhHant: '支付與交易',
    en: 'Payments',
    fr: 'Paiements',
    de: 'Zahlungen',
    ja: '決済と取引',
  ),
  '数据库与文件': (
    zh: '数据库与文件',
    zhHant: '資料庫與檔案',
    en: 'Database & files',
    fr: 'Bases et fichiers',
    de: 'Datenbank & Dateien',
    ja: 'データベースとファイル',
  ),
  '位置服务': (
    zh: '位置服务',
    zhHant: '位置服務',
    en: 'Location',
    fr: 'Localisation',
    de: 'Standort',
    ja: '位置情報',
  ),
  '内容抓取': (
    zh: '内容抓取',
    zhHant: '內容擷取',
    en: 'Content crawling',
    fr: 'Collecte de contenu',
    de: 'Inhaltserfassung',
    ja: 'コンテンツ収集',
  ),
  '浏览器自动化': (
    zh: '浏览器自动化',
    zhHant: '瀏覽器自動化',
    en: 'Browser automation',
    fr: 'Automatisation navigateur',
    de: 'Browser-Automatisierung',
    ja: 'ブラウザ自動化',
  ),
  '社交媒体': (
    zh: '社交媒体',
    zhHant: '社群媒體',
    en: 'Social media',
    fr: 'Réseaux sociaux',
    de: 'Social Media',
    ja: 'ソーシャルメディア',
  ),
  '设计与创意': (
    zh: '设计与创意',
    zhHant: '設計與創意',
    en: 'Design & creativity',
    fr: 'Design et création',
    de: 'Design & Kreativität',
    ja: 'デザインとクリエイティブ',
  ),
};
