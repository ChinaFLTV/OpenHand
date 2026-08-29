import '../../shared/util/input_value_parsing.dart';
import '../ai/index.dart';

class TemplateRuntimeMcpCapabilitySpec {
  const TemplateRuntimeMcpCapabilitySpec({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    required this.descriptionZh,
    required this.descriptionEn,
    this.labelZhHant,
    this.labelFr,
    this.labelDe,
    this.labelJa,
    this.descriptionZhHant,
    this.descriptionFr,
    this.descriptionDe,
    this.descriptionJa,
    required this.keywords,
    this.packageName,
    this.suggestedServerName,
    this.suggestedCommand,
    this.suggestedArgs = const <String>[],
    this.suggestedUrl,
    this.openHandManaged = false,
    this.optional = true,
  });

  final String id;
  final String labelZh;
  final String labelEn;
  final String descriptionZh;
  final String descriptionEn;
  final String? labelZhHant;
  final String? labelFr;
  final String? labelDe;
  final String? labelJa;
  final String? descriptionZhHant;
  final String? descriptionFr;
  final String? descriptionDe;
  final String? descriptionJa;
  final List<String> keywords;
  final String? packageName;
  final String? suggestedServerName;
  final String? suggestedCommand;
  final List<String> suggestedArgs;
  final String? suggestedUrl;
  final bool openHandManaged;
  final bool optional;

  bool get hasSuggestedServer =>
      nullIfBlank(suggestedServerName) != null &&
      (nullIfBlank(suggestedCommand) != null ||
          nullIfBlank(suggestedUrl) != null);

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label_zh': labelZh,
    'label_en': labelEn,
    'description_zh': descriptionZh,
    'description_en': descriptionEn,
    if (labelZhHant != null) 'label_zh_hant': labelZhHant,
    if (labelFr != null) 'label_fr': labelFr,
    if (labelDe != null) 'label_de': labelDe,
    if (labelJa != null) 'label_ja': labelJa,
    if (descriptionZhHant != null) 'description_zh_hant': descriptionZhHant,
    if (descriptionFr != null) 'description_fr': descriptionFr,
    if (descriptionDe != null) 'description_de': descriptionDe,
    if (descriptionJa != null) 'description_ja': descriptionJa,
    'keywords': keywords,
    if (packageName != null) 'package_name': packageName,
    if (suggestedServerName != null)
      'suggested_server_name': suggestedServerName,
    if (suggestedCommand != null) 'suggested_command': suggestedCommand,
    if (suggestedArgs.isNotEmpty) 'suggested_args': suggestedArgs,
    if (suggestedUrl != null) 'suggested_url': suggestedUrl,
    'openhand_managed': openHandManaged,
    'optional': optional,
  };
}

class TemplateRuntimeDependencySpec {
  const TemplateRuntimeDependencySpec({
    required this.templateId,
    required this.labelZh,
    required this.labelEn,
    this.labelZhHant,
    this.labelFr,
    this.labelDe,
    this.labelJa,
    required this.pluginIds,
    required this.mcpCapabilities,
    required this.mcpKeywords,
    required this.toolSearchFallbackQuery,
  });

  final String templateId;
  final String labelZh;
  final String labelEn;
  final String? labelZhHant;
  final String? labelFr;
  final String? labelDe;
  final String? labelJa;
  final List<String> pluginIds;
  final List<TemplateRuntimeMcpCapabilitySpec> mcpCapabilities;
  final List<String> mcpKeywords;
  final String toolSearchFallbackQuery;

  bool matchesPlugin(String pluginId) {
    final normalized = nullIfBlank(pluginId)?.toLowerCase();
    if (normalized == null) return false;
    return pluginIds.any((id) => nullIfBlank(id)?.toLowerCase() == normalized);
  }

  List<TemplateRuntimeMcpCapabilitySpec> matchingCapabilities(String raw) {
    return mcpCapabilities
        .where(
          (capability) => TemplateRuntimeDependencyRegistry.containsAnyKeyword(
            raw,
            capability.keywords,
          ),
        )
        .toList(growable: false);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'template_id': templateId,
    'label_zh': labelZh,
    'label_en': labelEn,
    if (labelZhHant != null) 'label_zh_hant': labelZhHant,
    if (labelFr != null) 'label_fr': labelFr,
    if (labelDe != null) 'label_de': labelDe,
    if (labelJa != null) 'label_ja': labelJa,
    'plugin_ids': pluginIds,
    'mcp_keywords': mcpKeywords,
    'tool_search_fallback_query': toolSearchFallbackQuery,
    'mcp_capabilities': mcpCapabilities
        .map((item) => item.toJson())
        .toList(growable: false),
  };
}

