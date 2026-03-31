import '../model/ai_deny_command_rule.dart';
import '../model/ai_model_config.dart';
import '../service/ai_bash_tool_service.dart';
import '../service/ai_protocol_adapter.dart';
import '../service/ai_tool_runtime_service.dart';

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
  });

  final String sessionId;
  final AiResolvedToolCatalog catalog;
  final AiToolCall toolCall;
  final Map<String, Object?> decodedArguments;
  final AiModelConfig model;
  final Set<String> previouslyReadFiles;
  final List<AiDenyCommandRule> denyCommandRules;
  final bool requireWriteCommandConfirmation;
  final Future<bool> Function(BashCommandApprovalRequest request)? confirmWriteCommand;
  final Future<void>? cancelSignal;
  final void Function(BashToolExecutionUpdate update)? onBashUpdate;
}
