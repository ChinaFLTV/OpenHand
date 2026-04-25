import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/ai_bash_tool_service.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

/// 2026-04-10 DeleteFile 工具 — 对标 Cursor 的 delete_file。
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

    final rawPath = '${args['file_path'] ?? args['target_file'] ?? ''}'.trim();
    if (rawPath.isEmpty) {
      return AiToolUtils.invalidResult('DeleteFile', 'file_path is required.');
    }

    final filePath =
        AiToolUtils.requireAbsoluteFilePath(rawPath) ??
        AiToolUtils.resolvePath(rawPath);

    // Safety: prevent deleting directories, root paths, and common critical files
    if (_isUnsafePath(filePath)) {
      return AiToolUtils.invalidResult(
        'DeleteFile',
        'Refused to delete unsafe path: $filePath. '
            'Directory deletion and critical system paths are not allowed.',
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      return AiToolUtils.simpleSuccessResult(
        command: 'DeleteFile $filePath',
        output: 'File does not exist (no action needed): $filePath',
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(filePath),
      );
    }

    // Check that it's actually a file, not a directory
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.directory) {
      return AiToolUtils.invalidResult(
        'DeleteFile',
        'Path is a directory, not a file: $filePath. '
            'Use Bash with explicit user confirmation for directory removal.',
      );
    }

    // 2026-04-13: 写操作权限确认检查（删除为不可逆破坏性操作）
    final confirmationResult = await AiToolUtils.requestWriteConfirmation(
      toolName: 'DeleteFile',
      operationDescription: 'Delete file (irreversible)',
      targetPath: filePath,
      requireWriteConfirmation: context.requireWriteCommandConfirmation,
      confirmWriteCommand: context.confirmWriteCommand,
      cancelSignal: context.cancelSignal,
    );
    if (confirmationResult != null) {
      return confirmationResult;
    }

    try {
      await file.delete();
      return AiToolUtils.simpleSuccessResult(
        command: 'DeleteFile $filePath',
        output: 'Deleted: $filePath',
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(filePath),
        isWriteCommand: true,
        metadata: <String, Object?>{
          'tool_source': 'builtin',
          'file_mutation_kind': 'delete',
          'file_mutation_path': filePath,
        },
      );
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'DeleteFile $filePath',
        workingDirectory: p.dirname(filePath),
        stdout: '',
        stderr: 'Failed to delete $filePath: $error',
        durationMs: startedAt.elapsedMilliseconds,
        resultText: 'status: failed\nerror: Failed to delete $filePath: $error',
      );
    }
  }

  bool _isUnsafePath(String filePath) {
    final normalized = p.normalize(filePath);
    // Block root paths
    if (normalized == '/' || normalized == p.separator) return true;
    // Block home directory itself
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty && normalized == home) return true;
    // Block critical system directories and OS-managed locations
    final criticalPrefixes = <String>[
      // Unix/macOS common
      '/System',
      '/usr',
      '/bin',
      '/sbin',
      '/etc',
      '/var',
      '/Library',
      '/Volumes',
      // Linux-specific
      '/proc',
      '/sys',
      '/dev',
      '/boot',
      '/run',
      '/snap',
      // Windows (only relevant on Windows)
      if (Platform.isWindows) ...[
        r'C:\Windows',
        r'C:\Program Files',
        r'C:\Program Files (x86)',
      ],
    ];
    final normalizedLower = normalized.toLowerCase();
    for (final prefix in criticalPrefixes) {
      if (normalizedLower.startsWith(prefix.toLowerCase())) return true;
    }
    return false;
  }
}
