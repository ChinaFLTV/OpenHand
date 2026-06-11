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

List<AiPromptSharedSectionSpec> aiPromptSharedSectionsForTemplate(
  String templateId,
) {
  if (templateId == 'machine_expert') {
    return const <AiPromptSharedSectionSpec>[];
  }
  if (templateId == 'hermes_talker') {
    return _defaultPromptSharedSections
        .where((section) => section.tag != 'workflow')
        .toList(growable: false);
  }
  if (templateId == 'siri_helper') {
    return const <AiPromptSharedSectionSpec>[];
  }
  return _defaultPromptSharedSections;
}

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
