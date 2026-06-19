import 'dart:io';

import 'package:path/path.dart' as p;

import '../../service/fs/ai_file_history_service.dart';
import '../../service/fs/ai_file_mutation_ledger.dart';
import '../../service/fs/ai_file_tracker_service.dart';
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
    final rawFilePath = '${args['file_path'] ?? ''}'.trim();
    if (rawFilePath.isEmpty) {
      return AiToolUtils.invalidResult(
        'MultiEdit',
        'MultiEdit requires a non-empty file_path.',
      );
    }
    final filePath = AiToolUtils.resolvePath(rawFilePath);
    final edits = args['edits'];
    if (edits is! List || edits.isEmpty) {
      return AiToolUtils.invalidResult(
        'MultiEdit',
        'MultiEdit requires a non-empty edits array.',
      );
    }
    final file = File(filePath);
    final bool fileExists = await file.exists();

    // 2026-04-13: 写操作权限确认检查
    final confirmationResult = await AiToolUtils.requestWriteConfirmation(
      toolName: 'MultiEdit',
      operationDescription:
          'Apply ${edits.length} edit${edits.length > 1 ? 's' : ''} to file',
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
      toolName: 'MultiEdit',
      filePath: filePath,
      previouslyReadFiles: context.previouslyReadFiles,
      requireExistingFileRead: fileExists,
      fileTracker: fileTracker,
    );
    if (readValidation != null) return readValidation;

    // 2026-04-12: 保存历史版本（仅对已存在的文件）
    String? versionId;
    String? beforeContentForLedger;
    if (fileExists) {
      versionId = await AiToolUtils.saveFileVersionBeforeMutation(
        filePath: filePath,
        sessionId: context.sessionId,
        toolCallId: context.toolCall.id,
        fileHistory: fileHistory,
      );
      beforeContentForLedger = await AiToolUtils.readFileContentForLedger(
        filePath,
      );
    }

    final String initialContent;
    if (fileExists) {
      try {
        initialContent = await file.readAsString();
      } on FormatException {
        return AiToolUtils.invalidResult(
          'MultiEdit',
          'File does not appear to be a valid text file: $filePath',
        );
      }
    } else {
      initialContent = '';
    }
    var content = initialContent;
    for (var editIndex = 0; editIndex < edits.length; editIndex++) {
      final rawEdit = edits[editIndex];
      if (rawEdit is! Map) {
        return AiToolUtils.invalidResult(
          'MultiEdit',
          'edits[$editIndex] must be an object.',
        );
      }
      final edit = Map<String, Object?>.from(rawEdit);
      final oldString = '${edit['old_string'] ?? ''}';
      final newString = '${edit['new_string'] ?? ''}';
      final replaceAll = edit['replace_all'] == true;
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
    }
    await AiToolUtils.writeTextFileSafely(file, content);

    // 2026-04-12: 更新追踪器（写入成功后更新 lastReadTime）
    await AiToolUtils.updateTrackerAfterMutation(
      filePath: filePath,
      fileTracker: fileTracker,
    );

    // 2026-04-12: 添加写入验证 - 读回文件确认修改已生效
    final String verificationContent;
    try {
      verificationContent = await file.readAsString();
    } catch (e) {
      return AiToolUtils.invalidResult(
        'MultiEdit',
        'File was written but verification read failed: $e',
      );
    }
    final verificationPassed = verificationContent == content;
    if (!verificationPassed) {
      return AiToolUtils.invalidResult(
        'MultiEdit',
        'File was written but verification failed: content mismatch after write. '
            'This may indicate a write permission issue or concurrent modification.',
      );
    }

    // 2026-05-03: ledger 记录双快照
    final mutationLedger =
        context.metadata['mutation_ledger'] as AiFileMutationLedger?;
    final ledgerRecordId = await AiToolUtils.recordFileMutationToLedger(
      ledger: mutationLedger,
      sessionId: context.sessionId,
      toolCallId: context.toolCall.id,
      toolName: 'MultiEdit',
      filePath: filePath,
      kind: fileExists ? FileMutationKind.modify : FileMutationKind.create,
      beforeContent: beforeContentForLedger,
      afterContent: verificationContent,
    );

    return AiToolUtils.simpleSuccessResult(
      command: 'MultiEdit $filePath',
      output:
          'Updated $filePath with ${edits.length} edit${edits.length > 1 ? 's' : ''} (verified)',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'file_mutation_kind': 'multi_edit',
        'file_mutation_path': filePath,
        'file_mutation_edit_count': edits.length,
        'file_mutation_verified': verificationPassed,
        if (versionId != null) 'file_mutation_history_version_id': versionId,
        if (ledgerRecordId != null)
          'file_mutation_ledger_record_id': ledgerRecordId,
      },
    );
  }
}
