import '../ai/index.dart';

class TemplateRuntimeMcpCapabilitySpec {
  const TemplateRuntimeMcpCapabilitySpec({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    required this.descriptionZh,
    required this.descriptionEn,
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
  final List<String> keywords;
  final String? packageName;
  final String? suggestedServerName;
  final String? suggestedCommand;
  final List<String> suggestedArgs;
  final String? suggestedUrl;
  final bool openHandManaged;
  final bool optional;

  bool get hasSuggestedServer =>
      (suggestedServerName?.trim().isNotEmpty ?? false) &&
      ((suggestedCommand?.trim().isNotEmpty ?? false) ||
          (suggestedUrl?.trim().isNotEmpty ?? false));

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label_zh': labelZh,
    'label_en': labelEn,
    'description_zh': descriptionZh,
    'description_en': descriptionEn,
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
    required this.pluginIds,
    required this.mcpCapabilities,
    required this.mcpKeywords,
    required this.toolSearchFallbackQuery,
  });

  final String templateId;
  final String labelZh;
  final String labelEn;
  final List<String> pluginIds;
  final List<TemplateRuntimeMcpCapabilitySpec> mcpCapabilities;
  final List<String> mcpKeywords;
  final String toolSearchFallbackQuery;

  bool matchesPlugin(String pluginId) {
    final normalized = pluginId.trim().toLowerCase();
    return pluginIds.any((id) => id.toLowerCase() == normalized);
  }

  bool matchesMcpText(String raw) {
    return TemplateRuntimeDependencyRegistry.containsAnyKeyword(
      raw,
      mcpKeywords,
    );
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
    pluginIds: webReversePluginIds,
    mcpKeywords: webReverseMcpKeywords,
    toolSearchFallbackQuery: webReverseToolSearchFallbackQuery,
    mcpCapabilities: <TemplateRuntimeMcpCapabilitySpec>[
      TemplateRuntimeMcpCapabilitySpec(
        id: 'web_reverse_cdp_mcp',
        labelZh: '会话内 CDP MCP',
        labelEn: 'Session CDP MCP',
        descriptionZh: '由 Web 逆向会话按需通过 npx 准备 chrome-devtools-mcp。',
        descriptionEn:
            'Prepared per Web Reverse session through npx and chrome-devtools-mcp.',
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
        descriptionZh: 'JavaScript 反混淆、AST 分析、sourcemap 与打包产物定位能力。',
        descriptionEn:
            'JavaScript deobfuscation, AST analysis, sourcemap, and bundled asset inspection.',
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
        descriptionZh: 'jadx、apktool、aapt、IDA、radare2、Flutter 逆向与分析器能力。',
        descriptionEn:
            'jadx, apktool, aapt, IDA, radare2, Flutter reverse and analyzer capabilities.',
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
        descriptionZh: 'mitm、代理、证书与 TLS 相关的辅助分析能力。',
        descriptionEn:
            'MITM, proxy, certificate, and TLS-related analysis capability.',
        keywords: <String>['mitm', 'proxy', 'cert', 'certificate', 'tls'],
      ),
    ],
  );

  static const List<TemplateRuntimeDependencySpec> reverseEngineeringSpecs =
      <TemplateRuntimeDependencySpec>[webReverse, androidReverse];

  static TemplateRuntimeDependencySpec? byTemplateId(String? templateId) {
    final normalized = (templateId ?? '').trim();
    if (normalized.isEmpty) return null;
    for (final spec in reverseEngineeringSpecs) {
      if (spec.templateId == normalized) return spec;
    }
    return null;
  }

  static List<TemplateRuntimeDependencySpec> specsForPlugin(String pluginId) {
    return reverseEngineeringSpecs
        .where((spec) => spec.matchesPlugin(pluginId))
        .toList(growable: false);
  }

  static List<TemplateRuntimeDependencySpec> specsForMcpText(String raw) {
    return reverseEngineeringSpecs
        .where((spec) => spec.matchesMcpText(raw))
        .toList(growable: false);
  }

  static bool containsAnyKeyword(String raw, Iterable<String> keywords) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return false;
    for (final keyword in keywords) {
      final normalized = keyword.trim().toLowerCase();
      if (normalized.isNotEmpty && text.contains(normalized)) return true;
    }
    return false;
  }

  static List<String> uniquePluginIdsForReverseTemplates() {
    final ids = <String>{};
    for (final spec in reverseEngineeringSpecs) {
      ids.addAll(spec.pluginIds);
    }
    return List<String>.unmodifiable(ids);
  }
}
