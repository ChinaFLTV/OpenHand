import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../shared/util/path_safety.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/fs/ai_file_mutation_ledger.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// DeleteFile 工具，对标 Cursor 的 delete_file。
///
/// 删除指定路径的文件。操作在以下情况下会优雅失败：
/// - 文件不存在
/// - 路径不安全（目录删除、根路径等）
/// - 权限不足
class AiDeleteFileTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.deleteFile;

  @override
  List<String> get aliases => const <String>['DeleteFile'];

  /// 删除操作是不可逆的破坏性操作。
  @override
  bool get isDestructive => true;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();

    final rawPath = AiToolUtils.readFirstString(args, const <String>[
      'file_path',
      'target_file',
    ]);
    if (rawPath.isEmpty) {
      return AiToolUtils.invalidResult('DeleteFile', '必须提供 file_path。');
    }

    final filePath = AiToolUtils.resolvePathForContext(context, rawPath);
    final boundaryError = await AiToolUtils.validatePathWithinWorkingDirectory(
      context: context,
      toolName: 'DeleteFile',
      path: filePath,
    );
    if (boundaryError != null) return boundaryError;

    // 禁止删除根路径、系统目录及其内部文件。
    if (_isUnsafePath(filePath)) {
      return AiToolUtils.invalidResult(
        'DeleteFile',
        '拒绝删除不安全路径：$filePath。禁止删除目录和关键系统路径。',
      );
    }

    final file = File(filePath);
    if (!await AiToolUtils.fileExistsBounded(file)) {
      return AiToolUtils.simpleSuccessResult(
        command: 'DeleteFile $filePath',
        output: '文件不存在，无需处理：$filePath',
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(filePath),
      );
    }

    // 仅允许删除文件。
    final stat = await AiToolUtils.fileStatBounded(file);
    if (stat.type == FileSystemEntityType.directory) {
      return AiToolUtils.invalidResult(
        'DeleteFile',
        '目标是目录而不是文件：$filePath。删除目录必须通过 Bash 并取得用户明确确认。',
      );
    }

    final fileTracker = context.fileTracker;
    final fileHistory = context.fileHistory;

    final readValidation = await AiToolUtils.validateReadBeforeMutation(
      toolName: 'DeleteFile',
      filePath: filePath,
      previouslyReadFiles: context.previouslyReadFiles,
      fileTracker: fileTracker,
    );
    if (readValidation != null) return readValidation;

    // 写操作权限确认检查（删除为不可逆破坏性操作）
    final confirmationResult = await AiToolUtils.requestWriteConfirmation(
      toolName: 'DeleteFile',
      operationDescription: '删除文件（不可恢复）',
      targetPath: filePath,
      requireWriteConfirmation: context.requireWriteCommandConfirmation,
      confirmWriteCommand: context.confirmWriteCommand,
      cancelSignal: context.cancelSignal,
      timeoutMs: context.writeConfirmationTimeoutMs,
    );
    if (confirmationResult != null) {
      return confirmationResult;
    }

    try {
      final versionId = await AiToolUtils.saveFileVersionBeforeMutation(
        filePath: filePath,
        sessionId: context.sessionId,
        toolCallId: context.toolCall.id,
        fileHistory: fileHistory,
      );

      // 在删除前抓取 before 内容入 ledger
      final mutationLedger = context.mutationLedger;
      final beforeContentForLedger = await AiToolUtils.readFileContentForLedger(
        filePath,
      );
      final guardedDelete = await AiToolUtils.deleteFileWithMutationGuard(
        toolName: 'DeleteFile',
        file: file,
        previouslyReadFiles: context.previouslyReadFiles,
        fileTracker: fileTracker,
      );
      if (guardedDelete != null) return guardedDelete;
      final ledgerRecordId = await AiToolUtils.recordFileMutationToLedger(
        ledger: mutationLedger,
        sessionId: context.sessionId,
        toolCallId: context.toolCall.id,
        toolName: 'DeleteFile',
        filePath: filePath,
        kind: FileMutationKind.delete,
        beforeContent: beforeContentForLedger,
        afterContent: null,
      );
      return AiToolUtils.simpleSuccessResult(
        command: 'DeleteFile $filePath',
        output: '已删除：$filePath',
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(filePath),
        isWriteCommand: true,
        metadata: <String, Object?>{
          'tool_source': 'builtin',
          'file_mutation_kind': 'delete',
          'file_mutation_path': filePath,
          if (versionId != null) 'file_mutation_history_version_id': versionId,
          if (ledgerRecordId != null)
            'file_mutation_ledger_record_id': ledgerRecordId,
        },
      );
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'DeleteFile $filePath',
        workingDirectory: p.dirname(filePath),
        stdout: '',
        stderr: '删除文件失败：$filePath：$error',
        durationMs: startedAt.elapsedMilliseconds,
        resultText: 'status: failed\nerror: 删除文件失败：$filePath：$error',
      );
    }
  }

  bool _isUnsafePath(String filePath) {
    final normalized = p.normalize(filePath);
    if (!p.isAbsolute(normalized)) return true;
    final filesystemRoot = p.rootPrefix(normalized);
    if (filesystemRoot.isEmpty || p.equals(normalized, filesystemRoot)) {
      return true;
    }
    if (p.equals(normalized, OpenHandPaths.homeDirectoryPath())) return true;

    final criticalRoots = Platform.isWindows
        ? <String>[
            p.join(filesystemRoot, 'Windows'),
            p.join(filesystemRoot, 'Program Files'),
            p.join(filesystemRoot, 'Program Files (x86)'),
            p.join(filesystemRoot, 'ProgramData'),
          ]
        : const <String>[
            '/System',
            '/usr',
            '/bin',
            '/sbin',
            '/etc',
            '/var',
            '/Library',
            '/private/etc',
            '/private/var',
            '/proc',
            '/sys',
            '/dev',
            '/boot',
            '/run',
            '/snap',
          ];
    return criticalRoots.any((root) => isPathWithinOrEqual(root, normalized));
  }
}
