import '../model/ai_deny_command_rule.dart';
import '../model/ai_model_config.dart';
import '../service/bash/ai_bash_tool_service.dart';
import '../service/chat/ai_protocol_adapter.dart';
import '../service/fs/ai_file_history_service.dart';
import '../service/fs/ai_file_mutation_ledger.dart';
import '../service/fs/ai_file_tracker_service.dart';
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

  // 下面几项是被多个工具反复读取的元数据槽，键名与类型在这里落一份。
  // 它们不是新字段，只是 [metadata] 的具名读法：此前每个工具各写一遍
  // `metadata['file_tracker'] as AiFileTrackerService?`，键名敲错既不报错也
  // 不报空，只会静默退化成「没有该服务」的分支。

  /// 文件读取追踪服务，未注入时为 null。
  AiFileTrackerService? get fileTracker =>
      metadata['file_tracker'] as AiFileTrackerService?;

  /// 文件历史版本服务，未注入时为 null。
  AiFileHistoryService? get fileHistory =>
      metadata['file_history'] as AiFileHistoryService?;

  /// 文件变更账本，未启用时为 null。
  AiFileMutationLedger? get mutationLedger =>
      metadata['mutation_ledger'] as AiFileMutationLedger?;

  /// 写操作确认的等待上限（毫秒），未配置时为 null。
  int? get writeConfirmationTimeoutMs =>
      metadata['write_confirmation_timeout_ms'] as int?;
}
