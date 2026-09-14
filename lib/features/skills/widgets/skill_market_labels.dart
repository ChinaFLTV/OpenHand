import 'package:flutter/widgets.dart';

import '../../../shared/util/localized_text.dart';

typedef _SkillMarketCopy = ({
  String zh,
  String zhHant,
  String en,
  String fr,
  String de,
  String ja,
});

final RegExp _cjkPattern = RegExp(r'[\u3400-\u9FFF\uF900-\uFAFF]');
final RegExp _bilingualNamePattern = RegExp(
  r'^(.+?)\s+([A-Z][A-Z0-9][A-Z0-9 .&/+_-]{0,48})$',
);
final RegExp _latinBrandPattern = RegExp(r'^[A-Z0-9]+$');
final RegExp _slugSplitter = RegExp(r'[-_\s]+');
final RegExp _latinBrandNoise = RegExp(r'[\s.&/+_-]');

String _copy(BuildContext context, _SkillMarketCopy text) {
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

String _lookup(
  BuildContext context,
  Map<String, _SkillMarketCopy> table,
  String key, {
  String? fallbackName,
}) {
  final normalized = key.trim().toLowerCase();
  if (normalized.isEmpty) {
    return fallbackName?.trim() ?? '';
  }
  final hit = table[normalized];
  if (hit != null) {
    return _copy(context, hit);
  }
  final apiName = fallbackName?.trim() ?? '';
  if (apiName.isNotEmpty && openHandIsChineseLocale(context)) {
    return apiName;
  }
  return _humanizeKey(normalized);
}

String _humanizeKey(String key) {
  final parts = key
      .split(_slugSplitter)
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return key;
  }
  return parts
      .map((part) {
        if (part.length == 1) {
          return part.toUpperCase();
        }
        return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      })
      .join(' ');
}

bool _isLatinBrand(String value) {
  final compact = value.replaceAll(_latinBrandNoise, '');
  return compact.length >= 2 && _latinBrandPattern.hasMatch(compact);
}

/// 市场技能标题：中英并列时按当前语言只保留一侧。
String skillMarketDisplayName(BuildContext context, String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  final match = _bilingualNamePattern.firstMatch(trimmed);
  if (match == null) {
    return trimmed;
  }
  final local = match[1]!.trim();
  final latin = match[2]!.trim();
  if (!_cjkPattern.hasMatch(local) || !_isLatinBrand(latin)) {
    return trimmed;
  }
  final latinTitle = _humanizeKey(latin);
  return openHandLocalizedText(
    context,
    zh: local,
    zhHant: local,
    en: latinTitle,
    fr: latinTitle,
    de: latinTitle,
    ja: local,
  );
}

String skillMarketPublisherLabel({
  required String publisherName,
  required String ownerName,
  String ownerHandle = '',
  String slug = '',
}) {
  final publisher = publisherName.trim();
  if (publisher.isNotEmpty) {
    return publisher;
  }
  final owner = ownerName.trim();
  if (owner.isNotEmpty) {
    return owner;
  }
  final handle = ownerHandle.trim();
  if (handle.isNotEmpty) {
    return handle;
  }
  return slug.trim();
}

String skillMarketCategoryLabel(
  BuildContext context,
  String key, {
  String? fallbackName,
}) {
  return _lookup(context, _taxonomy, key, fallbackName: fallbackName);
}

String skillMarketSourceValueLabel(BuildContext context, String key) {
  return _lookup(context, _sources, key, fallbackName: key);
}

String skillMarketScannerLabel(BuildContext context, String key) {
  return _lookup(context, _scanners, key, fallbackName: key);
}

String skillMarketSecurityStatusLabel(
  BuildContext context, {
  required String status,
  required String statusText,
}) {
  final normalized = status.trim().toLowerCase();
  final mapped = _securityStatuses[normalized];
  if (mapped != null) {
    return _copy(context, mapped);
  }
  final text = statusText.trim();
  if (text.isEmpty) {
    return status.trim();
  }
  if (!openHandIsChineseLocale(context) && _cjkPattern.hasMatch(text)) {
    return _humanizeKey(normalized.isEmpty ? text : normalized);
  }
  return text;
}

String skillMarketApiKeyLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '接口密钥',
    zhHant: '介面金鑰',
    en: 'API key',
    fr: 'Clé API',
    de: 'API-Schlüssel',
    ja: 'APIキー',
  );
}

String skillMarketApiKeyRequiredLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '需要',
    zhHant: '需要',
    en: 'Required',
    fr: 'Requise',
    de: 'Erforderlich',
    ja: '必要',
  );
}

String skillMarketApiKeyOptionalLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '无需',
    zhHant: '不需要',
    en: 'Not required',
    fr: 'Non requise',
    de: 'Nicht erforderlich',
    ja: '不要',
  );
}

String skillMarketDownloadsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '下载',
    zhHant: '下載',
    en: 'Downloads',
    fr: 'Téléchargements',
    de: 'Downloads',
    ja: 'ダウンロード',
  );
}

String skillMarketInstallsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '安装',
    zhHant: '安裝',
    en: 'Installs',
    fr: 'Installations',
    de: 'Installationen',
    ja: 'インストール',
  );
}

String skillMarketStarsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '收藏',
    zhHant: '收藏',
    en: 'Stars',
    fr: 'Favoris',
    de: 'Favoriten',
    ja: 'お気に入り',
  );
}

String skillMarketFilesMoreLabel(BuildContext context, int hiddenCount) {
  return openHandLocalizedText(
    context,
    zh: '还有 $hiddenCount 个文件',
    zhHant: '還有 $hiddenCount 個檔案',
    en: '$hiddenCount more files',
    fr: '$hiddenCount fichiers de plus',
    de: '$hiddenCount weitere Dateien',
    ja: '他 $hiddenCount 件',
  );
}

const Map<String, _SkillMarketCopy> _sources = <String, _SkillMarketCopy>{
  'enterprise': (
    zh: '企业',
    zhHant: '企業',
    en: 'Enterprise',
    fr: 'Entreprise',
    de: 'Unternehmen',
    ja: 'エンタープライズ',
  ),
  'community': (
    zh: '社区',
    zhHant: '社群',
    en: 'Community',
    fr: 'Communauté',
    de: 'Community',
    ja: 'コミュニティ',
  ),
};

const Map<String, _SkillMarketCopy> _scanners = <String, _SkillMarketCopy>{
  'keen': (
    zh: 'Keen',
    zhHant: 'Keen',
    en: 'Keen',
    fr: 'Keen',
    de: 'Keen',
    ja: 'Keen',
  ),
  'sanbu': (
    zh: '三部',
    zhHant: '三部',
    en: 'Sanbu',
    fr: 'Sanbu',
    de: 'Sanbu',
    ja: '三部',
  ),
};

const Map<String, _SkillMarketCopy> _securityStatuses =
    <String, _SkillMarketCopy>{
      'benign': (
        zh: '安全，无风险',
        zhHant: '安全，無風險',
        en: 'Safe, no risk',
        fr: 'Sûr, sans risque',
        de: 'Sicher, kein Risiko',
        ja: '安全、リスクなし',
      ),
      'malicious': (
        zh: '存在风险',
        zhHant: '存在風險',
        en: 'Risky',
        fr: 'Risqué',
        de: 'Riskant',
        ja: 'リスクあり',
      ),
      'suspicious': (
        zh: '需要注意',
        zhHant: '需要注意',
        en: 'Needs review',
        fr: 'À vérifier',
        de: 'Prüfung nötig',
        ja: '要確認',
      ),
      'unknown': (
        zh: '未知',
        zhHant: '未知',
        en: 'Unknown',
        fr: 'Inconnu',
        de: 'Unbekannt',
        ja: '不明',
      ),
    };

