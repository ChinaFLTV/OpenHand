import 'dart:io';

import 'package:path/path.dart' as p;

import '../../service/fs/ai_file_history_service.dart';
import '../../service/fs/ai_file_mutation_ledger.dart';
import '../../service/fs/ai_file_tracker_service.dart';
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
    final rawFilePath = '${args['file_path'] ?? ''}'.trim();
    final oldString = '${args['old_string'] ?? ''}';
    final newString = '${args['new_string'] ?? ''}';
    final replaceAll = args['replace_all'] == true;
    if (rawFilePath.isEmpty) {
      return AiToolUtils.invalidResult(
        'Edit',
        'Edit requires a non-empty file_path.',
      );
    }
    final filePath = AiToolUtils.resolvePath(rawFilePath);
    if (oldString == newString) {
      return AiToolUtils.invalidResult(
        'Edit',
        'old_string and new_string must differ.',
      );
    }
    final file = File(filePath);
    final fileExists = await file.exists();
    if (!fileExists && oldString.isNotEmpty) {
      return AiToolUtils.invalidResult(
        'Edit',
        'File does not exist: $filePath',
      );
    }

    // 2026-04-13: 写操作权限确认检查
    final confirmationResult = await AiToolUtils.requestWriteConfirmation(
      toolName: 'Edit',
      operationDescription:
          'Replace "${oldString.length > 50 ? '${oldString.substring(0, 50)}...' : oldString}" with new content',
      targetPath: filePath,
      requireWriteConfirmation: context.requireWriteCommandConfirmation,
      confirmWriteCommand: context.confirmWriteCommand,
      cancelSignal: context.cancelSignal,
      timeoutMs: context.metadata['write_confirmation_timeout_ms'] as int?,
    );
    if (confirmationResult != null) {
      return confirmationResult;
    }

    // 2026-04-12: 从 metadata 获取追踪服务（遵循 AiToolExecutionContext 冻结约束）
    final fileTracker =
        context.metadata['file_tracker'] as AiFileTrackerService?;
    final fileHistory =
        context.metadata['file_history'] as AiFileHistoryService?;

    final readValidation = await AiToolUtils.validateReadBeforeMutation(
      toolName: 'Edit',
      filePath: filePath,
      previouslyReadFiles: context.previouslyReadFiles,
      requireExistingFileRead: fileExists,
      fileTracker: fileTracker,
    );
    if (readValidation != null) return readValidation;

    // 2026-04-12: 保存历史版本（在修改前）
    String? versionId;
    if (fileExists) {
      versionId = await AiToolUtils.saveFileVersionBeforeMutation(
        filePath: filePath,
        sessionId: context.sessionId,
        toolCallId: context.toolCall.id,
        fileHistory: fileHistory,
      );
    }

    // 2026-05-03: 新型 ledger — 双快照捕获 before 内容
    final mutationLedger =
        context.metadata['mutation_ledger'] as AiFileMutationLedger?;
    final beforeContentForLedger = fileExists
        ? await AiToolUtils.readFileContentForLedger(filePath)
        : null;

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
    final guardedWrite = await AiToolUtils.writeTextFileWithMutationGuard(
      toolName: 'Edit',
      file: file,
      content: writeContent,
      previouslyReadFiles: context.previouslyReadFiles,
      requireExistingFileRead: fileExists,
      fileTracker: fileTracker,
    );
    if (guardedWrite != null) return guardedWrite;

    // 2026-04-12: 添加写入验证 - 读回文件确认修改已生效
    final String verificationContent;
    try {
      verificationContent = await file.readAsString();
    } catch (e) {
      return AiToolUtils.invalidResult(
        'Edit',
        'File was written but verification read failed: $e',
      );
    }
    final verificationPassed = verificationContent == writeContent;
    if (!verificationPassed) {
      return AiToolUtils.invalidResult(
        'Edit',
        'File was written but verification failed: content mismatch after write. '
            'This may indicate a concurrent modification.',
      );
    }

    final replacementCount = replacement.replacementCount;
    final outputMessage = !fileExists
        ? 'Created $filePath (verified)'
        : replaceAll
        ? 'Updated $filePath (replaced $replacementCount occurrence${replacementCount > 1 ? 's' : ''}, verified)'
        : 'Updated $filePath (verified)';

    // 2026-05-03: ledger 记录双快照
    final ledgerRecordId = await AiToolUtils.recordFileMutationToLedger(
      ledger: mutationLedger,
      sessionId: context.sessionId,
      toolCallId: context.toolCall.id,
      toolName: 'Edit',
      filePath: filePath,
      kind: fileExists ? FileMutationKind.modify : FileMutationKind.create,
      beforeContent: beforeContentForLedger,
      afterContent: verificationContent,
    );

    return AiToolUtils.simpleSuccessResult(
      command: 'Edit $filePath',
      output: outputMessage,
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
        'file_mutation_replacement_count': replacementCount,
        'file_mutation_verified': verificationPassed,
        if (versionId != null) 'file_mutation_history_version_id': versionId,
        if (ledgerRecordId != null)
          'file_mutation_ledger_record_id': ledgerRecordId,
      },
    );
  }
}
