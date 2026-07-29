import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../shared/util/input_value_parsing.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiMultiEditTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.multiEdit;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final rawFilePath = AiToolUtils.readString(args['file_path']);
    if (rawFilePath.isEmpty) {
      return AiToolUtils.invalidResult(
        'MultiEdit',
        'MultiEdit requires a non-empty file_path.',
      );
    }
    final filePath = AiToolUtils.resolvePath(rawFilePath);
    final notebookValidation = AiToolUtils.validateNotebookTextMutation(
      toolName: 'MultiEdit',
      filePath: filePath,
    );
    if (notebookValidation != null) return notebookValidation;
    final edits = AiToolUtils.readList(args['edits']);
    if (edits == null || edits.isEmpty) {
      return AiToolUtils.invalidResult(
        'MultiEdit',
        'MultiEdit requires a non-empty edits array.',
      );
    }
    for (var editIndex = 0; editIndex < edits.length; editIndex++) {
      final rawEdit = edits[editIndex];
      if (rawEdit is! Map) {
        return AiToolUtils.invalidResult(
          'MultiEdit',
          'edits[$editIndex] must be an object.',
        );
      }
      final edit = stringKeyedMapFromValue(rawEdit);
      final payloadSizeValidation =
          AiToolUtils.validateGeneratedTextPayloadSize(
            toolName: 'MultiEdit',
            fieldName: 'edits[$editIndex].new_string',
            value: '${edit['new_string'] ?? ''}',
          );
      if (payloadSizeValidation != null) return payloadSizeValidation;
    }

    final file = File(filePath);
    final fileExists = await AiToolUtils.fileExistsBounded(file);
    if (!fileExists && _requiresExistingFile(edits)) {
      return AiToolUtils.invalidResult(
        'MultiEdit',
        await AiToolUtils.missingPathMessage(subject: 'File', path: filePath),
      );
    }

    final preparation = await AiToolUtils.prepareFileMutation(
      context: context,
      toolName: 'MultiEdit',
      operationDescription:
          'Apply ${edits.length} edit${edits.length > 1 ? 's' : ''} to file',
      filePath: filePath,
      fileExists: fileExists,
    );
    if (preparation.error != null) return preparation.error!;

    final AiEditableTextSnapshot editableText;
    if (fileExists) {
      try {
        editableText = await AiToolUtils.readEditableTextFile(file);
      } on AiEditableTextFileTooLargeException catch (error) {
        return AiToolUtils.invalidResult('MultiEdit', error.message);
      } on FormatException {
        return AiToolUtils.invalidResult(
          'MultiEdit',
          'File does not appear to be a valid text file: $filePath',
        );
      }
    } else {
      editableText = AiEditableTextSnapshot.empty();
    }
    var content = editableText.normalizedContent;
    final appliedNewStrings = <String>[];
    for (var editIndex = 0; editIndex < edits.length; editIndex++) {
      final rawEdit = edits[editIndex];
      if (rawEdit is! Map) {
        return AiToolUtils.invalidResult(
          'MultiEdit',
          'edits[$editIndex] must be an object.',
        );
      }
      final edit = stringKeyedMapFromValue(rawEdit);
      final oldString = '${edit['old_string'] ?? ''}';
      final newString = '${edit['new_string'] ?? ''}';
      final replaceAll = AiToolUtils.readBool(edit['replace_all']) == true;
      final sequentialValidation = AiToolUtils.validateSequentialEditTarget(
        oldString: oldString,
        previousNewStrings: appliedNewStrings,
      );
      if (sequentialValidation != null) {
        return AiToolUtils.invalidResult(
          'MultiEdit',
          'edits[$editIndex] failed: $sequentialValidation',
        );
      }
      final replacement = AiToolUtils.applyExactStringEdit(
        content: content,
        oldString: oldString,
        newString: newString,
        replaceAll: replaceAll,
        allowCreationFromEmptyOldString: !fileExists && editIndex == 0,
      );
      if (!replacement.success) {
        return AiToolUtils.invalidResult(
          'MultiEdit',
          'edits[$editIndex] failed: ${replacement.errorMessage}',
        );
      }
      content = replacement.content;
      appliedNewStrings.add(newString);
    }
    final writeContent = editableText.restoreLineEndings(content);
    final committed = await AiToolUtils.commitTextFileMutation(
      context: context,
      toolName: 'MultiEdit',
      file: file,
      filePath: filePath,
      content: writeContent,
      fileExists: fileExists,
      preparation: preparation,
    );
    if (committed.failure != null) return committed.failure!;
    final ledgerRecordId = committed.ledgerRecordId;

    return AiToolUtils.simpleSuccessResult(
      command: 'MultiEdit $filePath',
      output:
          'Updated $filePath with ${edits.length} edit${edits.length > 1 ? 's' : ''} (verified)',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      isWriteCommand: true,
      metadata: AiToolUtils.fileMutationResultMetadata(
        kind: 'multi_edit',
        filePath: filePath,
        preparation: preparation,
        ledgerRecordId: ledgerRecordId,
        extra: <String, Object?>{'file_mutation_edit_count': edits.length},
      ),
    );
  }

  bool _requiresExistingFile(List<Object?> edits) {
    final firstEdit = edits.first;
    if (firstEdit is! Map) return false;
    return '${firstEdit['old_string'] ?? ''}'.isNotEmpty;
  }
}
