import 'dart:io';

import 'package:path/path.dart' as p;

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
    // 模型可能省略开头斜杠，相对路径统一按工作目录解析。
    final filePath = AiToolUtils.resolvePathForContext(context, rawFilePath);
    final boundaryError = await AiToolUtils.validatePathWithinWorkingDirectory(
      context: context,
      toolName: 'Write',
      path: filePath,
    );
    if (boundaryError != null) return boundaryError;
    final content = '${args['content'] ?? ''}';

    final contentSizeValidation = AiToolUtils.validateGeneratedTextPayloadSize(
      toolName: 'Write',
      fieldName: 'content',
      value: content,
    );
    if (contentSizeValidation != null) return contentSizeValidation;

    final file = File(filePath);
    final fileExists = await AiToolUtils.fileExistsBounded(file);

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

    final committed = await AiToolUtils.commitTextFileMutation(
      context: context,
      toolName: 'Write',
      file: file,
      filePath: filePath,
      content: content,
      fileExists: fileExists,
      preparation: preparation,
    );
    if (committed.failure != null) return committed.failure!;
    final ledgerRecordId = committed.ledgerRecordId;

    return AiToolUtils.simpleSuccessResult(
      command: 'Write $filePath',
      output: 'Wrote ${content.length} characters to $filePath (verified)',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      isWriteCommand: true,
      metadata: AiToolUtils.fileMutationResultMetadata(
        kind: 'write',
        filePath: filePath,
        preparation: preparation,
        ledgerRecordId: ledgerRecordId,
        extra: <String, Object?>{
          'file_mutation_content_char_count': content.length,
        },
      ),
    );
  }
}
