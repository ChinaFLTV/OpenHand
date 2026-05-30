// ignore_for_file: avoid_print
//
// Standalone Dart CLI to preview the assembled prompt-template bundles for
// each of the 5 thread templates (default / machine_expert /
// hardness_engineering / programming_expert / hermes_talker), exactly as
// `AiPromptTemplateRepository.loadBundle` would resolve them at runtime
// (system_instructions + v4 discipline appendix + memory tone policy).
//
// Usage: `dart run scripts/preview_prompts.dart`
// Output: build/preview/<template_id>/{system,developer,compression_summary}.md
//
// This script intentionally avoids importing any code from `lib/` so it can
// run with plain `dart run` (no flutter SDK linking). The marker rules below
// MUST stay in sync with `lib/features/ai/service/prompt/ai_prompt_template_repository.dart`:
//   - skip v4 discipline append when system already contains either
//       Markdown headings: "Atomic Change Discipline" / "Uncertainty Honesty"
//       or XML tags: <atomic_change_discipline> / <uncertainty_honesty>
//   - else, if CJK ratio (non-whitespace) ≥ 15% → append v4_discipline_zh.md
//                                                else → append v4_discipline_en.md
//   - append shared identity/refusal/tone/workflow snippets only when the
//       target xml tag is absent; machine_expert is intentionally exempt
//   - skip memory tone policy when system already contains (lower):
//       "## memory tone policy"

import 'dart:io';

const List<({String id, String dir})> _templates = <({String id, String dir})>[
  (id: 'default', dir: 'assets/prompts/default'),
  (id: 'machine_expert', dir: 'assets/prompts/machine_expert'),
  (id: 'hardness_engineering', dir: 'assets/prompts/hardness_engineering'),
  (id: 'programming_expert', dir: 'assets/prompts/programming_expert'),
  (id: 'hermes_talker', dir: 'assets/prompts/hermes_talker'),
  (id: 'web_reverse_expert', dir: 'assets/prompts/web_reverse_expert'),
];

const String _memoryTonePolicySection = '''

## Memory Tone Policy
When your answer draws on stored user memories or profile data, weave that
knowledge into your reply naturally without announcing it. Do NOT say "I
remember that…", "from memory…", "you told me earlier…", or similar
tell-tales. Treat memory as invisible context, not as something the user
needs to be reminded you're tracking.
''';

bool _looksLikeChinese(String text) {
  int cjk = 0;
  int total = 0;
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

bool _hasXmlSectionTag(String instructions, String tag) {
  return instructions.toLowerCase().contains('<${tag.toLowerCase()}>');
}

String _appendSharedSectionsIfAbsent(String instructions, String templateId) {
  if (templateId == 'machine_expert') {
    return instructions;
  }
  final sections = <({String tag, String assetPath})>[
    (tag: 'identity', assetPath: 'assets/prompts/_shared/identity.md'),
    (tag: 'refusal_handling', assetPath: 'assets/prompts/_shared/refusal.md'),
    (tag: 'tone_and_formatting', assetPath: 'assets/prompts/_shared/tone.md'),
    if (templateId != 'hermes_talker')
      (tag: 'workflow', assetPath: 'assets/prompts/_shared/workflow.md'),
  ];
  var output = instructions.trimRight();
  for (final section in sections) {
    if (_hasXmlSectionTag(output, section.tag)) {
      continue;
    }
    final snippet = _readOrEmpty(section.assetPath);
    if (snippet.isEmpty) continue;
    output = '$output\n\n$snippet';
  }
  return '$output\n';
}

bool _hasV4DisciplineMarker(String instructions) {
  const headingPatterns = <String>[
    'atomic change discipline',
    'uncertainty honesty',
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
  final lower = instructions.toLowerCase();
  return lower.contains('<atomic_change_discipline>') ||
      lower.contains('<uncertainty_honesty>');
}

String _appendV4DisciplineIfAbsent(String instructions) {
  if (_hasV4DisciplineMarker(instructions)) {
    return instructions;
  }
  final assetPath = _looksLikeChinese(instructions)
      ? 'assets/prompts/common/v4_discipline_zh.md'
      : 'assets/prompts/common/v4_discipline_en.md';
  final snippet = _readOrEmpty(assetPath);
  if (snippet.isEmpty) return instructions;
  return '${instructions.trimRight()}\n\n$snippet\n';
}

String _appendMemoryTonePolicyIfAbsent(String instructions) {
  if (instructions.toLowerCase().contains('## memory tone policy')) {
    return instructions;
  }
  return '${instructions.trimRight()}\n$_memoryTonePolicySection';
}

String _readOrEmpty(String path) {
  final f = File(path);
  if (!f.existsSync()) return '';
  return f.readAsStringSync().trim();
}

void main() {
  final outRoot = Directory('build/preview');
  if (outRoot.existsSync()) outRoot.deleteSync(recursive: true);
  outRoot.createSync(recursive: true);

  print('Dry-run preview output: ${outRoot.absolute.path}');
  print('');

  for (final t in _templates) {
    final outDir = Directory('${outRoot.path}/${t.id}')..createSync();
    final system = _readOrEmpty('${t.dir}/system_instructions.md');
    final developer = _readOrEmpty('${t.dir}/developer_instructions.md');
    final compression = _readOrEmpty(
      '${t.dir}/compression_summary_instructions.md',
    );

    if (system.isEmpty || developer.isEmpty || compression.isEmpty) {
      print(
        '⚠️  ${t.id}: missing one or more prompt files in ${t.dir} '
        '(system=${system.isNotEmpty}, dev=${developer.isNotEmpty}, '
        'compression=${compression.isNotEmpty})',
      );
      continue;
    }

    final v4Marker = _hasV4DisciplineMarker(system);
    final tonePolicyMarker = system.toLowerCase().contains(
      '## memory tone policy',
    );
    final cjkRatio = _cjkRatioPct(system);

    final assembled = _appendMemoryTonePolicyIfAbsent(
      _appendV4DisciplineIfAbsent(_appendSharedSectionsIfAbsent(system, t.id)),
    );

    File(
      '${outDir.path}/system_instructions.assembled.md',
    ).writeAsStringSync(assembled);
    File('${outDir.path}/system_instructions.raw.md').writeAsStringSync(system);
    File(
      '${outDir.path}/developer_instructions.md',
    ).writeAsStringSync(developer);
    File(
      '${outDir.path}/compression_summary_instructions.md',
    ).writeAsStringSync(compression);

    print('• ${t.id}');
    print(
      '    raw chars     : sys=${system.length} dev=${developer.length} '
      'comp=${compression.length}',
    );
    print(
      '    assembled sys : ${assembled.length} chars '
      '(+${assembled.length - system.length})',
    );
    print(
      '    cjk ratio     : ${cjkRatio.toStringAsFixed(1)}% '
      '(→ ${_looksLikeChinese(system) ? "zh" : "en"} discipline)',
    );
    print(
      '    v4 marker     : ${v4Marker ? "PRESENT (skip append)" : "absent (append)"}',
    );
    print(
      '    tone marker   : ${tonePolicyMarker ? "PRESENT (skip append)" : "absent (append)"}',
    );
    print('    out dir       : ${outDir.path}');
    print('');
  }

  print('done.');
}

double _cjkRatioPct(String text) {
  int cjk = 0;
  int total = 0;
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
  return total == 0 ? 0.0 : cjk * 100.0 / total;
}
