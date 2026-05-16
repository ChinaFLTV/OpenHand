import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/fs/ai_file_history_service.dart';
import '../service/fs/ai_file_mutation_ledger.dart';
import '../service/fs/ai_file_tracker_service.dart';
import '../service/runtime/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

class AiWriteTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.write;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final rawFilePath = '${args['file_path'] ?? ''}'.trim();
    if (rawFilePath.isEmpty) {
      return AiToolUtils.invalidResult(
        'Write',
        'Write requires a non-empty file_path.',
      );
    }
    // Resolve relative paths to absolute using the working directory rather
    // than hard-rejecting them — models sometimes omit the leading '/'.
    final filePath = AiToolUtils.resolvePath(rawFilePath);
    final content = '${args['content'] ?? ''}';

    // Guard against excessively large writes that could exhaust memory or
    // disk space.  10 MB is a generous limit for any single text file an AI
    // model would reasonably produce.
    const maxContentBytes = 10 * 1024 * 1024; // 10 MB
    if (content.length > maxContentBytes) {
      return AiToolUtils.invalidResult(
        'Write',
        'Content exceeds the maximum allowed size '
            '(${content.length} chars, limit $maxContentBytes). '
            'Split the output into smaller files.',
      );
    }

    final file = File(filePath);
    final fileExists = await file.exists();

    // 2026-04-13: 写操作权限确认检查
    final confirmationResult = await AiToolUtils.requestWriteConfirmation(
      toolName: 'Write',
      operationDescription: fileExists
          ? 'Overwrite file with ${content.length} characters'
          : 'Create new file with ${content.length} characters',
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
      toolName: 'Write',
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
      beforeContentForLedger =
          await AiToolUtils.readFileContentForLedger(filePath);
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
        'Write',
        'File was written but verification read failed: $e',
      );
    }
    final verificationPassed = verificationContent == content;
    // 2026-04-14: 修复验证逻辑 - 只要内容不匹配就报错（之前错误地要求同时满足字符数不匹配）
    if (!verificationPassed) {
      return AiToolUtils.invalidResult(
        'Write',
        'File was written but verification failed: content mismatch. '
            'Expected ${content.length} chars, got ${verificationContent.length} chars. '
            'This may indicate a write permission issue or concurrent modification.',
      );
    }

    // 2026-05-03: 新型 ledger 记录双快照
    final mutationLedger =
        context.metadata['mutation_ledger'] as AiFileMutationLedger?;
    final ledgerRecordId = await AiToolUtils.recordFileMutationToLedger(
      ledger: mutationLedger,
      sessionId: context.sessionId,
      toolCallId: context.toolCall.id,
      toolName: 'Write',
      filePath: filePath,
      kind: fileExists ? FileMutationKind.modify : FileMutationKind.create,
      beforeContent: beforeContentForLedger,
      afterContent: content,
    );

    return AiToolUtils.simpleSuccessResult(
      command: 'Write $filePath',
      output: 'Wrote ${content.length} characters to $filePath (verified)',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'file_mutation_kind': 'write',
        'file_mutation_path': filePath,
        'file_mutation_content_char_count': content.length,
        'file_mutation_verified': verificationPassed,
        if (versionId != null) 'file_mutation_history_version_id': versionId,
        if (ledgerRecordId != null)
          'file_mutation_ledger_record_id': ledgerRecordId,
      },
    );
  }
}
