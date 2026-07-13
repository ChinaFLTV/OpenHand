import 'dart:io';

import 'package:path/path.dart' as p;

import '../../service/fs/ai_file_mutation_ledger.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiWriteTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.write;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final rawFilePath = AiToolUtils.readString(args['file_path']);
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

    final contentSizeValidation = AiToolUtils.validateGeneratedTextPayloadSize(
      toolName: 'Write',
      fieldName: 'content',
      value: content,
    );
    if (contentSizeValidation != null) return contentSizeValidation;

    final file = File(filePath);
    final fileExists = await file.exists();

    final preparation = await AiToolUtils.prepareFileMutation(
      context: context,
      toolName: 'Write',
      operationDescription: fileExists
          ? 'Overwrite file with ${content.length} characters'
          : 'Create new file with ${content.length} characters',
      filePath: filePath,
      fileExists: fileExists,
    );
    if (preparation.error != null) return preparation.error!;

    final guardedWrite = await AiToolUtils.writeTextFileWithMutationGuard(
      toolName: 'Write',
      file: file,
      content: content,
      previouslyReadFiles: context.previouslyReadFiles,
      requireExistingFileRead: fileExists,
      fileTracker: preparation.fileTracker,
    );
    if (guardedWrite != null) return guardedWrite;

    final verificationError = await AiToolUtils.verifyTextFileWrite(
      toolName: 'Write',
      file: file,
      expectedContent: content,
    );
    if (verificationError != null) return verificationError;

    // Ledger 同时记录写入前后的快照。
    final mutationLedger =
        context.metadata['mutation_ledger'] as AiFileMutationLedger?;
    final ledgerRecordId = await AiToolUtils.recordFileMutationToLedger(
      ledger: mutationLedger,
      sessionId: context.sessionId,
      toolCallId: context.toolCall.id,
      toolName: 'Write',
      filePath: filePath,
      kind: fileExists ? FileMutationKind.modify : FileMutationKind.create,
      beforeContent: preparation.beforeContent,
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
        'file_mutation_verified': true,
        if (preparation.historyVersionId != null)
          'file_mutation_history_version_id': preparation.historyVersionId,
        if (ledgerRecordId != null)
          'file_mutation_ledger_record_id': ledgerRecordId,
      },
    );
  }
}