const Map<String, _SkillMarketCopy> _taxonomy = <String, _SkillMarketCopy>{
  'pay-skill': (
    zh: '付费技能',
    zhHant: '付費技能',
    en: 'Paid skill',
    fr: 'Compétence payante',
    de: 'Bezahlter Skill',
    ja: '有料スキル',
  ),
  'office-efficiency': (
    zh: '办公效率',
    zhHant: '辦公效率',
    en: 'Office efficiency',
    fr: 'Productivité',
    de: 'Büroeffizienz',
    ja: '業務効率',
  ),
  'content-creation': (
    zh: '内容创作',
    zhHant: '內容創作',
    en: 'Content creation',
    fr: 'Création de contenu',
    de: 'Content-Erstellung',
    ja: 'コンテンツ制作',
  ),
  'dev-programming': (
    zh: '开发编程',
    zhHant: '開發程式',
    en: 'Development',
    fr: 'Développement',
    de: 'Entwicklung',
    ja: '開発',
  ),
  'data-analysis': (
    zh: '数据分析',
    zhHant: '資料分析',
    en: 'Data analysis',
    fr: 'Analyse de données',
    de: 'Datenanalyse',
    ja: 'データ分析',
  ),
  'design-media': (
    zh: '设计多媒体',
    zhHant: '設計多媒體',
    en: 'Design & media',
    fr: 'Design et médias',
    de: 'Design & Medien',
    ja: 'デザインとメディア',
  ),
  'ai-agent': (
    zh: '智能体',
    zhHant: '智慧體',
    en: 'AI agent',
    fr: 'Agent IA',
    de: 'KI-Agent',
    ja: 'AIエージェント',
  ),
  'knowledge-management': (
    zh: '知识管理',
    zhHant: '知識管理',
    en: 'Knowledge management',
    fr: 'Gestion des connaissances',
    de: 'Wissensmanagement',
    ja: 'ナレッジ管理',
  ),
  'business-ops': (
    zh: '商业运营',
    zhHant: '商業營運',
    en: 'Business operations',
    fr: 'Opérations business',
    de: 'Geschäftsprozesse',
    ja: 'ビジネス運営',
  ),
  'education': (
    zh: '教育学习',
    zhHant: '教育學習',
    en: 'Education',
    fr: 'Éducation',
    de: 'Bildung',
    ja: '教育',
  ),
  'professional': (
    zh: '行业专业',
    zhHant: '行業專業',
    en: 'Professional',
    fr: 'Métier',
    de: 'Branche',
    ja: '専門領域',
  ),
  'it-ops-security': (
    zh: 'IT 运维与安全',
    zhHant: 'IT 維運與安全',
    en: 'IT ops & security',
    fr: 'IT et sécurité',
    de: 'IT-Betrieb & Sicherheit',
    ja: 'IT運用とセキュリティ',
  ),
  'life-service': (
    zh: '生活服务',
    zhHant: '生活服務',
    en: 'Life services',
    fr: 'Services du quotidien',
    de: 'Alltagsservices',
    ja: '生活サービス',
  ),
  'agent-context': (
    zh: '上下文管理',
    zhHant: '上下文管理',
    en: 'Context management',
    fr: 'Gestion du contexte',
    de: 'Kontextverwaltung',
    ja: 'コンテキスト管理',
  ),
  'agent-framework': (
    zh: '智能体框架',
    zhHant: '智慧體框架',
    en: 'Agent framework',
    fr: 'Cadre d’agent',
    de: 'Agent-Framework',
    ja: 'エージェント枠組み',
  ),
  'agent-memory': (
    zh: '记忆增强',
    zhHant: '記憶增強',
    en: 'Memory boost',
    fr: 'Mémoire enrichie',
    de: 'Gedächtniserweiterung',
    ja: '記憶強化',
  ),
  'agent-multi-agent': (
    zh: '多智能体协作',
    zhHant: '多智慧體協作',
    en: 'Multi-agent collaboration',
    fr: 'Collaboration multi-agents',
    de: 'Multi-Agent-Kollaboration',
    ja: 'マルチエージェント協調',
  ),
  'agent-prompt': (
    zh: '提示词优化',
    zhHant: '提示詞優化',
    en: 'Prompt tuning',
    fr: 'Optimisation de prompt',
    de: 'Prompt-Optimierung',
    ja: 'プロンプト最適化',
  ),
  'agent-task-automation': (
    zh: '任务自动化',
    zhHant: '任務自動化',
    en: 'Task automation',
    fr: 'Automatisation des tâches',
    de: 'Aufgabenautomatisierung',
    ja: 'タスク自動化',
  ),
  'agent-tool-use': (
    zh: '工具调用',
    zhHant: '工具呼叫',
    en: 'Tool use',
    fr: 'Utilisation d’outils',
    de: 'Werkzeugnutzung',
    ja: 'ツール呼び出し',
  ),
  'agent-workflow': (
    zh: '工作流编排',
    zhHant: '工作流編排',
    en: 'Workflow orchestration',
    fr: 'Orchestration de workflow',
    de: 'Workflow-Orchestrierung',
    ja: 'ワークフロー編成',
  ),
  'biz-crm': (
    zh: '客户管理',
    zhHant: '客戶管理',
    en: 'CRM',
    fr: 'CRM',
    de: 'CRM',
    ja: '顧客管理',
  ),
  'biz-customer-service': (
    zh: '客服助手',
    zhHant: '客服助手',
    en: 'Customer service',
    fr: 'Service client',
    de: 'Kundenservice',
    ja: 'カスタマーサポート',
  ),
  'biz-ecommerce': (
    zh: '电商运营',
    zhHant: '電商營運',
    en: 'E-commerce',
    fr: 'E-commerce',
    de: 'E-Commerce',
    ja: 'EC運営',
  ),
  'biz-growth': (
    zh: '增长分析',
    zhHant: '成長分析',
    en: 'Growth analysis',
    fr: 'Analyse de croissance',
    de: 'Wachstumsanalyse',
    ja: '成長分析',
  ),
  'biz-project-management': (
    zh: '项目管理',
    zhHant: '專案管理',
    en: 'Project management',
    fr: 'Gestion de projet',
    de: 'Projektmanagement',
    ja: 'プロジェクト管理',
  ),
  'biz-sales': (
    zh: '销售助手',
    zhHant: '銷售助手',
    en: 'Sales assistant',
    fr: 'Assistant commercial',
    de: 'Vertriebsassistent',
    ja: '営業アシスタント',
  ),
  'biz-sop': (
    zh: '流程生成',
    zhHant: '流程產生',
    en: 'SOP generation',
    fr: 'Génération de SOP',
    de: 'SOP-Erstellung',
    ja: 'SOP生成',
  ),
  'biz-user-ops': (
    zh: '用户运营',
    zhHant: '用戶營運',
    en: 'User operations',
    fr: 'Opérations utilisateurs',
    de: 'Nutzerbetrieb',
    ja: 'ユーザー運営',
  ),
  'content-article': (
    zh: '文章写作',
    zhHant: '文章寫作',
    en: 'Article writing',
    fr: 'Rédaction d’articles',
    de: 'Artikel schreiben',
    ja: '記事作成',
  ),
  'content-marketing-copy': (
    zh: '营销文案',
    zhHant: '行銷文案',
    en: 'Marketing copy',
    fr: 'Textes marketing',
    de: 'Marketingtexte',
    ja: 'マーケティング文案',
  ),
  'content-rewrite': (
    zh: '内容改写',
    zhHant: '內容改寫',
    en: 'Rewriting',
    fr: 'Réécriture',
    de: 'Umschreiben',
    ja: 'リライト',
  ),
  'content-short-video-script': (
    zh: '短视频脚本',
    zhHant: '短影片腳本',
    en: 'Short-video scripts',
    fr: 'Scripts courte vidéo',
    de: 'Kurzvideo-Skripte',
    ja: 'ショート動画脚本',
  ),
  'content-social-media': (
    zh: '自媒体运营',
    zhHant: '自媒體營運',
    en: 'Social media',
    fr: 'Réseaux sociaux',
    de: 'Social Media',
    ja: 'SNS運営',
  ),
  'content-title': (
    zh: '标题生成',
    zhHant: '標題產生',
    en: 'Title generation',
    fr: 'Génération de titres',
    de: 'Titelgenerierung',
    ja: 'タイトル生成',
  ),
  'content-topic-planning': (
    zh: '选题策划',
    zhHant: '選題策劃',
    en: 'Topic planning',
    fr: 'Planification de sujets',
    de: 'Themenplanung',
    ja: '企画立案',
  ),
  'data-competitor': (
    zh: '竞品分析',
    zhHant: '競品分析',
    en: 'Competitor analysis',
    fr: 'Analyse concurrentielle',
    de: 'Wettbewerbsanalyse',
    ja: '競合分析',
  ),
  'data-insight': (
    zh: '数据洞察',
    zhHant: '資料洞察',
    en: 'Data insights',
    fr: 'Insights data',
    de: 'Dateninsights',
    ja: 'データ洞察',
  ),
  'data-metrics-monitoring': (
    zh: '指标监控',
    zhHant: '指標監控',
    en: 'Metrics monitoring',
    fr: 'Suivi des métriques',
    de: 'Kennzahlenüberwachung',
    ja: '指標監視',
  ),
  'data-report': (
    zh: '报表生成',
    zhHant: '報表產生',
    en: 'Report generation',
    fr: 'Génération de rapports',
    de: 'Berichterstellung',
    ja: 'レポート生成',
  ),
  'data-user-analysis': (
    zh: '用户分析',
    zhHant: '用戶分析',
    en: 'User analysis',
    fr: 'Analyse utilisateurs',
    de: 'Nutzeranalyse',
    ja: 'ユーザー分析',
  ),
  'data-visualization': (
    zh: '数据可视化',
    zhHant: '資料視覺化',
    en: 'Data visualization',
    fr: 'Visualisation de données',
    de: 'Datenvisualisierung',
    ja: 'データ可視化',
  ),
  'data-web-scraping': (
    zh: '网页抓取',
    zhHant: '網頁擷取',
    en: 'Web scraping',
    fr: 'Collecte web',
    de: 'Web-Scraping',
    ja: 'ウェブ収集',
  ),
  'design-audio': (
    zh: '音频处理',
    zhHant: '音訊處理',
    en: 'Audio processing',
    fr: 'Traitement audio',
    de: 'Audioverarbeitung',
    ja: '音声処理',
  ),
  'design-brand': (
    zh: '品牌设计',
    zhHant: '品牌設計',
    en: 'Brand design',
    fr: 'Design de marque',
    de: 'Markendesign',
    ja: 'ブランドデザイン',
  ),
  'design-image-edit': (
    zh: '图片编辑',
    zhHant: '圖片編輯',
    en: 'Image editing',
    fr: 'Retouche d’image',
    de: 'Bildbearbeitung',
    ja: '画像編集',
  ),
  'design-image-gen': (
    zh: '图片生成',
    zhHant: '圖片產生',
    en: 'Image generation',
    fr: 'Génération d’images',
    de: 'Bildgenerierung',
    ja: '画像生成',
  ),
  'design-poster': (
    zh: '海报设计',
    zhHant: '海報設計',
    en: 'Poster design',
    fr: 'Design d’affiche',
    de: 'Posterdesign',
    ja: 'ポスターデザイン',
  ),
  'design-ui': (
    zh: '界面设计',
    zhHant: '介面設計',
    en: 'UI design',
    fr: 'Design d’interface',
    de: 'UI-Design',
    ja: 'UIデザイン',
  ),
  'design-video': (
    zh: '视频处理',
    zhHant: '影片處理',
    en: 'Video processing',
    fr: 'Traitement vidéo',
    de: 'Videoverarbeitung',
    ja: '動画処理',
  ),
  'design-visual-asset': (
    zh: '视觉素材',
    zhHant: '視覺素材',
    en: 'Visual assets',
    fr: 'Assets visuels',
    de: 'Bildmaterial',
    ja: 'ビジュアル素材',
  ),
  'dev-backend': (
    zh: '后端开发',
    zhHant: '後端開發',
    en: 'Backend',
    fr: 'Backend',
    de: 'Backend',
    ja: 'バックエンド',
  ),
  'dev-bug-fix': (
    zh: '缺陷修复',
    zhHant: '缺陷修復',
    en: 'Bug fixing',
    fr: 'Correction de bugs',
    de: 'Fehlerbehebung',
    ja: '不具合修正',
  ),
  'dev-code-gen': (
    zh: '代码生成',
    zhHant: '程式產生',
    en: 'Code generation',
    fr: 'Génération de code',
    de: 'Codegenerierung',
    ja: 'コード生成',
  ),
  'dev-code-review': (
    zh: '代码审查',
    zhHant: '程式審查',
    en: 'Code review',
    fr: 'Revue de code',
    de: 'Code-Review',
    ja: 'コードレビュー',
  ),
  'dev-frontend': (
    zh: '前端开发',
    zhHant: '前端開發',
    en: 'Frontend',
    fr: 'Frontend',
    de: 'Frontend',
    ja: 'フロントエンド',
  ),
  'dev-git': (
    zh: '版本协作',
    zhHant: '版本協作',
    en: 'Git assistant',
    fr: 'Assistant Git',
    de: 'Git-Assistent',
    ja: 'Git補助',
  ),
  'dev-script': (
    zh: '脚本工具',
    zhHant: '指令稿工具',
    en: 'Scripting tools',
    fr: 'Outils de script',
    de: 'Skriptwerkzeuge',
    ja: 'スクリプトツール',
  ),
  'edu-course-design': (
    zh: '课程设计',
    zhHant: '課程設計',
    en: 'Course design',
    fr: 'Conception de cours',
    de: 'Kursdesign',
    ja: 'コース設計',
  ),
  'edu-explanation': (
    zh: '知识讲解',
    zhHant: '知識講解',
    en: 'Explanations',
    fr: 'Explications',
    de: 'Erklärungen',
    ja: '解説',
  ),
  'edu-grading': (
    zh: '作业批改',
    zhHant: '作業批改',
    en: 'Grading',
    fr: 'Correction',
    de: 'Bewertung',
    ja: '採点',
  ),
  'edu-question-gen': (
    zh: '题目生成',
    zhHant: '題目產生',
    en: 'Question generation',
    fr: 'Génération de questions',
    de: 'Fragengenerierung',
    ja: '問題生成',
  ),
  'edu-teaching-aid': (
    zh: '教学辅助',
    zhHant: '教學輔助',
    en: 'Teaching aids',
    fr: 'Aide pédagogique',
    de: 'Unterrichtshilfen',
    ja: '授業補助',
  ),
  'edu-tutoring': (
    zh: '学习辅导',
    zhHant: '學習輔導',
    en: 'Tutoring',
    fr: 'Tutorat',
    de: 'Nachhilfe',
    ja: '学習指導',
  ),
  'itops-config': (
    zh: '配置生成',
    zhHant: '設定產生',
    en: 'Config generation',
    fr: 'Génération de config',
    de: 'Konfigurationserstellung',
    ja: '設定生成',
  ),
  'itops-devops': (
    zh: '持续交付',
    zhHant: '持續交付',
    en: 'DevOps',
    fr: 'DevOps',
    de: 'DevOps',
    ja: 'DevOps',
  ),
  'itops-security-scan': (
    zh: '安全扫描',
    zhHant: '安全掃描',
    en: 'Security scanning',
    fr: 'Analyse de sécurité',
    de: 'Sicherheitsprüfung',
    ja: 'セキュリティスキャン',
  ),
  'itops-server': (
    zh: '服务器运维',
    zhHant: '伺服器維運',
    en: 'Server ops',
    fr: 'Exploitation serveur',
    de: 'Serverbetrieb',
    ja: 'サーバー運用',
  ),
  'itops-troubleshooting': (
    zh: '故障排查',
    zhHant: '故障排查',
    en: 'Troubleshooting',
    fr: 'Dépannage',
    de: 'Fehlerdiagnose',
    ja: '障害切り分け',
  ),
  'knowledge-base-qa': (
    zh: '知识库问答',
    zhHant: '知識庫問答',
    en: 'Knowledge Q&A',
    fr: 'Q&R base de connaissances',
    de: 'Wissens-Q&A',
    ja: 'ナレッジQ&A',
  ),
  'knowledge-doc-qa': (
    zh: '文档问答',
    zhHant: '文件問答',
    en: 'Document Q&A',
    fr: 'Q&R documentaire',
    de: 'Dokumenten-Q&A',
    ja: '文書Q&A',
  ),
  'knowledge-notes': (
    zh: '笔记整理',
    zhHant: '筆記整理',
    en: 'Note organization',
    fr: 'Organisation de notes',
    de: 'Notizorganisation',
    ja: 'ノート整理',
  ),
  'knowledge-organize': (
    zh: '资料整理',
    zhHant: '資料整理',
    en: 'Material organization',
    fr: 'Organisation des documents',
    de: 'Materialorganisation',
    ja: '資料整理',
  ),
  'knowledge-retrieval': (
    zh: '信息检索',
    zhHant: '資訊檢索',
    en: 'Information retrieval',
    fr: 'Recherche d’information',
    de: 'Informationssuche',
    ja: '情報検索',
  ),
  'knowledge-summary': (
    zh: '摘要总结',
    zhHant: '摘要總結',
    en: 'Summarization',
    fr: 'Synthèse',
    de: 'Zusammenfassung',
    ja: '要約',
  ),
  'life-consumption': (
    zh: '消费决策',
    zhHant: '消費決策',
    en: 'Purchase decisions',
    fr: 'Décisions d’achat',
    de: 'Kaufentscheidungen',
    ja: '消費判断',
  ),
  'life-family': (
    zh: '家庭助手',
    zhHant: '家庭助手',
    en: 'Family assistant',
    fr: 'Assistant familial',
    de: 'Familienassistent',
    ja: '家庭アシスタント',
  ),
  'life-travel': (
    zh: '旅行规划',
    zhHant: '旅行規劃',
    en: 'Travel planning',
    fr: 'Planification de voyage',
    de: 'Reiseplanung',
    ja: '旅行計画',
  ),
  'office-automation': (
    zh: '流程自动化',
    zhHant: '流程自動化',
    en: 'Process automation',
    fr: 'Automatisation des processus',
    de: 'Prozessautomatisierung',
    ja: '業務自動化',
  ),
  'office-doc': (
    zh: '文档处理',
    zhHant: '文件處理',
    en: 'Document processing',
    fr: 'Traitement de documents',
    de: 'Dokumentverarbeitung',
    ja: '文書処理',
  ),
  'office-email': (
    zh: '邮件处理',
    zhHant: '郵件處理',
    en: 'Email processing',
    fr: 'Traitement d’e-mails',
    de: 'E-Mail-Verarbeitung',
    ja: 'メール処理',
  ),
  'office-meeting-notes': (
    zh: '会议纪要',
    zhHant: '會議紀要',
    en: 'Meeting notes',
    fr: 'Comptes rendus',
    de: 'Besprechungsnotizen',
    ja: '議事録',
  ),
  'office-pdf': (
    zh: 'PDF 处理',
    zhHant: 'PDF 處理',
    en: 'PDF processing',
    fr: 'Traitement PDF',
    de: 'PDF-Verarbeitung',
    ja: 'PDF処理',
  ),
  'office-ppt': (
    zh: '幻灯片生成',
    zhHant: '投影片產生',
    en: 'Slide generation',
    fr: 'Génération de diapositives',
    de: 'Folien generieren',
    ja: 'スライド生成',
  ),
  'office-report': (
    zh: '日报周报',
    zhHant: '日報週報',
    en: 'Status reports',
    fr: 'Rapports d’activité',
    de: 'Statusberichte',
    ja: '日報・週報',
  ),
  'office-spreadsheet': (
    zh: '表格处理',
    zhHant: '試算表處理',
    en: 'Spreadsheet processing',
    fr: 'Tableurs',
    de: 'Tabellenverarbeitung',
    ja: '表計算',
  ),
  'pro-finance': (
    zh: '金融分析',
    zhHant: '金融分析',
    en: 'Financial analysis',
    fr: 'Analyse financière',
    de: 'Finanzanalyse',
    ja: '金融分析',
  ),
  'pro-government': (
    zh: '政务服务',
    zhHant: '政務服務',
    en: 'Government services',
    fr: 'Services publics',
    de: 'Behördenservices',
    ja: '行政サービス',
  ),
  'pro-industry-research': (
    zh: '行业研究',
    zhHant: '行業研究',
    en: 'Industry research',
    fr: 'Études sectorielles',
    de: 'Branchenforschung',
    ja: '業界調査',
  ),
  'pro-legal': (
    zh: '法律合规',
    zhHant: '法律合規',
    en: 'Legal & compliance',
    fr: 'Juridique et conformité',
    de: 'Recht & Compliance',
    ja: '法務コンプライアンス',
  ),
  'pro-research': (
    zh: '科研学术',
    zhHant: '科研學術',
    en: 'Academic research',
    fr: 'Recherche académique',
    de: 'Wissenschaft',
    ja: '学術研究',
  ),
  'pro-risk-control': (
    zh: '风险风控',
    zhHant: '風險風控',
    en: 'Risk control',
    fr: 'Contrôle des risques',
    de: 'Risikokontrolle',
    ja: 'リスク管理',
  ),
  'pro-tax-accounting': (
    zh: '财税处理',
    zhHant: '財稅處理',
    en: 'Tax & accounting',
    fr: 'Fiscalité et comptabilité',
    de: 'Steuern & Buchhaltung',
    ja: '税務会計',
  ),
};
