import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/silent_log.dart';
import '../service/ai_bash_tool_service.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

/// 2026-04-10 ReadLints 工具 — 对标 Cursor 的 read_lints 诊断工具。
///
/// 通过调用 `dart analyze` / `flutter analyze` 获取指定文件或目录的
/// 编译错误、警告和提示信息。
///
/// 用法：
/// - 指定 paths 数组限定范围（推荐：只对编辑过的文件调用）
/// - 不指定 paths 则分析整个工作区（较慢，应谨慎使用）
class AiReadLintsTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.readLints;

  @override
  List<String> get aliases => const <String>['ReadLints'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();

    final paths = _parsePaths(args['paths']);
    final workingDirectory = AiToolUtils.resolvePath(
      '${args['working_directory'] ?? ''}'.trim(),
    );

    try {
      final output = await _runAnalyze(workingDirectory, paths);
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
      return value
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    if (value is String && value.trim().isNotEmpty) {
      return <String>[value.trim()];
    }
    return const <String>[];
  }

  Future<String> _runAnalyze(
    String workingDirectory,
    List<String> paths,
  ) async {
    // Determine whether to use flutter analyze or dart analyze
    final usesFlutter =
        File(p.join(workingDirectory, 'pubspec.yaml')).existsSync() &&
        _pubspecMentionsFlutter(p.join(workingDirectory, 'pubspec.yaml'));

    final executable = usesFlutter ? 'flutter' : 'dart';
    final analyzeArgs = <String>['analyze', '--no-fatal-infos'];

    // If specific paths given, analyze those; otherwise analyze from root
    if (paths.isNotEmpty) {
      for (final path in paths) {
        analyzeArgs.add(AiToolUtils.resolvePath(path));
      }
    }

    // Use Process.start so we can hard-kill the lingering analyzer on
    // timeout — `Process.run(...).timeout(...)` only abandons the Dart
    // future while `flutter analyze` keeps consuming CPU/disk for the
    // remainder of its run.
    Process? process;
    var timedOut = false;
    try {
      process = await Process.start(
        executable,
        analyzeArgs,
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (error, stack) {
      silentLog('ai_read_lints_tool', 'spawn $executable', error, stack);
      throw FormatException(
        'Failed to launch "$executable analyze": ${error.message}',
      );
    }

    final stdoutFuture = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();

    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        timedOut = true;
        process?.kill(ProcessSignal.sigkill);
        return 124;
      },
    );

    final stdoutText = await stdoutFuture.timeout(
      const Duration(seconds: 1),
      onTimeout: () => '',
    );
    final stderrText = await stderrFuture.timeout(
      const Duration(seconds: 1),
      onTimeout: () => '',
    );

    if (timedOut) {
      return 'Analysis timed out after 60 seconds (analyzer process killed)';
    }

    final stdout = stdoutText.trimRight();
    final stderr = stderrText.trimRight();

    // dart/flutter analyze returns exit code 0 for success, non-zero for issues found
    // Both cases are valid — we want to show the diagnostics
    final combined = <String>[];
    if (stdout.isNotEmpty) combined.add(stdout);
    if (stderr.isNotEmpty && exitCode != 0) combined.add(stderr);

    final output = combined.join('\n').trimRight();
    if (output.isEmpty) return '(no diagnostics found — all clean)';

    // Truncate if too large
    if (output.length > AiToolUtils.maxSearchOutputCharacters) {
      return '${output.substring(0, AiToolUtils.maxSearchOutputCharacters)}\n'
          '... (diagnostics truncated)';
    }
    return output;
  }

  bool _pubspecMentionsFlutter(String pubspecPath) {
    try {
      final content = File(pubspecPath).readAsStringSync();
      return content.contains('flutter:') || content.contains('sdk: flutter');
    } catch (_) {
      return false;
    }
  }
}
