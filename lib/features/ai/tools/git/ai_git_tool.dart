import '../../../../app/support/safe_subprocess.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// 2026-04-10 Git 工具 — 提供结构化 Git 操作，对标 Cursor Agent 的 Git 集成。
///
/// 支持操作：status, diff, log, blame, show, branch, stash_list.
/// 比 Bash 执行 raw git 命令更安全（只读操作、无交互模式）且输出更结构化。
/// 写操作（commit, push, checkout 等）保留在 Bash 中，需用户确认。
class AiGitTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.git;

  @override
  List<String> get aliases => const <String>['Git'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();

    final operation = '${args['operation'] ?? ''}'.trim();
    if (operation.isEmpty) {
      return AiToolUtils.invalidResult('Git', 'operation is required.');
    }

    final workingDirectory = AiToolUtils.resolvePath(
      '${args['working_directory'] ?? ''}'.trim(),
    );

    try {
      final output = await _executeGitOperation(
        operation,
        args,
        workingDirectory,
        toolCallId: context.toolCall.id,
      );
      return AiToolUtils.simpleSuccessResult(
        command: 'Git $operation',
        output: output,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: workingDirectory,
      );
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'Git $operation',
        workingDirectory: workingDirectory,
        stdout: '',
        stderr: '$error',
        durationMs: startedAt.elapsedMilliseconds,
        resultText:
            'status: failed\nerror: Git operation "$operation" failed: $error',
      );
    }
  }

  Future<String> _executeGitOperation(
    String operation,
    Map<String, Object?> args,
    String workingDirectory, {
    String? toolCallId,
  }) async {
    switch (operation) {
      case 'status':
        return _run(workingDirectory, <String>[
          'status',
          '--porcelain=v2',
          '--branch',
          '--show-stash',
        ], toolCallId: toolCallId);

      case 'diff':
        final target = '${args['target'] ?? ''}'.trim();
        final filePath = '${args['file_path'] ?? ''}'.trim();
        final staged = args['staged'] == true;
        if (target.isNotEmpty && target.startsWith('-')) {
          throw ArgumentError('Git diff target must not start with "-".');
        }
        final gitArgs = <String>['--no-pager', 'diff', '--stat', '-p'];
        if (staged) gitArgs.add('--cached');
        if (target.isNotEmpty) gitArgs.add(target);
        if (filePath.isNotEmpty) {
          gitArgs.add('--');
          gitArgs.add(filePath);
        }
        return _run(workingDirectory, gitArgs, toolCallId: toolCallId);

      case 'log':
        final count = AiToolUtils.readInt(args['count']) ?? 10;
        final safeCnt = count.clamp(1, 100);
        final filePath = '${args['file_path'] ?? ''}'.trim();
        final author = '${args['author'] ?? ''}'.trim();
        final since = '${args['since'] ?? ''}'.trim();
        final gitArgs = <String>[
          '--no-pager',
          'log',
          '--oneline',
          '--decorate',
          '--graph',
          '-n',
          '$safeCnt',
          '--format=%h %ad %an: %s',
          '--date=short',
        ];
        if (author.isNotEmpty) gitArgs.add('--author=$author');
        if (since.isNotEmpty) gitArgs.add('--since=$since');
        if (filePath.isNotEmpty) {
          gitArgs.add('--');
          gitArgs.add(filePath);
        }
        return _run(workingDirectory, gitArgs, toolCallId: toolCallId);

      case 'blame':
        final filePath = '${args['file_path'] ?? ''}'.trim();
        if (filePath.isEmpty) {
          throw ArgumentError('Git blame requires file_path.');
        }
        final startLine = AiToolUtils.readInt(args['start_line']);
        final endLine = AiToolUtils.readInt(args['end_line']);
        final gitArgs = <String>['--no-pager', 'blame', '--date=short'];
        if (startLine != null && endLine != null) {
          gitArgs.add('-L');
          gitArgs.add('$startLine,$endLine');
        }
        gitArgs.add('--');
        gitArgs.add(filePath);
        return _run(workingDirectory, gitArgs, toolCallId: toolCallId);

      case 'show':
        final ref = '${args['target'] ?? args['ref'] ?? 'HEAD'}'.trim();
        if (ref.startsWith('-')) {
          throw ArgumentError('Git show ref must not start with "-".');
        }
        return _run(workingDirectory, <String>[
          '--no-pager',
          'show',
          '--stat',
          '-p',
          ref,
        ], toolCallId: toolCallId);

      case 'branch':
        return _run(workingDirectory, <String>[
          'branch',
          '-vv',
          '--list',
        ], toolCallId: toolCallId);

      case 'stash_list':
        return _run(workingDirectory, <String>[
          'stash',
          'list',
        ], toolCallId: toolCallId);

      default:
        return 'Unknown Git operation: $operation. Supported: status, diff, log, blame, show, branch, stash_list.';
    }
  }

  Future<String> _run(
    String workingDirectory,
    List<String> args, {
    String? toolCallId,
  }) async {
    final result = await runProcessWithTimeout(
      'git',
      args,
      workingDirectory: workingDirectory,
      timeout: const Duration(minutes: 2),
      tag: 'ai_git_tool',
      toolCallId: toolCallId,
    );
    if (result == null) {
      throw Exception('git ${args.join(' ')} timed out or failed to spawn');
    }
    final stdout = (result.stdout as String).trimRight();
    final stderr = (result.stderr as String).trimRight();
    if (result.exitCode != 0) {
      throw Exception(
        'git ${args.join(' ')} exited with code ${result.exitCode}\n'
        '${stderr.isNotEmpty ? stderr : stdout}',
      );
    }
    if (stdout.isEmpty) return '(no output)';
    // Truncate very large output
    if (stdout.length > AiToolUtils.maxSearchOutputCharacters) {
      return '${stdout.substring(0, AiToolUtils.maxSearchOutputCharacters)}\n'
          '... (output truncated at ${AiToolUtils.maxSearchOutputCharacters} characters)';
    }
    return stdout;
  }
}
