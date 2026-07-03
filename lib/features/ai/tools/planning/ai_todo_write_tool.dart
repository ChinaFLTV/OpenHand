import '../../../../shared/util/input_value_parsing.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiTodoWriteTool extends AiTool {
  static const int _verificationReminderTodoThreshold = 3;
  static const String _statusPending = 'pending';
  static const String _statusInProgress = 'in_progress';
  static const String _statusCompleted = 'completed';
  static const String _statusFailed = 'failed';
  static const Set<String> _allowedStatuses = <String>{
    _statusPending,
    _statusInProgress,
    _statusCompleted,
    _statusFailed,
  };
  static const String _verificationReminder =
      'verification_reminder: All major todos are marked completed. Before a final completion claim, verify the change with ReadLints, tests, build, a direct command, or Task(subagent_type: verify), and report any skipped check explicitly.';
  static final RegExp _verificationTodoPattern = RegExp(
    r'\b(verif|test|tests|lint|analy[sz]e|build|check)\b|验证|校验|测试|构建|检查',
    caseSensitive: false,
  );

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.todoWrite;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final todos = AiToolUtils.readList(args['todos']);
    if (todos == null) {
      return AiToolUtils.invalidResult(
        'TodoWrite',
        'TodoWrite requires a todos array.',
      );
    }
    final normalizedTodos = <Map<String, Object?>>[];
    final providedIds = trimmedNonEmptyStrings(
      todos.whereType<Map>().map((todo) => todo['id']),
    ).toSet();
    final seenIds = <String>{};
    var inProgressCount = 0;
    for (var todoIndex = 0; todoIndex < todos.length; todoIndex++) {
      final rawTodo = todos[todoIndex];
      if (rawTodo is! Map) {
        return AiToolUtils.invalidResult(
          'TodoWrite',
          'Each todo must be an object.',
        );
      }
      final todo = stringKeyedMapFromValue(rawTodo);
      final id = _resolveTodoId(
        todo: todo,
        providedIds: providedIds,
        seenIds: seenIds,
        fallbackIndex: todoIndex,
      );
      final content = '${todo['content'] ?? ''}'.trim();
      final status = '${todo['status'] ?? ''}'.trim();
      final activeForm = '${todo['activeForm'] ?? todo['active_form'] ?? ''}'
          .trim();
      if (content.isEmpty) {
        return AiToolUtils.invalidResult(
          'TodoWrite',
          'Each todo must include content.',
        );
      }
      if (!seenIds.add(id)) {
        return AiToolUtils.invalidResult(
          'TodoWrite',
          'Todo ids must be unique within a single TodoWrite call.',
        );
      }
      if (!_allowedStatuses.contains(status)) {
        return AiToolUtils.invalidResult(
          'TodoWrite',
          'Todo status must be pending, in_progress, completed, or failed.',
        );
      }
      if (status == _statusInProgress) inProgressCount += 1;
      normalizedTodos.add(<String, Object?>{
        'id': id,
        'content': content,
        'status': status,
        if (activeForm.isNotEmpty) 'activeForm': activeForm,
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
                return '${_markerForStatus('${todo['status']}')} '
                    '${todo['id']}: ${todo['content']}';
              })
              .join('\n');
    final allCompleted =
        normalizedTodos.isNotEmpty &&
        normalizedTodos.every((todo) => todo['status'] == _statusCompleted);
    final shouldEmitVerificationReminder =
        normalizedTodos.length >= _verificationReminderTodoThreshold &&
        allCompleted &&
        !normalizedTodos.any(_looksLikeVerificationTodo);
    final lines = shouldEmitVerificationReminder
        ? '$baseLines\n\n$_verificationReminder'
        : baseLines;
    final oldTodos = _normalizeCurrentTodos(context.metadata['current_todos']);
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
        'oldTodos': oldTodos,
        'newTodos': normalizedTodos,
        'todo_all_completed': allCompleted,
        'todo_items_for_next_turn': allCompleted
            ? const <Map<String, Object?>>[]
            : normalizedTodos,
        if (shouldEmitVerificationReminder) 'todo_verification_reminder': true,
      },
    );
  }

  String _resolveTodoId({
    required Map<String, Object?> todo,
    required Set<String> providedIds,
    required Set<String> seenIds,
    required int fallbackIndex,
  }) {
    final explicitId = '${todo['id'] ?? ''}'.trim();
    if (explicitId.isNotEmpty) return explicitId;
    var candidateNumber = fallbackIndex + 1;
    var candidate = '$candidateNumber';
    while (providedIds.contains(candidate) || seenIds.contains(candidate)) {
      candidateNumber += 1;
      candidate = '$candidateNumber';
    }
    return candidate;
  }

  bool _looksLikeVerificationTodo(Map<String, Object?> todo) {
    return _verificationTodoPattern.hasMatch('${todo['content'] ?? ''}');
  }

  String _markerForStatus(String status) {
    if (status == _statusCompleted) return '[x]';
    if (status == _statusInProgress) return '[-]';
    if (status == _statusFailed) return '[!]';
    return '[ ]';
  }

  List<Map<String, Object?>> _normalizeCurrentTodos(Object? rawTodos) {
    if (rawTodos is! List) return const <Map<String, Object?>>[];
    final normalized = <Map<String, Object?>>[];
    final seenIds = <String>{};
    for (final rawTodo in rawTodos) {
      if (rawTodo is! Map) continue;
      final todo = stringKeyedMapFromValue(rawTodo);
      final id = '${todo['id'] ?? ''}'.trim();
      final content = '${todo['content'] ?? ''}'.trim();
      final status = '${todo['status'] ?? ''}'.trim();
      final activeForm = '${todo['activeForm'] ?? todo['active_form'] ?? ''}'
          .trim();
      if (id.isEmpty || content.isEmpty || status.isEmpty || !seenIds.add(id)) {
        continue;
      }
      normalized.add(<String, Object?>{
        'id': id,
        'content': content,
        'status': status,
        if (activeForm.isNotEmpty) 'activeForm': activeForm,
      });
    }
    return normalized;
  }
}