class TemplateRuntimeDependencyRegistry {
  const TemplateRuntimeDependencyRegistry._();

  static const List<String> webReversePluginIds = <String>[
    'nodejs',
    'playwright',
    'mitmproxy',
  ];

  static const List<String> androidReversePluginIds = <String>[
    'java',
    'nodejs',
    'python',
    'pip',
    'playwright',
    'frida',
    'mitmproxy',
    'apktool',
    'jadx',
    'radare2',
    'blutter',
    'doldrums',
    'anything_analyzer',
  ];

  static const List<String> webReverseMcpKeywords = <String>[
    'cdp',
    'chrome',
    'chromium',
    'devtools',
    'browser',
    'playwright',
    'puppeteer',
    'network',
    'dom',
    'javascript',
    'js-reverse',
  ];

  static const List<String> androidReverseMcpKeywords = <String>[
    'adb',
    'android',
    'apk',
    'aapt',
    'apksigner',
    'apktool',
    'jadx',
    'frida',
    'objection',
    'ida',
    'radare',
    'r2',
    'mitm',
    'proxy',
    'cert',
    'certificate',
    'flutter',
    'dart',
    'blutter',
    'doldrums',
    'anything',
    'analyzer',
    'logcat',
    'device',
    'shell',
  ];

  static const String webReverseToolSearchFallbackQuery =
      'select:cdp,chrome,devtools,playwright,network,dom,js-reverse';

  static const String androidReverseToolSearchFallbackQuery =
      'select:adb,android,frida,ida,apktool,jadx,anything-analyzer,flutter';

  static const TemplateRuntimeDependencySpec
  webReverse = TemplateRuntimeDependencySpec(
    templateId: AiPromptTemplatePolicies.webReverseExpertTemplateId,
    labelZh: 'Web 逆向专家',
    labelEn: 'Web Reverse Expert',
    labelZhHant: 'Web 逆向專家',
    labelFr: 'Expert reverse Web',
    labelDe: 'Web-Reverse-Experte',
    labelJa: 'Web リバースエキスパート',
    pluginIds: webReversePluginIds,
    mcpKeywords: webReverseMcpKeywords,
    toolSearchFallbackQuery: webReverseToolSearchFallbackQuery,
    mcpCapabilities: <TemplateRuntimeMcpCapabilitySpec>[
      TemplateRuntimeMcpCapabilitySpec(
        id: 'web_reverse_cdp_mcp',
        labelZh: '会话内 CDP MCP',
        labelEn: 'Session CDP MCP',
        labelZhHant: '會話內 CDP MCP',
        labelFr: 'MCP CDP de session',
        labelDe: 'Sitzungs-CDP-MCP',
        labelJa: 'セッション CDP MCP',
        descriptionZh: '由 Web 逆向会话按需通过 npx 准备 chrome-devtools-mcp。',
        descriptionEn:
            'Prepared per Web Reverse session through npx and chrome-devtools-mcp.',
        descriptionZhHant: '由 Web 逆向會話按需透過 npx 準備 chrome-devtools-mcp。',
        descriptionFr:
            'Préparé à la demande par la session Web Reverse via npx et chrome-devtools-mcp.',
        descriptionDe:
            'Wird pro Web-Reverse-Sitzung bei Bedarf über npx und chrome-devtools-mcp vorbereitet.',
        descriptionJa:
            'Web リバースセッションごとに npx と chrome-devtools-mcp で必要時に準備されます。',
        keywords: <String>[
          'cdp',
          'chrome',
          'chromium',
          'devtools',
          'js-reverse',
        ],
        packageName: 'chrome-devtools-mcp@latest',
        suggestedServerName: 'Web Reverse CDP MCP',
        suggestedCommand: 'npx',
        suggestedArgs: <String>['--yes', 'chrome-devtools-mcp@latest'],
        openHandManaged: true,
      ),
      TemplateRuntimeMcpCapabilitySpec(
        id: 'playwright_mcp',
        labelZh: 'Playwright MCP',
        labelEn: 'Playwright MCP',
        descriptionZh: '浏览器自动化与页面检查能力，可在插件页安装并同步注册到 MCP。',
        descriptionEn:
            'Browser automation and inspection capability installed from the plugin page and registered into MCP.',
        descriptionZhHant: '瀏覽器自動化與頁面檢查能力，可在外掛頁安裝並同步註冊到 MCP。',
        descriptionFr:
            'Automatisation du navigateur et inspection de pages, installées depuis la page des plugins puis enregistrées dans MCP.',
        descriptionDe:
            'Browser-Automatisierung und Seitenprüfung, über die Plugin-Seite installiert und in MCP registriert.',
        descriptionJa: 'ブラウザ自動化とページ検査機能。プラグインページからインストールし、MCP に登録します。',
        keywords: <String>[
          'playwright',
          'browser',
          'chromium',
          'firefox',
          'webkit',
        ],
        packageName: '@playwright/mcp',
        suggestedServerName: 'Playwright MCP',
        suggestedCommand: 'npx',
        suggestedArgs: <String>['--yes', '@playwright/mcp'],
      ),
      TemplateRuntimeMcpCapabilitySpec(
        id: 'js_reverse_mcp',
        labelZh: 'JS Reverse MCP',
        labelEn: 'JS Reverse MCP',
        labelFr: 'MCP JS Reverse',
        labelDe: 'JS-Reverse-MCP',
        labelJa: 'JS リバース MCP',
        descriptionZh: 'JavaScript 反混淆、AST 分析、sourcemap 与打包产物定位能力。',
        descriptionEn:
            'JavaScript deobfuscation, AST analysis, sourcemap, and bundled asset inspection.',
        descriptionZhHant: 'JavaScript 反混淆、AST 分析、sourcemap 與打包產物定位能力。',
        descriptionFr:
            'Désobfuscation JavaScript, analyse AST, sourcemap et inspection des artefacts empaquetés.',
        descriptionDe:
            'JavaScript-Deobfuskation, AST-Analyse, Sourcemaps und Prüfung gebündelter Assets.',
        descriptionJa: 'JavaScript の難読化解除、AST 解析、sourcemap、バンドル成果物の検査機能。',
        keywords: <String>[
          'js-reverse',
          'javascript',
          'deobfuscate',
          'ast',
          'sourcemap',
          'source-map',
          'webpack',
          'vite',
        ],
        suggestedServerName: 'JS Reverse MCP',
        suggestedCommand: 'npx',
        suggestedArgs: <String>['--yes', '<js-reverse-mcp-package>'],
      ),
    ],
  );

