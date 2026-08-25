import '../service/runtime/ai_tool_runtime_service.dart';
import 'ai_tool_execution_context.dart';

abstract class AiTool {
  /// 工具对应的内置类型。
  AiBuiltinToolKind get kind;

  /// 工具的别名列表，用于向后兼容旧名称。
  /// 注册时 [AiToolRegistry] 会将别名一并映射到本工具。
  List<String> get aliases => const <String>[];

  /// 工具是否执行破坏性操作（删除、覆盖、发送等不可逆操作）。
  /// 破坏性工具必须覆盖并返回 true。
  bool get isDestructive => false;

  /// 执行工具逻辑。
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context);

  /// 释放工具资源；实现必须支持重复调用。
  Future<void> dispose() => Future<void>.value();
}
