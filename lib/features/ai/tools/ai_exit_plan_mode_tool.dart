import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

class AiExitPlanModeTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.exitPlanMode;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final plan = '${args['plan'] ?? ''}'.trim();
    if (plan.isEmpty) {
      return AiToolUtils.invalidResult(
          'ExitPlanMode', 'ExitPlanMode requires a non-empty plan.');
    }
    return AiToolUtils.simpleSuccessResult(
      command: 'ExitPlanMode',
      output:
          'Plan captured. Present the plan to the user and wait for explicit approval before implementation.',
      durationMs: startedAt.elapsedMilliseconds,
      metadata: <String, Object?>{
        'plan_mode_awaiting_approval': true,
        'pending_plan': plan,
      },
    );
  }
}
