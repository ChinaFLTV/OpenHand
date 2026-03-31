import 'dart:io';

import '../service/ai_bash_tool_service.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

// 2026-04-01 01:21:38 从 AiToolRuntimeService._executeGrepTool 提取
class AiGrepTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.grep;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final pattern = '${args['pattern'] ?? ''}'.trim();
    if (pattern.isEmpty) {
      return AiToolUtils.invalidResult('Grep', 'Grep requires pattern.');
    }
    final path = AiToolUtils.resolvePath('${args['path'] ?? ''}'.trim());
    final glob = '${args['glob'] ?? ''}'.trim();
    final outputMode =
        '${args['output_mode'] ?? 'files_with_matches'}'.trim();
    final before = AiToolUtils.readInt(args['-B']);
    final after = AiToolUtils.readInt(args['-A']);
    final contextLines = AiToolUtils.readInt(args['-C']);
    final showLineNumbers = args['-n'] == true;
    final caseInsensitive = args['-i'] == true;
    final type = '${args['type'] ?? ''}'.trim();
    final headLimit = AiToolUtils.readInt(args['head_limit']);
    final multiline = args['multiline'] == true;

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
    if (before != null) rgArgs..add('-B')..add('$before');
    if (after != null) rgArgs..add('-A')..add('$after');
    if (contextLines != null) rgArgs..add('-C')..add('$contextLines');
    if (showLineNumbers) rgArgs.add('-n');
    if (caseInsensitive) rgArgs.add('-i');
    if (type.isNotEmpty) rgArgs..add('--type')..add(type);
    if (glob.isNotEmpty) rgArgs..add('--glob')..add(glob);
    if (multiline) rgArgs..add('-U')..add('--multiline-dotall');
    rgArgs..add(pattern)..add(path);

    final rgResult = await _runProcess('rg', rgArgs);
    if (rgResult.exitCode == 0 ||
        (rgResult.exitCode == 1 && rgResult.stdout.trim().isEmpty)) {
      var output = rgResult.stdout.trimRight();
      if (output.isEmpty) {
        output = outputMode == 'count' ? '(zero matches)' : '(no matches)';
      } else if (headLimit != null && headLimit > 0) {
        output = output.split('\n').take(headLimit).join('\n');
      }
      if (output.length > AiToolUtils.maxSearchOutputCharacters) {
        output = '${output.substring(0, AiToolUtils.maxSearchOutputCharacters)}...';
      }
      return AiToolUtils.simpleSuccessResult(
        command: 'Grep $pattern',
        output: output,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: path,
      );
    }
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: 'Grep $pattern',
      workingDirectory: path,
      stdout: rgResult.stdout,
      stderr: rgResult.stderr,
      durationMs: startedAt.elapsedMilliseconds,
      exitCode: rgResult.exitCode,
      resultText:
          'status: failed\nexit_code: ${rgResult.exitCode}\nstdout:\n${rgResult.stdout.trimRight()}\nstderr:\n${rgResult.stderr.trimRight()}'
              .trim(),
    );
  }

  Future<ProcessResult> _runProcess(String executable, List<String> args) async {
    try {
      return await Process.run(executable, args);
    } on ProcessException catch (error) {
      return ProcessResult(0, 127, '', error.message);
    }
  }
}
