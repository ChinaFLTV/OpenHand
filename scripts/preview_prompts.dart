// ignore_for_file: avoid_print
//
// 预览当前所有线程模板在运行时拼装后的 Prompt 文件。
// 用法：`dart run scripts/preview_prompts.dart`
// 输出：build/preview/<template_id>/，包含原始、装配后的系统指令及开发者、压缩指令。

import 'dart:io';

import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/shared/util/bounded_delete.dart';
import 'package:path/path.dart' as p;

List<AiPromptTemplatePolicy> get _templates => AiPromptTemplatePolicies
    .byTemplateId
    .values
    .map((entry) => entry.policy)
    .toList(growable: false);

String _readOrEmpty(String path) {
  final f = File(path);
  if (!f.existsSync()) return '';
  return f.readAsStringSync().trim();
}

Future<void> main() async {
  final buildRoot = Directory(p.absolute('build'));
  final outRoot = Directory(p.join(buildRoot.path, 'preview'));
  if (outRoot.existsSync()) {
    await deletePathBounded(outRoot.path, allowedRoot: buildRoot.path);
  }
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

    final assembled = AiPromptTemplateAssembler.assembleSystem(policy, {
      for (final path in AiPromptTemplateAssembler.systemAssetPaths(policy))
        path: _readOrEmpty(path),
    });

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
    print('    输出目录：${outDir.path}');
    print('');
  }

  print('完成。');
}
