import '../service/runtime/ai_tool_runtime_service.dart';
import 'ai_tool_execution_context.dart';

/// 工具中断行为：用户发送新消息时当前工具的处理方式。
enum AiToolInterruptBehavior {
  /// 继续运行，新消息排队等待。（默认，安全）
  block,

  /// 取消工具执行并丢弃结果。
  cancel,
}

/// 工具权限校验结果。
///
/// 由 [AiTool.checkPermissions] 返回，[AiToolRegistry] 在 `execute()` 前检查。
/// - [AiToolPermissionAllowed]：放行，继续执行工具。
/// - [AiToolPermissionDenied]：拒绝，[AiToolRegistry] 返回错误结果，不调用 execute()。
sealed class AiToolPermissionResult {
  const AiToolPermissionResult();
}

/// 权限通过，允许继续执行工具。
final class AiToolPermissionAllowed extends AiToolPermissionResult {
  const AiToolPermissionAllowed();
}

/// 权限被拒绝，工具不执行。
final class AiToolPermissionDenied extends AiToolPermissionResult {
  const AiToolPermissionDenied(this.reason);

  /// 拒绝原因，将展示给模型和用户。
  final String reason;
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
  AiToolInterruptBehavior get interruptBehavior =>
      AiToolInterruptBehavior.block;

  /// 工具执行前的权限校验钩子。
  ///
  /// 在 [execute] 被调用前由 [AiToolRegistry.tryExecute] 自动调用。
  /// 返回 [AiToolPermissionAllowed] 放行，返回 [AiToolPermissionDenied] 则
  /// Registry 返回拒绝结果，不调用 [execute]。
  ///
  /// 默认放行（fail-open for permissions）。
  /// 高风险工具（如删除、网络写入）可覆盖此方法实现自定义校验逻辑。
  ///
  /// 注意：Bash 工具的写命令人工确认（[BashCommandApprovalRequest]）在
  /// [execute] 内部处理，属于操作级确认，与此权限门不冲突。
  Future<AiToolPermissionResult> checkPermissions(
    AiToolExecutionContext context,
  ) async {
    return const AiToolPermissionAllowed();
  }

  /// Executes the tool logic given the execution context.
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context);

  /// Determines if the tool supports the kind.
  bool supports(AiBuiltinToolKind kind) => this.kind == kind;
}
