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
    required this.sharedSections,
    required this.extensionSections,
    required this.compressionIdentity,
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
    this.availability = AiPromptTemplateAvailabilityScope.all,
  });

  final String id;
  final String name;
  final String iconName;
  final String description;
  final String internalVersion;
  final String promptAssetDirectory;
  final AiPromptTemplateAvailabilityScope availability;
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
  static const String hardnessEngineeringTemplateId = 'hardness_engineering';
  static const String programmingExpertTemplateId = 'programming_expert';
  static const String hermesTalkerTemplateId = 'hermes_talker';
  static const String webReverseExpertTemplateId = 'web_reverse_expert';
  static const String androidReverseExpertTemplateId = 'android_reverse_expert';
  static const String siriHelperTemplateId = 'siri_helper';

  static const String defaultPromptAssetDirectory = 'assets/prompts/default';
  static const String machineExpertPromptAssetDirectory =
      'assets/prompts/machine_expert';
  static const String hardnessEngineeringPromptAssetDirectory =
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
        name: 'Default Assistant',
        iconName: AiThreadTemplateIconNames.autoAwesomeRounded,
        description:
            'A Claude Code style general-purpose template for tool-assisted work, MCP usage, and local skill activation.',
        internalVersion: '3.0.0',
        promptAssetDirectory: defaultPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: defaultTemplateId,
        promptAssetDirectory: defaultPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.generic,
        sharedSections: _defaultPromptSharedSections,
        extensionSections: <AiPromptSharedSectionSpec>[],
        compressionIdentity:
            'You are OpenHand. Produce a relay-safe conversation checkpoint.',
      ),
    ),
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: machineExpertTemplateId,
        name: '机器专家',
        iconName: AiThreadTemplateIconNames.buildCircleRounded,
        description: '主要是通过本地终端程序去与目标机器交互，完成用户提出的任务或需求。',
        internalVersion: '1.1.0',
        promptAssetDirectory: machineExpertPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: machineExpertTemplateId,
        promptAssetDirectory: machineExpertPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.machineExpert,
        sharedSections: <AiPromptSharedSectionSpec>[],
        extensionSections: <AiPromptSharedSectionSpec>[],
        compressionIdentity:
            'You are OpenHand Machine Expert. Produce a relay-safe terminal interaction checkpoint.',
      ),
    ),
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: hardnessEngineeringTemplateId,
        name: 'Harness Engineering',
        iconName: AiThreadTemplateIconNames.hubRounded,
        description:
            '多角色编排协调模式。OpenHand 作为 OS 层统一编排，将编码任务委托给用户配置的 CLI 工具（调查者→规划者→实施者→验收者），并管理结构化持久化上下文。',
        internalVersion: '1.0.0',
        promptAssetDirectory: hardnessEngineeringPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: hardnessEngineeringTemplateId,
        promptAssetDirectory: hardnessEngineeringPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.generic,
        sharedSections: _defaultPromptSharedSections,
        extensionSections: <AiPromptSharedSectionSpec>[],
        compressionIdentity:
            'You are OpenHand Harness Engineering. Produce a relay-safe orchestration checkpoint.',
      ),
    ),
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: programmingExpertTemplateId,
        name: '编程专家',
        iconName: AiThreadTemplateIconNames.codeRounded,
        description:
            '对标 Claude Code 范式的全栈 AI 编程代理。以工具事实回灌、Plan/Todo 状态纪律、子代理隔离、对抗验证和上下文恢复推进端到端工程任务。',
        internalVersion: '1.2.0',
        promptAssetDirectory: programmingExpertPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: programmingExpertTemplateId,
        promptAssetDirectory: programmingExpertPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.generic,
        sharedSections: _defaultPromptSharedSections,
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
        iconName: AiThreadTemplateIconNames.forumRounded,
        description:
            '在 Default 模板基础上新增 skill_manager 工具与每 5 分钟运行的自我学习能力,持续在对话中积累用户画像与可复用技能。',
        internalVersion: '1.0.0',
        promptAssetDirectory: hermesTalkerPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: hermesTalkerTemplateId,
        promptAssetDirectory: hermesTalkerPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.generic,
        sharedSections: _hermesTalkerSharedSections,
        extensionSections: <AiPromptSharedSectionSpec>[],
        compressionIdentity:
            'You are OpenHand Hermes Talker. Produce a relay-safe assistant checkpoint.',
      ),
    ),
    AiPromptTemplateCatalogEntry(
      info: AiPromptTemplateInfo(
        id: webReverseExpertTemplateId,
        name: 'Web 逆向专家',
        iconName: AiThreadTemplateIconNames.travelExploreRounded,
        description:
            '通过 Google Chrome（或同核 Chromium）+ CDP 通道完成 Web 站点的接口逆向、参数还原、复现脚本产出。Dashboard 提供内嵌浏览器面板（screencast + 输入桥）与 F12 等价控制台。仅用于授权安全研究与学习。',
        internalVersion: '1.2.0',
        promptAssetDirectory: webReverseExpertPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: webReverseExpertTemplateId,
        promptAssetDirectory: webReverseExpertPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.webReverse,
        sharedSections: _defaultPromptSharedSections,
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
        iconName: AiThreadTemplateIconNames.assistantRounded,
        description: '默认模板的苹果设备特化版本，内置 Siri 风格系统提示词，适合依赖 Apple 生态语义与交互氛围的任务。',
        internalVersion: '1.0.0',
        promptAssetDirectory: siriHelperPromptAssetDirectory,
        availability: AiPromptTemplateAvailabilityScope.appleOnly,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: siriHelperTemplateId,
        promptAssetDirectory: siriHelperPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.generic,
        sharedSections: <AiPromptSharedSectionSpec>[],
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
        iconName: AiThreadTemplateIconNames.androidRounded,
        description:
            '通过 ADB + Frida + jadx / apktool + mitmproxy 完成 Android APP 接口逆向、加密破解、Hook 脚本产出。Dashboard 提供设备管理、Logcat、网络抓包、证书注入等面板。仅用于授权安全研究与学习。',
        internalVersion: '1.1.0',
        promptAssetDirectory: androidReverseExpertPromptAssetDirectory,
      ),
      policy: AiPromptTemplatePolicy(
        templateId: androidReverseExpertTemplateId,
        promptAssetDirectory: androidReverseExpertPromptAssetDirectory,
        toolCatalogProfile: AiPromptToolCatalogProfile.androidReverse,
        sharedSections: _defaultPromptSharedSections,
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

const List<AiPromptSharedSectionSpec> _defaultPromptSharedSections =
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

const List<AiPromptSharedSectionSpec> _hermesTalkerSharedSections =
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
