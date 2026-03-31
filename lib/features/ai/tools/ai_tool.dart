import '../service/ai_tool_runtime_service.dart';
import 'ai_tool_execution_context.dart';

abstract class AiTool {
  /// The builtin kind identifier this tool handles.
  AiBuiltinToolKind get kind;

  /// Executes the tool logic given the execution context.
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context);
  
  /// Determines if the tool supports the kind.
  bool supports(AiBuiltinToolKind kind) => this.kind == kind;
}
