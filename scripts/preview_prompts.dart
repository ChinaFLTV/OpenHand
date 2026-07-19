// ignore_for_file: avoid_print
//
// 预览当前所有线程模板在运行时拼装后的 Prompt 文件。
// 用法：`dart run scripts/preview_prompts.dart`
// 输出：build/preview/<template_id>/{system,developer,compression_summary}.md

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

  print('试运行预览输出：${outRoot.absolute.path}');
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
        '警告：${policy.templateId} 缺少 Prompt 文件：'
        '${policy.promptAssetDirectory} '
        '（system=${system.isNotEmpty}，developer=${developer.isNotEmpty}，'
        'compression=${compression.isNotEmpty}）',
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

    print('- ${policy.templateId}');
    print(
      '    原始字符数：system=${system.length} developer=${developer.length} '
      '压缩摘要=${compression.length}',
    );
    print(
      '    拼装后 system：${assembled.length} 字符 '
      '(+${assembled.length - system.length})',
    );
    print(
      '    CJK 占比：${cjkRatio.toStringAsFixed(1)}% '
      '(→ ${aiPromptInstructionsLooksLikeChinese(system) ? "中文" : "英文"}规范)',
    );
    print('    v4 标记：${v4Marker ? "已存在，跳过追加" : "不存在，将追加"}');
    print('    语气标记：${tonePolicyMarker ? "已存在，跳过追加" : "不存在，将追加"}');
    print('    输出目录：${outDir.path}');
    print('');
  }

  print('完成。');
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
