import '../../model/ai_thread_template_icon_names.dart';

class AiPromptSharedSectionSpec {
  const AiPromptSharedSectionSpec({required this.tag, required this.assetPath});

  final String tag;
  final String assetPath;
}

class AiPromptLoadedSection {
  const AiPromptLoadedSection({required this.tag, required this.content});

  final String tag;
  final String content;
}

class AiPromptTemplateAssetFiles {
  const AiPromptTemplateAssetFiles._();

  static const String systemInstructions = 'system_instructions.md';
  static const String developerInstructions = 'developer_instructions.md';
  static const String compressionSummaryInstructions =
      'compression_summary_instructions.md';
}

enum AiPromptToolCatalogProfile {
  generic,
  machineExpert,
  webReverse,
  androidReverse,
}

enum AiPromptCompressionPayloadStyle { standard, minimal }

class AiPromptTemplatePolicy {
  const AiPromptTemplatePolicy({
    required this.templateId,
    required this.promptAssetDirectory,
    required this.toolCatalogProfile,
    required this.extensionSections,
    required this.compressionIdentity,
    this.sharedSections = _baselinePromptSharedSections,
    this.promptAssetFileOverrides = const <String, String>{},
    this.compressionPayloadStyle = AiPromptCompressionPayloadStyle.standard,
    this.includesWebReverseRuntime = false,
  });

  final String templateId;
  final String promptAssetDirectory;
  final AiPromptToolCatalogProfile toolCatalogProfile;
  final List<AiPromptSharedSectionSpec> sharedSections;
  final List<AiPromptSharedSectionSpec> extensionSections;
  final String compressionIdentity;
  final Map<String, String> promptAssetFileOverrides;
  final AiPromptCompressionPayloadStyle compressionPayloadStyle;
  final bool includesWebReverseRuntime;

  String promptAssetPathFor(String fileName) {
    return promptAssetFileOverrides[fileName] ??
        '$promptAssetDirectory/$fileName';
  }

  bool get usesMinimalCompressionPayload =>
      compressionPayloadStyle == AiPromptCompressionPayloadStyle.minimal;

  bool get usesMachineToolCatalog =>
      toolCatalogProfile == AiPromptToolCatalogProfile.machineExpert;

  bool get usesWebReverseToolCatalog =>
      toolCatalogProfile == AiPromptToolCatalogProfile.webReverse;

  bool get usesAndroidReverseToolCatalog =>
      toolCatalogProfile == AiPromptToolCatalogProfile.androidReverse;
}

enum AiPromptTemplateAvailabilityScope { all, appleOnly }

class AiPromptTemplateInfo {
  const AiPromptTemplateInfo({
    required this.id,
    required this.name,
    required this.iconName,
    required this.description,
    required this.internalVersion,
    required this.promptAssetDirectory,
    this.nameZhHant,
    this.nameEn,
    this.nameFr,
    this.nameDe,
    this.nameJa,
    this.descriptionZhHant,
    this.descriptionEn,
    this.descriptionFr,
    this.descriptionDe,
    this.descriptionJa,
    this.availability = AiPromptTemplateAvailabilityScope.all,
  });

  final String id;
  final String name;
  final String iconName;
  final String description;
  final String? nameZhHant;
  final String? nameEn;
  final String? nameFr;
  final String? nameDe;
  final String? nameJa;
  final String? descriptionZhHant;
  final String? descriptionEn;
  final String? descriptionFr;
  final String? descriptionDe;
  final String? descriptionJa;
  final String internalVersion;
  final String promptAssetDirectory;
  final AiPromptTemplateAvailabilityScope availability;

  String nameForLocale(Object locale) => _templateTextForLocale(
    locale,
    zh: name,
    zhHant: nameZhHant,
    en: nameEn ?? name,
    fr: nameFr,
    de: nameDe,
    ja: nameJa,
  );

  String descriptionForLocale(Object locale) => _templateTextForLocale(
    locale,
    zh: description,
    zhHant: descriptionZhHant,
    en: descriptionEn ?? description,
    fr: descriptionFr,
    de: descriptionDe,
    ja: descriptionJa,
  );
}