  static const TemplateRuntimeDependencySpec
  androidReverse = TemplateRuntimeDependencySpec(
    templateId: AiPromptTemplatePolicies.androidReverseExpertTemplateId,
    labelZh: 'Android 逆向专家',
    labelEn: 'Android Reverse Expert',
    labelZhHant: 'Android 逆向專家',
    labelFr: 'Expert reverse Android',
    labelDe: 'Android-Reverse-Experte',
    labelJa: 'Android リバースエキスパート',
    pluginIds: androidReversePluginIds,
    mcpKeywords: androidReverseMcpKeywords,
    toolSearchFallbackQuery: androidReverseToolSearchFallbackQuery,
    mcpCapabilities: <TemplateRuntimeMcpCapabilitySpec>[
      TemplateRuntimeMcpCapabilitySpec(
        id: 'android_adb_mcp',
        labelZh: 'ADB MCP',
        labelEn: 'ADB MCP',
        descriptionZh: '设备枚举、adb shell、logcat、端口转发与 APK 操作。',
        descriptionEn:
            'Device listing, adb shell, logcat, port forwarding, and APK actions.',
        descriptionZhHant: '裝置枚舉、adb shell、logcat、連接埠轉發與 APK 操作。',
        descriptionFr:
            'Liste des appareils, adb shell, logcat, transfert de port et opérations APK.',
        descriptionDe:
            'Geräteliste, adb shell, logcat, Portweiterleitung und APK-Aktionen.',
        descriptionJa: 'デバイス一覧、adb shell、logcat、ポート転送、APK 操作。',
        keywords: <String>['adb', 'android', 'device', 'logcat', 'shell'],
        packageName: '@landicefu/android-adb-mcp-server',
        suggestedServerName: 'Android ADB MCP',
        suggestedCommand: 'npx',
        suggestedArgs: <String>['--yes', '@landicefu/android-adb-mcp-server'],
      ),
      TemplateRuntimeMcpCapabilitySpec(
        id: 'android_frida_mcp',
        labelZh: 'Frida MCP',
        labelEn: 'Frida MCP',
        descriptionZh: 'Frida 注入、Hook 与运行时动态验证。',
        descriptionEn: 'Frida injection, hooks, and runtime verification.',
        descriptionZhHant: 'Frida 注入、Hook 與執行期動態驗證。',
        descriptionFr: 'Injection Frida, hooks et vérification dynamique.',
        descriptionDe: 'Frida-Injektion, Hooks und Laufzeitverifikation.',
        descriptionJa: 'Frida 注入、Hook、実行時の動的検証。',
        keywords: <String>['frida', 'objection', 'hook', 'spawn'],
        packageName: 'frida-mcp',
        suggestedServerName: 'Android Frida MCP',
        suggestedCommand: 'npx',
        suggestedArgs: <String>['--yes', 'frida-mcp'],
      ),
      TemplateRuntimeMcpCapabilitySpec(
        id: 'android_static_mcp',
        labelZh: '静态分析 MCP',
        labelEn: 'Static analysis MCP',
        labelZhHant: '靜態分析 MCP',
        labelFr: 'MCP analyse statique',
        labelDe: 'Statische Analyse-MCP',
        labelJa: '静的解析 MCP',
        descriptionZh: 'jadx、apktool、aapt、IDA、radare2、Flutter 逆向与分析器能力。',
        descriptionEn:
            'jadx, apktool, aapt, IDA, radare2, Flutter reverse and analyzer capabilities.',
        descriptionZhHant: 'jadx、apktool、aapt、IDA、radare2、Flutter 逆向與分析器能力。',
        descriptionFr:
            'Capacités jadx, apktool, aapt, IDA, radare2, reverse Flutter et analyseurs.',
        descriptionDe:
            'Funktionen für jadx, apktool, aapt, IDA, radare2, Flutter-Reverse und Analyzer.',
        descriptionJa: 'jadx、apktool、aapt、IDA、radare2、Flutter リバース、アナライザー機能。',
        keywords: <String>[
          'apk',
          'aapt',
          'apksigner',
          'apktool',
          'jadx',
          'ida',
          'radare',
          'r2',
          'flutter',
          'dart',
          'blutter',
          'doldrums',
          'anything',
          'analyzer',
        ],
        suggestedServerName: 'Anything Analyzer MCP',
        suggestedCommand: 'npx',
        suggestedArgs: <String>['--yes', '<anything-analyzer-package>'],
      ),
      TemplateRuntimeMcpCapabilitySpec(
        id: 'android_network_mcp',
        labelZh: '网络/证书 MCP',
        labelEn: 'Network/cert MCP',
        labelZhHant: '網路/憑證 MCP',
        labelFr: 'MCP réseau/certificat',
        labelDe: 'Netzwerk/Zertifikat-MCP',
        labelJa: 'ネットワーク/証明書 MCP',
        descriptionZh: 'mitm、代理、证书与 TLS 相关的辅助分析能力。',
        descriptionEn:
            'MITM, proxy, certificate, and TLS-related analysis capability.',
        descriptionZhHant: 'mitm、代理、憑證與 TLS 相關的輔助分析能力。',
        descriptionFr:
            'Capacité d’analyse liée au MITM, au proxy, aux certificats et à TLS.',
        descriptionDe:
            'Analysefunktionen für MITM, Proxy, Zertifikate und TLS.',
        descriptionJa: 'MITM、プロキシ、証明書、TLS 関連の補助解析機能。',
        keywords: <String>['mitm', 'proxy', 'cert', 'certificate', 'tls'],
      ),
    ],
  );

