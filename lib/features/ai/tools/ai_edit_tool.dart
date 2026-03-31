import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

// 2026-04-01 01:21:38 从 AiToolRuntimeService._executeEditTool 提取
class AiEditTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.edit;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final filePath = AiToolUtils.requireAbsoluteFilePath('${args['file_path'] ?? ''}'.trim());
    final oldString = '${args['old_string'] ?? ''}';
    final newString = '${args['new_string'] ?? ''}';
    final replaceAll = args['replace_all'] == true;
    if (filePath == null) {
      return AiToolUtils.invalidResult('Edit', 'Edit requires an absolute file_path.');
    }
    if (oldString == newString) {
      return AiToolUtils.invalidResult('Edit', 'old_string and new_string must differ.');
    }
    final file = File(filePath);
    if (!await file.exists()) {
      return AiToolUtils.invalidResult('Edit', 'File does not exist: $filePath');
    }
    final readValidation = await AiToolUtils.validateReadBeforeMutation(
      toolName: 'Edit',
      filePath: filePath,
      previouslyReadFiles: context.previouslyReadFiles,
    );
    if (readValidation != null) return readValidation;
    final content = await file.readAsString();
    final replacement = AiToolUtils.replaceOnceOrAll(
      content: content,
      oldString: oldString,
      newString: newString,
      replaceAll: replaceAll,
    );
    if (!replacement.success) {
      return AiToolUtils.invalidResult('Edit', replacement.errorMessage);
    }
    await AiToolUtils.writeTextFileSafely(file, replacement.content);
    return AiToolUtils.simpleSuccessResult(
      command: 'Edit $filePath',
      output: 'Updated $filePath',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'file_mutation_kind': 'edit',
        'file_mutation_path': filePath,
        'file_mutation_old_string_char_count': oldString.length,
        'file_mutation_new_string_char_count': newString.length,
        'file_mutation_replace_all': replaceAll,
      },
    );
  }
}
