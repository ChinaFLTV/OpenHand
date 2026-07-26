import '../service/runtime/ai_tool_runtime_service.dart';
import 'ai_tool_execution_context.dart';

abstract class AiTool {
  /// The builtin kind identifier this tool handles.
  AiBuiltinToolKind get kind;

  /// 工具的别名列表，用于向后兼容旧名称。
  /// 注册时 [AiToolRegistry] 会将别名一并映射到本工具。
  List<String> get aliases => const <String>[];

  /// 工具是否执行破坏性操作（删除、覆盖、发送等不可逆操作）。
  /// 默认 false（fail-closed）。破坏性工具应覆盖返回 true。
  bool get isDestructive => false;

  /// Executes the tool logic given the execution context.
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context);

  /// Releases resources owned by this tool. Implementations must be
  /// idempotent because runtime shutdown can be requested more than once.
  Future<void> dispose() => Future<void>.value();
}