  static const TemplateRuntimeDependencySpec hermesTalker =
      TemplateRuntimeDependencySpec(
        templateId: AiPromptTemplatePolicies.hermesTalkerTemplateId,
        labelZh: 'Hermes Talker',
        labelEn: 'Hermes Talker',
        pluginIds: <String>[],
        mcpKeywords: <String>[],
        toolSearchFallbackQuery: 'select:memory,skill',
        mcpCapabilities: <TemplateRuntimeMcpCapabilitySpec>[],
      );

  static const List<TemplateRuntimeDependencySpec> runtimeSpecs =
      <TemplateRuntimeDependencySpec>[webReverse, androidReverse, hermesTalker];

  static const List<TemplateRuntimeDependencySpec> reverseEngineeringSpecs =
      <TemplateRuntimeDependencySpec>[webReverse, androidReverse];

  static TemplateRuntimeDependencySpec? byTemplateId(String? templateId) {
    final normalized = nullIfBlank(templateId);
    if (normalized == null) return null;
    for (final spec in reverseEngineeringSpecs) {
      if (spec.templateId == normalized) return spec;
    }
    return null;
  }

  static List<TemplateRuntimeDependencySpec> specsForPlugin(String pluginId) {
    return runtimeSpecs
        .where((spec) => spec.matchesPlugin(pluginId))
        .toList(growable: false);
  }

  static bool containsAnyKeyword(String raw, Iterable<String> keywords) {
    final text = nullIfBlank(raw)?.toLowerCase();
    if (text == null) return false;
    for (final keyword in keywords) {
      final normalized = nullIfBlank(keyword)?.toLowerCase();
      if (normalized != null && text.contains(normalized)) return true;
    }
    return false;
  }
}
