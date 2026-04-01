// 2026-04-01 02:29:02
// 参照 Claude Code Tool.ts 的 fail-closed 原则，为 AiTool 增加安全防护栏属性。
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool_execution_context.dart';

/// 工具中断行为：用户发送新消息时当前工具的处理方式。
enum AiToolInterruptBehavior {
  /// 继续运行，新消息排队等待。（默认，安全）
  block,

  /// 取消工具执行并丢弃结果。
  cancel,
}

abstract class AiTool {
  /// The builtin kind identifier this tool handles.
  AiBuiltinToolKind get kind;

  /// 工具的别名列表，用于向后兼容旧名称。
  /// 注册时 [AiToolRegistry] 会将别名一并映射到本工具。
  List<String> get aliases => const <String>[];

  /// 工具是否执行破坏性操作（删除、覆盖、发送等不可逆操作）。
  /// 默认 false（fail-closed）。破坏性工具应覆盖返回 true。
  bool get isDestructive => false;

  /// 用户发送新消息时工具的中断行为。
  /// 默认 [AiToolInterruptBehavior.block]（fail-closed，不丢弃进行中的操作）。
  AiToolInterruptBehavior get interruptBehavior => AiToolInterruptBehavior.block;

  /// Executes the tool logic given the execution context.
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context);

  /// Determines if the tool supports the kind.
  bool supports(AiBuiltinToolKind kind) => this.kind == kind;
}
