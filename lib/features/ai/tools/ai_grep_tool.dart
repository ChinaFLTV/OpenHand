import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/bash/ai_bash_tool_service.dart';
import '../service/runtime/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

class AiGrepTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.grep;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();

    // 参数解析
    final pattern = '${args['pattern'] ?? ''}'.trim();
    if (pattern.isEmpty) {
      return AiToolUtils.invalidResult('Grep', 'Grep requires pattern.');
    }

    // 路径解析和验证
    final rawPath = '${args['path'] ?? ''}'.trim();
    final path = rawPath.isEmpty
        ? AiToolUtils.defaultWorkingDirectory()
        : (p.isAbsolute(rawPath)
              ? p.normalize(rawPath)
              : p.normalize(
                  p.join(AiToolUtils.defaultWorkingDirectory(), rawPath),
                ));

    // 验证路径存在性
    final pathType = FileSystemEntity.typeSync(path);
    if (pathType == FileSystemEntityType.notFound) {
      return AiToolUtils.invalidResult('Grep', 'Path does not exist: $path');
    }

    final glob = '${args['glob'] ?? ''}'.trim();
    final outputMode = '${args['output_mode'] ?? 'files_with_matches'}'.trim();
    final before = AiToolUtils.readInt(args['-B']);
    final after = AiToolUtils.readInt(args['-A']);
    final contextLines = AiToolUtils.readInt(args['-C']);
    final showLineNumbers = args['-n'] == true;
    final caseInsensitive = args['-i'] == true;
    final type = '${args['type'] ?? ''}'.trim();
    final headLimit = AiToolUtils.readInt(args['head_limit']);
    final multiline = args['multiline'] == true;

    // 查找 rg 可执行文件（优先使用应用内嵌入的 vendor/ripgrep；
    // 仅当应用打包损坏导致内嵌二进制丢失时才会回退到系统 PATH）。
    final rgPath = await AiToolUtils.resolveRipgrepPath();
    if (rgPath == null) {
      const message =
          'ripgrep (rg) binary unavailable. The application bundles rg under '
          'vendor/ripgrep/{arch}-{os}/rg, so this normally never happens — '
          'reinstall the app or ensure the vendor directory was shipped. '
          'As a last resort install ripgrep system-wide (e.g. `brew install '
          'ripgrep` on macOS).';
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'Grep $pattern',
        workingDirectory: path,
        stdout: '',
        stderr: message,
        durationMs: startedAt.elapsedMilliseconds,
        exitCode: 127,
        resultText:
            'status: failed\nexit_code: 127\nstdout:\n\nstderr:\n$message',
      );
    }

    // 构建 rg 参数列表
    final rgArgs = <String>[];
    switch (outputMode) {
      case 'content':
        break;
      case 'count':
        rgArgs.add('--count');
      case 'files_with_matches':
        rgArgs.add('--files-with-matches');
      default:
        rgArgs.add('--files-with-matches');
    }
    if (before != null) {
      rgArgs
        ..add('-B')
        ..add('$before');
    }
    if (after != null) {
      rgArgs
        ..add('-A')
        ..add('$after');
    }
    if (contextLines != null) {
      rgArgs
        ..add('-C')
        ..add('$contextLines');
    }
    if (showLineNumbers) {
      rgArgs.add('-n');
    }
    if (caseInsensitive) {
      rgArgs.add('-i');
    }
    if (type.isNotEmpty) {
      rgArgs
        ..add('--type')
        ..add(type);
    }
    if (glob.isNotEmpty) {
      rgArgs
        ..add('--glob')
        ..add(glob);
    }
    if (multiline) {
      rgArgs
        ..add('-U')
        ..add('--multiline-dotall');
    }

    // 确定搜索目标和工作目录
    final String workingDir;
    final String searchTarget;
    if (pathType == FileSystemEntityType.directory) {
      // 目录：设置为工作目录，搜索 '.'
      workingDir = path;
      searchTarget = '.';
    } else {
      // 文件：父目录为工作目录，搜索文件名
      workingDir = p.dirname(path);
      searchTarget = p.basename(path);
    }
    rgArgs
      ..add(pattern)
      ..add(searchTarget);

    // 执行 rg 命令（使用共享工具方法）
    final rgResult = await AiToolUtils.runProcessSafely(
      rgPath,
      rgArgs,
      workingDirectory: workingDir,
    );
    if (rgResult.exitCode == 0 ||
        (rgResult.exitCode == 1 && rgResult.stdout.trim().isEmpty)) {
      var output = rgResult.stdout.trimRight();
      if (output.isEmpty) {
        output = outputMode == 'count' ? '(zero matches)' : '(no matches)';
      } else if (headLimit != null && headLimit > 0) {
        output = output.split('\n').take(headLimit).join('\n');
      }
      if (output.length > AiToolUtils.maxSearchOutputCharacters) {
        output =
            '${output.substring(0, AiToolUtils.maxSearchOutputCharacters)}...';
      }
      return AiToolUtils.simpleSuccessResult(
        command: 'Grep $pattern',
        output: output,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: path,
      );
    }

    // 处理执行失败
    final stderrText = rgResult.stderr.trimRight();
    final stdoutText = rgResult.stdout.trimRight();
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: 'Grep $pattern',
      workingDirectory: path,
      stdout: stdoutText,
      stderr: stderrText,
      durationMs: startedAt.elapsedMilliseconds,
      exitCode: rgResult.exitCode,
      resultText: _buildFailureResultText(
        exitCode: rgResult.exitCode,
        stdout: stdoutText,
        stderr: stderrText,
      ),
    );
  }

  /// 构建失败结果文本，提供更清晰的错误信息。
  String _buildFailureResultText({
    required int exitCode,
    required String stdout,
    required String stderr,
  }) {
    final buffer = StringBuffer('status: failed\nexit_code: $exitCode');
    if (stdout.isNotEmpty) {
      buffer
        ..writeln()
        ..write('stdout:\n')
        ..write(stdout);
    }
    if (stderr.isNotEmpty) {
      buffer
        ..writeln()
        ..write('stderr:\n')
        ..write(stderr);
    }
    // 为常见错误码添加提示
    if (exitCode == 2) {
      buffer
        ..writeln()
        ..write(
          'hint: Exit code 2 typically indicates a syntax error in the regex pattern.',
        );
    }
    return buffer.toString().trim();
  }
}