String _templateTextForLocale(
  Object locale, {
  required String zh,
  required String en,
  String? zhHans,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  final (:languageCode, :scriptCode) = _localeParts(locale);
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

({String languageCode, String? scriptCode}) _localeParts(Object locale) {
  try {
    final dynamic value = locale;
    final languageCode = '${value.languageCode}'.toLowerCase();
    final script = value.scriptCode;
    return (
      languageCode: languageCode,
      scriptCode: script == null ? null : '$script'.toLowerCase(),
    );
  } catch (_) {
    return (languageCode: 'en', scriptCode: null);
  }
}

class AiPromptTemplateCatalogEntry {
  const AiPromptTemplateCatalogEntry({
    required this.info,
    required this.policy,
  });

  final AiPromptTemplateInfo info;
  final AiPromptTemplatePolicy policy;

  String get id => policy.templateId;

  bool get isConsistent =>
      info.id == policy.templateId &&
      info.promptAssetDirectory == policy.promptAssetDirectory;
}

class AiPromptTemplatePolicies {
  const AiPromptTemplatePolicies._();

  static const String defaultTemplateId = 'default';
  static const String machineExpertTemplateId = 'machine_expert';
  static const String harnessEngineeringTemplateId = 'harness_engineering';
  static const String programmingExpertTemplateId = 'programming_expert';
  static const String hermesTalkerTemplateId = 'hermes_talker';
  static const String webReverseExpertTemplateId = 'web_reverse_expert';
  static const String androidReverseExpertTemplateId = 'android_reverse_expert';
  static const String siriHelperTemplateId = 'siri_helper';

  static const String defaultPromptAssetDirectory = 'assets/prompts/default';
  static const String machineExpertPromptAssetDirectory =
      'assets/prompts/machine_expert';
  static const String harnessEngineeringPromptAssetDirectory =
      'assets/prompts/harness_engineering';
  static const String programmingExpertPromptAssetDirectory =
      'assets/prompts/programming_expert';
  static const String hermesTalkerPromptAssetDirectory =
      'assets/prompts/hermes_talker';
  static const String webReverseExpertPromptAssetDirectory =
      'assets/prompts/web_reverse_expert';
  static const String androidReverseExpertPromptAssetDirectory =
      'assets/prompts/android_reverse_expert';
  static const String siriHelperPromptAssetDirectory =
      'assets/prompts/siri_helper';

  static const List<AiPromptTemplateCatalogEntry>
  entries = <AiPromptTemplateCatalogEntry>[
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: defaultTemplateId,
        name: '默认助手',
        nameZhHant: '預設助手',
        nameEn: 'Default Assistant',
        nameFr: 'Assistant par défaut',
        nameDe: 'Standardassistent',
        nameJa: 'デフォルトアシスタント',
        iconName: AiThreadTemplateIconNames.autoAwesomeRounded,
        description: 'Claude Code 风格的通用模板，适合工具辅助工作、MCP 使用与本地技能激活。',
        descriptionZhHant: 'Claude Code 風格的通用模板，適合工具輔助工作、MCP 使用與本地技能啟用。',
        descriptionEn:
            'A Claude Code style general-purpose template for tool-assisted work, MCP usage, and local skill activation.',
        descriptionFr:
            'Modèle général de style Claude Code pour le travail assisté par outils, MCP et les compétences locales.',
        descriptionDe:
            'Allgemeine Vorlage im Claude-Code-Stil für toolgestützte Arbeit, MCP und lokale Skills.',
        descriptionJa: 'Claude Code 風の汎用テンプレート。ツール支援作業、MCP、ローカルスキルの利用に適しています。',
        internalVersion: '3.0.0',
        promptAssetDirectory: defaultPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: defaultTemplateId,
        promptAssetDirectory: defaultPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.generic,
        extensionSections: <AiPromptSharedSectionSpec>[],
        compressionIdentity:
            'You are OpenHand. Produce a relay-safe conversation checkpoint.',
      ),
    ),
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: machineExpertTemplateId,
        name: '机器专家',
        nameZhHant: '機器專家',
        nameEn: 'Machine Expert',
        nameFr: 'Expert machine',
        nameDe: 'Maschinenexperte',
        nameJa: 'マシンエキスパート',
        iconName: AiThreadTemplateIconNames.buildCircleRounded,
        description: '主要是通过本地终端程序去与目标机器交互，完成用户提出的任务或需求。',
        descriptionZhHant: '主要透過本地終端程式與目標機器互動，完成使用者提出的任務或需求。',
        descriptionEn:
            'Uses the local terminal to interact with the target machine and complete the user’s task.',
        descriptionFr:
            'Utilise le terminal local pour interagir avec la machine cible et accomplir la tâche.',
        descriptionDe:
            'Nutzt das lokale Terminal, um mit der Zielmaschine zu arbeiten und die Aufgabe zu erledigen.',
        descriptionJa: 'ローカル端末で対象マシンとやり取りし、ユーザーのタスクを完了します。',
        internalVersion: '1.1.0',
        promptAssetDirectory: machineExpertPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: machineExpertTemplateId,
        promptAssetDirectory: machineExpertPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.machineExpert,
        extensionSections: <AiPromptSharedSectionSpec>[],
        compressionIdentity:
            'You are OpenHand Machine Expert. Produce a relay-safe terminal interaction checkpoint.',
      ),
    ),
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: harnessEngineeringTemplateId,
        name: 'Harness Engineering',
        nameZhHant: 'Harness Engineering',
        nameEn: 'Harness Engineering',
        nameFr: 'Harness Engineering',
        nameDe: 'Harness Engineering',
        nameJa: 'Harness Engineering',
        iconName: AiThreadTemplateIconNames.hubRounded,
        description:
            '多角色编排协调模式。OpenHand 作为 OS 层统一编排，将编码任务委托给用户配置的 CLI 工具（调查者→规划者→实施者→验收者），并管理结构化持久化上下文。',
        descriptionZhHant:
            '多角色編排協調模式。OpenHand 作為 OS 層統一編排，將編碼任務委託給使用者配置的 CLI 工具（調查者→規劃者→實施者→驗收者），並管理結構化持久化上下文。',
        descriptionEn:
            'Multi-role orchestration. OpenHand delegates coding work to configured CLI tools and manages structured persistent context.',
        descriptionFr:
            'Orchestration multi-rôles. OpenHand délègue le codage aux CLI configurés et gère le contexte persistant.',
        descriptionDe:
            'Mehrrollen-Orchestrierung. OpenHand delegiert Coding-Aufgaben an konfigurierte CLI-Tools und verwaltet strukturierten Kontext.',
        descriptionJa:
            '複数ロールのオーケストレーション。OpenHand が設定済み CLI ツールへ実装作業を委譲し、構造化された永続コンテキストを管理します。',
        internalVersion: '1.0.0',
        promptAssetDirectory: harnessEngineeringPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: harnessEngineeringTemplateId,
        promptAssetDirectory: harnessEngineeringPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.generic,
        extensionSections: <AiPromptSharedSectionSpec>[],
        compressionIdentity:
            'You are OpenHand Harness Engineering. Produce a relay-safe orchestration checkpoint.',
      ),
    ),
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: programmingExpertTemplateId,
        name: '编程专家',
        nameZhHant: '程式設計專家',
        nameEn: 'Programming Expert',
        nameFr: 'Expert programmation',
        nameDe: 'Programmierexperte',
        nameJa: 'プログラミングエキスパート',
        iconName: AiThreadTemplateIconNames.codeRounded,
        description:
            '对标 Claude Code 范式的全栈 AI 编程代理。以工具事实回灌、Plan/Todo 状态纪律、子代理隔离、对抗验证和上下文恢复推进端到端工程任务。',
        descriptionZhHant:
            '對標 Claude Code 範式的全端 AI 程式設計代理。以工具事實回饋、Plan/Todo 狀態紀律、子代理隔離、對抗驗證和上下文恢復推進端到端工程任務。',
        descriptionEn:
            'A Claude Code style full-stack coding agent with tool-grounded facts, planning discipline, subagents, validation, and context recovery.',
        descriptionFr:
            'Agent de programmation full-stack de style Claude Code avec faits d’outils, planification, sous-agents, validation et reprise de contexte.',
        descriptionDe:
            'Full-Stack-Coding-Agent im Claude-Code-Stil mit Tool-Fakten, Planung, Subagents, Validierung und Kontextwiederherstellung.',
        descriptionJa:
            'Claude Code 型のフルスタック開発エージェント。ツール事実、計画管理、サブエージェント、検証、文脈復元を使います。',
        internalVersion: '1.2.0',
        promptAssetDirectory: programmingExpertPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: programmingExpertTemplateId,
        promptAssetDirectory: programmingExpertPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.generic,
        extensionSections: _programmingExpertExtensionSections,
        compressionIdentity:
            'You are OpenHand Programming Expert. Produce a relay-safe coding checkpoint.',
        compressionPayloadStyle: AiPromptCompressionPayloadStyle.minimal,
      ),
    ),
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: hermesTalkerTemplateId,
        name: 'Hermes Talker',
        nameZhHant: 'Hermes Talker',
        nameEn: 'Hermes Talker',
        nameFr: 'Hermes Talker',
        nameDe: 'Hermes Talker',
        nameJa: 'Hermes Talker',
        iconName: AiThreadTemplateIconNames.forumRounded,
        description:
            '在 Default 模板基础上新增 skill_manager 工具与每 5 分钟运行的自我学习能力,持续在对话中积累用户画像与可复用技能。',
        descriptionZhHant:
            '在 Default 模板基礎上新增 skill_manager 工具與每 5 分鐘執行的自我學習能力，持續在對話中累積使用者輪廓與可複用技能。',
        descriptionEn:
            'Adds skill_manager and periodic self-learning to the Default template for reusable skills and user context.',
        descriptionFr:
            'Ajoute skill_manager et l’auto-apprentissage périodique au modèle Default pour les compétences réutilisables.',
        descriptionDe:
            'Ergänzt die Default-Vorlage um skill_manager und periodisches Selbstlernen für wiederverwendbare Skills.',
        descriptionJa:
            'Default テンプレートに skill_manager と定期的な自己学習を追加し、再利用可能なスキルとユーザー文脈を蓄積します。',
        internalVersion: '1.0.0',
        promptAssetDirectory: hermesTalkerPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: hermesTalkerTemplateId,
        promptAssetDirectory: hermesTalkerPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.generic,
        extensionSections: <AiPromptSharedSectionSpec>[],
        compressionIdentity:
            'You are OpenHand Hermes Talker. Produce a relay-safe assistant checkpoint.',
      ),
    ),
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: webReverseExpertTemplateId,
        name: 'Web 逆向专家',
        nameZhHant: 'Web 逆向專家',
        nameEn: 'Web Reverse Expert',
        nameFr: 'Expert reverse Web',
        nameDe: 'Web-Reverse-Experte',
        nameJa: 'Web リバースエキスパート',
        iconName: AiThreadTemplateIconNames.travelExploreRounded,
        description:
            '通过 Google Chrome（或同核 Chromium）+ CDP 通道完成 Web 站点的接口逆向、参数还原、复现脚本产出。Dashboard 提供内嵌浏览器面板（screencast + 输入桥）与 F12 等价控制台。仅用于授权安全研究与学习。',
        descriptionZhHant:
            '透過 Google Chrome（或同核心 Chromium）+ CDP 通道完成 Web 站點接口逆向、參數還原與復現腳本。Dashboard 提供內嵌瀏覽器面板與 F12 等價控制台。僅用於授權安全研究與學習。',
        descriptionEn:
            'Uses Chrome or Chromium with CDP for Web API reversing, parameter recovery, and reproduction scripts. For authorized research only.',
        descriptionFr:
            'Utilise Chrome ou Chromium avec CDP pour l’analyse d’API Web, les paramètres et les scripts de reproduction. Recherche autorisée uniquement.',
        descriptionDe:
            'Nutzt Chrome oder Chromium mit CDP für Web-API-Reverse, Parameterrekonstruktion und Repro-Skripte. Nur für autorisierte Forschung.',
        descriptionJa:
            'Chrome または Chromium と CDP で Web API 解析、パラメータ復元、再現スクリプト作成を行います。許可された研究専用です。',
        internalVersion: '1.2.0',
        promptAssetDirectory: webReverseExpertPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: webReverseExpertTemplateId,
        promptAssetDirectory: webReverseExpertPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.webReverse,
        extensionSections: <AiPromptSharedSectionSpec>[],
        compressionIdentity:
            'You are OpenHand Web Reverse Expert. Produce a relay-safe browser-reverse checkpoint with target URL, identified API entry, injected hook scripts, and saved artifacts under web_reverse_runtime.local_artifacts.',
        includesWebReverseRuntime: true,
      ),
    ),
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: siriHelperTemplateId,
        name: 'Siri 助手',
        nameZhHant: 'Siri 助手',
        nameEn: 'Siri Assistant',
        nameFr: 'Assistant Siri',
        nameDe: 'Siri-Assistent',
        nameJa: 'Siri アシスタント',
        iconName: AiThreadTemplateIconNames.assistantRounded,
        description: '默认模板的苹果设备特化版本，内置 Siri 风格系统提示词，适合依赖 Apple 生态语义与交互氛围的任务。',
        descriptionZhHant:
            '預設模板的 Apple 裝置特化版本，內建 Siri 風格系統提示詞，適合依賴 Apple 生態語義與互動氛圍的任務。',
        descriptionEn:
            'An Apple-focused Default template with Siri-style system instructions for Apple ecosystem tasks.',
        descriptionFr:
            'Version du modèle Default orientée Apple, avec instructions système de style Siri.',
        descriptionDe:
            'Apple-orientierte Default-Vorlage mit Siri-artigen Systemanweisungen.',
        descriptionJa:
            'Apple 向けの Default テンプレート。Siri 風のシステム指示で Apple エコシステムのタスクに適します。',
        internalVersion: '1.0.0',
        promptAssetDirectory: siriHelperPromptAssetDirectory,
        availability: AiPromptTemplateAvailabilityScope.appleOnly,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: siriHelperTemplateId,
        promptAssetDirectory: siriHelperPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.generic,
        extensionSections: <AiPromptSharedSectionSpec>[],
        compressionIdentity:
            'You are OpenHand Siri Helper. Produce a relay-safe assistant checkpoint with grounded facts and user-visible context preserved.',
        promptAssetFileOverrides: <String, String>{
          AiPromptTemplateAssetFiles.developerInstructions:
              '$defaultPromptAssetDirectory/${AiPromptTemplateAssetFiles.developerInstructions}',
          AiPromptTemplateAssetFiles.compressionSummaryInstructions:
              '$defaultPromptAssetDirectory/${AiPromptTemplateAssetFiles.compressionSummaryInstructions}',
        },
      ),
    ),
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: androidReverseExpertTemplateId,
        name: 'Android 逆向专家',
        nameZhHant: 'Android 逆向專家',
        nameEn: 'Android Reverse Expert',
        nameFr: 'Expert reverse Android',
        nameDe: 'Android-Reverse-Experte',
        nameJa: 'Android リバースエキスパート',
        iconName: AiThreadTemplateIconNames.androidRounded,
        description:
            '通过 ADB + Frida + jadx / apktool + mitmproxy 完成 Android APP 接口逆向、加密破解、Hook 脚本产出。Dashboard 提供设备管理、Logcat、网络抓包、证书注入等面板。仅用于授权安全研究与学习。',
        descriptionZhHant:
            '透過 ADB + Frida + jadx / apktool + mitmproxy 完成 Android APP 接口逆向、加密破解與 Hook 腳本。Dashboard 提供設備管理、Logcat、抓包、憑證注入等面板。僅用於授權安全研究與學習。',
        descriptionEn:
            'Uses ADB, Frida, jadx / apktool, and mitmproxy for Android API reversing, crypto analysis, and hook scripts. For authorized research only.',
        descriptionFr:
            'Utilise ADB, Frida, jadx / apktool et mitmproxy pour l’analyse Android, la crypto et les hooks. Recherche autorisée uniquement.',
        descriptionDe:
            'Nutzt ADB, Frida, jadx / apktool und mitmproxy für Android-Reverse, Kryptoanalyse und Hook-Skripte. Nur für autorisierte Forschung.',
        descriptionJa:
            'ADB、Frida、jadx / apktool、mitmproxy で Android API 解析、暗号解析、Hook スクリプト作成を行います。許可された研究専用です。',
        internalVersion: '1.1.0',
        promptAssetDirectory: androidReverseExpertPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: androidReverseExpertTemplateId,
        promptAssetDirectory: androidReverseExpertPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.androidReverse,
        extensionSections: <AiPromptSharedSectionSpec>[],
        compressionIdentity:
            'You are OpenHand Android Reverse Expert. Produce a relay-safe Android-reverse checkpoint with target package, identified API/method, Frida hook scripts, and saved artifacts under android_reverse_runtime.local_artifacts.',
      ),
    ),
  ];

  static final List<AiPromptTemplateInfo> templateInfos =
      List<AiPromptTemplateInfo>.unmodifiable(
        entries.map((entry) => entry.info),
      );

  static final Map<String, AiPromptTemplateCatalogEntry> byTemplateId =
      Map<String, AiPromptTemplateCatalogEntry>.unmodifiable(
        <String, AiPromptTemplateCatalogEntry>{
          for (final entry in entries) entry.id: entry,
        },
      );

  static final Map<String, AiPromptTemplatePolicy> byId =
      Map<String, AiPromptTemplatePolicy>.unmodifiable(
        <String, AiPromptTemplatePolicy>{
          for (final entry in entries) entry.id: entry.policy,
        },
      );

  static AiPromptTemplateCatalogEntry resolveEntry(String templateId) {
    final normalized = templateId.trim();
    if (normalized.isEmpty) {
      return byTemplateId[defaultTemplateId]!;
    }
    return byTemplateId[normalized] ?? byTemplateId[defaultTemplateId]!;
  }

  static AiPromptTemplatePolicy resolve(String templateId) {
    return resolveEntry(templateId).policy;
  }
}

