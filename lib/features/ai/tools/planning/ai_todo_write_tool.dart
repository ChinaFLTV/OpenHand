import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiTodoWriteTool extends AiTool {
  static const int _verificationReminderTodoThreshold = 3;
  static const String _verificationReminder =
      'verification_reminder: All major todos are marked completed. Before a final completion claim, verify the change with ReadLints, tests, build, a direct command, or Task(subagent_type: verify), and report any skipped check explicitly.';

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.todoWrite;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final todos = args['todos'];
    if (todos is! List) {
      return AiToolUtils.invalidResult(
        'TodoWrite',
        'TodoWrite requires a todos array.',
      );
    }
    final normalizedTodos = <Map<String, Object?>>[];
    final seenIds = <String>{};
    var inProgressCount = 0;
    for (final rawTodo in todos) {
      if (rawTodo is! Map) {
        return AiToolUtils.invalidResult(
          'TodoWrite',
          'Each todo must be an object.',
        );
      }
      final todo = Map<String, Object?>.from(rawTodo);
      final id = '${todo['id'] ?? ''}'.trim();
      final content = '${todo['content'] ?? ''}'.trim();
      final status = '${todo['status'] ?? ''}'.trim();
      if (id.isEmpty || content.isEmpty) {
        return AiToolUtils.invalidResult(
          'TodoWrite',
          'Each todo must include id and content.',
        );
      }
      if (!seenIds.add(id)) {
        return AiToolUtils.invalidResult(
          'TodoWrite',
          'Todo ids must be unique within a single TodoWrite call.',
        );
      }
      if (status != 'pending' &&
          status != 'in_progress' &&
          status != 'completed' &&
          status != 'failed') {
        return AiToolUtils.invalidResult(
          'TodoWrite',
          'Todo status must be pending, in_progress, completed, or failed.',
        );
      }
      if (status == 'in_progress') inProgressCount += 1;
      normalizedTodos.add(<String, Object?>{
        'id': id,
        'content': content,
        'status': status,
      });
    }
    if (inProgressCount > 1) {
      return AiToolUtils.invalidResult(
        'TodoWrite',
        'Only one todo may be in_progress at a time.',
      );
    }
    final baseLines = normalizedTodos.isEmpty
        ? '(todo list cleared)'
        : normalizedTodos
              .map((todo) {
                final status = '${todo['status']}';
                final marker = switch (status) {
                  'completed' => '[x]',
                  'in_progress' => '[-]',
                  'failed' => '[!]',
                  _ => '[ ]',
                };
                return '$marker ${todo['id']}: ${todo['content']}';
              })
              .join('\n');
    final shouldEmitVerificationReminder =
        normalizedTodos.length >= _verificationReminderTodoThreshold &&
        normalizedTodos.every((todo) => todo['status'] == 'completed');
    final lines = shouldEmitVerificationReminder
        ? '$baseLines\n\n$_verificationReminder'
        : baseLines;
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: 'TodoWrite',
      workingDirectory: AiToolUtils.defaultWorkingDirectory(),
      stdout: lines,
      stderr: '',
      durationMs: startedAt.elapsedMilliseconds,
      resultText: lines,
      metadata: <String, Object?>{
        'todo_items': normalizedTodos,
        'todo_list_replaced': true,
        if (shouldEmitVerificationReminder) 'todo_verification_reminder': true,
      },
    );
  }
}
