import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../shared/util/text_clip.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiEditTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.edit;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final rawFilePath = AiToolUtils.readString(args['file_path']);
    final oldString = '${args['old_string'] ?? ''}';
    final newString = '${args['new_string'] ?? ''}';
    final replaceAll = AiToolUtils.readBool(args['replace_all']) == true;
    if (rawFilePath.isEmpty) {
      return AiToolUtils.invalidResult(
        'Edit',
        'Edit requires a non-empty file_path.',
      );
    }
    final payloadSizeValidation = AiToolUtils.validateGeneratedTextPayloadSize(
      toolName: 'Edit',
      fieldName: 'new_string',
      value: newString,
    );
    if (payloadSizeValidation != null) return payloadSizeValidation;

    final filePath = AiToolUtils.resolvePathForContext(context, rawFilePath);
    final boundaryError = await AiToolUtils.validatePathWithinWorkingDirectory(
      context: context,
      toolName: 'Edit',
      path: filePath,
    );
    if (boundaryError != null) return boundaryError;
    final notebookValidation = AiToolUtils.validateNotebookTextMutation(
      toolName: 'Edit',
      filePath: filePath,
    );
    if (notebookValidation != null) return notebookValidation;
    if (oldString == newString) {
      return AiToolUtils.invalidResult(
        'Edit',
        'old_string and new_string must differ.',
      );
    }
    final file = File(filePath);
    final fileExists = await AiToolUtils.fileExistsBounded(file);
    if (!fileExists && oldString.isNotEmpty) {
      return AiToolUtils.invalidResult(
        'Edit',
        await AiToolUtils.missingPathMessage(subject: 'File', path: filePath),
      );
    }

    final preparation = await AiToolUtils.prepareFileMutation(
      context: context,
      toolName: 'Edit',
      operationDescription:
          'Replace "${clipText(oldString, 50)}" with new content',
      filePath: filePath,
      fileExists: fileExists,
    );
    if (preparation.error != null) return preparation.error!;

    final AiEditableTextSnapshot editableText;
    if (fileExists) {
      try {
        editableText = await AiToolUtils.readEditableTextFile(file);
      } on AiEditableTextFileTooLargeException catch (error) {
        return AiToolUtils.invalidResult('Edit', error.message);
      } on FormatException {
        return AiToolUtils.invalidResult(
          'Edit',
          'File does not appear to be a valid text file: $filePath',
        );
      }
    } else {
      editableText = AiEditableTextSnapshot.empty();
    }

    final replacement = AiToolUtils.applyExactStringEdit(
      content: editableText.normalizedContent,
      oldString: oldString,
      newString: newString,
      replaceAll: replaceAll,
      allowCreationFromEmptyOldString: !fileExists,
    );
    if (!replacement.success) {
      return AiToolUtils.invalidResult('Edit', replacement.errorMessage);
    }
    final writeContent = editableText.restoreLineEndings(replacement.content);
    final committed = await AiToolUtils.commitTextFileMutation(
      context: context,
      toolName: 'Edit',
      file: file,
      filePath: filePath,
      content: writeContent,
      fileExists: fileExists,
      preparation: preparation,
    );
    if (committed.failure != null) return committed.failure!;
    final ledgerRecordId = committed.ledgerRecordId;

    final replacementCount = replacement.replacementCount;
    final outputMessage = !fileExists
        ? 'Created $filePath (verified)'
        : replaceAll
        ? 'Updated $filePath (replaced $replacementCount occurrence${replacementCount > 1 ? 's' : ''}, verified)'
        : 'Updated $filePath (verified)';

    return AiToolUtils.simpleSuccessResult(
      command: 'Edit $filePath',
      output: outputMessage,
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      isWriteCommand: true,
      metadata: AiToolUtils.fileMutationResultMetadata(
        kind: 'edit',
        filePath: filePath,
        preparation: preparation,
        ledgerRecordId: ledgerRecordId,
        extra: <String, Object?>{
          'file_mutation_old_string_char_count': oldString.length,
          'file_mutation_new_string_char_count': newString.length,
          'file_mutation_replace_all': replaceAll,
          'file_mutation_replacement_count': replacementCount,
        },
      ),
    );
  }
}
