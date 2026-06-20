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

enum AiPromptToolCatalogProfile { generic, machineExpert, webReverse }

enum AiPromptCompressionPayloadStyle { standard, minimal }

class AiPromptTemplatePolicy {
  const AiPromptTemplatePolicy({
    required this.templateId,
    required this.promptAssetDirectory,
    required this.toolCatalogProfile,
    required this.sharedSections,
    required this.extensionSections,
    required this.compressionIdentity,
    this.compressionPayloadStyle = AiPromptCompressionPayloadStyle.standard,
    this.includesWebReverseRuntime = false,
  });

  final String templateId;
  final String promptAssetDirectory;
  final AiPromptToolCatalogProfile toolCatalogProfile;
  final List<AiPromptSharedSectionSpec> sharedSections;
  final List<AiPromptSharedSectionSpec> extensionSections;
  final String compressionIdentity;
  final AiPromptCompressionPayloadStyle compressionPayloadStyle;
  final bool includesWebReverseRuntime;

  bool get usesMinimalCompressionPayload =>
      compressionPayloadStyle == AiPromptCompressionPayloadStyle.minimal;

  bool get usesMachineToolCatalog =>
      toolCatalogProfile == AiPromptToolCatalogProfile.machineExpert;

  bool get usesWebReverseToolCatalog =>
      toolCatalogProfile == AiPromptToolCatalogProfile.webReverse;
}

class AiPromptTemplatePolicies {
  const AiPromptTemplatePolicies._();

  static const String defaultTemplateId = 'default';
  static const String machineExpertTemplateId = 'machine_expert';
  static const String hardnessEngineeringTemplateId = 'hardness_engineering';
  static const String programmingExpertTemplateId = 'programming_expert';
  static const String hermesTalkerTemplateId = 'hermes_talker';
  static const String webReverseExpertTemplateId = 'web_reverse_expert';
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
  static const String siriHelperPromptAssetDirectory =
      'assets/prompts/siri_helper';

  static const Map<String, AiPromptTemplatePolicy>
  byId = <String, AiPromptTemplatePolicy>{
    defaultTemplateId: AiPromptTemplatePolicy(
      templateId: defaultTemplateId,
      promptAssetDirectory: defaultPromptAssetDirectory,
      toolCatalogProfile: AiPromptToolCatalogProfile.generic,
      sharedSections: _defaultPromptSharedSections,
      extensionSections: <AiPromptSharedSectionSpec>[],
      compressionIdentity:
          'You are OpenHand. Produce a relay-safe conversation checkpoint.',
    ),
    machineExpertTemplateId: AiPromptTemplatePolicy(
      templateId: machineExpertTemplateId,
      promptAssetDirectory: machineExpertPromptAssetDirectory,
      toolCatalogProfile: AiPromptToolCatalogProfile.machineExpert,
      sharedSections: <AiPromptSharedSectionSpec>[],
      extensionSections: <AiPromptSharedSectionSpec>[],
      compressionIdentity:
          'You are OpenHand Machine Expert. Produce a relay-safe terminal interaction checkpoint.',
    ),
    hardnessEngineeringTemplateId: AiPromptTemplatePolicy(
      templateId: hardnessEngineeringTemplateId,
      promptAssetDirectory: hardnessEngineeringPromptAssetDirectory,
      toolCatalogProfile: AiPromptToolCatalogProfile.generic,
      sharedSections: _defaultPromptSharedSections,
      extensionSections: <AiPromptSharedSectionSpec>[],
      compressionIdentity:
          'You are OpenHand Harness Engineering. Produce a relay-safe orchestration checkpoint.',
    ),
    programmingExpertTemplateId: AiPromptTemplatePolicy(
      templateId: programmingExpertTemplateId,
      promptAssetDirectory: programmingExpertPromptAssetDirectory,
      toolCatalogProfile: AiPromptToolCatalogProfile.generic,
      sharedSections: _defaultPromptSharedSections,
      extensionSections: _programmingExpertExtensionSections,
      compressionIdentity:
          'You are OpenHand Programming Expert. Produce a relay-safe coding checkpoint.',
      compressionPayloadStyle: AiPromptCompressionPayloadStyle.minimal,
    ),
    hermesTalkerTemplateId: AiPromptTemplatePolicy(
      templateId: hermesTalkerTemplateId,
      promptAssetDirectory: hermesTalkerPromptAssetDirectory,
      toolCatalogProfile: AiPromptToolCatalogProfile.generic,
      sharedSections: _hermesTalkerSharedSections,
      extensionSections: <AiPromptSharedSectionSpec>[],
      compressionIdentity:
          'You are OpenHand Hermes Talker. Produce a relay-safe assistant checkpoint.',
    ),
    webReverseExpertTemplateId: AiPromptTemplatePolicy(
      templateId: webReverseExpertTemplateId,
      promptAssetDirectory: webReverseExpertPromptAssetDirectory,
      toolCatalogProfile: AiPromptToolCatalogProfile.webReverse,
      sharedSections: _defaultPromptSharedSections,
      extensionSections: <AiPromptSharedSectionSpec>[],
      compressionIdentity:
          'You are OpenHand Web Reverse Expert. Produce a relay-safe browser-reverse checkpoint with target URL, identified API entry, hook scripts injected, and saved artifacts under WD/.web_reverse/.',
      includesWebReverseRuntime: true,
    ),
    siriHelperTemplateId: AiPromptTemplatePolicy(
      templateId: siriHelperTemplateId,
      promptAssetDirectory: siriHelperPromptAssetDirectory,
      toolCatalogProfile: AiPromptToolCatalogProfile.generic,
      sharedSections: <AiPromptSharedSectionSpec>[],
      extensionSections: <AiPromptSharedSectionSpec>[],
      compressionIdentity:
          'You are OpenHand Siri Helper. Produce a relay-safe assistant checkpoint with grounded facts and user-visible context preserved.',
    ),
  };

  static AiPromptTemplatePolicy resolve(String templateId) {
    final normalized = templateId.trim();
    if (normalized.isEmpty) {
      return byId[defaultTemplateId]!;
    }
    return byId[normalized] ?? byId[defaultTemplateId]!;
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

List<AiPromptSharedSectionSpec> aiPromptSharedSectionsForTemplate(
  String templateId,
) => AiPromptTemplatePolicies.resolve(templateId).sharedSections;

List<AiPromptSharedSectionSpec> aiPromptExtensionSectionsForTemplate(
  String templateId,
) => AiPromptTemplatePolicies.resolve(templateId).extensionSections;

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