const String aiPromptMemoryTonePolicySection = '''

## Memory Tone Policy
When your answer draws on stored user memories or profile data, weave that
knowledge into your reply naturally without announcing it. Do NOT say "I
remember that…", "from memory…", "you told me earlier…", or similar
tell-tales. Treat memory as invisible context, not as something the user
needs to be reminded you're tracking.
''';

const String _memoryTonePolicyMarker = '## memory tone policy';

const List<AiPromptSharedSectionSpec> _baselinePromptSharedSections =
    <AiPromptSharedSectionSpec>[
      AiPromptSharedSectionSpec(
        tag: 'identity',
        assetPath: 'assets/prompts/_shared/identity.md',
      ),
      AiPromptSharedSectionSpec(
        tag: 'refusal_handling',
        assetPath: 'assets/prompts/_shared/refusal.md',
      ),
      AiPromptSharedSectionSpec(
        tag: 'tone_and_formatting',
        assetPath: 'assets/prompts/_shared/tone.md',
      ),
      AiPromptSharedSectionSpec(
        tag: 'workflow',
        assetPath: 'assets/prompts/_shared/workflow.md',
      ),
    ];

const List<AiPromptSharedSectionSpec>
_programmingExpertExtensionSections = <AiPromptSharedSectionSpec>[
  AiPromptSharedSectionSpec(
    tag: 'runtime_turn_model',
    assetPath:
        'assets/prompts/programming_expert/sections/runtime_turn_model.md',
  ),
  AiPromptSharedSectionSpec(
    tag: 'intent_workflows',
    assetPath: 'assets/prompts/programming_expert/sections/intent_workflows.md',
  ),
  AiPromptSharedSectionSpec(
    tag: 'project_resource_trust',
    assetPath:
        'assets/prompts/programming_expert/sections/project_resource_trust.md',
  ),
  AiPromptSharedSectionSpec(
    tag: 'resource_adaptation_workflow',
    assetPath:
        'assets/prompts/programming_expert/sections/resource_adaptation_workflow.md',
  ),
  AiPromptSharedSectionSpec(
    tag: 'context_recovery',
    assetPath: 'assets/prompts/programming_expert/sections/context_recovery.md',
  ),
];

