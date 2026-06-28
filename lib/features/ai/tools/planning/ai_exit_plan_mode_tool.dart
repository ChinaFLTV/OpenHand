import '../../model/ai_session.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiExitPlanModeTool extends AiTool {
  static const int _maxAllowedPromptCount = 8;
  static const int _maxAllowedPromptChars = 180;
  static const Set<String> _concreteCommandPrefixes = <String>{
    'bash',
    'bun',
    'cargo',
    'cd',
    'cmake',
    'curl',
    'dart',
    'flutter',
    'gh',
    'git',
    'go',
    'gradle',
    'java',
    'make',
    'mvn',
    'node',
    'npm',
    'pnpm',
    'python',
    'python3',
    'pytest',
    'sh',
    'uv',
    'uvx',
    'wget',
    'yarn',
    'zsh',
  };
  static final RegExp _shellOperatorPattern = RegExp(
    r'(`|\$\(|&&|\|\||[;|<>])',
  );

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.exitPlanMode;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final planResolution = _resolvePlan(context);
    final plan = planResolution.plan;
    if (plan.isEmpty) {
      return AiToolUtils.invalidResult(
        'ExitPlanMode',
        'ExitPlanMode requires a non-empty plan or recoverable plan context.',
      );
    }
    final allowedPromptsResult = _parseAllowedPrompts(args);
    if (allowedPromptsResult.error != null) {
      return AiToolUtils.invalidResult(
        'ExitPlanMode',
        allowedPromptsResult.error!,
      );
    }
    final allowedPrompts = allowedPromptsResult.items;
    return AiToolUtils.simpleSuccessResult(
      command: 'ExitPlanMode',
      output: allowedPrompts.isEmpty
          ? 'Plan captured. Present the plan to the user and wait for explicit approval before implementation.'
          : 'Plan captured with ${allowedPrompts.length} implementation permission prompt(s). Present the plan to the user and wait for explicit approval before implementation.',
      durationMs: startedAt.elapsedMilliseconds,
      metadata: <String, Object?>{
        'plan_mode_awaiting_approval': true,
        'pending_plan': plan,
        'pending_plan_source': planResolution.source,
        if (allowedPrompts.isNotEmpty) ...<String, Object?>{
          'plan_mode_allowed_prompts': allowedPrompts,
          'plan_mode_allowed_prompt_count': allowedPrompts.length,
        },
      },
    );
  }

  _PlanResolution _resolvePlan(AiToolExecutionContext context) {
    final argumentPlan = '${context.decodedArguments['plan'] ?? ''}'.trim();
    if (argumentPlan.isNotEmpty) {
      return _PlanResolution(plan: argumentPlan, source: 'argument');
    }
    final pendingPlan = '${context.metadata['pending_plan'] ?? ''}'.trim();
    if (pendingPlan.isNotEmpty) {
      return _PlanResolution(plan: pendingPlan, source: 'pending_plan');
    }
    final todoPlan = _planFromCurrentTodos(context.metadata['current_todos']);
    if (todoPlan.isNotEmpty) {
      return _PlanResolution(plan: todoPlan, source: 'current_todos');
    }
    return const _PlanResolution(plan: '', source: 'missing');
  }

  String _planFromCurrentTodos(Object? rawTodos) {
    if (rawTodos is! List) {
      return '';
    }
    final lines = <String>[];
    for (final rawTodo in rawTodos) {
      if (rawTodo is! Map) {
        continue;
      }
      final status = AiSessionTodoState.normalizeStatus(
        '${rawTodo['status'] ?? ''}',
      );
      if (status != AiSessionTodoState.pending &&
          status != AiSessionTodoState.inProgress) {
        continue;
      }
      final content = '${rawTodo['content'] ?? ''}'.trim();
      if (content.isEmpty) {
        continue;
      }
      lines.add('${lines.length + 1}. $content');
    }
    return lines.join('\n');
  }

  _AllowedPromptsParseResult _parseAllowedPrompts(Map<String, Object?> args) {
    final raw = args['allowed_prompts'] ?? args['allowedPrompts'];
    if (raw == null) {
      return const _AllowedPromptsParseResult(items: <Map<String, String>>[]);
    }
    final allowedPrompts = AiToolUtils.readList(raw);
    if (allowedPrompts == null) {
      return const _AllowedPromptsParseResult(
        items: <Map<String, String>>[],
        error: 'ExitPlanMode allowed_prompts must be an array when provided.',
      );
    }
    if (allowedPrompts.length > _maxAllowedPromptCount) {
      return const _AllowedPromptsParseResult(
        items: <Map<String, String>>[],
        error: 'ExitPlanMode allowed_prompts must contain at most 8 items.',
      );
    }
    final items = <Map<String, String>>[];
    final seen = <String>{};
    for (var i = 0; i < allowedPrompts.length; i++) {
      final entry = allowedPrompts[i];
      if (entry is! Map) {
        return _AllowedPromptsParseResult(
          items: const <Map<String, String>>[],
          error: 'ExitPlanMode allowed_prompts item #$i must be an object.',
        );
      }
      final tool = '${entry['tool'] ?? ''}'.trim();
      final prompt = '${entry['prompt'] ?? ''}'.trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      if (tool != 'Bash') {
        return _AllowedPromptsParseResult(
          items: const <Map<String, String>>[],
          error:
              'ExitPlanMode allowed_prompts item #$i supports only tool "Bash".',
        );
      }
      if (prompt.isEmpty) {
        return _AllowedPromptsParseResult(
          items: const <Map<String, String>>[],
          error:
              'ExitPlanMode allowed_prompts item #$i requires a non-empty prompt.',
        );
      }
      if (_looksLikeConcreteCommand(prompt)) {
        return _AllowedPromptsParseResult(
          items: const <Map<String, String>>[],
          error:
              'ExitPlanMode allowed_prompts item #$i must describe a semantic Bash action category, not a concrete shell command.',
        );
      }
      final boundedPrompt = prompt.length <= _maxAllowedPromptChars
          ? prompt
          : prompt.substring(0, _maxAllowedPromptChars);
      final key = '$tool\u0000$boundedPrompt';
      if (!seen.add(key)) {
        continue;
      }
      items.add(<String, String>{'tool': tool, 'prompt': boundedPrompt});
    }
    return _AllowedPromptsParseResult(items: items);
  }

  bool _looksLikeConcreteCommand(String prompt) {
    final normalized = prompt.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (_shellOperatorPattern.hasMatch(normalized)) {
      return true;
    }
    final firstToken = normalized.split(RegExp(r'\s+')).first;
    return _concreteCommandPrefixes.contains(firstToken);
  }
}

class _AllowedPromptsParseResult {
  const _AllowedPromptsParseResult({required this.items, this.error});

  final List<Map<String, String>> items;
  final String? error;
}

class _PlanResolution {
  const _PlanResolution({required this.plan, required this.source});

  final String plan;
  final String source;
}
