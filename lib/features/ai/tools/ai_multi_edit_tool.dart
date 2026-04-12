import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

// 2026-04-01 01:21:38 从 AiToolRuntimeService._executeMultiEditTool 提取
class AiMultiEditTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.multiEdit;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final filePath = AiToolUtils.requireAbsoluteFilePath(
        '${args['file_path'] ?? ''}'.trim());
    if (filePath == null) {
      return AiToolUtils.invalidResult(
          'MultiEdit', 'MultiEdit requires an absolute file_path.');
    }
    final edits = args['edits'];
    if (edits is! List || edits.isEmpty) {
      return AiToolUtils.invalidResult(
          'MultiEdit', 'MultiEdit requires a non-empty edits array.');
    }
    final file = File(filePath);
    final readValidation = await AiToolUtils.validateReadBeforeMutation(
      toolName: 'MultiEdit',
      filePath: filePath,
      previouslyReadFiles: context.previouslyReadFiles,
      requireExistingFileRead: await file.exists(),
    );
    if (readValidation != null) return readValidation;
    final bool fileExists = await file.exists();
    final String initialContent;
    if (fileExists) {
      try {
        initialContent = await file.readAsString();
      } on FormatException {
        return AiToolUtils.invalidResult('MultiEdit', 'File does not appear to be a valid text file: $filePath');
      }
    } else {
      initialContent = '';
    }
    var content = initialContent;
    var isCreatingFile = !fileExists;
    for (final rawEdit in edits) {
      if (rawEdit is! Map) {
        return AiToolUtils.invalidResult('MultiEdit', 'Each edit must be an object.');
      }
      final edit = Map<String, Object?>.from(rawEdit);
      final oldString = '${edit['old_string'] ?? ''}';
      final newString = '${edit['new_string'] ?? ''}';
      final replaceAll = edit['replace_all'] == true;
      if (oldString.isEmpty && isCreatingFile) {
        content = newString;
        isCreatingFile = false;
        continue;
      }
      final replacement = AiToolUtils.replaceOnceOrAll(
        content: content,
        oldString: oldString,
        newString: newString,
        replaceAll: replaceAll,
      );
      if (!replacement.success) {
        return AiToolUtils.invalidResult('MultiEdit', replacement.errorMessage);
      }
      content = replacement.content;
    }
    await AiToolUtils.writeTextFileSafely(file, content);
    return AiToolUtils.simpleSuccessResult(
      command: 'MultiEdit $filePath',
      output: 'Updated $filePath',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'file_mutation_kind': 'multi_edit',
        'file_mutation_path': filePath,
        'file_mutation_edit_count': edits.length,
      },
    );
  }
}
