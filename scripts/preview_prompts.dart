// ignore_for_file: avoid_print
//
// Standalone Dart CLI to preview the assembled prompt-template bundles for
// all current thread templates, exactly as OpenHand resolves them at runtime.
//
// Usage: `dart run scripts/preview_prompts.dart`
// Output: build/preview/<template_id>/{system,developer,compression_summary}.md

import 'dart:io';

import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';

List<AiPromptTemplatePolicy> get _templates =>
    AiPromptTemplatePolicies.byId.values.toList(growable: false);

String _appendSectionsIfAbsent(
  String instructions,
  Iterable<AiPromptSharedSectionSpec> specs,
) {
  final sections = specs
      .map(
        (section) => AiPromptLoadedSection(
          tag: section.tag,
          content: _readOrEmpty(section.assetPath),
        ),
      )
      .where((section) => section.content.trim().isNotEmpty)
      .toList(growable: false);
  if (sections.isEmpty) {
    return instructions;
  }
  return appendAiPromptSharedSectionsIfAbsent(instructions, sections);
}

String _appendTemplateSectionsIfAbsent(String instructions, String templateId) {
  final policy = AiPromptTemplatePolicies.resolve(templateId);
  final withShared = _appendSectionsIfAbsent(
    instructions,
    policy.sharedSections,
  );
  return _appendSectionsIfAbsent(withShared, policy.extensionSections);
}

String _appendV4DisciplineIfAbsent(String instructions) {
  final zhSnippet = _readOrEmpty('assets/prompts/common/v4_discipline_zh.md');
  final enSnippet = _readOrEmpty('assets/prompts/common/v4_discipline_en.md');
  return appendAiPromptV4DisciplineIfAbsent(
    instructions,
    zhSnippet: zhSnippet,
    enSnippet: enSnippet,
  );
}

String _appendMemoryTonePolicyIfAbsent(String instructions) {
  return appendAiPromptMemoryTonePolicyIfAbsent(instructions);
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

  for (final policy in _templates) {
    final outDir = Directory('${outRoot.path}/${policy.templateId}')
      ..createSync();
    final system = _readOrEmpty(
      policy.promptAssetPathFor(AiPromptTemplateAssetFiles.systemInstructions),
    );
    final developer = _readOrEmpty(
      policy.promptAssetPathFor(
        AiPromptTemplateAssetFiles.developerInstructions,
      ),
    );
    final compression = _readOrEmpty(
      policy.promptAssetPathFor(
        AiPromptTemplateAssetFiles.compressionSummaryInstructions,
      ),
    );

    if (system.isEmpty || developer.isEmpty || compression.isEmpty) {
      print(
        '⚠️  ${policy.templateId}: missing one or more prompt files in '
        '${policy.promptAssetDirectory} '
        '(system=${system.isNotEmpty}, dev=${developer.isNotEmpty}, '
        'compression=${compression.isNotEmpty})',
      );
      continue;
    }

    final v4Marker = aiPromptInstructionsHasV4DisciplineMarker(system);
    final tonePolicyMarker = aiPromptInstructionsHasMemoryTonePolicy(system);
    final cjkRatio = _cjkRatioPct(system);

    final assembled = _appendMemoryTonePolicyIfAbsent(
      _appendV4DisciplineIfAbsent(
        _appendTemplateSectionsIfAbsent(system, policy.templateId),
      ),
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

    print('• ${policy.templateId}');
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
      '(→ ${aiPromptInstructionsLooksLikeChinese(system) ? "zh" : "en"} discipline)',
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
