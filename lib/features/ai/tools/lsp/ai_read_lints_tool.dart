import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/safe_subprocess.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// 调用 `dart analyze` 或 `flutter analyze` 获取指定范围的诊断信息。
///
/// 通过调用 `dart analyze` / `flutter analyze` 获取指定文件或目录的
/// 编译错误、警告和提示信息。
///
/// 用法：
/// - 指定 paths 数组限定范围（推荐：只对编辑过的文件调用）
/// - 不指定 paths 则分析整个工作区（较慢，应谨慎使用）
class AiReadLintsTool extends AiTool {
  static const int _maxPubspecBytes = 2 * kBytesPerMiB;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.readLints;

  @override
  List<String> get aliases => const <String>['ReadLints'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();

    final paths = _parsePaths(args['paths']);
    final workingDirectory = AiToolUtils.resolvePathForContext(
      context,
      AiToolUtils.readString(args['working_directory']),
    );
    final boundaryError = await AiToolUtils.validatePathWithinWorkingDirectory(
      context: context,
      toolName: 'ReadLints',
      path: workingDirectory,
    );
    if (boundaryError != null) return boundaryError;

    try {
      final output = await _runAnalyze(
        workingDirectory,
        paths,
        toolCallId: context.toolCall.id,
      );
      return AiToolUtils.simpleSuccessResult(
        command: 'ReadLints',
        output: output,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: workingDirectory,
      );
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'ReadLints',
        workingDirectory: workingDirectory,
        stdout: '',
        stderr: '$error',
        durationMs: startedAt.elapsedMilliseconds,
        resultText: 'status: failed\nerror: ReadLints failed: $error',
      );
    }
  }

  List<String> _parsePaths(Object? value) {
    if (value is List) {
      return stringListFromValue(value);
    }
    if (value is String && value.trim().isNotEmpty) {
      final jsonList = optionalStringListFromJsonText(value, requireList: true);
      return jsonList ?? <String>[value.trim()];
    }
    return const <String>[];
  }

  Future<String> _runAnalyze(
    String workingDirectory,
    List<String> paths, {
    String? toolCallId,
  }) async {
    // 根据项目类型选择分析器。
    final pubspecPath = p.join(workingDirectory, 'pubspec.yaml');
    final usesFlutter =
        await isRegularFilePath(pubspecPath, followLinks: true) &&
        await _pubspecMentionsFlutter(pubspecPath);

    final executable = usesFlutter ? 'flutter' : 'dart';
    final analyzeArgs = <String>[
      'analyze',
      if (usesFlutter) '--no-fatal-infos',
    ];

    // 未指定路径时分析项目根目录。
    if (paths.isNotEmpty) {
      for (final path in paths) {
        analyzeArgs.add(_resolveAnalyzePath(path, workingDirectory));
      }
    }

    var timedOut = false;
    final result = await runProcessWithTimeout(
      executable,
      analyzeArgs,
      workingDirectory: workingDirectory,
      timeout: const Duration(seconds: 60),
      tag: 'ai_read_lints_tool',
      toolCallId: toolCallId,
      maxStdoutBytes: AiToolUtils.maxSearchOutputCharacters * 4,
      maxStderrBytes: AiToolUtils.maxSearchOutputCharacters * 4,
      timeoutResultBuilder: (pid, stdout, stderr) {
        timedOut = true;
        return ProcessResult(pid, 124, stdout, stderr);
      },
    );
    if (result == null) {
      throw FormatException('Failed to launch "$executable analyze".');
    }

    if (timedOut) {
      return 'Analysis timed out after 60 seconds (analyzer process killed)';
    }

    final stdout = (result.stdout as String).trimRight();
    final stderr = (result.stderr as String).trimRight();
    final exitCode = result.exitCode;

    // dart/flutter analyze returns exit code 0 for success, non-zero for issues found
    // Both cases are valid — we want to show the diagnostics
    final combined = <String>[];
    if (stdout.isNotEmpty) combined.add(stdout);
    if (stderr.isNotEmpty && exitCode != 0) combined.add(stderr);

    final output = combined.join('\n').trimRight();
    if (output.isEmpty) return '(no diagnostics found — all clean)';

    return AiToolUtils.truncateContent(
      output,
      AiToolUtils.maxSearchOutputCharacters,
      suffix: '\n...（诊断输出已截断）',
    );
  }

  String _resolveAnalyzePath(String path, String workingDirectory) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return workingDirectory;
    return p.isAbsolute(trimmed)
        ? p.normalize(trimmed)
        : p.normalize(p.join(workingDirectory, trimmed));
  }

  Future<bool> _pubspecMentionsFlutter(String pubspecPath) async {
    try {
      final content = await readBoundedFileString(
        File(pubspecPath),
        maxBytes: _maxPubspecBytes,
      );
      return content.contains('flutter:') || content.contains('sdk: flutter');
    } catch (_) {
      return false;
    }
  }
}
