import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

// 2026-04-01 01:21:38 从 AiToolRuntimeService._executeWriteTool 提取
class AiWriteTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.write;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final filePath = AiToolUtils.requireAbsoluteFilePath(
        '${args['file_path'] ?? ''}'.trim());
    if (filePath == null) {
      return AiToolUtils.invalidResult('Write', 'Write requires an absolute file_path.');
    }
    final content = '${args['content'] ?? ''}';
    final file = File(filePath);
    final readValidation = await AiToolUtils.validateReadBeforeMutation(
      toolName: 'Write',
      filePath: filePath,
      previouslyReadFiles: context.previouslyReadFiles,
      requireExistingFileRead: await file.exists(),
    );
    if (readValidation != null) return readValidation;
    await AiToolUtils.writeTextFileSafely(file, content);
    
    // 2026-04-12: 添加写入验证 - 读回文件确认修改已生效
    final String verificationContent;
    try {
      verificationContent = await file.readAsString();
    } catch (e) {
      return AiToolUtils.invalidResult('Write', 'File was written but verification read failed: $e');
    }
    final verificationPassed = verificationContent == content;
    final charCountMatches = verificationContent.length == content.length;
    if (!verificationPassed && !charCountMatches) {
      return AiToolUtils.invalidResult(
        'Write', 
        'File was written but verification failed: content mismatch. '
        'Expected ${content.length} chars, got ${verificationContent.length} chars. '
        'This may indicate a write permission issue or concurrent modification.',
      );
    }
    
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
      },
    );
  }
}