bool aiPromptInstructionsLooksLikeChinese(String text) {
  var cjk = 0;
  var total = 0;
  for (final rune in text.runes) {
    if (rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D) {
      continue;
    }
    total++;
    if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0xF900 && rune <= 0xFAFF)) {
      cjk++;
    }
  }
  if (total == 0) {
    return false;
  }
  return cjk * 100 ~/ total >= 15;
}

bool aiPromptInstructionsHasXmlSectionTag(String instructions, String tag) {
  return instructions.toLowerCase().contains('<${tag.toLowerCase()}>');
}

bool aiPromptInstructionsHasV4DisciplineMarker(String instructions) {
  const headingPatterns = <String>[
    'atomic change discipline',
    'uncertainty honesty',
    '通用纪律',
    '不确定性诚实',
  ];
  for (final heading in headingPatterns) {
    if (RegExp(
      '^#{1,6}\\s+${RegExp.escape(heading)}\\b',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(instructions)) {
      return true;
    }
  }
  const xmlTags = <String>[
    '<atomic_change_discipline>',
    '<uncertainty_honesty>',
    '<universal_discipline>',
  ];
  final lower = instructions.toLowerCase();
  for (final tag in xmlTags) {
    if (lower.contains(tag)) {
      return true;
    }
  }
  return false;
}

String aiPromptV4DisciplineAssetPath(String instructions) {
  return aiPromptInstructionsLooksLikeChinese(instructions)
      ? 'assets/prompts/common/v4_discipline_zh.md'
      : 'assets/prompts/common/v4_discipline_en.md';
}

bool aiPromptInstructionsHasMemoryTonePolicy(String instructions) {
  return instructions.toLowerCase().contains(_memoryTonePolicyMarker);
}

String appendAiPromptSharedSectionsIfAbsent(
  String instructions,
  Iterable<AiPromptLoadedSection> sections,
) {
  var output = instructions.trimRight();
  for (final section in sections) {
    if (aiPromptInstructionsHasXmlSectionTag(output, section.tag)) {
      continue;
    }
    final snippet = section.content.trim();
    if (snippet.isEmpty) {
      continue;
    }
    output = '$output\n\n$snippet';
  }
  return '$output\n';
}

String appendAiPromptV4DisciplineIfAbsent(
  String instructions, {
  required String zhSnippet,
  required String enSnippet,
}) {
  if (aiPromptInstructionsHasV4DisciplineMarker(instructions)) {
    return instructions;
  }
  final snippet = aiPromptInstructionsLooksLikeChinese(instructions)
      ? zhSnippet.trim()
      : enSnippet.trim();
  if (snippet.isEmpty) {
    return instructions;
  }
  return '${instructions.trimRight()}\n\n$snippet\n';
}

String appendAiPromptMemoryTonePolicyIfAbsent(
  String instructions, {
  String section = aiPromptMemoryTonePolicySection,
}) {
  if (aiPromptInstructionsHasMemoryTonePolicy(instructions)) {
    return instructions;
  }
  return '${instructions.trimRight()}\n$section';
}
