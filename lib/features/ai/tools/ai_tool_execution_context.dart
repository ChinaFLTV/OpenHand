import '../model/ai_deny_command_rule.dart';
import '../model/ai_model_config.dart';
import '../service/bash/ai_bash_tool_service.dart';
import '../service/chat/ai_protocol_adapter.dart';
import '../service/runtime/ai_tool_runtime_service.dart';

class AiToolExecutionContext {
  const AiToolExecutionContext({
    required this.sessionId,
    required this.catalog,
    required this.toolCall,
    required this.decodedArguments,
    required this.model,
    required this.previouslyReadFiles,
    required this.denyCommandRules,
    required this.requireWriteCommandConfirmation,
    required this.confirmWriteCommand,
    this.cancelSignal,
    this.onBashUpdate,
    this.metadata = const <String, Object?>{},
  });

  final String sessionId;
  final AiResolvedToolCatalog catalog;
  final AiToolCall toolCall;
  final Map<String, Object?> decodedArguments;
  final AiModelConfig model;
  final Set<String> previouslyReadFiles;
  final List<AiDenyCommandRule> denyCommandRules;
  final bool requireWriteCommandConfirmation;
  final Future<BashCommandApprovalDecision> Function(
    BashCommandApprovalRequest request,
  )?
  confirmWriteCommand;
  final Future<void>? cancelSignal;
  final void Function(BashToolExecutionUpdate update)? onBashUpdate;

  /// 扩展元数据槽：用于传递不属于核心上下文字段的额外工具参数。
  ///
  /// **约束**：不得直接向本 class 添加新字段。
  /// 所有扩展参数通过此 Map 传递，并在具体工具实现中安全读取。
  final Map<String, Object?> metadata;
}
