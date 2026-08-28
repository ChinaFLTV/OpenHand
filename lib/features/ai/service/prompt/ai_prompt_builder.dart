import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/bounded_line_budget.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/stable_hash.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../../../shared/util/tool_name_normalization.dart';
import '../../../instructions/index.dart';
import '../../../knowledge_base/index.dart';
import '../../../memory/index.dart';
import '../../../skills/index.dart';
import '../../model/ai_allow_command_rule.dart';
import '../../model/ai_attachment.dart';
import '../../model/ai_builtin_tool_config.dart' show AiBuiltinToolLoadStrategy;
import '../../model/ai_context_usage.dart';
import '../../model/ai_input_cache_policy.dart';
import '../../model/ai_message_content_format.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_session.dart';
import '../../model/ai_session_goal.dart';
import '../../model/ai_session_message.dart';
import '../../model/ai_session_runtime_context.dart';
import '../../model/ai_thread_template.dart';
import '../../model/ai_token_usage.dart';
import '../../tools/planning/ai_task_tool.dart';
import '../bash/ai_bash_tool_service.dart';
import '../chat/ai_protocol_adapter.dart';
import '../hook/ai_claude_hook_service.dart';
import '../mcp_bridge/android_reverse_mcp_tool_policy.dart';
import '../mcp_bridge/web_reverse_mcp_tool_policy.dart';
import '../runtime/ai_plan_approval_detector.dart';
import '../runtime/ai_plan_mode_guidance.dart';
import '../runtime/ai_plan_mode_tool_gate.dart';
import '../runtime/ai_tool_runtime_service.dart';
import '../web_reverse_runtime_metadata.dart';
import 'ai_output_format_prompts.dart';
import 'ai_prompt_sections.dart';
import 'ai_prompt_template_assembly.dart';
import 'ai_prompt_template_repository.dart';

const String aiPromptRuntimeTailSnapshotMetadataKey =
    'prompt_runtime_tail_snapshot';
const int _userProfilePromptMaxCharacters = 8 * kBytesPerKiB;
const int _userMemoryPromptMaxEntries = 64;
const int _userMemoryPromptEntryMaxCharacters = 2 * kBytesPerKiB;
const int _userMemoryPromptTagsMaxCharacters = 320;
const int _userMemoryPromptMaxCharacters = 24 * kBytesPerKiB;

class AiPromptBuildResult {
  const AiPromptBuildResult({
    required this.messages,
    required this.metadata,
    required this.promptCharacterCount,
    required this.systemMessageCount,
    required this.historyMessageCount,
    required this.memoryResourceIds,
  });

  final List<AiChatTurn> messages;
  final Map<String, Object?> metadata;
  final int promptCharacterCount;
  final int systemMessageCount;
  final int historyMessageCount;
  final Set<String> memoryResourceIds;
}

class _PromptSection {
  const _PromptSection(this.header, this.content);

  final String header;
  final String content;

  bool get hasContent => content.trim().isNotEmpty;
}

class _PromptAssemblyPlan {
  const _PromptAssemblyPlan({
    required this.stablePrefixTurns,
    required this.runtimePrefixTurns,
    required this.historyTurns,
    required this.latestUserTurns,
    required this.volatileTailTurns,
  });

  final List<AiChatTurn> stablePrefixTurns;
  final List<AiChatTurn> runtimePrefixTurns;
  final List<AiChatTurn> historyTurns;
  final List<AiChatTurn> latestUserTurns;
  final List<AiChatTurn> volatileTailTurns;

  List<AiChatTurn> materialize() => <AiChatTurn>[
    ...stablePrefixTurns,
    ...runtimePrefixTurns,
    ...historyTurns,
    ...latestUserTurns,
    ...volatileTailTurns,
  ];
}

class AiPromptBuilder {
  const AiPromptBuilder();

  static const String _promptAssemblyLayout =
      'stable_prefix.runtime_prefix.history.round_anchor_tail.v2';
  static const String _promptCacheAffinityKeyScope =
      'session_template_model.v1';
  static const int _runtimeTailSnapshotMaxTurns = 8;
  static const int _runtimeTailSnapshotMaxCharacters = 64 * kBytesPerKiB;
  static final AiBashToolService _bashWriteAnalyzer = AiBashToolService();
  static const JsonEncoder _promptJsonEncoder = kPrettyJsonEncoder;
  static const int _microCompactKeepRecentToolResults = 2;
  static const int _historyAssistantContentMaxChars = 1600;
  static const int _historyAssistantContentEdgeChars = 700;
  static const int _contextBudgetSummaryReserveTokens = 20000;
  static const int _contextBudgetAutoCompactBufferTokens = 13000;
  static const String _dingtalkSource = 'dingtalk_gateway';
  static const String _dingtalkExcludedMessageIdsKey =
      'dingtalk_excluded_message_ids';
  static const String _legacyDingTalkIgnoredMessageIdsKey =
      'dingtalk_ignored_message_ids';
  static const String _dingtalkContextMessageIdsKey =
      'dingtalk_context_message_ids';
  static const String _dingtalkSourceMessageIdKey =
      'dingtalk_source_message_id';
  static const int _contextBudgetWarningBufferTokens = 20000;
  static const int _contextBudgetErrorBufferTokens = 20000;
  static const int _contextBudgetManualCompactBufferTokens = 3000;
  static const int _checkpointPromptMaxChars = 40000;
  static const int _checkpointPromptEdgeChars = 18000;
  static const int _compressionAttachmentDetailMaxChars = 2000;
  static const int _compressionPromptToolResultThresholdChars =
      4 * kBytesPerKiB;
  static const int _compressionPromptToolResultHeadTailChars = 384;
  static const int _knowledgeToolPromptMaxChars = 12000;
  static const int _knowledgeToolPromptMaxResults = 8;
  static const int _knowledgeToolPromptPreviewMaxChars = 1200;
  static const int _compressionPromptMaxPlanRecords = 3;
  static const int _compressionPromptMaxPlanChars = 6000;
  static const int _promptGoalObjectiveMaxChars = 1200;
  static const int _promptGoalEvaluationMaxChars = 800;
  static const int _promptGoalHistoryLimit = 5;
  static const int _compressionPromptMaxTodoItems = 40;
  static const int _compressionPromptMaxTodoChars = 800;
  static const int _postCompactRestoreMaxFiles = 5;
  static const int _postCompactRestoreMaxFileBytes = 256 * kBytesPerKiB;
  static const int _postCompactRestoreMaxCharsPerFile = 12000;
  static const int _postCompactRestoreTotalChars = 30000;
  static const int _postCompactRestoreMaxSkills = 3;
  static const int _postCompactRestoreMaxSkillChars = 8000;
  static const int _postCompactRestoreTotalSkillChars = 20000;
  static const Duration _postCompactRestoreReadIdleTimeout = Duration(
    seconds: 3,
  );
  static const Duration _postCompactRestoreReadTotalTimeout = Duration(
    seconds: 10,
  );
  static const Duration _attachmentProbeIdleTimeout = Duration(seconds: 3);
  static const Duration _attachmentProbeTotalTimeout = Duration(seconds: 10);
  static const int _postCompactRestoreMaxPlanChars = 12000;
  static const int _postCompactRestoreMaxMcpChars = 12000;
  static const int _postCompactRestoreMaxMcpInstructionChars = 4000;
  static const int _postCompactRestoreMaxMcpTools = 40;
  static const int _postCompactRestoreMaxSessionStartHooks = 5;
  static const int _postCompactRestoreMaxSessionStartHookChars = 8000;
  static const int _postCompactRestoreMaxToolAgentChars = 8000;
  static const int _postCompactRestoreMaxDeferredTools = 40;
  static const int _postCompactRestoreMaxAgentResults = 3;
  static const int _postCompactRestoreMaxAgentResultChars = 12000;
  static const int _postCompactRestoreMaxCharsPerAgentResult = 4000;
  static const int _compressionUserManifestMaxChars = 12000;
  static const int _compressionUserManifestMaxCharsPerMessage = 1200;
  static const int _compressionResourceManifestMaxItems = 40;
  static const String _runtimeContextEnvelopeStart =
      '<openhand_runtime_context>';
  static const String _runtimeContextEnvelopeEnd =
      '</openhand_runtime_context>';
  static const String _runtimeContextEnvelopeIntro =
      'OpenHand runtime context for this turn; follow it unless higher-priority instructions conflict.';
  Future<AiPromptBuildResult> buildSessionPrompt({
    required AiPromptTemplateBundle templateBundle,
    required AiSession session,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
    required List<UserMemoryEntry> memoryEntries,
    required List<AiSessionMessage> sessionMessages,
    String? latestUserMessageId,
    String? runtimeContextAnchorMessageId,
    List<AiToolDefinition> availableTools = const <AiToolDefinition>[],
    Map<String, AiResolvedTool> resolvedToolsByName =
        const <String, AiResolvedTool>{},
    Map<String, String> mcpServerInstructionsByName = const <String, String>{},
    bool useDsmlToolCalls = false,
    bool planModeExecutionApprovedForSend = false,
    bool? planModeRecoveryInspectionRequired,
    // 供调用方（AiSessionController）在「等待计划批准」
    // 轮次传入「完整目录」，让 [2] Tool Catalog 文本跨轮保持字节一致，
    // 仅靠 [3d] 里的 plan.awaiting_approval 告诉模型「本轮不能调用工具」。
    // 同时 availableTools 可以保持为空，让 SDK 层 / 本地验证层拒绝任何工具调用。
    List<AiToolDefinition>? displayCatalogOverride,
  }) async {
    final templatePolicy = AiPromptTemplatePolicies.resolve(
      templateBundle.template.id,
    );
    final repositorySnapshot = _effectiveRepositorySnapshot(
      session: session,
      runtimeContext: runtimeContext,
    );
    final latestCompressionPoint = session.latestCompressionPoint;
    final promptMemoryEntries = runtimeContext.memoryEnabled
        ? _memoryEntriesForPrompt(memoryEntries)
        : const <UserMemoryEntry>[];
    final promptAllowCommandRules = _allowCommandRulesForPrompt(
      runtimeContext.allowCommandRules,
    );
    final visibleSessionMessages = _visibleSessionMessagesForPrompt(
      session: session,
      sessionMessages: sessionMessages,
      runtimeContext: runtimeContext,
    );
    final runtimeContextAnchor = _messageById(
      visibleSessionMessages,
      runtimeContextAnchorMessageId,
    );
    AiSessionMessage? latestUserMessage;
    final historyMessages = <AiSessionMessage>[];
    // 若 latestUser 之后已经有助手 / 工具消息（即
    // 当前是工具回合后的“续写轮”），则不再把 latestUser 抽出来追加到末尾，
    // 而是把它留在自然位置参与 history。否则同一回合内连续的两次 API 调用
    // 会得到两份截然不同的 messages 序列（前一份把 latestUser 放在工具结果
    // 之后，后一份把它放在工具结果之前），prefix cache 永远在第二条消息处
    // 就断裂，导致命中率塌方。
    // 实现：先把 latestUser 暂存到 historyMessages，扫完之后若发现它身后
    // 没有任何非 reasoning 的消息，则把它从 history 中剥离、走原来的“追加
    // 到末尾”路径；若身后有内容，则就地留在自然位置，并通过
    // latestUserMessageIdForInlineAttachments 把 isLatestUserMessage 语义
    // （inline 图片 + [Attachment]/id= 块）传递给 _mapHistoryMessages。
    var foundLatestUser = false;
    var latestUserHasSubsequentTurns = false;
    int? latestUserHistoryIndex;
    for (final message in visibleSessionMessages) {
      if (message.id == latestUserMessageId &&
          message.kind == AiSessionMessageKind.user) {
        latestUserMessage = message;
        foundLatestUser = true;
        latestUserHistoryIndex = historyMessages.length;
        historyMessages.add(message);
        continue;
      }
      if (foundLatestUser && message.kind != AiSessionMessageKind.reasoning) {
        latestUserHasSubsequentTurns = true;
      }
      historyMessages.add(message);
    }
    final latestUserInline =
        latestUserMessage != null && latestUserHasSubsequentTurns;
    if (!latestUserInline && latestUserHistoryIndex != null) {
      // 没有续写场景：把 latestUser 从 history 里剥离，走原来的“附加到末尾”路径。
      historyMessages.removeAt(latestUserHistoryIndex);
    }
    final latestUserAttachmentAvailability = latestUserMessage == null
        ? const <String, bool>{}
        : await _probeAttachmentAvailability(latestUserMessage, session);
    final historyToolCompressionConfig =
        _ToolCompressionConfig.forConversationHistory(runtimeContext);
    final historyTurns = _sanitizeToolSequence(
      _mapHistoryMessages(
        historyMessages,
        session,
        model,
        historyToolCompressionConfig,
        latestUserMessageIdForInlineAttachments: latestUserInline
            ? latestUserMessage.id
            : null,
        latestUserAttachmentAvailability: latestUserAttachmentAvailability,
      ),
    );
    final reasoningHistorySourceCount = historyMessages.where((message) {
      return message.kind == AiSessionMessageKind.reasoning &&
          message.content.trim().isNotEmpty;
    }).length;
    final reasoningHistoryEchoTurnCount = historyTurns.where((turn) {
      return turn.role == AiChatRole.assistant &&
          (turn.reasoningContent?.isNotEmpty ?? false);
    }).length;
    final latestUserTurns = (latestUserMessage == null || latestUserInline)
        ? const <AiChatTurn>[]
        : _mapUserMessage(
            latestUserMessage,
            session: session,
            model: model,
            content: _promptContentForMessage(latestUserMessage),
            isLatestUserMessage: true,
            attachmentAvailability: latestUserAttachmentAvailability,
          );
    final failedTodos = session.todoItems
        .where((item) => AiSessionTodoState.isFailureStatus(item.status))
        .map((item) => item.toJson())
        .toList(growable: false);
    final availableToolNames = _promptCatalogToolNames(availableTools);
    final promptCatalogTools = displayCatalogOverride ?? availableTools;
    final currentFileEditingToolNames = availableToolNames
        .where(_isFileEditingToolName)
        .toList(growable: false);
    final postCompactRehydration = _buildPostCompactRehydrationSnapshot(
      session: session,
      historyMessages: historyMessages,
      runtimeContext: runtimeContext,
      memoryEntries: promptMemoryEntries,
      repositorySnapshot: repositorySnapshot,
      availableToolNames: availableToolNames,
      resolvedToolsByName: resolvedToolsByName,
      mcpServerInstructionsByName: mcpServerInstructionsByName,
      latestCompressionPoint: latestCompressionPoint,
    );
    final effectivePlanModeRecoveryInspectionRequired =
        planModeRecoveryInspectionRequired ?? false;
    final planRecoveryRequired = effectivePlanModeRecoveryInspectionRequired;
    final exitPlanModeAvailable = AiPlanModeToolGate.hasExitPlanModeTool(
      availableToolNames,
    );
    final writeCommandConfirmationRequired = _writeCommandConfirmationRequired(
      session: session,
      runtimeContext: runtimeContext,
    );
    final runtimeToolGateReason = AiPlanModeToolGate.gateReason(
      isPlanMode: session.mode == AiSessionMode.plan,
      awaitingPlanApproval: session.awaitingPlanApproval,
      availableToolNames: availableToolNames,
      executionApprovedForSend: planModeExecutionApprovedForSend,
      recoveryInspectionRequired: effectivePlanModeRecoveryInspectionRequired,
    );
    final planModeReminder = _buildPlanModeReminder(
      session: session,
      executionApprovedForSend: planModeExecutionApprovedForSend,
      recoveryInspectionRequired: effectivePlanModeRecoveryInspectionRequired,
    );
    final goalModeReminder = _buildGoalModeReminder(session);
    final metadata = <String, Object?>{
      'session_created_at': session.createdAt.toUtc().toIso8601String(),
      'session_id': session.id,
      'session_template_id': session.templateId,
      'session_template_name': session.templateName,
      'session_template_version': session.templateInternalVersion,
      'current_model_id': model.modelId,
      'current_model_label': model.displayName,
      'session_mode': session.mode.storageValue,
      'full_access_permission': session.fullAccessPermission,
      'plan_mode_active': session.mode == AiSessionMode.plan,
      'current_todo_count': session.todoItems.length,
      'current_todos': session.todoItems
          .map((item) => item.toJson())
          .toList(growable: false),
      'failed_todo_count': failedTodos.length,
      'failed_todos': failedTodos,
      'recent_plan_tool_failure': AiPlanApprovalDetector.hasRecentToolFailure(
        session,
      ),
      'plan_recovery_required': planRecoveryRequired,
      'tool_catalog_authoritative': true,
      'current_tool_count': availableToolNames.length,
      'current_tool_names': availableToolNames,
      'current_file_editing_tool_names': currentFileEditingToolNames,
      'plan_mode_planning_tool_names': AiPlanModeToolGate.planningToolNames,
      'plan_mode_exit_plan_mode_available': exitPlanModeAvailable,
      'runtime_tool_gate_reason': runtimeToolGateReason,
      'plan_mode_execution_approved_for_send': planModeExecutionApprovedForSend,
      'plan_mode_recovery_inspection_required':
          effectivePlanModeRecoveryInspectionRequired,
      'awaiting_plan_approval': session.awaitingPlanApproval,
      'pending_plan': session.pendingPlan,
      'workspace_instruction_document_count':
          runtimeContext.workspaceInstructionDocuments.length,
      'workspace_instruction_paths': runtimeContext
          .workspaceInstructionDocuments
          .map((item) => item.path)
          .toList(growable: false),
      'working_directory': runtimeContext.workingDirectory,
      'single_round_tool_call_limit': runtimeContext.singleRoundToolCallLimit,
      'sequential_tool_round_limit': runtimeContext.sequentialToolRoundLimit,
      'platform_name': runtimeContext.platformName,
      // 日期会在午夜改变哈希并破坏 prefix-cache，不写入稳定 metadata。
      'time_zone_name': runtimeContext.timeZoneName,
      'write_command_confirmation_enabled':
          runtimeContext.writeCommandConfirmationEnabled,
      'write_command_confirmation_required': writeCommandConfirmationRequired,
      'allow_command_rule_count': promptAllowCommandRules.length,
      'allow_command_rules': promptAllowCommandRules
          .map((item) => item.toJson())
          .toList(growable: false),
      'repository_snapshot': repositorySnapshot?.toJson(),
      if (postCompactRehydration.isNotEmpty)
        'post_compact_rehydration': postCompactRehydration,
      'memory_enabled': runtimeContext.memoryEnabled,
      'environment': _buildPromptEnvironmentSnapshot(
        runtimeContext,
        allowCommandRules: promptAllowCommandRules,
        includeRepositorySnapshot: false,
      ),
      'app_theme': <String, String>{
        'brightness': runtimeContext.appThemeBrightness,
        'preset': runtimeContext.appThemePresetName,
        'primary_color': runtimeContext.appThemePrimaryColor,
      },
    };
    final webReverseRuntime = _buildWebReverseRuntimeSnapshot(
      session,
      templatePolicy: templatePolicy,
      availableToolNames: availableToolNames,
      resolvedToolsByName: resolvedToolsByName,
    );
    if (webReverseRuntime != null) {
      metadata['web_reverse_runtime'] = webReverseRuntime;
    }
    final androidReverseRuntime = _buildAndroidReverseRuntimeSnapshot(
      session,
      templatePolicy: templatePolicy,
      availableToolNames: availableToolNames,
      resolvedToolsByName: resolvedToolsByName,
    );
    if (androidReverseRuntime != null) {
      metadata['android_reverse_runtime'] = androidReverseRuntime;
    }

    final staticSessionState = _buildCompactStaticSessionState(
      session: session,
      runtimeContext: runtimeContext,
      allowCommandRules: promptAllowCommandRules,
    );
    final dynamicSessionState = _buildCompactDynamicSessionState(
      session: session,
      runtimeContext: runtimeContext,
      postCompactRehydration: postCompactRehydration,
      availableToolNames: availableToolNames,
      webReverseRuntime: webReverseRuntime,
      androidReverseRuntime: androidReverseRuntime,
      planModeExecutionApprovedForSend: planModeExecutionApprovedForSend,
      planModeRecoveryInspectionRequired:
          effectivePlanModeRecoveryInspectionRequired,
    );
    final focusContext = latestCompressionPoint == null
        ? ''
        : _renderFocusContext(
            historyMessages: historyMessages,
            latestUserMessage: latestUserMessage,
          );
    final restoredDiskContexts = await Future.wait<String>(<Future<String>>[
      _renderPostCompactRestoredFileContext(
        historyMessages: historyMessages,
        latestCompressionPoint: latestCompressionPoint,
      ),
      _renderPostCompactRestoredSkillContext(
        historyMessages: historyMessages,
        runtimeContext: runtimeContext,
        latestCompressionPoint: latestCompressionPoint,
      ),
    ]);
    final restoredFileContext = restoredDiskContexts[0];
    final restoredSkillContext = restoredDiskContexts[1];
    final restoredPlanContext = _renderPostCompactRestoredPlanContext(
      session: session,
      latestCompressionPoint: latestCompressionPoint,
    );
    final restoredMcpContext = _renderPostCompactRestoredMcpContext(
      runtimeContext: runtimeContext,
      templateId: session.templateId,
      availableTools: availableTools,
      mcpServerInstructionsByName: mcpServerInstructionsByName,
      latestCompressionPoint: latestCompressionPoint,
    );
    final restoredSessionStartHookContext =
        _renderPostCompactRestoredSessionStartHookContext(
          historyMessages: historyMessages,
          latestCompressionPoint: latestCompressionPoint,
        );
    final restoredToolAgentContext = _renderPostCompactRestoredToolAgentContext(
      availableTools: availableTools,
      resolvedToolsByName: resolvedToolsByName,
      latestCompressionPoint: latestCompressionPoint,
    );
    final restoredAgentResultContext =
        _renderPostCompactRestoredAgentResultContext(
          historyMessages: historyMessages,
          latestCompressionPoint: latestCompressionPoint,
        );

    // latestUserTurns 可能包含 hook 注入的 system
    // reminder（`<system-reminder>` 标签被 _mapMessageContent 提取为 system
    // turn）。这些 system turn 每轮都变，必须与 stable restored contexts 隔离
    // → 放入 volatile tail。
    final latestUserSystemTurns = <AiChatTurn>[];
    final latestUserNonSystemTurns = <AiChatTurn>[];
    for (final turn in latestUserTurns) {
      if (turn.role == AiChatRole.system) {
        latestUserSystemTurns.add(turn);
      } else {
        latestUserNonSystemTurns.add(turn);
      }
    }
    final outputFormatReminderTurns = _buildOutputFormatReminderTurns(
      runtimeContext: runtimeContext,
      model: model,
    );
    final userInstructionsBody = _renderUserInstructionsBody(
      runtimeContext.userInstructions,
      const <String>{},
    );
    final includeDynamicSessionState = _shouldIncludeDynamicSessionState(
      dynamicSessionState,
      latestUserInline: latestUserInline,
    );
    final dingtalkIdentityReminder = _dingtalkIdentityReminder(runtimeContext);

    final memoryResourceIds = <String>{};
    final workspaceInstructions = _renderWorkspaceInstructions(runtimeContext);
    final stablePrefixTurns = <AiChatTurn>[
      _systemSectionTurn(
        AiPromptSectionHeaders.systemInstructions,
        '${templateBundle.systemInstructions}$workspaceInstructions',
      ),
      _systemSectionTurn(
        AiPromptSectionHeaders.developerInstructions,
        templateBundle.developerInstructions,
      ),
      // Prefix-extension cache 架构将 Session State 拆成静态/动态两部分：
      // - [3s] Static（session 标识、环境、限制、workspace_instructions）— 会话内不变。
      // - [3d] Dynamic（todos、plan、mode）— 仅包含会话内真正可变字段，绑定
      //   到触发本次请求的 user/tool round anchor 之后。
      //   date/git 已移至 [3s] 或移除：跨天/每次写文件后改变 hash 破坏 prefix-cache。
      // 静态块固定在 history 之前；动态块首次生成后随 round anchor 持久化，
      // 后续历史在同一位置逐字重放，避免新 assistant/tool 内容插入时改写旧前缀。
      // 相邻轮次尽量满足 "Turn N+1 = Turn N tokens ++ [asst_N][user_N+1]"
      // 的前缀扩展性质；真正会变的提醒只污染当前轮尾部。Hook system-reminder
      // （从用户消息中提取、每轮不同）同样保留在 prompt 尾部。
      _systemSectionTurn(
        AiPromptSectionHeaders.userMemory,
        'Long-term user facts and preferences.\n\n'
        '${_renderUserProfileSection(promptMemoryEntries, runtimeContext.memoryEnabled, memoryResourceIds)}'
        '${_renderUserMemory(promptMemoryEntries, runtimeContext.memoryEnabled, memoryResourceIds)}',
      ),
      // 【指令】模块注入。
      // 为了不让「本轮临时跳过某条指令」的勾选击穿
      // [4.5] 这块的 prefix cache，[4.5] 始终渲染「全部 enabled 指令」，本轮
      // 要忽略哪几条由 [3d] Dynamic Session State 的
      // `skipped_user_instruction_ids` 告诉模型。渲染时会在每条指令标
      // 题里携带 id，保证模型能精准匹配。
      if (userInstructionsBody.isNotEmpty)
        _systemSectionTurn(
          AiPromptSectionHeaders.userInstructions,
          '以下是用户预设的可复用指令片段，视为权威项目级指引：除非与上方更高优先级的系统 / 开发者指令直接冲突，否则必须遵循。若 [3d] Dynamic Session State 里出现了 `skipped_user_instruction_ids`，本轮临时忽略该 id 对应的指令。 / '
          'The blocks below are user-defined reusable prompt fragments. Treat them as authoritative project guidance — follow them unless they directly conflict with higher-priority system or developer instructions above. If `skipped_user_instruction_ids` appears under [3d] Dynamic Session State, the instructions whose ids match that list MUST be ignored for this turn only.\n\n'
          '$userInstructionsBody',
        ),
      _systemSectionTurn(
        AiPromptSectionHeaders.conversationContext,
        _renderCompressionSummary(session, latestCompressionPoint),
      ),
      // restored contexts 移至 history 之前：
      // 它们在压缩点前保持稳定，放在此前缀区可增加缓存命中 token。
      ..._optionalSystemSectionTurns(<_PromptSection>[
        _PromptSection(
          AiPromptSectionHeaders.restoredFileContext,
          restoredFileContext,
        ),
        _PromptSection(
          AiPromptSectionHeaders.restoredSkillContext,
          restoredSkillContext,
        ),
        _PromptSection(
          AiPromptSectionHeaders.restoredPlanContext,
          restoredPlanContext,
        ),
        _PromptSection(
          AiPromptSectionHeaders.restoredMcpContext,
          restoredMcpContext,
        ),
        _PromptSection(
          AiPromptSectionHeaders.restoredSessionStartHookContext,
          restoredSessionStartHookContext,
        ),
        _PromptSection(
          AiPromptSectionHeaders.restoredToolAndAgentListing,
          restoredToolAgentContext,
        ),
        _PromptSection(
          AiPromptSectionHeaders.restoredAgentResultContext,
          restoredAgentResultContext,
        ),
      ]),
      // 静态会话状态位于历史记录前的稳定前缀中。
      _jsonSystemSectionTurn(
        AiPromptSectionHeaders.staticSessionState,
        staticSessionState,
      ),
      ...outputFormatReminderTurns,
    ];
    final runtimePrefixTurns = <AiChatTurn>[
      _systemSectionTurn(
        AiPromptSectionHeaders.toolCatalog,
        _renderRuntimeToolCatalog(
          promptCatalogTools,
          compact: true,
          templatePolicy: templatePolicy,
          awaitingPlanApproval: session.awaitingPlanApproval,
          useDsmlToolCalls: useDsmlToolCalls,
          resolvedToolsByName: resolvedToolsByName,
        ),
      ),
    ];
    final generatedRuntimeTailTurns = <AiChatTurn>[
      if (includeDynamicSessionState)
        _jsonRuntimeContextSectionTurn(
          AiPromptSectionHeaders.dynamicSessionState,
          dynamicSessionState,
        ),
      // Theme Context 属可自变状态（跟随系统明暗切换），入 runtime tail
      // 而非稳定前缀，避免主题翻转击穿全部 history 缓存。
      ..._buildThemeContextReminderTurns(runtimeContext: runtimeContext),
      if (focusContext.isNotEmpty)
        _runtimeContextSectionTurn(
          AiPromptSectionHeaders.focusContext,
          focusContext,
        ),
      if (planModeReminder != null && planModeReminder.isNotEmpty)
        _runtimeContextSectionTurn(
          AiPromptSectionHeaders.planModeReminder,
          planModeReminder,
        ),
      if (goalModeReminder != null && goalModeReminder.isNotEmpty)
        _runtimeContextSectionTurn(
          AiPromptSectionHeaders.systemReminder,
          goalModeReminder,
        ),
      if (dingtalkIdentityReminder != null)
        _runtimeContextSectionTurn('钉钉 Agent 身份', dingtalkIdentityReminder),
      // Hook system reminder（从用户消息的 <system-reminder> 中提取，每轮不同）
      // 保留在 prompt 最尾部。
      ...latestUserSystemTurns.map(_runtimeContextTurnFromSystemTurn),
    ];
    final persistedRuntimeTailTurns = _readPersistedRuntimeTailTurns(
      runtimeContextAnchor?.metadata[aiPromptRuntimeTailSnapshotMetadataKey],
    );
    final runtimeTailSnapshotTurns =
        persistedRuntimeTailTurns ?? generatedRuntimeTailTurns;
    final runtimeTailReplayedFromHistory =
        persistedRuntimeTailTurns != null &&
        historyMessages.any(
          (message) => message.id == runtimeContextAnchor?.id,
        );
    final runtimeTailTurns = runtimeTailReplayedFromHistory
        ? const <AiChatTurn>[]
        : runtimeTailSnapshotTurns;
    // 所有模板统一按稳定前缀、运行时目录、历史、当前轮锚点和运行时尾部组装，
    // 缓存亲和键取自真实请求前缀，逐轮状态始终从锚点原位重放。
    final promptAssembly = _PromptAssemblyPlan(
      stablePrefixTurns: stablePrefixTurns,
      runtimePrefixTurns: runtimePrefixTurns,
      historyTurns: historyTurns,
      latestUserTurns: latestUserNonSystemTurns,
      volatileTailTurns: runtimeTailTurns,
    );
    final messages = promptAssembly.materialize();
    final systemMessageCount = messages
        .where((item) => item.role == AiChatRole.system)
        .length;
    metadata['current_prompt_system_message_count'] = systemMessageCount;

    final promptCharacterCount = messages.fold<int>(
      0,
      (sum, item) => sum + item.promptCharacterCount,
    );
    final contextUsageCharacters = _buildContextUsageCharacterCounts(
      stablePrefixTurns: stablePrefixTurns,
      runtimePrefixTurns: runtimePrefixTurns,
      historyTurns: historyTurns,
      latestUserTurns: latestUserNonSystemTurns,
      volatileTailTurns: runtimeTailTurns,
      promptCatalogTools: promptCatalogTools,
      nativeTools: useDsmlToolCalls
          ? const <AiToolDefinition>[]
          : availableTools,
      resolvedToolsByName: resolvedToolsByName,
      model: model,
      workspaceInstructionCharacters: workspaceInstructions.length,
    );
    final estimatedContextTokens = math.max(
      1,
      (contextUsageCharacters.values.fold<int>(0, (a, b) => a + b) /
              math.max(1, runtimeContext.estimatedCharactersPerToken))
          .ceil(),
    );
    metadata[aiContextUsageMetadataKey] =
        AiContextUsageBreakdown.fromCharacterCounts(
          contextUsageCharacters,
          totalTokens: estimatedContextTokens,
        ).toJson();
    final stablePrefixMessageCount = stablePrefixTurns.length;
    final runtimePrefixMessageCount = runtimePrefixTurns.length;
    final historyMessageCount = historyTurns.length;
    final latestUserMessageCount = latestUserNonSystemTurns.length;
    final volatileTailMessageCount = runtimeTailTurns.length;
    final stablePrefixHash = _promptFingerprint(
      stablePrefixTurns.map(_fingerprintTurn).join('\n\n'),
    );
    final cacheAnchorHash = _promptFingerprint(
      <AiChatTurn>[
        ...stablePrefixTurns,
        ...runtimePrefixTurns,
      ].map(_fingerprintTurn).join('\n\n'),
    );
    final toolCatalogHash = _promptFingerprint(
      _promptCatalogSignature(promptCatalogTools),
    );
    final inputCachePolicy = AiInputCachePolicy.resolve(
      model: model,
      runtimeContext: runtimeContext,
    );
    final cacheAffinityKind = AiPromptCacheAffinity.kindForModel(model);
    final cacheAffinitySupported =
        cacheAffinityKind != AiPromptCacheAffinityKind.none;
    final cacheAffinityEnabled =
        inputCachePolicy.stablePromptPrefixEnabled && cacheAffinitySupported;
    final cacheAffinityRequiresGatewayForwarding =
        AiPromptCacheAffinity.requiresGatewayForwardingForModel(model);
    final cacheAffinityStrong =
        cacheAffinityEnabled && !cacheAffinityRequiresGatewayForwarding;
    final cacheAffinityBestEffort =
        inputCachePolicy.usesAutomaticProviderCache && !cacheAffinityStrong;
    final promptCacheAffinityKey = _promptCacheAffinityKey(
      session: session,
      model: model,
    );
    final previousCapturedAt =
        '${session.lastPromptMetadata['captured_at'] ?? ''}'.trim();
    final previousStablePrefixHash =
        '${session.lastPromptMetadata['stable_prefix_hash'] ?? ''}'.trim();
    final previousCacheAnchorHash =
        '${session.lastPromptMetadata['cache_anchor_hash'] ?? ''}'.trim();
    final currentCapturedAt = DateTime.now().toUtc();
    final idleGapSeconds = () {
      if (previousCapturedAt.isEmpty) return null;
      final previousInstant = utcDateTimeFromValue(previousCapturedAt);
      if (previousInstant == null) return null;
      return currentCapturedAt.difference(previousInstant).inSeconds;
    }();
    metadata
      ..['captured_at'] = currentCapturedAt.toIso8601String()
      ..['current_prompt_character_count'] = promptCharacterCount
      ..['prompt_assembly_layout'] = _promptAssemblyLayout
      ..['stable_prefix_hash'] = stablePrefixHash
      ..['previous_stable_prefix_hash'] = previousStablePrefixHash
      ..['cache_anchor_hash'] = cacheAnchorHash
      ..['previous_cache_anchor_hash'] = previousCacheAnchorHash
      ..['stable_prefix_message_count'] = stablePrefixMessageCount
      ..['stable_prefix_character_count'] = stablePrefixTurns.fold<int>(
        0,
        (sum, turn) => sum + turn.promptCharacterCount,
      )
      ..['runtime_prefix_message_count'] = runtimePrefixMessageCount
      ..['runtime_prefix_character_count'] = runtimePrefixTurns.fold<int>(
        0,
        (sum, turn) => sum + turn.promptCharacterCount,
      )
      ..['history_message_count'] = historyMessageCount
      ..['latest_user_message_count'] = latestUserMessageCount
      ..['volatile_tail_message_count'] = volatileTailMessageCount
      ..['non_stable_prompt_message_count'] =
          runtimePrefixMessageCount +
          historyMessageCount +
          latestUserMessageCount +
          volatileTailMessageCount
      ..['tool_catalog_hash'] = toolCatalogHash
      ..['previous_tool_catalog_hash'] =
          '${session.lastPromptMetadata['tool_catalog_hash'] ?? ''}'.trim()
      ..['cache_enabled'] = inputCachePolicy.stablePromptPrefixEnabled
      ..['input_cache_enabled'] = inputCachePolicy.stablePromptPrefixEnabled
      ..['cache_global_enabled'] = inputCachePolicy.globalEnabled
      ..['cache_explicit_control_supported'] =
          inputCachePolicy.explicitControlSupported
      ..['cache_model_explicit_prompt_cache_enabled'] =
          inputCachePolicy.explicitControlEnabled
      ..['cache_update_mode'] = runtimeContext.aiInputCacheUpdateMode
      ..['cache_update_interval'] = runtimeContext.aiInputCacheUpdateInterval
      ..['cache_breakpoint_count'] = runtimeContext.aiInputCacheBreakpointCount
      ..['cache_breakpoint_positions'] =
          runtimeContext.aiInputCacheBreakpointPositions
      ..['cache_control_strategy'] = inputCachePolicy.strategy.storageValue
      ..['cache_protocol_controlled'] =
          inputCachePolicy.injectsExplicitCacheControl
      ..['cache_provider_automatic_cache_protected'] =
          inputCachePolicy.injectsExplicitCacheControl || cacheAffinityStrong
      ..['cache_provider_automatic_cache_best_effort'] = cacheAffinityBestEffort
      ..['cache_affinity_supported'] = cacheAffinitySupported
      ..['cache_affinity_enabled'] = cacheAffinityEnabled
      ..['cache_affinity_strategy'] = cacheAffinityKind.storageValue
      ..['cache_affinity_body_marker_supported'] =
          AiPromptCacheAffinity.kindUsesBodyAffinityMarker(cacheAffinityKind)
      ..['cache_affinity_requires_gateway_forwarding'] =
          cacheAffinityRequiresGatewayForwarding
      ..['cache_background_requests_deferred'] =
          inputCachePolicy.defersBackgroundRequests
      ..['reasoning_history_echo_required'] = model.requiresReasoningEcho
      ..['reasoning_history_source_count'] = reasoningHistorySourceCount
      ..['reasoning_history_echo_turn_count'] = reasoningHistoryEchoTurnCount
      ..['reasoning_history_echo_complete'] =
          !model.requiresReasoningEcho ||
          reasoningHistoryEchoTurnCount >= reasoningHistorySourceCount
      ..['tool_result_prompt_guard_enabled'] =
          historyToolCompressionConfig.guardsFreshToolResults
      ..['tool_result_prompt_threshold_chars'] =
          historyToolCompressionConfig.thresholdChars
      ..['tool_result_prompt_head_tail_chars'] =
          historyToolCompressionConfig.headTailWindowChars
      ..['dynamic_session_state_delivery'] = runtimeTailReplayedFromHistory
          ? 'round_anchor_history'
          : includeDynamicSessionState
          ? 'round_anchor_tail'
          : dynamicSessionState.isNotEmpty
          ? 'omitted_for_tool_continuation'
          : 'empty'
      ..['runtime_tail_anchor_message_id'] =
          runtimeContextAnchorMessageId?.trim() ?? ''
      ..['runtime_tail_snapshot_reused'] = persistedRuntimeTailTurns != null
      ..['runtime_tail_replayed_from_history'] = runtimeTailReplayedFromHistory
      ..['runtime_tail_snapshot_turn_count'] = runtimeTailSnapshotTurns.length
      ..['runtime_tail_snapshot_character_count'] = runtimeTailSnapshotTurns
          .fold<int>(0, (sum, turn) => sum + turn.promptCharacterCount)
      ..[aiPromptRuntimeTailSnapshotMetadataKey] = _serializeRuntimeTailTurns(
        runtimeTailSnapshotTurns,
      )
      ..['cache_affinity_key_scope'] = _promptCacheAffinityKeyScope
      ..['stable_cache_key'] = promptCacheAffinityKey
      ..['previous_stable_cache_key'] =
          '${session.lastPromptMetadata['stable_cache_key'] ?? ''}'.trim()
      ..['idle_gap_seconds'] = idleGapSeconds
      ..['ttl_suspected'] =
          idleGapSeconds != null &&
          idleGapSeconds >= 3600 &&
          previousStablePrefixHash.isNotEmpty &&
          previousStablePrefixHash == stablePrefixHash
      ..addAll(
        _buildContextBudgetMetadata(
          model: model,
          promptCharacterCount: promptCharacterCount,
          estimatedCharactersPerToken:
              runtimeContext.estimatedCharactersPerToken,
        ),
      );
    return AiPromptBuildResult(
      messages: messages,
      metadata: metadata,
      promptCharacterCount: promptCharacterCount,
      systemMessageCount: systemMessageCount,
      historyMessageCount: historyMessageCount,
      memoryResourceIds: Set<String>.unmodifiable(memoryResourceIds),
    );
  }

  AiChatTurn _systemSectionTurn(String header, String content) {
    return AiChatTurn(
      role: AiChatRole.system,
      content: _sectionText(header, content),
    );
  }

  AiChatTurn _runtimeContextSectionTurn(String header, String content) {
    return _runtimeContextTurn(_sectionText(header, content));
  }

  AiChatTurn _runtimeContextTurnFromSystemTurn(AiChatTurn turn) {
    return _runtimeContextTurn(turn.content);
  }

  AiChatTurn _runtimeContextTurn(String content) {
    final body = content.trimRight();
    return AiChatTurn(
      role: AiChatRole.user,
      content:
          '$_runtimeContextEnvelopeStart\n$_runtimeContextEnvelopeIntro\n\n$body\n$_runtimeContextEnvelopeEnd',
    );
  }

  String? _dingtalkIdentityReminder(AiSessionRuntimeContext runtimeContext) {
    if (runtimeContext.toolExecutionMetadata['source'] != _dingtalkSource) {
      return null;
    }
    return '当前请求来自已绑定的钉钉账号。你就是该账号在此会话中的工作代理，'
        '普通对话回复、查询、消息状态同步和表情处理无需再向账号主人确认。'
        '仅真正有外部副作用、不可逆或高风险的写操作，按工具自身的确认策略执行；'
        '不要在普通回复中声称需要等待账号主人确认。';
  }

  List<AiSessionMessage> _visibleSessionMessagesForPrompt({
    required AiSession session,
    required List<AiSessionMessage> sessionMessages,
    required AiSessionRuntimeContext runtimeContext,
  }) {
    final metadata = runtimeContext.toolExecutionMetadata;
    final excludedIds = <String>{};
    if (metadata['source'] == _dingtalkSource) {
      for (final key in const <String>[
        _dingtalkExcludedMessageIdsKey,
        _legacyDingTalkIgnoredMessageIdsKey,
      ]) {
        final rawIds = metadata[key];
        if (rawIds is! List) continue;
        excludedIds.addAll(
          rawIds
              .map((value) => '$value'.trim())
              .where((value) => value.isNotEmpty),
        );
      }
    }
    final visible = <AiSessionMessage>[];
    var omitDingTalkRound = false;
    for (final item in sessionMessages) {
      if (excludedIds.isNotEmpty && item.kind == AiSessionMessageKind.user) {
        final contextIds = <String>{};
        final rawContextIds = item.metadata[_dingtalkContextMessageIdsKey];
        if (rawContextIds is List) {
          contextIds.addAll(
            rawContextIds
                .map((value) => '$value'.trim())
                .where((value) => value.isNotEmpty),
          );
        }
        final sourceId = '${item.metadata[_dingtalkSourceMessageIdKey] ?? ''}'
            .trim();
        if (sourceId.isNotEmpty) contextIds.add(sourceId);
        omitDingTalkRound =
            contextIds.isNotEmpty && contextIds.any(excludedIds.contains);
      }
      if (omitDingTalkRound ||
          item.isDeleted ||
          _shouldOmitPausedGoalQueueMessageFromPrompt(session, item)) {
        continue;
      }
      visible.add(item);
    }
    return visible;
  }

  AiChatTurn _jsonSystemSectionTurn(String header, Object? value) {
    return _systemSectionTurn(header, _jsonCodeBlock(value));
  }

  AiChatTurn _jsonRuntimeContextSectionTurn(String header, Object? value) {
    return _runtimeContextSectionTurn(header, _jsonCodeBlock(value));
  }

  String _sectionText(String header, String content) {
    final body = content.trimRight();
    return body.isEmpty ? header : '$header\n\n$body';
  }

  Map<AiContextUsageCategory, int> _buildContextUsageCharacterCounts({
    required List<AiChatTurn> stablePrefixTurns,
    required List<AiChatTurn> runtimePrefixTurns,
    required List<AiChatTurn> historyTurns,
    required List<AiChatTurn> latestUserTurns,
    required List<AiChatTurn> volatileTailTurns,
    required List<AiToolDefinition> promptCatalogTools,
    required List<AiToolDefinition> nativeTools,
    required Map<String, AiResolvedTool> resolvedToolsByName,
    required AiModelConfig model,
    required int workspaceInstructionCharacters,
  }) {
    final counts = <AiContextUsageCategory, int>{
      for (final category in AiContextUsageCategory.values) category: 0,
    };
    void add(AiContextUsageCategory category, int characters) {
      if (characters > 0) {
        counts[category] = (counts[category] ?? 0) + characters;
      }
    }

    for (final turn in stablePrefixTurns) {
      if (turn.content.startsWith(AiPromptSectionHeaders.systemInstructions)) {
        final instructionCharacters = math.min(
          workspaceInstructionCharacters,
          turn.promptCharacterCount,
        );
        add(AiContextUsageCategory.instructions, instructionCharacters);
        add(
          AiContextUsageCategory.systemPrompt,
          turn.promptCharacterCount - instructionCharacters,
        );
        continue;
      }
      add(_contextUsageCategoryForTurn(turn), turn.promptCharacterCount);
    }
    for (final turn in runtimePrefixTurns) {
      _addToolContextCharacters(
        counts,
        characters: turn.promptCharacterCount,
        tools: promptCatalogTools,
        resolvedToolsByName: resolvedToolsByName,
        model: model,
      );
    }
    add(
      AiContextUsageCategory.conversation,
      historyTurns.fold<int>(0, (sum, turn) => sum + turn.promptCharacterCount),
    );
    add(
      AiContextUsageCategory.conversation,
      latestUserTurns.fold<int>(
        0,
        (sum, turn) => sum + turn.promptCharacterCount,
      ),
    );
    for (final turn in volatileTailTurns) {
      add(_contextUsageCategoryForTurn(turn), turn.promptCharacterCount);
    }
    if (nativeTools.isNotEmpty) {
      final serialized = nativeTools
          .map((tool) => _toolDefinitionJson(tool, model))
          .toList(growable: false);
      _addToolContextCharacters(
        counts,
        characters: jsonEncode(serialized).length,
        tools: nativeTools,
        resolvedToolsByName: resolvedToolsByName,
        model: model,
      );
    }
    return counts;
  }

  AiContextUsageCategory _contextUsageCategoryForTurn(AiChatTurn turn) {
    final content = turn.content;
    if (content.contains(AiPromptSectionHeaders.userMemory)) {
      return AiContextUsageCategory.memory;
    }
    if (content.contains(AiPromptSectionHeaders.userInstructions) ||
        content.contains(AiPromptSectionHeaders.workspaceInstructions)) {
      return AiContextUsageCategory.instructions;
    }
    if (content.contains(AiPromptSectionHeaders.restoredSkillContext)) {
      return AiContextUsageCategory.skills;
    }
    if (content.contains(AiPromptSectionHeaders.restoredMcpContext)) {
      return AiContextUsageCategory.mcp;
    }
    if (content.contains(
          AiPromptSectionHeaders.restoredSessionStartHookContext,
        ) ||
        content.contains(AiPromptSectionHeaders.systemReminder)) {
      return AiContextUsageCategory.hooks;
    }
    if (content.contains(AiPromptSectionHeaders.conversationContext) ||
        content.contains(AiPromptSectionHeaders.focusContext) ||
        content.contains(AiPromptSectionHeaders.restoredFileContext) ||
        content.contains(AiPromptSectionHeaders.restoredAgentResultContext)) {
      return AiContextUsageCategory.conversation;
    }
    if (content.contains(AiPromptSectionHeaders.staticSessionState) ||
        content.contains(AiPromptSectionHeaders.dynamicSessionState) ||
        content.contains(AiPromptSectionHeaders.planModeReminder) ||
        content.contains(AiPromptSectionHeaders.restoredPlanContext) ||
        content.contains(AiPromptSectionHeaders.restoredToolAndAgentListing)) {
      return AiContextUsageCategory.runtime;
    }
    return AiContextUsageCategory.systemPrompt;
  }

  void _addToolContextCharacters(
    Map<AiContextUsageCategory, int> counts, {
    required int characters,
    required List<AiToolDefinition> tools,
    required Map<String, AiResolvedTool> resolvedToolsByName,
    required AiModelConfig model,
  }) {
    if (characters <= 0) return;
    if (tools.isEmpty) {
      counts[AiContextUsageCategory.runtime] =
          (counts[AiContextUsageCategory.runtime] ?? 0) + characters;
      return;
    }
    final sourceByName = <String, AiRuntimeToolSource>{};
    for (final resolved in resolvedToolsByName.values) {
      sourceByName[resolved.name] = resolved.source;
      sourceByName[resolved.definition.name] = resolved.source;
    }
    final weights = <AiContextUsageCategory, int>{};
    for (final tool in tools) {
      final source =
          sourceByName[tool.name] ??
          (tool.name.startsWith('mcp__')
              ? AiRuntimeToolSource.mcp
              : tool.name.startsWith('skill__')
              ? AiRuntimeToolSource.skill
              : AiRuntimeToolSource.builtin);
      final category = switch (source) {
        AiRuntimeToolSource.builtin => AiContextUsageCategory.builtinTools,
        AiRuntimeToolSource.mcp => AiContextUsageCategory.mcp,
        AiRuntimeToolSource.skill => AiContextUsageCategory.skills,
      };
      weights[category] =
          (weights[category] ?? 0) +
          jsonEncode(_toolDefinitionJson(tool, model)).length;
    }
    final totalWeight = weights.values.fold<int>(0, (a, b) => a + b);
    if (totalWeight <= 0) {
      counts[AiContextUsageCategory.runtime] =
          (counts[AiContextUsageCategory.runtime] ?? 0) + characters;
      return;
    }
    final ranked = weights.entries.toList(growable: false);
    var allocated = 0;
    for (var index = 0; index < ranked.length; index += 1) {
      final entry = ranked[index];
      final value = index == ranked.length - 1
          ? characters - allocated
          : characters * entry.value ~/ totalWeight;
      counts[entry.key] = (counts[entry.key] ?? 0) + value;
      allocated += value;
    }
  }

  Map<String, Object?> _toolDefinitionJson(
    AiToolDefinition tool,
    AiModelConfig model,
  ) {
    return model.protocolType == AiProtocolType.claude
        ? tool.toClaudeJson()
        : tool.toOpenAiJson();
  }

  bool _shouldIncludeDynamicSessionState(
    Map<String, Object?> dynamicSessionState, {
    required bool latestUserInline,
  }) {
    if (latestUserInline || dynamicSessionState.isEmpty) return false;
    return dynamicSessionState.keys.any(_isVolatileDynamicSessionStateKey);
  }

  bool _isVolatileDynamicSessionStateKey(String key) {
    return switch (key) {
      'mode' ||
      'rehydration' ||
      'web_reverse_runtime' ||
      'android_reverse_runtime' ||
      'goal' ||
      'todos' ||
      'plan' ||
      'skipped_user_instruction_ids' => true,
      _ => false,
    };
  }

  String _fingerprintTurn(AiChatTurn turn) {
    final toolCalls = turn.toolCalls
        .map(
          (toolCall) =>
              '${toolCall.id}\u001f${toolCall.name}\u001f${toolCall.arguments}',
        )
        .join('\u001e');
    final parts = turn.parts
        .map(
          (part) => <String>[
            part.kind.name,
            part.text ?? '',
            part.filePath ?? '',
            part.mimeType ?? '',
          ].join('\u001f'),
        )
        .join('\u001e');
    return <String>[
      turn.roleName,
      turn.toolCallId ?? '',
      toolCalls,
      parts,
      turn.reasoningContent ?? '',
      turn.content,
    ].join('\u001d');
  }

  AiSessionMessage? _messageById(
    List<AiSessionMessage> messages,
    String? messageId,
  ) {
    final normalizedId = messageId?.trim() ?? '';
    if (normalizedId.isEmpty) return null;
    for (final message in messages.reversed) {
      if (message.id == normalizedId) return message;
    }
    return null;
  }

  List<Map<String, String>> _serializeRuntimeTailTurns(List<AiChatTurn> turns) {
    return turns
        .map(
          (turn) => <String, String>{
            'role': turn.roleName,
            'content': turn.content,
          },
        )
        .toList(growable: false);
  }

  List<AiChatTurn>? _readPersistedRuntimeTailTurns(Object? value) {
    if (value is! List || value.length > _runtimeTailSnapshotMaxTurns) {
      return null;
    }
    final turns = <AiChatTurn>[];
    var characterCount = 0;
    for (final item in value) {
      if (item is! Map) return null;
      final entry = stringKeyedMapFromValue(item);
      if ('${entry['role'] ?? ''}'.trim() != 'user') return null;
      final content = entry['content'];
      if (content is! String || content.isEmpty) return null;
      characterCount += content.length;
      if (characterCount > _runtimeTailSnapshotMaxCharacters) return null;
      turns.add(AiChatTurn(role: AiChatRole.user, content: content));
    }
    return List<AiChatTurn>.unmodifiable(turns);
  }

  String _jsonCodeBlock(Object? value) {
    return '```json\n${_promptJsonEncoder.convert(value)}\n```';
  }

  List<AiChatTurn> _optionalSystemSectionTurns(
    Iterable<_PromptSection> sections,
  ) {
    return <AiChatTurn>[
      for (final section in sections)
        if (section.hasContent)
          _systemSectionTurn(section.header, section.content),
    ];
  }

  List<AiChatTurn> _buildOutputFormatReminderTurns({
    required AiSessionRuntimeContext runtimeContext,
    required AiModelConfig model,
  }) {
    final turns = <AiChatTurn>[];
    switch (runtimeContext.messageContentFormat) {
      case AiMessageContentFormat.markdown:
        break;
      case AiMessageContentFormat.plainText:
        if (AiOutputFormatPrompts.plainText.isNotEmpty) {
          turns.add(
            _systemSectionTurn(
              AiPromptSectionHeaders.outputFormatReminder,
              AiOutputFormatPrompts.plainText,
            ),
          );
        }
      case AiMessageContentFormat.html:
        final htmlPrompt = AiOutputFormatPrompts.htmlFor(
          runtimeContext.htmlContentRichness,
        );
        if (htmlPrompt.isNotEmpty) {
          turns.add(
            _systemSectionTurn(
              AiPromptSectionHeaders.outputFormatReminder,
              htmlPrompt,
            ),
          );
        }
        if (_isGptSeriesModel(model.modelId) &&
            AiOutputFormatPrompts.gptChatRules.isNotEmpty) {
          turns.add(
            _systemSectionTurn(
              AiPromptSectionHeaders.gptChatRulesReminder,
              AiOutputFormatPrompts.gptChatRules,
            ),
          );
        }
    }
    return turns;
  }

  /// Theme Context 属于会话内可自变的状态（跟随系统的明暗模式会在日落等
  /// 时刻自动翻转）。它若留在稳定前缀，一次主题切换就会让全部 history
  /// 缓存失效；因此与其它易变状态一致，作为 runtime tail 轮次锚定内容
  /// 下发：随 round anchor 快照持久化、后续轮从历史逐字重放，
  /// 新主题在下一个 round anchor 生效。
  List<AiChatTurn> _buildThemeContextReminderTurns({
    required AiSessionRuntimeContext runtimeContext,
  }) {
    if (runtimeContext.messageContentFormat != AiMessageContentFormat.html) {
      return const <AiChatTurn>[];
    }
    final themeContext = AiOutputFormatPrompts.themeContextFor(
      brightness: runtimeContext.appThemeBrightness,
      presetName: runtimeContext.appThemePresetName,
      primaryColor: runtimeContext.appThemePrimaryColor,
    );
    if (themeContext.isEmpty) {
      return const <AiChatTurn>[];
    }
    return <AiChatTurn>[
      _runtimeContextSectionTurn(
        AiPromptSectionHeaders.themeContextReminder,
        themeContext,
      ),
    ];
  }

  String _renderWorkspaceInstructions(AiSessionRuntimeContext runtimeContext) {
    final documents = runtimeContext.workspaceInstructionDocuments;
    if (documents.isEmpty) {
      return '';
    }
    final buffer = StringBuffer()
      ..writeln()
      ..writeln()
      ..writeln(AiPromptSectionHeaders.workspaceInstructions)
      ..writeln()
      ..writeln(
        'The following workspace instruction files are active. Later entries are generally more specific than earlier ones.',
      );
    for (final document in documents) {
      buffer
        ..writeln()
        ..writeln('## ${document.name}')
        ..writeln('path: ${document.path}')
        ..writeln()
        ..writeln(document.content.trimRight());
    }
    return buffer.toString().trimRight();
  }

  Map<String, Object?> _buildContextBudgetMetadata({
    required AiModelConfig model,
    required int promptCharacterCount,
    required int estimatedCharactersPerToken,
  }) {
    final safeCharactersPerToken = math.max(1, estimatedCharactersPerToken);
    final estimatedPromptTokens = math.max(
      1,
      estimateAiTokensFromCharacters(
        promptCharacterCount,
        charactersPerToken: safeCharactersPerToken,
      ),
    );
    // 用户未在模型配置里填 maxContextTokens 时，回退到统一默认，避免
    // TopBar 上下文胶囊永远显示 “0% · 未知”。回退值仅用于 UI 估算，
    // 不影响实际拼装；通过 context_budget_window_inferred 标识。
    final configuredMaxContextTokens = model.maxContextTokens;
    final bool windowInferred =
        configuredMaxContextTokens == null || configuredMaxContextTokens <= 0;
    final int maxContextTokens = windowInferred
        ? kInferredModelContextWindowTokens
        : configuredMaxContextTokens;
    final summaryReserveTokens = math.min(
      _contextBudgetSummaryReserveTokens,
      math.max(1, maxContextTokens ~/ 2),
    );
    final effectiveWindowTokens = math.max(
      1,
      maxContextTokens - summaryReserveTokens,
    );
    final autoCompactBufferTokens = math.min(
      _contextBudgetAutoCompactBufferTokens,
      math.max(1, effectiveWindowTokens ~/ 10),
    );
    final warningBufferTokens = math.min(
      _contextBudgetWarningBufferTokens,
      math.max(1, effectiveWindowTokens ~/ 10),
    );
    final errorBufferTokens = math.min(
      _contextBudgetErrorBufferTokens,
      math.max(1, effectiveWindowTokens ~/ 10),
    );
    final manualCompactBufferTokens = math.min(
      _contextBudgetManualCompactBufferTokens,
      math.max(1, effectiveWindowTokens ~/ 50),
    );
    final autoCompactThresholdTokens = math.max(
      1,
      effectiveWindowTokens - autoCompactBufferTokens,
    );
    final warningThresholdTokens = math.max(
      1,
      autoCompactThresholdTokens - warningBufferTokens,
    );
    final errorThresholdTokens = math.max(
      1,
      autoCompactThresholdTokens - errorBufferTokens,
    );
    final blockingLimitTokens = math.max(
      1,
      effectiveWindowTokens - manualCompactBufferTokens,
    );
    final remainingTokens = effectiveWindowTokens - estimatedPromptTokens;
    final usageRatio = estimatedPromptTokens / effectiveWindowTokens;
    final percentLeft = math.max(
      0,
      (((autoCompactThresholdTokens - estimatedPromptTokens) /
                  autoCompactThresholdTokens) *
              100)
          .round(),
    );
    final isAtBlockingLimit = estimatedPromptTokens >= blockingLimitTokens;
    final isAboveAutoCompactThreshold =
        estimatedPromptTokens >= autoCompactThresholdTokens;
    final isAboveWarningThreshold =
        estimatedPromptTokens >= warningThresholdTokens;
    final isAboveErrorThreshold = estimatedPromptTokens >= errorThresholdTokens;
    final status = isAtBlockingLimit
        ? 'critical'
        : isAboveAutoCompactThreshold
        ? 'auto_compact'
        : isAboveErrorThreshold || isAboveWarningThreshold
        ? 'warning'
        : 'ok';
    return <String, Object?>{
      'context_budget_status': status,
      'context_budget_window_inferred': windowInferred,
      'context_budget_estimated_prompt_tokens': estimatedPromptTokens,
      'context_budget_estimated_chars_per_token': safeCharactersPerToken,
      'context_budget_model_max_tokens': maxContextTokens,
      'context_budget_summary_reserve_tokens': summaryReserveTokens,
      'context_budget_effective_window_tokens': effectiveWindowTokens,
      'context_budget_auto_compact_threshold_tokens':
          autoCompactThresholdTokens,
      'context_budget_warning_threshold_tokens': warningThresholdTokens,
      'context_budget_error_threshold_tokens': errorThresholdTokens,
      'context_budget_blocking_limit_tokens': blockingLimitTokens,
      'context_budget_remaining_tokens': remainingTokens,
      'context_budget_usage_percent': (usageRatio * 100).round(),
      'context_budget_percent_left': percentLeft,
      'context_budget_warning_buffer_tokens': warningBufferTokens,
      'context_budget_error_buffer_tokens': errorBufferTokens,
      'context_budget_manual_compact_buffer_tokens': manualCompactBufferTokens,
      'context_budget_auto_compact_buffer_tokens': autoCompactBufferTokens,
      'context_budget_is_above_warning_threshold': isAboveWarningThreshold,
      'context_budget_is_above_error_threshold': isAboveErrorThreshold,
      'context_budget_is_above_auto_compact_threshold':
          isAboveAutoCompactThreshold,
      'context_budget_is_at_blocking_limit': isAtBlockingLimit,
    };
  }

  Map<String, Object?> _buildPostCompactRehydrationSnapshot({
    required AiSession session,
    required List<AiSessionMessage> historyMessages,
    required AiSessionRuntimeContext runtimeContext,
    required List<UserMemoryEntry> memoryEntries,
    required AiRepositorySnapshot? repositorySnapshot,
    required List<String> availableToolNames,
    required Map<String, AiResolvedTool> resolvedToolsByName,
    required Map<String, String> mcpServerInstructionsByName,
    required AiSessionMessage? latestCompressionPoint,
  }) {
    // 未发生压缩时返回空 map：这是「恢复上下文清单」，没压缩点就
    // 没必要把工具数 / MCP / agent_types 等会话级近静态数据塞进 [3d]，每轮多
    // 上千 token 体积只会增加 prefix-cache 抖动风险。
    if (latestCompressionPoint == null) return const <String, Object?>{};
    final skillToolCount = availableToolNames
        .where((name) => name.startsWith('skill__'))
        .length;
    final mcpToolCount = availableToolNames
        .where((name) => name.startsWith('mcp__'))
        .length;
    final builtinToolCount =
        availableToolNames.length - skillToolCount - mcpToolCount;
    final mcpServerNames = runtimeContext.availableMcpServers
        .where(
          (server) =>
              server.enabled && server.isVisibleToTemplate(session.templateId),
        )
        .map((server) => server.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    mcpServerNames.sort(_comparePromptCatalogNames);
    final promptMcpServerInstructions = _mcpServerInstructionsForPrompt(
      mcpServerInstructionsByName,
    );
    final mcpServerInstructionNames = promptMcpServerInstructions.keys.toList(
      growable: false,
    );
    mcpServerInstructionNames.sort(_comparePromptCatalogNames);
    final sidecarMarkdownPath = _sessionCompactMemoryMarkdownPath(
      session,
      latestCompressionPoint,
    );
    final recentFileAnchors = _recentFileContextAnchors(historyMessages);
    final recentInvokedSkills = _recentInvokedSkillAnchors(historyMessages);
    final recentSessionStartHooks = _recentSessionStartHookAnchors(
      historyMessages: historyMessages,
      latestCompressionPoint: latestCompressionPoint,
    );
    final recentAgentResults = _recentAgentResultAnchors(
      historyMessages: historyMessages,
      latestCompressionPoint: latestCompressionPoint,
    );
    final deferredTools = _postCompactDeferredBuiltinTools(resolvedToolsByName);
    final taskAgentTypes = _postCompactTaskAgentTypes(
      availableToolNames: availableToolNames,
      resolvedToolsByName: resolvedToolsByName,
    );
    final restoredChannels = <String>[
      'system_instructions',
      'developer_instructions',
      'tool_catalog',
      'session_state',
      'conversation_checkpoint',
      'recent_history_tail',
      if (runtimeContext.memoryEnabled) 'user_memory',
      if (runtimeContext.workspaceInstructionDocuments.isNotEmpty)
        'workspace_instructions',
      if (_renderUserInstructionsBody(
        runtimeContext.userInstructions,
        const <String>{},
      ).isNotEmpty)
        'user_instructions',
      if (repositorySnapshot != null) 'repository_snapshot',
      if (session.todoItems.isNotEmpty) 'todos',
      if (session.pendingPlan?.trim().isNotEmpty == true) 'pending_plan',
      if (session.planHistory.isNotEmpty) 'plan_history',
      if (_hasRestorablePlanContext(session)) 'plan_context',
      if (mcpToolCount > 0 ||
          mcpServerNames.isNotEmpty ||
          mcpServerInstructionNames.isNotEmpty)
        'mcp_context',
      if (mcpServerInstructionNames.isNotEmpty) 'mcp_instructions',
      if (recentFileAnchors.isNotEmpty) 'recent_file_anchors',
      if (recentInvokedSkills.isNotEmpty) 'invoked_skills',
      if (recentSessionStartHooks.isNotEmpty) 'session_start_hooks',
      if (recentAgentResults.isNotEmpty) 'agent_results',
      if (deferredTools.isNotEmpty) 'deferred_builtin_tools',
      if (taskAgentTypes.isNotEmpty) 'agent_listing',
    ];
    return <String, Object?>{
      'active': true,
      'checkpoint_message_id': latestCompressionPoint.id,
      'checkpoint_created_at': latestCompressionPoint.createdAt
          .toUtc()
          .toIso8601String(),
      'session_memory_sidecar_present': sidecarMarkdownPath != null,
      'session_memory_sidecar_path': sidecarMarkdownPath,
      'restored_channels': restoredChannels,
      'runtime_tool_count': availableToolNames.length,
      'builtin_tool_count': builtinToolCount,
      'skill_tool_count': skillToolCount,
      'mcp_tool_count': mcpToolCount,
      'mcp_server_count': mcpServerNames.length,
      'mcp_server_instruction_count': mcpServerInstructionNames.length,
      if (mcpServerNames.isNotEmpty) 'mcp_server_names': mcpServerNames,
      if (mcpServerInstructionNames.isNotEmpty)
        'mcp_server_instruction_names': mcpServerInstructionNames,
      'memory_enabled': runtimeContext.memoryEnabled,
      'memory_entry_count': memoryEntries.length,
      'workspace_instruction_document_count':
          runtimeContext.workspaceInstructionDocuments.length,
      'todo_count': session.todoItems.length,
      'plan_record_count': session.planHistory.length,
      'pending_plan_present': session.pendingPlan?.trim().isNotEmpty == true,
      'repository_snapshot_present': repositorySnapshot != null,
      'recent_file_anchor_count': recentFileAnchors.length,
      'session_start_hook_count': recentSessionStartHooks.length,
      'agent_result_count': recentAgentResults.length,
      if (recentAgentResults.isNotEmpty)
        'agent_results': recentAgentResults
            .map(
              (message) => <String, Object?>{
                'message_id': message.id,
                'created_at': message.createdAt.toUtc().toIso8601String(),
                'tool_name': '${message.metadata['tool_name'] ?? ''}'.trim(),
                'action': '${message.metadata['action'] ?? ''}'.trim(),
                'subagent_type': '${message.metadata['subagent_type'] ?? ''}'
                    .trim(),
                'status': '${message.metadata['status'] ?? ''}'.trim(),
              },
            )
            .toList(growable: false),
      'deferred_builtin_tool_count': deferredTools.length,
      if (deferredTools.isNotEmpty)
        'deferred_builtin_tool_names': deferredTools
            .map((tool) => tool.name)
            .toList(growable: false),
      'agent_type_count': taskAgentTypes.length,
      if (taskAgentTypes.isNotEmpty) 'agent_types': taskAgentTypes,
      if (recentFileAnchors.isNotEmpty)
        'recent_file_anchors': recentFileAnchors,
      'invoked_skill_count': recentInvokedSkills.length,
      if (recentInvokedSkills.isNotEmpty) 'invoked_skills': recentInvokedSkills,
    };
  }

  String? _sessionCompactMemoryMarkdownPath(
    AiSession session,
    AiSessionMessage? latestCompressionPoint,
  ) {
    if (latestCompressionPoint == null) {
      return null;
    }
    final sessionsDirectoryPath = session.environment.sessionsDirectoryPath
        .trim();
    if (sessionsDirectoryPath.isEmpty || session.id.trim().isEmpty) {
      return null;
    }
    return p.join(
      sessionsDirectoryPath,
      session.id,
      'memory',
      'compact-latest.md',
    );
  }

  Map<String, Object?> _buildPromptEnvironmentSnapshot(
    AiSessionRuntimeContext runtimeContext, {
    required List<AiAllowCommandRule> allowCommandRules,
    required bool includeRepositorySnapshot,
  }) {
    final workingDirectory = runtimeContext.workingDirectory.trim().isEmpty
        ? OpenHandPaths.applicationDirectoryPath()
        : runtimeContext.workingDirectory.trim();
    final snapshot = <String, Object?>{
      'working_directory': workingDirectory,
      'platform_name': runtimeContext.platformName,
      'time_zone_name': runtimeContext.timeZoneName,
      'single_round_tool_call_limit': runtimeContext.singleRoundToolCallLimit,
      'sequential_tool_round_limit': runtimeContext.sequentialToolRoundLimit,
      'write_command_confirmation_enabled':
          runtimeContext.writeCommandConfirmationEnabled,
      'workspace_instruction_paths': runtimeContext
          .workspaceInstructionDocuments
          .map((item) => item.path)
          .toList(growable: false),
    };
    if (allowCommandRules.isNotEmpty) {
      snapshot['allow_command_rules'] = allowCommandRules
          .map((item) => item.toJson())
          .toList(growable: false);
    }
    final sandbox = runtimeContext.sandboxSettings;
    snapshot['sandbox'] = <String, Object?>{
      'enabled': sandbox.enabled,
      if (sandbox.enabled) ...<String, Object?>{
        'fail_if_unavailable': sandbox.failIfUnavailable,
        'allow_unsandboxed_commands': sandbox.allowUnsandboxedCommands,
        'auto_allow_bash_if_sandboxed': sandbox.autoAllowBashIfSandboxed,
        'sandboxed_builtin_tools': sandbox.sandboxedBuiltinTools,
        'filesystem_rule_count': sandbox.filesystemRules.length,
        'excluded_command_count': sandbox.excludedCommands.length,
        'allowed_domain_count': sandbox.allowedDomains.length,
        'denied_domain_count': sandbox.deniedDomains.length,
        'http_proxy_port': sandbox.httpProxyPort,
        'socks_proxy_port': sandbox.socksProxyPort,
      },
    };
    if (includeRepositorySnapshot) {
      snapshot['repository_snapshot'] = runtimeContext.repositorySnapshot
          ?.toJson();
    }
    return snapshot;
  }

  Map<String, Object?> _buildCompactStaticSessionState({
    required AiSession session,
    required AiSessionRuntimeContext runtimeContext,
    required List<AiAllowCommandRule> allowCommandRules,
  }) {
    final workingDirectory = runtimeContext.workingDirectory.trim().isEmpty
        ? OpenHandPaths.applicationDirectoryPath()
        : runtimeContext.workingDirectory.trim();

    final staticState = <String, Object?>{
      // session.mode 不会一生不变（用户随时可在 plan / normal
      // 之间切换），迁到 [3d] Dynamic；避免切换模式就抹掉所有 prefix cache。
      'context': <String, Object?>{
        'cwd': workingDirectory,
        'platform': runtimeContext.platformName,
        'tz': runtimeContext.timeZoneName,
      },
      'limits': <String, Object?>{
        'tpr': runtimeContext.singleRoundToolCallLimit,
        'r': runtimeContext.sequentialToolRoundLimit,
      },
      'permission': <String, Object?>{
        'full_access': session.fullAccessPermission,
        'write_cmd_confirm_required': _writeCommandConfirmationRequired(
          session: session,
          runtimeContext: runtimeContext,
        ),
      },
    };

    if (allowCommandRules.isNotEmpty) {
      staticState['allow_cmd_rules'] = allowCommandRules
          .map((rule) {
            final note = rule.note.trim();
            return note.isEmpty
                ? '${rule.matchMode.storageValue}:${rule.pattern.trim()}'
                : '${rule.matchMode.storageValue}:${rule.pattern.trim()} ($note)';
          })
          .toList(growable: false);
    }

    if (runtimeContext.workspaceInstructionDocuments.isNotEmpty) {
      staticState['workspace_instructions'] = runtimeContext
          .workspaceInstructionDocuments
          .map((item) => item.path)
          .toList(growable: false);
    }

    return staticState;
  }

  bool _writeCommandConfirmationRequired({
    required AiSession session,
    required AiSessionRuntimeContext runtimeContext,
  }) {
    return runtimeContext.writeCommandConfirmationEnabled &&
        !session.fullAccessPermission;
  }

  Map<String, Object?> _buildCompactDynamicSessionState({
    required AiSession session,
    required AiSessionRuntimeContext runtimeContext,
    required Map<String, Object?> postCompactRehydration,
    required List<String> availableToolNames,
    required Map<String, Object?>? webReverseRuntime,
    required Map<String, Object?>? androidReverseRuntime,
    required bool planModeExecutionApprovedForSend,
    required bool planModeRecoveryInspectionRequired,
  }) {
    final dynamicState = <String, Object?>{};

    // 缓存友好策略：[3d] 只保留「会话内会变 && 模型实际会用」的字段。
    // session.title 与 git 快照不进入 prompt：标题对执行无约束价值，git
    // 状态可由工具按需读取；二者进入稳定前缀会让新线程无法复用内置 Prompt
    // 缓存，进入动态尾部则会破坏前缀延展。
    if (session.mode != AiSessionMode.chat) {
      dynamicState['mode'] = session.mode.storageValue;
    }

    // 仅在真实存在压缩点（active=true）时注入 rehydration 块。
    // 否则该块会把会话级近静态数据（工具数 / MCP 列表 / agent_types 等）每轮带进
    // [3d]，徒增体积而无实际"恢复上下文"语义。
    final rehydrationActive = postCompactRehydration['active'] == true;
    if (rehydrationActive) {
      dynamicState['rehydration'] = postCompactRehydration;
    }
    if (webReverseRuntime != null && webReverseRuntime.isNotEmpty) {
      dynamicState['web_reverse_runtime'] = webReverseRuntime;
    }
    if (androidReverseRuntime != null && androidReverseRuntime.isNotEmpty) {
      dynamicState['android_reverse_runtime'] = androidReverseRuntime;
    }

    final goalSnapshot = _goalStatePromptSnapshot(session.goalState);
    if (goalSnapshot.isNotEmpty) {
      dynamicState['goal'] = goalSnapshot;
    }

    if (session.todoItems.isNotEmpty) {
      dynamicState['todos'] = session.todoItems
          .map((item) => item.toJson())
          .toList(growable: false);
    }

    if (session.mode == AiSessionMode.plan || session.awaitingPlanApproval) {
      dynamicState['plan'] = <String, Object?>{
        'active': session.mode == AiSessionMode.plan,
        'awaiting_approval': session.awaitingPlanApproval,
        'tool_gate_reason': AiPlanModeToolGate.gateReason(
          isPlanMode: session.mode == AiSessionMode.plan,
          awaitingPlanApproval: session.awaitingPlanApproval,
          availableToolNames: availableToolNames,
          executionApprovedForSend: planModeExecutionApprovedForSend,
          recoveryInspectionRequired: planModeRecoveryInspectionRequired,
        ),
        'available_tool_count': availableToolNames.length,
        'planning_tool_allowlist': AiPlanModeToolGate.planningToolNames,
        'exit_plan_mode_available': AiPlanModeToolGate.hasExitPlanModeTool(
          availableToolNames,
        ),
        if (planModeExecutionApprovedForSend) 'execution_tools_approved': true,
        if (planModeRecoveryInspectionRequired)
          'recovery_inspection_required': true,
        if (session.pendingPlan != null &&
            session.pendingPlan!.trim().isNotEmpty)
          'pending_plan': session.pendingPlan!.trim(),
        if (session.pendingPlanAllowedPrompts.isNotEmpty)
          'pending_plan_allowed_prompts': _planAllowedPromptsSnapshot(
            session.pendingPlanAllowedPrompts,
          ),
      };
    }

    // todoReminder / planModeReminder 不再写入 [3d]：
    // 它们每轮都可能新增 / 失效 / 改写，强行塞进位于 prefix 的 [3d] 会让
    // 整段 history 缓存失效。统一改为 history 之后的独立 system 块
    // (# System Reminder / # Plan Mode Reminder)，与其它 volatile tail
    // 提醒共享一份"不入 prefix"的策略。

    // 本轮被临时跳过的用户指令 id 列表，让 [4.5] 保持
    // 字节稳定（缓存友好），实际忽略哪几条从 [3d] 读取。
    if (runtimeContext.skippedInstructionIds.isNotEmpty) {
      final ids = runtimeContext.skippedInstructionIds.toList()..sort();
      dynamicState['skipped_user_instruction_ids'] = ids;
    }

    return dynamicState;
  }

  Map<String, Object?> _goalStatePromptSnapshot(AiSessionGoalState state) {
    final current = state.current;
    final history = state.history.reversed
        .take(_promptGoalHistoryLimit)
        .toList(growable: false)
        .reversed
        .map(_goalRecordPromptSnapshot)
        .toList(growable: false);
    if (current == null && history.isEmpty) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      if (current != null) 'current': _goalRecordPromptSnapshot(current),
      if (history.isNotEmpty) 'history_recent': history,
    };
  }

  Map<String, Object?> _goalRecordPromptSnapshot(AiSessionGoalRecord goal) {
    final lastEvaluation = goal.lastEvaluation;
    return <String, Object?>{
      'id': goal.id,
      'status': goal.status.storageValue,
      'objective': clipTextWithEllipsis(
        goal.objective,
        _promptGoalObjectiveMaxChars,
      ),
      'turn_count': goal.turnCount,
      'max_turns': goal.maxTurns ?? aiSessionGoalDefaultMaxAutoTurns,
      'tokens_used': goal.tokensUsed,
      if (goal.tokenBudget != null) 'token_budget': goal.tokenBudget,
      'evaluator': <String, Object?>{
        'provider_config_id': goal.evaluatorProviderConfigId,
        'model_id': goal.evaluatorModelId,
        'model_label': goal.evaluatorModelLabel,
      },
      if ((goal.statusReason ?? '').trim().isNotEmpty)
        'status_reason': clipTextWithEllipsis(
          goal.statusReason!.trim(),
          _promptGoalEvaluationMaxChars,
        ),
      if (lastEvaluation != null)
        'last_evaluation': _goalEvaluationPromptSnapshot(lastEvaluation),
      if ((goal.lastAssistantMessageId ?? '').trim().isNotEmpty)
        'last_assistant_message_id': goal.lastAssistantMessageId,
      if ((goal.lastAutoUserMessageId ?? '').trim().isNotEmpty)
        'last_auto_user_message_id': goal.lastAutoUserMessageId,
    };
  }

  Map<String, Object?> _goalEvaluationPromptSnapshot(
    AiSessionGoalEvaluationRecord evaluation,
  ) {
    return <String, Object?>{
      'id': evaluation.id,
      'round_index': evaluation.roundIndex,
      'passed': evaluation.passed,
      'summary': clipTextWithEllipsis(
        evaluation.summary,
        _promptGoalEvaluationMaxChars,
      ),
      if (evaluation.confidence != null) 'confidence': evaluation.confidence,
      if ((evaluation.followUpPrompt ?? '').trim().isNotEmpty)
        'follow_up_prompt': clipTextWithEllipsis(
          evaluation.followUpPrompt!.trim(),
          _promptGoalEvaluationMaxChars,
        ),
      if (evaluation.evidence.isNotEmpty)
        'evidence': evaluation.evidence
            .map((item) => clipTextWithEllipsis(item, 240))
            .toList(growable: false),
      if (evaluation.missing.isNotEmpty)
        'missing': evaluation.missing
            .map((item) => clipTextWithEllipsis(item, 240))
            .toList(growable: false),
      if ((evaluation.error ?? '').trim().isNotEmpty)
        'error': clipTextWithEllipsis(evaluation.error!.trim(), 240),
    };
  }

  String _renderRuntimeToolCatalog(
    List<AiToolDefinition> availableTools, {
    bool compact = false,
    required AiPromptTemplatePolicy templatePolicy,
    bool awaitingPlanApproval = false,
    bool useDsmlToolCalls = false,
    Map<String, AiResolvedTool> resolvedToolsByName =
        const <String, AiResolvedTool>{},
  }) {
    final skillTools = <AiToolDefinition>[];
    final mcpTools = <AiToolDefinition>[];
    final builtinTools = <AiToolDefinition>[];
    for (final tool in availableTools) {
      final name = tool.name.trim();
      if (name.isEmpty) {
        continue;
      }
      if (name.startsWith('skill__')) {
        skillTools.add(tool);
      } else if (name.startsWith('mcp__')) {
        mcpTools.add(tool);
      } else {
        builtinTools.add(tool);
      }
    }
    int compareTools(AiToolDefinition a, AiToolDefinition b) =>
        _compareToolDefinitionsForPromptCatalog(
          a,
          b,
          resolvedToolsByName: resolvedToolsByName,
        );

    skillTools.sort(compareTools);
    mcpTools.sort(compareTools);
    builtinTools.sort(compareTools);
    final visibleToolCount =
        skillTools.length + mcpTools.length + builtinTools.length;
    if (visibleToolCount == 0) {
      if (awaitingPlanApproval) {
        return AiPlanModeGuidance.emptyCatalogAwaitingApproval;
      }
      return 'No runtime tools are available in this response. Do not invent tool names or assume a tool exists because it existed in an earlier turn.';
    }
    final isMachineExpert = templatePolicy.usesMachineToolCatalog;
    final isWebReverse = templatePolicy.usesWebReverseToolCatalog;
    final isAndroidReverse = templatePolicy.usesAndroidReverseToolCatalog;
    final buffer = StringBuffer();
    if (compact) {
      buffer.writeln(
        'Authoritative tool list for this turn. Absent tools are unavailable.',
      );
    } else {
      buffer
        ..writeln(
          'This is the authoritative runtime tool catalog for the current response. Use only exact tool names from this list. If a tool is absent here, it is unavailable for this turn.',
        )
        ..writeln();
      if (isMachineExpert) {
        buffer.writeln(
          'Capability invocation priority for the Machine Expert template: '
          'Builtin terminal-interaction workflow is the absolute top priority and MUST drive the main loop '
          '(target-terminal binding, command dispatch, output parsing, blocking recovery, write-command confirmation). '
          'External skill__* / mcp__* tools — even those that look like "machine-expert" / "terminal-automation" — '
          'may only be consulted as auxiliary knowledge sources (command syntax, error interpretation, domain specifics) '
          'and MUST NOT replace or reorder this template\'s built-in workflow, its phase output templates, or its safety gates. '
          'All `write text` / `do script` / `keystroke` / `tmux send-keys` dispatch MUST go through the built-in Bash tool '
          'so it passes the local deny-list and write-command confirmation pipeline.',
        );
      } else if (isWebReverse) {
        buffer.writeln(
          'Capability invocation priority for the Web Reverse Expert template: '
          'CDP MCP tools backed by the OpenHand-managed Chrome CDP runtime and local jsonl/HAR artifacts are the first-line path for navigation, DOM, Network, Console, Storage, screenshots, Raw CDP, WebSocket/SSE, and HAR work. Treat chrome-devtools-mcp and current-page `js-reverse_*` wrappers as CDP MCP routes. '
          'Live CDP requires the injected `cdp_runtime` to report `browser_alive=true` plus a current CDP endpoint/port; while live, do not launch a new browser or attach via Bash. '
          'When `browser_alive` is false or no current endpoint/port exists, live CDP MCP actions are unavailable: use local jsonl/HAR artifacts and ask the user to restart the browser before live browser operations. '
          'Read / Grep / Glob / LS handle local artifacts and static code search before Bash; Bash is for reproduction scripts and shell-only toolchains. '
          'Bash/WebFetch/WebSearch target-origin capture is blocked; use CDP MCP tools, ToolSearch, or local jsonl/HAR first. '
          'skill__* tools are auxiliary knowledge only. Do not use Playwright, Puppeteer, Selenium/WebDriver, Browserless, or other non-CDP browser automation for target-origin capture; if CDP cannot expose the needed state, explain the gap and use local artifacts or ask the user to restore CDP. '
          'Hook scripts MUST be loaded from `assets/prompts/web_reverse_expert/snippets/`; never hand-craft hook code.',
        );
      } else if (isAndroidReverse) {
        buffer.writeln(
          'Capability invocation priority for the Android Reverse Expert template: '
          'ADB MCP (or adb Bash) is the first-line device channel for shell, file transfer, logcat, and forward/reverse port mapping. '
          'Frida MCP (or frida CLI Bash) is the first-line dynamic instrumentation channel; spawn before attach where possible. '
          'Static analysis (jadx / apktool / radare2 / IDA Pro MCP) precedes dynamic hooking — decompile before hooking unknown code. '
          'Hook scripts MUST be loaded from `assets/prompts/android_reverse_expert/snippets/`; never hand-craft hook code. '
          'Read / Grep / Glob / LS handle local artifacts and static searches before Bash; Bash is for ADB/Frida/static-analysis toolchains and reproduction scripts. '
          'Stop and report after 2 consecutive Frida/ADB failures on the same target; never silently downgrade.',
        );
      } else {
        buffer.writeln(
          'Choose tools by task fit, not by trial order. '
          'For local file read/search/list/edit, use Read/Grep/Glob/LS/Edit family before Bash. '
          'Use a skill only when the user explicitly selected it or the request clearly needs that skill\'s specialized workflow. '
          'When no listed capability is required, stay on the base instructions and ask only for missing requirements that block the response. '
          'Prefer MCP when it is the clearest live data/action surface; use builtin tools for local files, shell, search, and routine implementation.',
        );
      }
    }
    if (skillTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          compact
              ? (isMachineExpert ? '## Skills (auxiliary only)' : '## Skills')
              : (isMachineExpert
                    ? '## Skill Tools (auxiliary knowledge only — do NOT replace built-in terminal workflow)'
                    : isWebReverse
                    ? '## Skill Tools (auxiliary knowledge only — CDP remains source of truth)'
                    : isAndroidReverse
                    ? '## Skill Tools (auxiliary knowledge only — ADB/Frida remain source of truth)'
                    : '## Skill Tools (load only on clear match)'),
        );
      for (final tool in skillTools) {
        _renderToolEntry(buffer, tool, compact: compact);
      }
    }
    if (mcpTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          compact
              ? '## MCP'
              : isWebReverse
              ? '## MCP Tools (CDP-first for Web Reverse)'
              : isAndroidReverse
              ? '## MCP Tools (ADB/Frida-first for Android Reverse)'
              : '## MCP Tools (medium priority)',
        );
      for (final tool in mcpTools) {
        _renderToolEntry(buffer, tool, compact: compact);
      }
    }
    if (builtinTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          compact
              ? '## Builtin'
              : isWebReverse
              ? '## Builtin Tools (artifact/search/reproduce support)'
              : isAndroidReverse
              ? '## Builtin Tools (artifact/search/reproduce support)'
              : '## Builtin Tools (baseline)',
        );
      for (final tool in builtinTools) {
        // 紧凑模式仍保留内置工具完整描述与必填参数，兼容忽略 API 工具数组的模型。
        _renderToolEntry(buffer, tool, compact: compact);
      }
    }
    if (useDsmlToolCalls && visibleToolCount > 0) {
      buffer
        ..writeln()
        ..writeln('## Tool Invocation Format (DSML)')
        ..writeln(
          'This model does NOT support protocol-native function calling. '
          'To invoke a tool, append the following XML at the END of your reply '
          '(after any natural-language explanation, with no trailing prose). '
          'Output exactly one `<DSML:function_calls>` block per turn; the runtime '
          'will execute the calls and feed the results back as a tool message.',
        )
        ..writeln()
        ..writeln('```xml')
        ..writeln('<DSML:function_calls>')
        ..writeln('  <DSML:invoke name="ExactToolName">')
        ..writeln(
          '    <DSML:parameter name="stringKey">plain text</DSML:parameter>',
        )
        ..writeln(
          '    <DSML:parameter name="arrayKey" string="false">[{"id":"1","status":"pending"}]</DSML:parameter>',
        )
        ..writeln(
          '    <DSML:parameter name="objectKey" string="false">{"k":"v"}</DSML:parameter>',
        )
        ..writeln('  </DSML:invoke>')
        ..writeln('</DSML:function_calls>')
        ..writeln('```')
        ..writeln()
        ..writeln(
          'Rules: (1) Use ONLY exact tool names listed above — do NOT invent '
          'unlisted aliases like `todo_write`, `u_TodoWrite`, or wrap calls in '
          '`##TOOL_CALL##` markers. Use `TodoWrite` only when that exact name '
          'appears in the catalog. '
          '(2) String parameters are the default. For object/array/number/bool '
          'parameters, add `string="false"` and put the bare JSON value inside. '
          'For an array parameter (e.g. `todos`), emit `[...]` directly — DO '
          'NOT wrap it as `{"todos":[...]}` and do NOT use `<![CDATA[...]]>`. '
          '(3) Never wrap the DSML block in Markdown code fences in the actual '
          'output. (4) Place the DSML block at the very end of your reply with '
          'no text after `</DSML:function_calls>`.',
        );
    }
    return buffer.toString().trimRight();
  }

  void _renderToolEntry(
    StringBuffer buffer,
    AiToolDefinition tool, {
    bool compact = false,
    bool builtinCompact = false,
  }) {
    if (builtinCompact) {
      final description = _truncateToolDescription(
        tool.description,
        maxCharacters: 80,
      );
      buffer
        ..writeln()
        ..writeln('- ${tool.name}: $description');
      return;
    }
    final description = compact
        ? _truncateToolDescription(tool.description, maxCharacters: 120)
        : _truncateToolDescription(tool.description);
    final requiredArguments = _toolArgumentNames(
      tool.parameters,
      requiredOnly: true,
    );
    buffer
      ..writeln()
      ..write('- ${tool.name}: $description');
    if (requiredArguments.isNotEmpty) {
      buffer.write(
        compact
            ? ' Args: ${requiredArguments.join(', ')}.'
            : ' Required args: ${requiredArguments.join(', ')}.',
      );
    }
    if (!compact) {
      final optionalArguments = _toolArgumentNames(
        tool.parameters,
        requiredOnly: false,
      );
      if (optionalArguments.isNotEmpty) {
        buffer.write(' Optional args: ${optionalArguments.join(', ')}.');
      }
    }
    buffer.writeln();
  }

  String _truncateToolDescription(
    String description, {
    int maxCharacters = 220,
  }) {
    final normalized = normalizeDescriptionText(description);
    if (normalized.length <= maxCharacters) {
      return normalized;
    }
    return clipTextByCodeUnits(normalized, maxCharacters);
  }

  String _normalizeToolNameForPromptCatalog(String value) {
    return normalizeAsciiLookupKey(value);
  }

  int _compareToolDefinitionsForPromptCatalog(
    AiToolDefinition a,
    AiToolDefinition b, {
    Map<String, AiResolvedTool> resolvedToolsByName =
        const <String, AiResolvedTool>{},
  }) {
    final resolvedA = resolvedToolsByName[a.name];
    final resolvedB = resolvedToolsByName[b.name];
    final sourceCompare = _toolSourcePromptRank(
      resolvedA,
    ).compareTo(_toolSourcePromptRank(resolvedB));
    if (sourceCompare != 0) return sourceCompare;

    final configA = resolvedA?.builtinConfig;
    final configB = resolvedB?.builtinConfig;
    if (configA != null || configB != null) {
      final sortOrderCompare = (configA?.sortOrder ?? 100000).compareTo(
        configB?.sortOrder ?? 100000,
      );
      if (sortOrderCompare != 0) return sortOrderCompare;
      final priorityCompare = (configA?.priority ?? 100).compareTo(
        configB?.priority ?? 100,
      );
      if (priorityCompare != 0) return priorityCompare;
    }
    return _comparePromptCatalogNames(a.name, b.name);
  }

  int _toolSourcePromptRank(AiResolvedTool? tool) {
    return switch (tool?.source) {
      AiRuntimeToolSource.skill => 0,
      AiRuntimeToolSource.mcp => 1,
      AiRuntimeToolSource.builtin => 2,
      null => 3,
    };
  }

  int _comparePromptCatalogNames(String a, String b) {
    final normalizedCompare = _normalizeToolNameForPromptCatalog(
      a,
    ).compareTo(_normalizeToolNameForPromptCatalog(b));
    if (normalizedCompare != 0) {
      return normalizedCompare;
    }
    return a.compareTo(b);
  }

  List<String> _promptCatalogToolNames(List<AiToolDefinition> tools) {
    final names = tools
        .map((tool) => tool.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    names.sort(_comparePromptCatalogNames);
    return names;
  }

  String _promptCatalogSignature(List<AiToolDefinition> tools) {
    final entries = tools
        .where((tool) => tool.name.trim().isNotEmpty)
        .toList(growable: false);
    entries.sort(_compareToolDefinitionsForPromptCatalog);
    return entries
        .map(
          (tool) => <String>[
            tool.name.trim(),
            tool.description.trim(),
            _promptJsonEncoder.convert(_canonicalPromptJson(tool.parameters)),
          ].join('\u001f'),
        )
        .join('\u001e');
  }

  Object? _canonicalPromptJson(Object? value) {
    if (value is Map) {
      final entries = value.entries
          .map(
            (entry) => MapEntry<String, Object?>(
              '${entry.key}',
              _canonicalPromptJson(entry.value),
            ),
          )
          .toList(growable: false);
      entries.sort((left, right) => left.key.compareTo(right.key));
      return Map<String, Object?>.fromEntries(entries);
    }
    if (value is Iterable) {
      return value.map(_canonicalPromptJson).toList(growable: false);
    }
    return value;
  }

  String _promptFingerprint(String content) {
    if (content.isEmpty) {
      return '0';
    }
    return stableFnv1a32Hex(content);
  }

  String _promptCacheAffinityKey({
    required AiSession session,
    required AiModelConfig model,
  }) {
    return stableSha256Hex(
      [
        _promptCacheAffinityKeyScope,
        session.id,
        session.templateId,
        session.templateInternalVersion,
        model.normalizedBaseUrl,
        model.protocolType.storageValue,
        model.apiDialect.storageValue,
        model.providerKind.storageValue,
        model.modelId,
      ].join('\n'),
    );
  }

  List<String> _toolArgumentNames(
    Map<String, Object?> parameters, {
    required bool requiredOnly,
  }) {
    final properties = stringKeyedMapFromValue(parameters['properties']);
    if (properties.isEmpty) return const <String>[];
    final requiredNames = stringListFromValue(parameters['required']).toSet();
    final names = properties.keys
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .where(
          (item) => requiredOnly
              ? requiredNames.contains(item)
              : !requiredNames.contains(item),
        )
        .toList(growable: false);
    names.sort(_comparePromptCatalogNames);
    return names;
  }

  List<AiChatTurn> _mapMessageContent({
    required AiChatRole role,
    required String content,
    String? toolCallId,
    List<AiToolCall> toolCalls = const <AiToolCall>[],
    List<AiChatContentPart> parts = const <AiChatContentPart>[],
    String? reasoningContent,
    bool stripSystemReminders = false,
    bool inlineSystemReminders = false,
  }) {
    if (stripSystemReminders) {
      final cleaned = content
          .replaceAll(_systemReminderPattern, '')
          .replaceAll(kExcessiveNewlinesPattern, '\n\n')
          .trim();
      if (cleaned.isEmpty && toolCalls.isEmpty && parts.isEmpty) {
        return const <AiChatTurn>[];
      }
      return <AiChatTurn>[
        AiChatTurn(
          role: role,
          content: cleaned,
          toolCallId: toolCallId,
          toolCalls: toolCalls,
          parts: parts,
          reasoningContent: reasoningContent,
        ),
      ];
    }
    final extracted = _extractSystemReminders(content);
    if (inlineSystemReminders) {
      final buffer = StringBuffer(extracted.content.trim());
      for (final reminder in extracted.reminders) {
        final normalizedReminder = _normalizeInlineHistoryReminder(reminder);
        if (normalizedReminder.isEmpty) continue;
        if (buffer.isNotEmpty) {
          buffer
            ..writeln()
            ..writeln();
        }
        buffer.write(normalizedReminder);
      }
      final inlineContent = buffer.toString().trim();
      if (inlineContent.isEmpty && toolCalls.isEmpty && parts.isEmpty) {
        return const <AiChatTurn>[];
      }
      return <AiChatTurn>[
        AiChatTurn(
          role: role,
          content: inlineContent,
          toolCallId: toolCallId,
          toolCalls: toolCalls,
          parts: parts,
          reasoningContent: reasoningContent,
        ),
      ];
    }
    final turns = extracted.reminders
        .map(
          (reminder) => _systemSectionTurn(
            AiPromptSectionHeaders.systemReminder,
            reminder,
          ),
        )
        .toList(growable: true);
    if (extracted.content.trim().isEmpty &&
        toolCalls.isEmpty &&
        parts.isEmpty) {
      return turns;
    }
    turns.add(
      AiChatTurn(
        role: role,
        content: extracted.content,
        toolCallId: toolCallId,
        toolCalls: toolCalls,
        parts: parts,
        reasoningContent: reasoningContent,
      ),
    );
    return turns;
  }

  static final RegExp _systemReminderPattern = RegExp(
    r'<system-reminder>([\s\S]*?)</system-reminder>',
    caseSensitive: false,
  );

  _ExtractedReminderContent _extractSystemReminders(String content) {
    final reminders = _systemReminderPattern
        .allMatches(content)
        .map((match) => (match.group(1) ?? '').trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final stripped = content
        .replaceAll(_systemReminderPattern, '')
        .replaceAll(kExcessiveNewlinesPattern, '\n\n')
        .trim();
    return _ExtractedReminderContent(content: stripped, reminders: reminders);
  }

  List<AiChatTurn> buildCompressionPrompt({
    required AiPromptTemplateBundle templateBundle,
    required AiThreadTemplate template,
    required AiSession session,
    required AiSessionRuntimeContext runtimeContext,
    required List<AiSessionMessage> messagesToCompress,
    required AiSessionMessage? previousCompressionPoint,
  }) {
    final templatePolicy = AiPromptTemplatePolicies.resolve(template.id);
    final usesMinimalCompressionPayload =
        templatePolicy.usesMinimalCompressionPayload;
    final sessionStateSnapshot = _buildCompressionSessionStateSnapshot(
      session: session,
      runtimeContext: runtimeContext,
    );
    final payload = <String, Object?>{
      'session_title': session.title,
      'template_name': template.name,
      if (!usesMinimalCompressionPayload) 'session_id': session.id,
      if (!usesMinimalCompressionPayload) 'template_id': template.id,
      'locale_tag': runtimeContext.localeTag,
      if (!usesMinimalCompressionPayload)
        'compression_threshold_chars': runtimeContext.compressionThresholdChars,
      'previous_checkpoint_present': previousCompressionPoint != null,
      'messages_to_compress_count': messagesToCompress.length,
      'user_message_count': messagesToCompress
          .where((message) => message.kind == AiSessionMessageKind.user)
          .length,
      if (sessionStateSnapshot.isNotEmpty)
        'session_state': sessionStateSnapshot,
    };
    final userMessageManifest = _renderCompressionUserMessageManifest(
      messagesToCompress,
    );
    final resourceManifest = _renderCompressionResourceManifest(
      messagesToCompress,
    );
    // 先压缩工具结果，再总结对话；持久化历史保持无损。
    final compressionConfig = _ToolCompressionConfig.forCompressionPrompt(
      runtimeContext,
    );
    final microCompactContentMap = _computeMicroCompactContentMap(
      messagesToCompress,
      compressionConfig,
    );
    String renderForCompression(AiSessionMessage m) {
      final compacted = microCompactContentMap[m.id];
      if (compacted != null) return compacted;
      if (m.kind.isToolResultKind) {
        return _promptHistoryToolResultContent(m, compressionConfig);
      }
      return _renderMessageForCompression(m);
    }

    final transcript = messagesToCompress
        .map(
          (message) =>
              '- [${message.createdAt.toIso8601String()}][${message.role.storageValue}][${message.kind.storageValue}] ${renderForCompression(message)}',
        )
        .join('\n');
    final previousCheckpointText = previousCompressionPoint == null
        ? 'No earlier checkpoint.'
        : _boundedCheckpointPromptView(previousCompressionPoint.content);
    final compressionSystemContent = _compressionSystemInstructionsForPolicy(
      templatePolicy,
    );
    return <AiChatTurn>[
      _systemSectionTurn(
        AiPromptSectionHeaders.compressionSystemInstructions,
        compressionSystemContent,
      ),
      _systemSectionTurn(
        AiPromptSectionHeaders.compressionDeveloperInstructions,
        templateBundle.compressionSummaryInstructions,
      ),
      AiChatTurn(
        role: AiChatRole.user,
        content:
            '${AiPromptSectionHeaders.compressionTaskPayload}\n\n${_jsonCodeBlock(payload)}\n\n## Previous Checkpoint\n\n$previousCheckpointText${userMessageManifest.isEmpty ? '' : '\n\n## User Messages Manifest\n\n$userMessageManifest'}${resourceManifest.isEmpty ? '' : '\n\n## Resource Recovery Manifest\n\n$resourceManifest'}\n\n## Messages To Compress\n\n$transcript',
      ),
    ];
  }

  Map<String, Object?> _buildCompressionSessionStateSnapshot({
    required AiSession session,
    required AiSessionRuntimeContext runtimeContext,
  }) {
    final pendingPlan = session.pendingPlan?.trim();
    final writeCommandConfirmationRequired = _writeCommandConfirmationRequired(
      session: session,
      runtimeContext: runtimeContext,
    );
    final hasIncompleteTodo = _hasIncompleteTodoItems(session.todoItems);
    final compressionExitPlanModeAvailable =
        session.mode == AiSessionMode.plan &&
        !session.awaitingPlanApproval &&
        hasIncompleteTodo;
    final planToolNames = session.mode == AiSessionMode.plan
        ? <String>[
            ...AiPlanModeToolGate.planningToolNames,
            if (compressionExitPlanModeAvailable)
              AiPlanModeToolGate.exitPlanModeToolName,
          ]
        : AiPlanModeToolGate.planningToolNames;
    final recentPlanRecords = session.planHistory.reversed
        .take(_compressionPromptMaxPlanRecords)
        .toList(growable: false)
        .reversed
        .map(_compressionPlanRecordSnapshot)
        .toList(growable: false);
    return <String, Object?>{
      'mode': session.mode.storageValue,
      'awaiting_plan_approval': session.awaitingPlanApproval,
      'full_access_permission': session.fullAccessPermission,
      'write_command_confirmation_enabled':
          runtimeContext.writeCommandConfirmationEnabled,
      'write_command_confirmation_required': writeCommandConfirmationRequired,
      if (pendingPlan != null && pendingPlan.isNotEmpty)
        'pending_plan': clipTextWithEllipsis(
          pendingPlan,
          _compressionPromptMaxPlanChars,
        ),
      if (session.pendingPlanAllowedPrompts.isNotEmpty)
        'pending_plan_allowed_prompts': _planAllowedPromptsSnapshot(
          session.pendingPlanAllowedPrompts,
        ),
      'current_todo_count': session.todoItems.length,
      if (session.todoItems.isNotEmpty)
        'current_todos': _compressionTodoListSnapshot(session.todoItems),
      if (_goalStatePromptSnapshot(session.goalState).isNotEmpty)
        'goal': _goalStatePromptSnapshot(session.goalState),
      if (session.mode == AiSessionMode.plan || session.awaitingPlanApproval)
        'plan_mode': <String, Object?>{
          'planning_tool_names': AiPlanModeToolGate.planningToolNames,
          'has_incomplete_todo': hasIncompleteTodo,
          'exit_plan_mode_available': compressionExitPlanModeAvailable,
          'tool_gate_reason': AiPlanModeToolGate.gateReason(
            isPlanMode: session.mode == AiSessionMode.plan,
            awaitingPlanApproval: session.awaitingPlanApproval,
            availableToolNames: planToolNames,
            executionApprovedForSend: false,
            recoveryInspectionRequired: false,
          ),
        },
      'plan_record_count': session.planHistory.length,
      if (recentPlanRecords.isNotEmpty)
        'recent_plan_records': recentPlanRecords,
    };
  }

  bool _hasIncompleteTodoItems(List<AiSessionTodoItem> todoItems) {
    return AiSessionTodoState.hasIncomplete(todoItems);
  }

  Map<String, Object?> _compressionPlanRecordSnapshot(
    AiSessionPlanRecord record,
  ) {
    final plan = record.plan.trim();
    return <String, Object?>{
      'id': record.id,
      'created_at': record.createdAt.toUtc().toIso8601String(),
      'updated_at': record.updatedAt.toUtc().toIso8601String(),
      'status': record.status.storageValue,
      if (plan.isNotEmpty)
        'plan': clipTextWithEllipsis(plan, _compressionPromptMaxPlanChars),
      if (record.allowedPrompts.isNotEmpty)
        'allowed_prompts': _planAllowedPromptsSnapshot(record.allowedPrompts),
      'step_count': record.steps.length,
      if (record.steps.isNotEmpty)
        'steps': _compressionTodoListSnapshot(record.steps),
    };
  }

  Map<String, Object?> _compressionTodoListSnapshot(
    List<AiSessionTodoItem> items,
  ) {
    final visible = items
        .take(_compressionPromptMaxTodoItems)
        .map(_compressionTodoSnapshot)
        .toList(growable: false);
    return <String, Object?>{
      'items': visible,
      if (items.length > visible.length)
        'omitted': items.length - visible.length,
    };
  }

  List<Map<String, String>> _planAllowedPromptsSnapshot(
    List<AiSessionPlanAllowedPrompt> allowedPrompts,
  ) {
    return allowedPrompts
        .map(
          (item) => <String, String>{
            'tool': item.tool,
            'prompt': clipTextWithEllipsis(item.prompt.trim(), 180),
          },
        )
        .where(
          (item) =>
              (item['tool'] ?? '').isNotEmpty &&
              (item['prompt'] ?? '').isNotEmpty,
        )
        .toList(growable: false);
  }

  Map<String, Object?> _compressionTodoSnapshot(AiSessionTodoItem item) {
    return <String, Object?>{
      'id': item.id,
      'content': clipTextWithEllipsis(
        item.content.trim(),
        _compressionPromptMaxTodoChars,
      ),
      'status': item.status,
    };
  }

  Map<String, Object?>? _buildWebReverseRuntimeSnapshot(
    AiSession session, {
    required AiPromptTemplatePolicy templatePolicy,
    required List<String> availableToolNames,
    required Map<String, AiResolvedTool> resolvedToolsByName,
  }) {
    if (!templatePolicy.includesWebReverseRuntime) {
      return null;
    }
    final config = _boundedPromptMetadataMap(
      session.metadata['web_reverse_config'],
    );

    Object? meta(String key) =>
        _boundedWebReverseMetadataValue(session.metadata[key]);
    final sessionCdpMcpEnabled = webReverseRuntimeBoolTrue(
      config['cdp_mcp_enabled'],
    );
    final cdpRuntime = _sanitizeWebReverseCdpRuntime(
      _webReverseCdpRuntimeMetadata(session),
    );
    final dashboardCurrentTarget = meta('web_reverse_browser_current_target');
    final cdpRuntimeDead = _isWebReverseCdpRuntimeDead(cdpRuntime);
    final cdpRuntimeLive = _isWebReverseCdpRuntimeLive(cdpRuntime);
    _disambiguateWebReverseConfigPort(config, cdpRuntime);
    final cdpMcpToolNames = _webReverseCdpMcpToolNames(resolvedToolsByName);
    final deferredCdpMcpToolNames = _webReverseDeferredCdpMcpToolNames(
      resolvedToolsByName,
    );
    final hasToolSearch = availableToolNames.any(
      (name) => name.trim().toLowerCase() == 'toolsearch',
    );

    final rootDir = p.join(
      OpenHandPaths.defaultRootDirectoryPath(),
      'web_reverse',
      'sessions',
      session.id,
    );
    final presentKeys =
        session.metadata.keys
            .where((key) => key.startsWith('web_reverse_'))
            .toList(growable: false)
          ..sort();
    return <String, Object?>{
      'source_of_truth':
          'Dashboard panels and AI-visible state are backed by the same OpenHand-managed Chrome CDP session plus local jsonl/HAR artifacts.',
      'cdp_first_required': true,
      'fallback_policy': cdpRuntimeDead
          ? 'Live CDP MCP actions require browser_alive=true plus a current CDP endpoint/port. With browser_alive=false, do not treat historical last_* values as live CDP state; use local jsonl/HAR artifacts, or ask the user to restart/restore CDP before live browser operations. Do not use target-origin WebFetch/Bash/WebSearch or non-CDP browser automation as the offline fallback.'
          : !cdpRuntimeLive
          ? 'Live CDP MCP actions require cdp_runtime.browser_alive=true plus a current CDP endpoint/port. Without confirmed live CDP runtime, use local jsonl/HAR artifacts, or ask the user to restart/restore the Web Reverse browser before live browser operations.'
          : 'Use CDP MCP tools plus OpenHand-managed CDP runtime state and local jsonl/HAR artifacts first. If CDP cannot expose the required state or fails repeatedly, state the reason and use local artifacts; ask the user to restart/restore CDP before target-origin live browser operations.',
      'target_origin_fetch_guard': cdpRuntimeLive
          ? 'When the live CDP runtime is available, WebFetch, WebSearch, and explicit Bash HTTP(S) requests to the target origin are blocked. External docs/static references remain allowed.'
          : 'Active for the configured target origin even while live CDP is unavailable. Do not use target-origin WebFetch/Bash/WebSearch; use local jsonl/HAR artifacts, or ask the user to restart/restore CDP before live browser operations. External docs/static references remain allowed.',
      'cdp_mcp_tool_availability': <String, Object?>{
        'session_ai_cdp_mcp_enabled': sessionCdpMcpEnabled,
        'browser_runtime_live': cdpRuntimeLive,
        'current_turn_callable': cdpMcpToolNames.isNotEmpty,
        'live_cdp_actions_current_turn_callable':
            cdpRuntimeLive && cdpMcpToolNames.isNotEmpty,
        'current_turn_callable_count': cdpMcpToolNames.length,
        'current_turn_callable_names': cdpMcpToolNames,
        'tool_search_available': hasToolSearch,
        'tool_search_deferred_cdp_mcp_count': deferredCdpMcpToolNames.length,
        'tool_search_deferred_cdp_mcp_names': deferredCdpMcpToolNames,
        if (!cdpRuntimeLive)
          'runtime_liveness_blocker':
              'Live CDP actions are blocked until cdp_runtime.browser_alive=true and a current CDP endpoint/port is present. Tool availability alone is not enough.',
        if (cdpMcpToolNames.isEmpty && deferredCdpMcpToolNames.isNotEmpty) ...{
          'tool_search_recommended_query':
              'select:${deferredCdpMcpToolNames.take(8).join(',')}',
          'guidance': cdpRuntimeLive
              ? 'CDP / Chrome DevTools / js-reverse MCP tools are deferred behind ToolSearch. Before any live CDP action, query with tool_search_recommended_query, then invoke the exact returned tool_name through ToolSearch.'
              : 'CDP / Chrome DevTools / js-reverse MCP tools are deferred behind ToolSearch, but live CDP actions remain blocked until cdp_runtime.browser_alive=true plus a current CDP endpoint/port. Query schemas only after the runtime is restored.',
        } else if (cdpMcpToolNames.isEmpty)
          'warning': sessionCdpMcpEnabled
              ? 'No CDP / Chrome DevTools / js-reverse MCP tool is callable in # [2] Tool Catalog for this turn. Do not invent cdp_* or bare MCP names. The session has AI-side CDP MCP enabled, but the catalog is not ready; use local jsonl/HAR artifacts, or ask the user to refresh/disable-enable the Web Reverse MCP before live CDP actions.'
              : 'No CDP / Chrome DevTools / js-reverse MCP tool is callable in # [2] Tool Catalog for this turn. Do not invent cdp_* or bare MCP names. This session has AI-side CDP MCP disabled by default; use local jsonl/HAR artifacts or ask the user to enable it in the Web Reverse debugger before live CDP MCP actions.'
        else if (!cdpRuntimeLive)
          'guidance':
              'Exact CDP / Chrome DevTools / js-reverse MCP tool names are visible, but do not use them for live browser actions until cdp_runtime.browser_alive=true plus a current CDP endpoint/port.'
        else
          'guidance':
              'Use only exact current_turn_callable_names from # [2] Tool Catalog for live CDP actions.',
      },
      if (config.isNotEmpty) 'config': config,
      'cdp_runtime': cdpRuntime,
      if (cdpRuntimeDead)
        'cdp_runtime_warning':
            'browser_alive=false: cdp_runtime contains historical last_* values only, not a live CDP endpoint. Use local jsonl/HAR artifacts, or ask the user to restart the browser before live CDP MCP actions.'
      else if (!cdpRuntimeLive)
        'cdp_runtime_warning':
            'cdp_runtime does not confirm browser_alive=true plus a current CDP endpoint/port. Treat live CDP state as unavailable until OpenHand records both.',
      'dashboard_state': <String, Object?>{
        'last_tab': meta('web_reverse_dashboard_last_tab'),
        'browser_tab_order': meta('web_reverse_browser_tab_order'),
        'browser_tab_urls': meta('web_reverse_browser_tab_urls'),
        if (cdpRuntimeDead)
          'browser_last_current_target': dashboardCurrentTarget
        else
          'browser_current_target': dashboardCurrentTarget,
      },
      'dashboard_tabs': const <String>[
        'browser',
        'overview',
        'network',
        'console',
        'sources',
        'breakpoints',
        'realtime',
        'snippets',
        'elements',
        'hooks',
        'crons',
        'crypto',
        'performance',
        'memory',
        'application',
        'security',
        'recorder',
      ],
      'local_artifacts': <String, Object?>{
        'root_dir': rootDir,
        'network_jsonl': p.join(rootDir, 'network.jsonl'),
        'console_jsonl': p.join(rootDir, 'console.jsonl'),
        'har_dir': p.join(rootDir, 'har'),
        'scripts_dir': p.join(rootDir, 'scripts'),
        'screenshots_dir': p.join(rootDir, 'screenshots'),
      },
      'local_read_hints': <String>[
        'Read ${p.join(rootDir, 'network.jsonl')} with offset/limit when recent network events are needed',
        'Read ${p.join(rootDir, 'console.jsonl')} with offset/limit when recent console events are needed',
        'Grep pattern __OH_ in ${p.join(rootDir, 'console.jsonl')}',
      ],
      'dashboard_visible_metadata_keys': presentKeys,
    };
  }

  Map<String, Object?>? _buildAndroidReverseRuntimeSnapshot(
    AiSession session, {
    required AiPromptTemplatePolicy templatePolicy,
    required List<String> availableToolNames,
    required Map<String, AiResolvedTool> resolvedToolsByName,
  }) {
    if (!templatePolicy.usesAndroidReverseToolCatalog) return null;
    final config = _boundedPromptMetadataMap(
      session.metadata['android_reverse_config'],
    );
    final rawRuntime = _boundedAndroidReverseMetadataValue(
      session.metadata['android_reverse_runtime'],
    );
    final runtime = rawRuntime is Map<String, Object?> ? rawRuntime : null;
    final rootDir =
        '${runtime?['artifacts_root_dir'] ?? p.join(OpenHandPaths.defaultRootDirectoryPath(), 'android_reverse', 'sessions', session.id)}';
    final callableMcpToolNames = _androidReverseMcpToolNames(
      resolvedToolsByName,
    );
    final deferredMcpToolNames = _androidReverseDeferredMcpToolNames(
      resolvedToolsByName,
    );
    final hasToolSearch = availableToolNames.any(
      (name) => name.trim().toLowerCase() == 'toolsearch',
    );
    final presentKeys =
        session.metadata.keys
            .where((key) => key.startsWith('android_reverse_'))
            .toList(growable: false)
          ..sort();
    return <String, Object?>{
      'source_of_truth':
          'Dashboard panels and AI-visible state are backed by the OpenHand-managed ADB session plus local reverse artifacts.',
      if (config.isNotEmpty) 'config': config,
      if (runtime != null) 'runtime': runtime,
      'mcp_tool_availability': <String, Object?>{
        'current_turn_callable': callableMcpToolNames.isNotEmpty,
        'current_turn_callable_count': callableMcpToolNames.length,
        'current_turn_callable_names': callableMcpToolNames,
        'tool_search_available': hasToolSearch,
        'tool_search_deferred_count': deferredMcpToolNames.length,
        'tool_search_deferred_names': deferredMcpToolNames,
        if (callableMcpToolNames.isEmpty && deferredMcpToolNames.isNotEmpty)
          'tool_search_recommended_query':
              'select:${deferredMcpToolNames.take(8).join(',')}'
        else if (callableMcpToolNames.isEmpty)
          'warning':
              'No ADB / Frida / IDA Pro MCP tool is callable in # [2] Tool Catalog for this turn. Do not invent adb_* or frida_* names; use adb/frida Bash only after confirming device/tool availability.',
      },
      'dashboard_tabs': const <String>[
        'devices',
        'overview',
        'toolchain',
        'mcp',
        'plugins',
        'packages',
        'processes',
        'logcat',
        'frida',
        'network',
        'static_analysis',
        'certs',
        'crypto',
      ],
      'local_artifacts': <String, Object?>{
        'root_dir': rootDir,
        'logcat_jsonl': p.join(rootDir, 'logcat.jsonl'),
        'logcat_dir': p.join(rootDir, 'logcat'),
        'network_jsonl': p.join(rootDir, 'network.jsonl'),
        'devices_dir': p.join(rootDir, 'devices'),
        'packages_dir': p.join(rootDir, 'packages'),
        'apks_dir': p.join(rootDir, 'apks'),
        'screenshots_dir': p.join(rootDir, 'screenshots'),
        'recordings_dir': p.join(rootDir, 'recordings'),
        'network_dir': p.join(rootDir, 'network'),
        'network_readme': p.join(rootDir, 'network', 'README.md'),
        'network_proxy_probe_script': p.join(
          rootDir,
          'network',
          'proxy_probe.sh',
        ),
        'mitmproxy_addon': p.join(rootDir, 'network', 'openhand_mitm_jsonl.py'),
        'frida_dir': p.join(rootDir, 'frida'),
        'frida_scripts_dir': p.join(rootDir, 'frida', 'scripts'),
        'frida_output_dir': p.join(rootDir, 'frida', 'output'),
        'frida_readme': p.join(rootDir, 'frida', 'README.md'),
        'frida_doctor_script': p.join(rootDir, 'frida', 'frida_doctor.sh'),
        'frida_capture_script': p.join(
          rootDir,
          'frida',
          'run_frida_capture.sh',
        ),
        'decompiled_dir': p.join(rootDir, 'decompiled'),
        'mcp_dir': p.join(rootDir, 'mcp'),
        'mcp_templates_json': p.join(
          rootDir,
          'mcp',
          'openhand_android_reverse_mcp_templates.json',
        ),
        'mcp_readme': p.join(rootDir, 'mcp', 'README.md'),
        'mcp_setup_guide': p.join(rootDir, 'mcp', 'SETUP.md'),
        'certs_dir': p.join(rootDir, 'certs'),
        'certs_readme': p.join(rootDir, 'certs', 'README.md'),
        'network_security_config': p.join(
          rootDir,
          'certs',
          'res',
          'xml',
          'network_security_config.xml',
        ),
        'manifest_network_config_snippet': p.join(
          rootDir,
          'certs',
          'AndroidManifest.application.xml',
        ),
        'root_ca_install_script': p.join(
          rootDir,
          'certs',
          'install_mitm_ca_root.sh',
        ),
        'generate_debug_keystore_script': p.join(
          rootDir,
          'certs',
          'generate_debug_keystore.sh',
        ),
        'sign_repacked_apk_script': p.join(
          rootDir,
          'certs',
          'sign_repacked_apk.sh',
        ),
        'verify_apk_signature_script': p.join(
          rootDir,
          'certs',
          'verify_apk_signature.sh',
        ),
        'toolchain_dir': p.join(rootDir, 'toolchain'),
        'toolchain_readme': p.join(rootDir, 'toolchain', 'README.md'),
        'toolchain_setup_commands': p.join(
          rootDir,
          'toolchain',
          'setup_commands.json',
        ),
        'scripts_dir': p.join(rootDir, 'scripts'),
        'scripts_readme': p.join(rootDir, 'scripts', 'README.md'),
        'reproduce_python': p.join(rootDir, 'scripts', 'reproduce_http.py'),
        'reproduce_curl': p.join(rootDir, 'scripts', 'reproduce_curl.sh'),
        'evidence_bundle_script': p.join(
          rootDir,
          'scripts',
          'make_evidence_bundle.sh',
        ),
        'evidence_bundle_glob': p.join(
          rootDir,
          'scripts',
          'evidence_bundle_*.md',
        ),
        'adb_one_shot_script': p.join(rootDir, 'scripts', 'adb_one_shot.sh'),
        'dynamic_probe_script': p.join(
          rootDir,
          'scripts',
          'android_dynamic_probe.sh',
        ),
        'logs_dir': p.join(rootDir, 'logs'),
      },
      'local_read_hints': <String>[
        'Read ${p.join(rootDir, 'logcat.jsonl')} with offset/limit when recent logcat is needed',
        'Glob ${p.join(rootDir, 'logcat')} with pattern **/*',
        'Read ${p.join(rootDir, 'network.jsonl')} with offset/limit when recent network events are needed',
        'Glob ${p.join(rootDir, 'devices')} with pattern **/*',
        'Glob ${p.join(rootDir, 'packages')} with pattern **/*',
        'Glob ${p.join(rootDir, 'network')} with pattern **/*',
        'Read ${p.join(rootDir, 'network', 'README.md')}',
        '${p.join(rootDir, 'network', 'proxy_probe.sh')} --timeout 6',
        'Glob ${p.join(rootDir, 'apks')} with pattern **/*',
        'Glob ${p.join(rootDir, 'screenshots')} with pattern **/*',
        'Glob ${p.join(rootDir, 'recordings')} with pattern **/*',
        'Glob ${p.join(rootDir, 'frida')} with pattern **/*',
        'Glob ${p.join(rootDir, 'frida', 'scripts')} with pattern *',
        'Glob ${p.join(rootDir, 'frida', 'output')} with pattern *',
        'Read ${p.join(rootDir, 'frida', 'README.md')}',
        '${p.join(rootDir, 'frida', 'frida_doctor.sh')} --timeout 6',
        '${p.join(rootDir, 'frida', 'run_frida_capture.sh')} --help',
        'Glob ${p.join(rootDir, 'decompiled')} with pattern **/*',
        'Glob ${p.join(rootDir, 'decompiled')} with pattern **/quick_scan/SUMMARY.md, then Read matches',
        'Glob ${p.join(rootDir, 'decompiled')} with pattern **/quick_scan/*',
        'Glob ${p.join(rootDir, 'mcp')} with pattern **/*',
        'Read ${p.join(rootDir, 'mcp', 'SETUP.md')}',
        'Read ${p.join(rootDir, 'mcp', 'README.md')}',
        'Read ${p.join(rootDir, 'mcp', 'openhand_android_reverse_mcp_templates.json')}',
        'Read ${p.join(rootDir, 'toolchain', 'README.md')}',
        'Read ${p.join(rootDir, 'toolchain', 'setup_commands.json')}',
        'Read ${p.join(rootDir, 'scripts', 'README.md')}',
        'Read ${p.join(rootDir, 'scripts', 'reproduce_http.py')} with limit 220',
        'Read ${p.join(rootDir, 'scripts', 'reproduce_curl.sh')} with limit 220',
        p.join(rootDir, 'scripts', 'make_evidence_bundle.sh'),
        'Glob ${p.join(rootDir, 'scripts')} with pattern evidence_bundle_*.md',
        '${p.join(rootDir, 'scripts', 'adb_one_shot.sh')} --timeout 6 devices',
        '${p.join(rootDir, 'scripts', 'android_dynamic_probe.sh')} --timeout 6',
        'Glob ${p.join(rootDir, 'certs')} with pattern **/*',
        'Read ${p.join(rootDir, 'certs', 'README.md')}',
        'bash ${p.join(rootDir, 'certs', 'verify_apk_signature.sh')} <apk>',
      ],
      'dashboard_actions': const <String>[
        'devices: wireless adb, tcpip 5555, root/remount/reboot, forward/reverse mappings, field snapshot/report artifacts, battery/display/storage/foreground/ABI, shell presets, APK install, file push/pull, screenshot, screenrecord',
        'toolchain: diagnostics plus generated toolchain/README.md and setup_commands.json with copy-only install/update/uninstall commands',
        'mcp: Android-related MCP health, discovered mcp__* names, ToolSearch query, setup checklist, and generated linkage artifacts',
        'plugins: Node/Java/Python/pip/Playwright/Frida/mitmproxy/apktool/jadx runtime prerequisites with install/update/uninstall actions',
        'mcp_artifacts: generated mcp/SETUP.md, mcp/openhand_android_reverse_mcp_templates.json, mcp/README.md, scripts/adb_one_shot.sh, scripts/android_dynamic_probe.sh, frida/README.md, and frida/frida_doctor.sh',
        'static_analysis: quick APK scan writes SUMMARY.md plus badging/Manifest/components/certs/nested APKs/Flutter/native/suspicious files/business network candidates/network sources/URL/domain/IP summaries to decompiled/<target>/quick_scan',
        'packages: analyze launcher/activity, generate markdown/json package reports, launch without guessing MainActivity, force-stop, clear data, uninstall, pull APKs to artifacts, filter logcat by package',
        'processes: copy PID/name, kill, force-stop package, filter logcat by PID',
        'logcat: tag/level/PID/package filters, clear device logcat, save current lines to logcat.jsonl, capture txt/json snapshots under logcat/',
        'network: generate mitmproxy JSONL addon, README, proxy preflight script, configure device proxy, write HTTP flow summaries to network.jsonl and flows.mitm',
        'certs: generate Network Security Config, manifest snippet, root CA install script, APK resigning scripts, APK signing check, SSL pinning hook command',
        'reproduce: scripts/README.md plus reproduce_http.py, reproduce_curl.sh, and make_evidence_bundle.sh for final runnable delivery',
        'frida: built-in hook snippets, saved script/metadata/output artifacts, frida_doctor.sh read-only diagnostics, run_frida_capture.sh stdout/stderr capture, device frida-server status, ABI, push/start, forward/reverse, spawn/attach copy commands',
      ],
      'dashboard_visible_metadata_keys': presentKeys,
    };
  }

  Map<String, Object?> _boundedPromptMetadataMap(Object? value) {
    final bounded = _boundedWebReverseMetadataValue(value);
    return bounded is Map<String, Object?>
        ? bounded
        : const <String, Object?>{};
  }

  Object? _boundedWebReverseMetadataValue(Object? value, {int depth = 0}) {
    if (value == null || value is num || value is bool) {
      return value;
    }
    if (value is String) {
      const maxChars = 2000;
      if (value.length <= maxChars) return value;
      return clipTextByCodeUnits(value, maxChars, suffix: '...[truncated]');
    }
    if (depth >= 3) {
      return '$value';
    }
    if (value is Iterable) {
      return value
          .take(32)
          .map(
            (item) => _boundedWebReverseMetadataValue(item, depth: depth + 1),
          )
          .toList(growable: false);
    }
    if (value is Map) {
      final entries = value.entries
          .map(
            (entry) =>
                MapEntry<String, Object?>('${entry.key}'.trim(), entry.value),
          )
          .where((entry) => entry.key.isNotEmpty)
          .toList(growable: false);
      entries.sort(
        (left, right) => _comparePromptCatalogNames(left.key, right.key),
      );
      final result = <String, Object?>{};
      var count = 0;
      for (final entry in entries) {
        if (count >= 32) break;
        result[entry.key] = _boundedWebReverseMetadataValue(
          entry.value,
          depth: depth + 1,
        );
        count++;
      }
      return result;
    }
    return '$value';
  }

  Object? _boundedAndroidReverseMetadataValue(Object? value, {int depth = 0}) {
    return _boundedWebReverseMetadataValue(value, depth: depth);
  }

  Object? _sanitizeWebReverseCdpRuntime(Object? value) {
    final mapped = webReverseRuntimeObjectMap(value);
    if (mapped == null) return value;
    final runtime = Map<String, Object?>.from(mapped);
    final browserAlive = runtime['browser_alive'];
    if (webReverseRuntimeBoolTrue(browserAlive)) {
      runtime['browser_alive'] = true;
      return runtime;
    }
    if (!webReverseRuntimeBoolFalse(browserAlive)) return runtime;
    runtime['browser_alive'] = false;

    final lastPort = runtime['last_cdp_port'] ?? runtime['cdp_port'];
    final lastTarget =
        runtime['last_current_target'] ?? runtime['current_target'];
    runtime
      ..remove('cdp_port')
      ..remove('cdp_host')
      ..remove('cdp_http_endpoint')
      ..remove('json_version_url')
      ..remove('json_list_url')
      ..remove('current_target');
    if (lastPort != null) {
      runtime['last_cdp_port'] = lastPort;
    }
    if (lastTarget != null) {
      runtime['last_current_target'] = lastTarget;
    }
    return runtime;
  }

  Object? _webReverseCdpRuntimeMetadata(AiSession session) {
    return _boundedWebReverseMetadataValue(
      webReverseCurrentCdpRuntimeMetadata(session.metadata),
    );
  }

  bool _isWebReverseCdpRuntimeDead(Object? value) {
    return value is Map && webReverseRuntimeBoolFalse(value['browser_alive']);
  }

  bool _isWebReverseCdpRuntimeLive(Object? value) {
    return webReverseCdpRuntimeIsLive(value);
  }

  void _disambiguateWebReverseConfigPort(
    Map<String, Object?> config,
    Object? cdpRuntime,
  ) {
    if (!config.containsKey('cdp_port')) return;
    if (!webReverseCdpRuntimeIsLive(cdpRuntime)) return;
    config['desired_cdp_port'] = config.remove('cdp_port');
  }

  List<String> _webReverseCdpMcpToolNames(
    Map<String, AiResolvedTool> resolvedToolsByName,
  ) {
    final names = WebReverseMcpToolPolicy.forceVisibleToolNames(
      AiResolvedToolCatalog(
        definitions: const <AiToolDefinition>[],
        toolsByName: resolvedToolsByName,
      ),
    ).toList();
    names.sort();
    return names;
  }

  List<String> _webReverseDeferredCdpMcpToolNames(
    Map<String, AiResolvedTool> resolvedToolsByName,
  ) {
    return _deferredMcpToolNames(
      resolvedToolsByName,
      _webReverseCdpMcpToolNames,
    );
  }

  List<String> _androidReverseMcpToolNames(
    Map<String, AiResolvedTool> resolvedToolsByName,
  ) {
    final names = AndroidReverseMcpToolPolicy.forceVisibleToolNames(
      AiResolvedToolCatalog(
        definitions: const <AiToolDefinition>[],
        toolsByName: resolvedToolsByName,
      ),
    ).toList();
    names.sort();
    return names;
  }

  List<String> _androidReverseDeferredMcpToolNames(
    Map<String, AiResolvedTool> resolvedToolsByName,
  ) {
    return _deferredMcpToolNames(
      resolvedToolsByName,
      _androidReverseMcpToolNames,
    );
  }

  List<String> _deferredMcpToolNames(
    Map<String, AiResolvedTool> resolvedToolsByName,
    List<String> Function(Map<String, AiResolvedTool>) visibleToolNames,
  ) {
    final toolSearch = resolvedToolsByName.values.where(
      (tool) => tool.builtinKind == AiBuiltinToolKind.toolSearch,
    );
    final deferredToolsByName = <String, AiResolvedTool>{};
    for (final tool in toolSearch) {
      deferredToolsByName.addAll(tool.toolSearchDeferredTools);
    }
    if (deferredToolsByName.isEmpty) {
      for (final tool in toolSearch) {
        for (final entry in tool.toolSearchDeferredToolDefinitions.entries) {
          deferredToolsByName[entry.key] = AiResolvedTool(
            name: entry.key,
            definition: entry.value,
            source: AiRuntimeToolSource.mcp,
          );
        }
      }
    }
    if (deferredToolsByName.isEmpty) return const <String>[];
    return visibleToolNames(deferredToolsByName);
  }

  String _compressionSystemInstructionsForPolicy(
    AiPromptTemplatePolicy templatePolicy,
  ) {
    final identity = templatePolicy.compressionIdentity;
    return '''CRITICAL: Respond with TEXT ONLY. Do not call tools.

- Use only the previous checkpoint and transcript in the task payload.
- Do not invent facts, tool results, files, commands, or user intent.
- Follow the compression developer instructions exactly.

$identity''';
  }

  List<AiChatTurn> _mapHistoryMessages(
    List<AiSessionMessage> messages,
    AiSession session,
    AiModelConfig model,
    _ToolCompressionConfig compressionConfig, {
    String? latestUserMessageIdForInlineAttachments,
    Map<String, bool> latestUserAttachmentAvailability = const <String, bool>{},
    bool preferInlineSystemReminders = false,
    bool preferInlineSystemArtifacts = false,
  }) {
    final shouldEchoReasoning = model.requiresReasoningEcho;
    final turns = <AiChatTurn>[];
    var index = 0;
    String? roundReasoning;
    var roundReasoningHasAssistantTurn = false;
    // 找出"已被模型消费"的边界。任何 assistant / toolCall 消息都意味着
    // 模型已经基于之前的工具结果产出了下一步动作；index 大于
    // `lastConsumerIndex` 的 tool 结果属于尚未被消费的最新工具输入。新鲜
    // 与历史工具结果必须走同一摘要形态：同一条工具结果不能先以 preview
    // 入 prompt、下一轮再被改写成 summary，否则所有模板的 provider prefix
    // cache 都会在该历史位置断裂。
    var lastConsumerIndex = -1;
    for (var i = 0; i < messages.length; i++) {
      final kind = messages[i].kind;
      if (kind == AiSessionMessageKind.assistant ||
          kind == AiSessionMessageKind.toolCall) {
        lastConsumerIndex = i;
      }
    }
    final stableConsumerBoundary = lastConsumerIndex;
    while (index < messages.length) {
      final message = messages[index];
      if (message.kind == AiSessionMessageKind.reasoning) {
        // 仅为强制回传推理内容的模型缓存新思考轮，避免破坏下一轮前缀缓存。
        final trimmed = message.content.trim();
        roundReasoning = shouldEchoReasoning && trimmed.isNotEmpty
            ? trimmed
            : null;
        roundReasoningHasAssistantTurn = false;
        index += 1;
        continue;
      }
      if (message.kind == AiSessionMessageKind.user) {
        // 用户消息结束上一思考轮。
        if (roundReasoning != null && !roundReasoningHasAssistantTurn) {
          turns.add(_reasoningOnlyAssistantTurn(roundReasoning));
        }
        roundReasoning = null;
        roundReasoningHasAssistantTurn = false;
      }
      if (message.kind == AiSessionMessageKind.toolCall) {
        final mappedGroup = _mapToolExchange(
          messages,
          index,
          session,
          model,
          compressionConfig,
          lastConsumerIndex: stableConsumerBoundary,
          preferInlineSystemReminders: preferInlineSystemReminders,
        );
        if (mappedGroup.turns.isNotEmpty) {
          final attachedTurns = _attachReasoningToAssistantTurns(
            mappedGroup.turns,
            roundReasoning,
          );
          turns.addAll(attachedTurns);
          if (roundReasoning != null && _containsAssistantTurn(attachedTurns)) {
            roundReasoningHasAssistantTurn = true;
          }
        }
        index = mappedGroup.nextIndex;
        continue;
      }
      if (message.kind.isToolResultKind) {
        index += 1;
        continue;
      }
      final isLatestUserInline =
          latestUserMessageIdForInlineAttachments != null &&
          message.id == latestUserMessageIdForInlineAttachments;
      final mapped = _mapNonToolHistoryMessage(
        message,
        session,
        model,
        compressionConfig,
        messageIndex: index,
        lastConsumerIndex: stableConsumerBoundary,
        isLatestUserInline: isLatestUserInline,
        attachmentAvailability: isLatestUserInline
            ? latestUserAttachmentAvailability
            : const <String, bool>{},
        preferInlineSystemReminders: preferInlineSystemReminders,
        preferInlineSystemArtifacts: preferInlineSystemArtifacts,
      );
      final mappedWithRuntimeTail = <AiChatTurn>[
        ...mapped,
        ...?_readPersistedRuntimeTailTurns(
          message.metadata[aiPromptRuntimeTailSnapshotMetadataKey],
        ),
      ];
      if (mappedWithRuntimeTail.isNotEmpty) {
        final attachedTurns = _attachReasoningToAssistantTurns(
          mappedWithRuntimeTail,
          roundReasoning,
        );
        turns.addAll(attachedTurns);
        if (roundReasoning != null && _containsAssistantTurn(attachedTurns)) {
          roundReasoningHasAssistantTurn = true;
        }
      }
      index += 1;
    }
    if (roundReasoning != null && !roundReasoningHasAssistantTurn) {
      turns.add(_reasoningOnlyAssistantTurn(roundReasoning));
    }
    return turns;
  }

  static AiChatTurn _reasoningOnlyAssistantTurn(String reasoning) {
    return AiChatTurn(
      role: AiChatRole.assistant,
      content: '',
      reasoningContent: reasoning,
    );
  }

  static bool _containsAssistantTurn(List<AiChatTurn> turns) {
    return turns.any((turn) => turn.role == AiChatRole.assistant);
  }

  static List<AiChatTurn> _attachReasoningToAssistantTurns(
    List<AiChatTurn> turns,
    String? reasoning,
  ) {
    if (reasoning == null || reasoning.isEmpty) {
      return turns;
    }
    return turns
        .map(
          (turn) =>
              turn.role == AiChatRole.assistant &&
                  (turn.reasoningContent == null ||
                      turn.reasoningContent!.isEmpty)
              ? turn.copyWith(reasoningContent: reasoning)
              : turn,
        )
        .toList(growable: false);
  }

  List<AiChatTurn> _sanitizeToolSequence(List<AiChatTurn> turns) {
    final sanitizedTurns = <AiChatTurn>[];
    var availableToolCallIds = const <String>{};
    for (final turn in turns) {
      if (turn.role == AiChatRole.assistant && turn.toolCalls.isNotEmpty) {
        sanitizedTurns.add(turn);
        availableToolCallIds = turn.toolCalls
            .map((item) => item.id.trim())
            .where((item) => item.isNotEmpty)
            .toSet();
        continue;
      }
      if (turn.role == AiChatRole.system &&
          turn.content.startsWith('# System Reminder')) {
        sanitizedTurns.add(turn);
        continue;
      }
      if (turn.role == AiChatRole.tool) {
        final toolCallId = turn.toolCallId?.trim();
        if (toolCallId == null ||
            toolCallId.isEmpty ||
            !availableToolCallIds.contains(toolCallId)) {
          continue;
        }
        sanitizedTurns.add(turn);
        continue;
      }
      availableToolCallIds = const <String>{};
      sanitizedTurns.add(turn);
    }
    return sanitizedTurns;
  }

  _MappedToolExchange _mapToolExchange(
    List<AiSessionMessage> messages,
    int startIndex,
    AiSession session,
    AiModelConfig model,
    _ToolCompressionConfig compressionConfig, {
    required int lastConsumerIndex,
    bool preferInlineSystemReminders = false,
  }) {
    final firstMessage = messages[startIndex];
    final groupedToolCallMessages = <AiSessionMessage>[];
    final groupedToolCalls = <AiToolCall>[];
    final expectedToolCallIds = <String>{};
    var cursor = startIndex;
    while (cursor < messages.length &&
        messages[cursor].kind == AiSessionMessageKind.toolCall) {
      final toolCallMessage = messages[cursor];
      final toolCalls = _readToolCalls(toolCallMessage.metadata);
      if (toolCalls.isEmpty) {
        if (groupedToolCallMessages.isEmpty) {
          return _MappedToolExchange(
            turns: _mapNonToolHistoryMessage(
              toolCallMessage,
              session,
              model,
              compressionConfig,
              messageIndex: cursor,
              lastConsumerIndex: lastConsumerIndex,
              preferInlineSystemReminders: preferInlineSystemReminders,
            ),
            nextIndex: cursor + 1,
          );
        }
        break;
      }
      groupedToolCallMessages.add(toolCallMessage);
      for (final toolCall in toolCalls) {
        if (!expectedToolCallIds.add(toolCall.id)) {
          continue;
        }
        groupedToolCalls.add(
          _sanitizeToolCallForPromptHistory(
            toolCall,
            metadata: toolCallMessage.metadata,
          ),
        );
      }
      cursor += 1;
    }
    if (groupedToolCalls.isEmpty) {
      return _MappedToolExchange(
        turns: _mapNonToolHistoryMessage(
          firstMessage,
          session,
          model,
          compressionConfig,
          messageIndex: startIndex,
          lastConsumerIndex: lastConsumerIndex,
          preferInlineSystemReminders: preferInlineSystemReminders,
        ),
        nextIndex: startIndex + 1,
      );
    }
    final toolMessagesByCallId = <String, AiSessionMessage>{};
    final toolMessageIndexByCallId = <String, int>{};
    while (cursor < messages.length && messages[cursor].kind.isToolResultKind) {
      final toolMessage = messages[cursor];
      final toolCallId = _readToolCallId(toolMessage.metadata);
      if (toolCallId != null &&
          expectedToolCallIds.contains(toolCallId) &&
          !toolMessagesByCallId.containsKey(toolCallId)) {
        toolMessagesByCallId[toolCallId] = toolMessage;
        toolMessageIndexByCallId[toolCallId] = cursor;
      }
      cursor += 1;
    }
    if (toolMessagesByCallId.length != expectedToolCallIds.length) {
      return _MappedToolExchange(
        turns: const <AiChatTurn>[],
        nextIndex: cursor,
      );
    }
    final groupedToolContent = _promptHistoryToolCallAssistantContent(
      groupedToolCalls,
    );
    final turns = <AiChatTurn>[
      ..._mapMessageContent(
        role: AiChatRole.assistant,
        content: groupedToolContent,
        toolCalls: groupedToolCalls,
      ),
    ];
    AiSessionMessage? runtimeTailAnchor;
    var runtimeTailAnchorIndex = -1;
    for (final toolCall in groupedToolCalls) {
      final toolMessage = toolMessagesByCallId[toolCall.id]!;
      final toolMessageIndex = toolMessageIndexByCallId[toolCall.id]!;
      // 钩子提醒留在工具载荷内，保持助手与工具消息相邻。
      turns.addAll(
        _mapMessageContent(
          role: AiChatRole.tool,
          toolCallId: toolCall.id,
          content: _promptHistoryToolResultContent(
            toolMessage,
            compressionConfig,
            isFreshUnconsumedResult: toolMessageIndex > lastConsumerIndex,
            inlineSystemReminders: true,
          ),
          inlineSystemReminders: true,
        ),
      );
      if (toolMessage.metadata.containsKey(
            aiPromptRuntimeTailSnapshotMetadataKey,
          ) &&
          toolMessageIndex > runtimeTailAnchorIndex) {
        runtimeTailAnchor = toolMessage;
        runtimeTailAnchorIndex = toolMessageIndex;
      }
    }
    if (runtimeTailAnchor != null) {
      turns.addAll(
        _readPersistedRuntimeTailTurns(
              runtimeTailAnchor
                  .metadata[aiPromptRuntimeTailSnapshotMetadataKey],
            ) ??
            const <AiChatTurn>[],
      );
    }
    return _MappedToolExchange(turns: turns, nextIndex: cursor);
  }

  List<AiChatTurn> _mapNonToolHistoryMessage(
    AiSessionMessage message,
    AiSession session,
    AiModelConfig model,
    _ToolCompressionConfig compressionConfig, {
    required int messageIndex,
    required int lastConsumerIndex,
    bool isLatestUserInline = false,
    Map<String, bool> attachmentAvailability = const <String, bool>{},
    bool preferInlineSystemReminders = false,
    bool preferInlineSystemArtifacts = false,
  }) {
    final promptContent = _promptContentForMessage(
      message,
      inlineSystemReminders: preferInlineSystemReminders,
    );
    switch (message.kind) {
      case AiSessionMessageKind.user:
        return _mapUserMessage(
          message,
          session: session,
          model: model,
          content: promptContent,
          isLatestUserMessage: isLatestUserInline,
          attachmentAvailability: attachmentAvailability,
          stripSystemReminders: true,
        );
      case AiSessionMessageKind.assistant:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: _compactHistoricalAssistantContent(promptContent),
          inlineSystemReminders: preferInlineSystemReminders,
        );
      case AiSessionMessageKind.toolCall:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: _promptHistoryStandaloneToolCallContent(message),
          inlineSystemReminders: preferInlineSystemReminders,
        );
      case AiSessionMessageKind.tool:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: _promptHistoryToolResultContent(
            message,
            compressionConfig,
            isFreshUnconsumedResult: messageIndex > lastConsumerIndex,
            inlineSystemReminders: preferInlineSystemReminders,
          ),
          inlineSystemReminders: preferInlineSystemReminders,
        );
      case AiSessionMessageKind.mcp:
      case AiSessionMessageKind.skill:
      case AiSessionMessageKind.hook:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: '[${message.kind.storageValue}] $promptContent',
          inlineSystemReminders: preferInlineSystemReminders,
        );
      case AiSessionMessageKind.compressionPoint:
      case AiSessionMessageKind.fileMutationSummary:
      case AiSessionMessageKind.status:
        return _mapMessageContent(
          role: preferInlineSystemArtifacts
              ? AiChatRole.assistant
              : AiChatRole.system,
          content: '[${message.kind.storageValue}] $promptContent',
          stripSystemReminders: preferInlineSystemReminders,
        );
      case AiSessionMessageKind.selfLearning:
        // 自学习卡片是事后审计产物，不应进入主模型上下文。
        return const <AiChatTurn>[];
      case AiSessionMessageKind.reasoning:
        return const <AiChatTurn>[];
    }
  }

  List<AiChatTurn> _mapUserMessage(
    AiSessionMessage message, {
    required AiSession session,
    required AiModelConfig model,
    required String content,
    bool isLatestUserMessage = false,
    Map<String, bool> attachmentAvailability = const <String, bool>{},
    bool stripSystemReminders = false,
    bool inlineSystemReminders = false,
  }) {
    return _mapMessageContent(
      role: AiChatRole.user,
      content: content,
      parts: _attachmentPartsForMessage(
        message,
        session,
        model,
        isLatestUserMessage: isLatestUserMessage,
        attachmentAvailability: attachmentAvailability,
      ),
      stripSystemReminders: stripSystemReminders,
      inlineSystemReminders: inlineSystemReminders,
    );
  }

  String _promptContentForMessage(
    AiSessionMessage message, {
    bool inlineSystemReminders = false,
    List<String> additionalSystemReminders = const <String>[],
  }) {
    final buffer = StringBuffer(message.content.trim());
    final hookReminders = <String>[
      ..._readStringList(message.metadata[aiHookSystemRemindersMetadataKey]),
      ...additionalSystemReminders
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
    ];
    for (final reminder in hookReminders) {
      if (inlineSystemReminders) {
        final normalizedReminder = _normalizeInlineHistoryReminder(reminder);
        if (normalizedReminder.isEmpty) {
          continue;
        }
        buffer
          ..writeln()
          ..writeln()
          ..write(normalizedReminder);
        continue;
      }
      buffer
        ..writeln()
        ..writeln()
        ..write('<system-reminder>$reminder</system-reminder>');
    }
    if (message.kind == AiSessionMessageKind.user) {
      final userHookFeedback = _readStringList(
        message.metadata[aiUserPromptHookFeedbackMetadataKey],
      );
      for (final feedback in userHookFeedback) {
        buffer
          ..writeln()
          ..writeln()
          ..write(
            '<user-prompt-submit-hook>$feedback</user-prompt-submit-hook>',
          );
      }
    }
    if (message.kind == AiSessionMessageKind.user) {
      final knowledgeBasePromptAppend =
          KnowledgeMessageMetadata.promptAppendContent(message.metadata);
      if (knowledgeBasePromptAppend.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln()
          ..write(knowledgeBasePromptAppend);
      }
    }
    return buffer.toString().trim();
  }

  String _normalizeInlineHistoryReminder(String reminder) {
    final trimmed = reminder.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return '[system_reminder] $trimmed';
  }

  String _compactHistoricalAssistantContent(String content) {
    final trimmed = content.trimRight();
    if (trimmed.length <= _historyAssistantContentMaxChars) {
      return trimmed;
    }
    final edge = math.min(
      _historyAssistantContentEdgeChars,
      _historyAssistantContentMaxChars ~/ 2,
    );
    final headEnd = safeUtf16PrefixCodeUnits(trimmed, edge);
    final tailStart = safeUtf16SuffixStart(trimmed, trimmed.length - edge);
    final head = trimmed.substring(0, headEnd).trimRight();
    final tail = trimmed.substring(tailStart).trimLeft();
    final omitted = trimmed.length - head.length - tail.length;
    return '''$head

[assistant_message_middle_omitted: $omitted chars]

$tail''';
  }

  Future<Map<String, bool>> _probeAttachmentAvailability(
    AiSessionMessage message,
    AiSession session,
  ) async {
    final attachments = _readAttachments(message.metadata);
    if (attachments.isEmpty) return const <String, bool>{};
    final availability = <String, bool>{};
    final deadline = MonotonicDeadline(
      _attachmentProbeTotalTimeout,
      timeoutMessage: '附件可用性探测超过总时限。',
    );
    for (final attachment in attachments) {
      if (!attachment.isImage && !attachment.isVideo && !attachment.isAudio) {
        continue;
      }
      final path = attachment.storagePath.trim();
      if (path.isEmpty ||
          availability.containsKey(path) ||
          !_isTrustedAttachmentStoragePath(session, attachment)) {
        continue;
      }
      final remaining = deadline.remainingOrNull();
      if (remaining == null) break;
      final timeout = remaining < _attachmentProbeIdleTimeout
          ? remaining
          : _attachmentProbeIdleTimeout;
      try {
        availability[path] =
            await FileSystemEntity.type(
              path,
              followLinks: false,
            ).timeout(timeout) ==
            FileSystemEntityType.file;
      } catch (error, stackTrace) {
        availability[path] = false;
        silentLog('ai_prompt_builder', '探测附件文件', error, stackTrace);
      }
    }
    deadline.stop();
    return availability;
  }

  List<AiChatContentPart> _attachmentPartsForMessage(
    AiSessionMessage message,
    AiSession session,
    AiModelConfig model, {
    bool isLatestUserMessage = false,
    Map<String, bool> attachmentAvailability = const <String, bool>{},
  }) {
    final attachments = _readAttachments(message.metadata);
    if (attachments.isEmpty) {
      return const <AiChatContentPart>[];
    }
    final adapter = AiProtocolRegistry.adapterForModel(model);
    final supportsInlineImages = adapter.supportsAttachmentsForModel(model);
    final modelProfile = model.profileFor(model.modelId);
    final supportsInlineVideos =
        modelProfile.supportsAttachments != false &&
        modelProfile.isMultimodal != false &&
        modelProfile.supportedModalities.contains(AiModelModality.video);
    final supportsInlineAudio =
        modelProfile.supportsAttachments != false &&
        modelProfile.isMultimodal != false &&
        modelProfile.supportedModalities.contains(AiModelModality.audio);
    final parts = <AiChatContentPart>[];
    for (final attachment in attachments) {
      if (attachment.isImage) {
        // 历史图片改用带元数据和摘要的占位文本，限制上下文体积。
        if (!isLatestUserMessage) {
          parts.add(
            AiChatContentPart.text(_composeImagePlaceholder(attachment)),
          );
          continue;
        }
        final summaryText = attachment.summaryText.trim();
        final promptText = attachment.promptText.trim();
        final storagePath = attachment.storagePath.trim();
        final mimeType = attachment.mimeType.trim();
        final hasTrustedStoragePath = _isTrustedAttachmentStoragePath(
          session,
          attachment,
        );
        final hasLocalImageFile =
            hasTrustedStoragePath &&
            storagePath.isNotEmpty &&
            mimeType.isNotEmpty &&
            attachmentAvailability[storagePath] == true;
        final detailText = summaryText.isNotEmpty ? summaryText : promptText;
        // 始终提供附件标识，以便模型按约定生成匹配的图片摘要。
        // `[图片附件；图片元数据：{id=...,...}]` placeholders.
        final idLine = 'id=${attachment.id}';
        if (detailText.isNotEmpty) {
          parts.add(
            AiChatContentPart.text('[Attachment]\n$idLine\n$detailText'),
          );
        }
        if (!hasLocalImageFile) {
          if (detailText.isEmpty) {
            parts.add(
              AiChatContentPart.text(
                '[Attachment]\n$idLine\nImage attachment: ${attachment.name} is unavailable in local storage.',
              ),
            );
          }
          continue;
        }
        if (!supportsInlineImages) {
          // 明确提示模型不支持内联图片，避免模型臆测图片内容。
          const modelWarning =
              '[当前模型不支持直接查看图片内容，无法分析此图片。'
              '请切换到支持多模态/视觉的模型（如含有 vl、vision、omni 等关键字的模型）后重试。]';
          if (detailText.isEmpty) {
            parts.add(
              AiChatContentPart.text(
                '[Attachment]\n$idLine\nImage attachment: ${attachment.name}.\n$modelWarning',
              ),
            );
          } else {
            parts.add(const AiChatContentPart.text(modelWarning));
          }
          continue;
        }
        parts.add(
          AiChatContentPart.imageFile(
            filePath: storagePath,
            mimeType: mimeType,
          ),
        );
        continue;
      }
      if (attachment.isVideo) {
        final storagePath = attachment.storagePath.trim();
        final mimeType = attachment.mimeType.trim();
        final metadataText =
            '[Video attachment]\nid=${attachment.id}\n'
            '${attachment.name} (${attachment.mimeType}, ${formatByteSize(attachment.sizeBytes)})';
        if (!isLatestUserMessage) {
          parts.add(AiChatContentPart.text(metadataText));
          continue;
        }
        final hasLocalVideoFile =
            _isTrustedAttachmentStoragePath(session, attachment) &&
            storagePath.isNotEmpty &&
            isVideoMimeType(mimeType) &&
            attachmentAvailability[storagePath] == true;
        parts.add(AiChatContentPart.text(metadataText));
        if (!hasLocalVideoFile) {
          parts.add(
            const AiChatContentPart.text(
              '[Video attachment is unavailable in local storage.]',
            ),
          );
          continue;
        }
        if (!supportsInlineVideos) {
          parts.add(
            const AiChatContentPart.text(
              '[The current model does not support direct video input.]',
            ),
          );
          continue;
        }
        parts.add(
          AiChatContentPart.videoFile(
            filePath: storagePath,
            mimeType: mimeType,
          ),
        );
        continue;
      }
      if (attachment.isAudio) {
        final storagePath = attachment.storagePath.trim();
        final mimeType = attachment.mimeType.trim();
        final metadataText =
            '[Audio attachment]\nid=${attachment.id}\n'
            '${attachment.name} (${attachment.mimeType}, ${formatByteSize(attachment.sizeBytes)})';
        if (!isLatestUserMessage) {
          parts.add(AiChatContentPart.text(metadataText));
          continue;
        }
        final hasLocalAudioFile =
            _isTrustedAttachmentStoragePath(session, attachment) &&
            storagePath.isNotEmpty &&
            isAudioMimeType(mimeType) &&
            attachmentAvailability[storagePath] == true;
        parts.add(AiChatContentPart.text(metadataText));
        if (!hasLocalAudioFile) {
          parts.add(
            const AiChatContentPart.text(
              '[Audio attachment is unavailable in local storage.]',
            ),
          );
          continue;
        }
        if (!supportsInlineAudio) {
          parts.add(
            const AiChatContentPart.text(
              '[The current model does not support direct audio input.]',
            ),
          );
          continue;
        }
        parts.add(
          AiChatContentPart.audioFile(
            filePath: storagePath,
            mimeType: mimeType,
          ),
        );
        continue;
      }
      final promptText = attachment.promptText.trim();
      if (promptText.isEmpty) {
        continue;
      }
      parts.add(AiChatContentPart.text(promptText));
    }
    return parts;
  }

  /// 构建历史用户消息中图片附件的文本占位内容。
  /// `[图片附件；图片元数据：{…};图片路径：{abs};原始图片路径：{abs};图片介绍：{summary}]`
  String _composeImagePlaceholder(AiMessageAttachment attachment) {
    final metadata = <String, Object?>{
      'id': attachment.id,
      'name': attachment.name,
      'mime_type': attachment.mimeType,
      'size_bytes': attachment.sizeBytes,
      if (attachment.pixelCount != null) 'pixel_count': attachment.pixelCount,
      if (attachment.compressionRatio != null)
        'compression_ratio': attachment.compressionRatio,
    };
    final metadataText = metadata.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
    final storagePath = attachment.storagePath.trim().isEmpty
        ? '(unknown)'
        : attachment.storagePath.trim();
    final originalSourcePath = attachment.originalSourcePath?.trim();
    final originalText =
        (originalSourcePath == null || originalSourcePath.isEmpty)
        ? '(unknown)'
        : originalSourcePath;
    final summary = attachment.summaryText.trim();
    final summaryText = summary.isEmpty ? '(待补充)' : summary;
    return '[图片附件；图片元数据：{$metadataText};图片路径：{$storagePath};原始图片路径：{$originalText};图片介绍：{$summaryText}]';
  }

  bool _isTrustedAttachmentStoragePath(
    AiSession session,
    AiMessageAttachment attachment,
  ) {
    final storagePath = attachment.storagePath.trim();
    final sessionsDirectoryPath = session.environment.sessionsDirectoryPath
        .trim();
    final sessionId = session.id.trim();
    if (storagePath.isEmpty ||
        sessionsDirectoryPath.isEmpty ||
        sessionId.isEmpty) {
      return false;
    }
    final normalizedStoragePath = p.normalize(storagePath);
    // 旧目录结构。
    final legacyRoot = p.normalize(
      p.join(sessionsDirectoryPath, 'attachments', sessionId),
    );
    if (p.isWithin(legacyRoot, normalizedStoragePath)) {
      return true;
    }
    // 当前目录结构。
    final modernRoot = p.normalize(
      p.join(sessionsDirectoryPath, sessionId, 'attachments'),
    );
    return p.isWithin(modernRoot, normalizedStoragePath);
  }

  String _renderCompressionUserMessageManifest(
    List<AiSessionMessage> messages,
  ) {
    final userMessages = messages
        .where((message) => message.kind == AiSessionMessageKind.user)
        .toList(growable: false);
    if (userMessages.isEmpty) {
      return '';
    }
    final buffer = StringBuffer()
      ..writeln(
        'All source user messages are listed here so compression preserves the user\'s original intent and wording.',
      );
    var usedChars = buffer.length;
    var rendered = 0;
    for (final message in userMessages) {
      final rawContent = _renderMessageForCompression(message).trim();
      final content = _truncateCompressionManifestText(
        rawContent.isEmpty ? '[empty user message]' : rawContent,
        _compressionUserManifestMaxCharsPerMessage,
        'user_message_truncated',
      ).replaceAll('\n', '\n  ');
      final entry =
          '\n- [${message.createdAt.toIso8601String()}][id=${message.id}] $content';
      if (usedChars + entry.length > _compressionUserManifestMaxChars) {
        break;
      }
      buffer.write(entry);
      usedChars += entry.length;
      rendered += 1;
    }
    final omitted = userMessages.length - rendered;
    if (omitted > 0) {
      buffer.write(
        '\n- [user_messages_manifest_truncated: omitted $omitted messages]',
      );
    }
    return buffer.toString().trimRight();
  }

  String _renderCompressionResourceManifest(List<AiSessionMessage> messages) {
    final lines = <String>[];
    final seen = <String>{};
    for (final message in messages) {
      final metadata = message.metadata;
      for (final anchor in _fileContextAnchorsForMessage(message)) {
        final path = '${anchor['path'] ?? ''}'.trim();
        if (lines.length >= _compressionResourceManifestMaxItems ||
            path.isEmpty ||
            !seen.add('file:$path')) {
          continue;
        }
        final attributes = <String>[
          'file',
          if ('${anchor['source'] ?? ''}'.trim().isNotEmpty)
            'source=${anchor['source']}',
          'message_id=${message.id}',
          if ('${anchor['file_kind'] ?? ''}'.trim().isNotEmpty)
            'kind=${anchor['file_kind']}',
          if ('${anchor['render_mode'] ?? ''}'.trim().isNotEmpty)
            'render=${anchor['render_mode']}',
          if ('${anchor['mutation_kind'] ?? ''}'.trim().isNotEmpty)
            'mutation=${anchor['mutation_kind']}',
          if (anchor['truncated'] == true) 'truncated=true',
        ];
        lines.add('- ${attributes.join(' · ')} · $path');
      }

      final webUrl = _firstNonEmptyMetadataValue(metadata, const <String>[
        'webfetch_final_url',
        'webfetch_source_url',
        'webfetch_redirect_url',
      ]);
      if (lines.length < _compressionResourceManifestMaxItems &&
          webUrl.isNotEmpty &&
          seen.add('url:$webUrl')) {
        lines.add('- url · message_id=${message.id} · $webUrl');
      }
      if (lines.length >= _compressionResourceManifestMaxItems) {
        break;
      }
    }
    if (lines.isEmpty) {
      return '';
    }
    final omitted = _countCompressionResourceAnchors(messages) - lines.length;
    return <String>[
      'Minimal anchors for resources that can be reloaded after compaction.',
      ...lines,
      if (omitted > 0)
        '- [resource_manifest_truncated: omitted $omitted anchors]',
    ].join('\n');
  }

  int _countCompressionResourceAnchors(List<AiSessionMessage> messages) {
    final seen = <String>{};
    for (final message in messages) {
      final metadata = message.metadata;
      for (final anchor in _fileContextAnchorsForMessage(message)) {
        final path = '${anchor['path'] ?? ''}'.trim();
        if (path.isNotEmpty) {
          seen.add('file:$path');
        }
      }
      final webUrl = _firstNonEmptyMetadataValue(metadata, const <String>[
        'webfetch_final_url',
        'webfetch_source_url',
        'webfetch_redirect_url',
      ]);
      if (webUrl.isNotEmpty) {
        seen.add('url:$webUrl');
      }
    }
    return seen.length;
  }

  String _firstNonEmptyMetadataValue(
    Map<String, Object?> metadata,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = '${metadata[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _truncateCompressionManifestText(
    String content,
    int maxChars,
    String marker,
  ) {
    if (content.length <= maxChars) {
      return content.trimRight();
    }
    final head = content
        .substring(0, safeUtf16PrefixCodeUnits(content, maxChars))
        .trimRight();
    final omitted = content.length - head.length;
    return '$head\n[$marker: omitted $omitted chars]';
  }

  String _renderMessageForCompression(AiSessionMessage message) {
    final buffer = StringBuffer(_promptContentForMessage(message));
    final attachments = _readAttachments(message.metadata);
    if (attachments.isEmpty) {
      return buffer.toString().trim();
    }
    buffer
      ..writeln()
      ..writeln()
      ..writeln('Attachments:');
    for (final attachment in attachments) {
      buffer.writeln('- ${_renderAttachmentForCompression(attachment)}');
    }
    return buffer.toString().trim();
  }

  String _renderAttachmentForCompression(AiMessageAttachment attachment) {
    final summary = attachment.summaryText.trim();
    if (summary.isNotEmpty) {
      return _boundedCompressionAttachmentDetail(summary);
    }
    if (attachment.isImage) {
      return '[image] ${attachment.name} (${attachment.mimeType})';
    }
    if (attachment.isVideo) {
      return '[video] ${attachment.name} (${attachment.mimeType})';
    }
    final promptText = attachment.promptText.trim();
    if (promptText.isNotEmpty) {
      return _boundedCompressionAttachmentDetail(promptText);
    }
    return '[${attachment.kind.storageValue}] ${attachment.name} (${attachment.mimeType})';
  }

  String _boundedCompressionAttachmentDetail(String detail) {
    final trimmed = detail.trim();
    if (trimmed.length <= _compressionAttachmentDetailMaxChars) {
      return trimmed;
    }
    final head = trimmed
        .substring(
          0,
          safeUtf16PrefixCodeUnits(
            trimmed,
            _compressionAttachmentDetailMaxChars,
          ),
        )
        .trimRight();
    final omitted = trimmed.length - head.length;
    return '$head\n[attachment_content_truncated: omitted $omitted chars]';
  }

  List<AiMessageAttachment> _readAttachments(Map<String, Object?> metadata) {
    return AiMessageAttachment.listFromMetadata(
      metadata[aiSessionMessageAttachmentsMetadataKey],
    ).take(aiMessageAttachmentLimit).toList(growable: false);
  }

  String _renderUserMemory(
    List<UserMemoryEntry> memoryEntries,
    bool memoryEnabled,
    Set<String> resourceIds,
  ) {
    if (!memoryEnabled) {
      return 'Memory is disabled for the current runtime request.';
    }
    // 用户画像由专门的 [User Profile] 段单独渲染（见
    // [_renderUserProfileSection]），此处需要排除掉 user_profile 条目，
    // 以免在系统提示中重复出现同一段画像内容。
    final filtered = memoryEntries
        .where((e) => e.type != UserMemoryEntry.userProfileType)
        .toList(growable: false);
    if (filtered.isEmpty) {
      return 'No saved user memory entries.';
    }
    final render = renderLinesWithinBudget<UserMemoryEntry>(
      items: filtered,
      maxItems: _userMemoryPromptMaxEntries,
      maxCharacters: _userMemoryPromptMaxCharacters,
      lineBuilder: (entry) {
        final promptTags = _memoryTagsForPrompt(entry);
        final tags = promptTags.isEmpty
            ? ''
            : ' (tags: ${clipTextWithOmissionMarker(promptTags.join(', '), maxCodeUnits: _userMemoryPromptTagsMaxCharacters, marker: 'memory_tags_truncated').text})';
        final contentBudget =
            _userMemoryPromptEntryMaxCharacters - 2 - tags.length;
        final content = clipTextWithOmissionMarker(
          entry.content,
          maxCodeUnits: math.max(1, contentBudget),
          marker: 'memory_content_truncated',
        ).text;
        return '- $content$tags';
      },
      omissionMarkerBuilder: (omitted) =>
          '[memory_entries_omitted: $omitted entries]',
    );
    // 被采用的恒是 filtered 的前 includedItemCount 条，回填引用 id 即可。
    resourceIds.addAll(
      filtered
          .take(render.includedItemCount)
          .map((entry) => entry.id)
          .where((id) => id.trim().isNotEmpty),
    );
    assert(render.text.length <= _userMemoryPromptMaxCharacters);
    return render.text;
  }

  List<UserMemoryEntry> _memoryEntriesForPrompt(
    List<UserMemoryEntry> memoryEntries,
  ) {
    final entries = memoryEntries
        .where((entry) => nullIfBlank(entry.content) != null)
        .toList(growable: false);
    entries.sort(_compareMemoryEntriesForPrompt);
    return entries;
  }

  int _compareMemoryEntriesForPrompt(UserMemoryEntry a, UserMemoryEntry b) {
    final typeRankCompare = _memoryTypeRank(
      a.type,
    ).compareTo(_memoryTypeRank(b.type));
    if (typeRankCompare != 0) return typeRankCompare;
    final createdAtCompare = b.createdAt
        .toUtc()
        .microsecondsSinceEpoch
        .compareTo(a.createdAt.toUtc().microsecondsSinceEpoch);
    if (createdAtCompare != 0) return createdAtCompare;
    final idCompare = _comparePromptText(a.id, b.id);
    if (idCompare != 0) return idCompare;
    final contentCompare = _comparePromptText(a.content, b.content);
    if (contentCompare != 0) return contentCompare;
    return _comparePromptText(
      jsonEncode(_memoryTagsForPrompt(a)),
      jsonEncode(_memoryTagsForPrompt(b)),
    );
  }

  int _memoryTypeRank(String type) {
    return type == UserMemoryEntry.userProfileType ? 0 : 1;
  }

  List<String> _memoryTagsForPrompt(UserMemoryEntry entry) {
    final tags = UserMemoryEntry.normalizeTags(entry.tags);
    tags.sort(_comparePromptText);
    return tags;
  }

  int _comparePromptText(String a, String b) {
    final lowerCompare = a.toLowerCase().compareTo(b.toLowerCase());
    if (lowerCompare != 0) return lowerCompare;
    return a.compareTo(b);
  }

  List<AiAllowCommandRule> _allowCommandRulesForPrompt(
    List<AiAllowCommandRule> rules,
  ) {
    final visible = rules
        .map(
          (rule) => rule.copyWith(
            id: rule.id.trim(),
            pattern: rule.pattern.trim(),
            note: rule.note.trim(),
          ),
        )
        .where((rule) => rule.pattern.isNotEmpty)
        .toList(growable: false);
    visible.sort(_compareAllowCommandRulesForPrompt);
    return visible;
  }

  int _compareAllowCommandRulesForPrompt(
    AiAllowCommandRule a,
    AiAllowCommandRule b,
  ) {
    final modeCompare = a.matchMode.storageValue.compareTo(
      b.matchMode.storageValue,
    );
    if (modeCompare != 0) return modeCompare;
    final patternCompare = _comparePromptText(a.pattern, b.pattern);
    if (patternCompare != 0) return patternCompare;
    final noteCompare = _comparePromptText(a.note, b.note);
    if (noteCompare != 0) return noteCompare;
    return _comparePromptText(a.id, b.id);
  }

  Map<String, String> _mcpServerInstructionsForPrompt(
    Map<String, String> instructionsByName,
  ) {
    final entries = instructionsByName.entries
        .map((entry) => MapEntry(entry.key.trim(), entry.value.trim()))
        .where((entry) => entry.key.isNotEmpty && entry.value.isNotEmpty)
        .toList(growable: false);
    entries.sort((left, right) {
      final keyCompare = _comparePromptCatalogNames(left.key, right.key);
      if (keyCompare != 0) return keyCompare;
      return _comparePromptText(left.value, right.value);
    });
    final result = <String, String>{};
    for (final entry in entries) {
      result.putIfAbsent(entry.key, () => entry.value);
    }
    return result;
  }

  /// 渲染用户画像独立子段。当 user_profile 为空 / memory 被关闭时返回空字符串
  /// （连同后续 `_renderUserMemory` 一起就只剩通用记忆段，不破坏原有结构）。
  ///
  /// 保持固定短模板，避免稳定画像段自身浪费上下文。
  String _renderUserProfileSection(
    List<UserMemoryEntry> memoryEntries,
    bool memoryEnabled,
    Set<String> resourceIds,
  ) {
    if (!memoryEnabled) return '';
    UserMemoryEntry? profile;
    for (final entry in memoryEntries) {
      if (entry.type == UserMemoryEntry.userProfileType) {
        profile = entry;
        break;
      }
    }
    const prefix = '## User Profile\n';
    const suffix = '\n\n';
    final content = clipTextWithOmissionMarker(
      profile?.content ?? '',
      maxCodeUnits:
          _userProfilePromptMaxCharacters - prefix.length - suffix.length,
      marker: 'user_profile_truncated',
    ).text;
    if (content.isEmpty) return '';
    if (profile != null && profile.id.trim().isNotEmpty) {
      resourceIds.add(profile.id.trim());
    }
    final rendered = '$prefix$content$suffix';
    assert(rendered.length <= _userProfilePromptMaxCharacters);
    return rendered;
  }

  /// 渲染【指令】模块正文。仅返回正文，不包含 section header / 提示文本，
  /// 用于在 system turn 模板里被原位 interpolated。返回空串表示当前没有
  /// 任何应当注入的指令（外层会跳过整个 turn）。
  String _renderUserInstructionsBody(
    List<UserInstructionEntry> instructions,
    Set<String> skippedIds,
  ) {
    if (instructions.isEmpty) return '';
    final visible = _userInstructionsForPrompt(instructions, skippedIds);
    if (visible.isEmpty) return '';
    final buf = StringBuffer();
    for (int i = 0; i < visible.length; i++) {
      final entry = visible[i];
      final body = entry.body.trim();
      final name = entry.name.trim().isEmpty
          ? 'Instruction'
          : entry.name.trim();
      // 携带 id，供 [3d] Dynamic State 中的
      // `skipped_user_instruction_ids` 精准定位。
      buf.writeln('## ${i + 1}. $name (v${entry.version}, id=${entry.id})');
      if (entry.description.trim().isNotEmpty) {
        buf.writeln('_${entry.description.trim()}_');
      }
      if (entry.applyTo.trim().isNotEmpty) {
        buf.writeln('- applyTo: ${entry.applyTo.trim()}');
      }
      final taskTypes = _instructionTaskTypesForPrompt(entry);
      if (taskTypes.isNotEmpty) {
        buf.writeln('- taskTypes: ${taskTypes.join(", ")}');
      }
      final keywords = _instructionKeywordsForPrompt(entry);
      if (keywords.isNotEmpty) {
        buf.writeln('- keywords: ${keywords.join(", ")}');
      }
      buf
        ..writeln()
        ..writeln(body)
        ..writeln();
    }
    return buf.toString();
  }

  List<UserInstructionEntry> _userInstructionsForPrompt(
    List<UserInstructionEntry> instructions,
    Set<String> skippedIds,
  ) {
    final visible = instructions
        .where(
          (entry) =>
              entry.enabled &&
              !skippedIds.contains(entry.id) &&
              entry.body.trim().isNotEmpty,
        )
        .toList(growable: false);
    visible.sort(_compareUserInstructionsForPrompt);
    return visible;
  }

  int _compareUserInstructionsForPrompt(
    UserInstructionEntry a,
    UserInstructionEntry b,
  ) {
    final sortOrderCompare = a.sortOrder.compareTo(b.sortOrder);
    if (sortOrderCompare != 0) return sortOrderCompare;
    final createdAtCompare = a.createdAt
        .toUtc()
        .microsecondsSinceEpoch
        .compareTo(b.createdAt.toUtc().microsecondsSinceEpoch);
    if (createdAtCompare != 0) return createdAtCompare;
    final idCompare = _comparePromptText(a.id, b.id);
    if (idCompare != 0) return idCompare;
    return _comparePromptText(a.name, b.name);
  }

  List<String> _instructionTaskTypesForPrompt(UserInstructionEntry entry) {
    final values = UserInstructionEntry.normalizeStringList(
      entry.taskTypes,
      maxItems: UserInstructionEntry.maxTaskTypes,
      maxItemLength: 64,
      dedupeCaseInsensitive: true,
    );
    values.sort(_comparePromptText);
    return values;
  }

  List<String> _instructionKeywordsForPrompt(UserInstructionEntry entry) {
    final values = UserInstructionEntry.normalizeStringList(
      entry.keywords,
      maxItems: UserInstructionEntry.maxKeywords,
      maxItemLength: 64,
      dedupeCaseInsensitive: true,
    );
    values.sort(_comparePromptText);
    return values;
  }

  String _renderCompressionSummary(
    AiSession session,
    AiSessionMessage? latestCompressionPoint,
  ) {
    if (latestCompressionPoint == null) {
      return 'No compressed conversation summary yet.';
    }
    return '### Thread\n- ${session.title}\n\n${_boundedCheckpointPromptView(latestCompressionPoint.content)}';
  }

  String _boundedCheckpointPromptView(String content) {
    final trimmed = content.trim();
    if (trimmed.length <= _checkpointPromptMaxChars) {
      return trimmed;
    }
    final head = trimmed
        .substring(
          0,
          safeUtf16PrefixCodeUnits(trimmed, _checkpointPromptEdgeChars),
        )
        .trimRight();
    final tailStart = safeUtf16SuffixStart(
      trimmed,
      trimmed.length - _checkpointPromptEdgeChars,
    );
    final tail = trimmed.substring(tailStart).trimLeft();
    final omitted = trimmed.length - head.length - tail.length;
    return '''$head

[checkpoint_middle_omitted]
This durable checkpoint is ${trimmed.length} characters. The middle $omitted characters were omitted from this prompt view to keep post-compact context bounded. Preserve concrete facts from the visible head/tail; if exact omitted detail is needed, inspect the persisted session checkpoint.

$tail''';
  }

  /// 构建最近工具结果及最新用户附件的紧凑摘要；无内容时返回空字符串。
  String _renderFocusContext({
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage? latestUserMessage,
  }) {
    final lines = <String>[];

    // 最近工具结果按时间顺序排列。
    final recentToolMessages = <AiSessionMessage>[];
    for (
      var i = historyMessages.length - 1;
      i >= 0 && recentToolMessages.length < 3;
      i--
    ) {
      final message = historyMessages[i];
      switch (message.kind) {
        case AiSessionMessageKind.tool:
        case AiSessionMessageKind.skill:
        case AiSessionMessageKind.mcp:
          recentToolMessages.add(message);
        case AiSessionMessageKind.user:
        case AiSessionMessageKind.assistant:
        case AiSessionMessageKind.reasoning:
        case AiSessionMessageKind.toolCall:
        case AiSessionMessageKind.compressionPoint:
        case AiSessionMessageKind.hook:
        case AiSessionMessageKind.selfLearning:
        case AiSessionMessageKind.fileMutationSummary:
        case AiSessionMessageKind.status:
          break;
      }
    }
    if (recentToolMessages.isNotEmpty) {
      lines.add('## Recent tool outcomes (most recent last)');
      for (final message in recentToolMessages.reversed) {
        final toolName =
            '${message.metadata['tool_name'] ?? message.metadata['name'] ?? 'tool'}';
        final status = '${message.metadata['status'] ?? ''}'.trim();
        final command = '${message.metadata['command'] ?? ''}'.trim();
        final writeConfirmationDecision = _writeConfirmationDecision(
          message.metadata,
        );
        final gateDescriptorParts = _toolGateDescriptorParts(message.metadata);
        final outputDescriptorParts = _toolOutputDescriptorParts(
          message.metadata,
        );
        final pathHint = _fileContextAnchorPathPreview(message);
        final snippet = _firstNonEmptyLine(message.content, 160);
        final descriptor = <String>[
          toolName,
          if (status.isNotEmpty) 'status=$status',
          if (writeConfirmationDecision.isNotEmpty)
            'write_confirmation=$writeConfirmationDecision',
          ...gateDescriptorParts,
          ...outputDescriptorParts,
          if (command.isNotEmpty) 'cmd=${clipTextWithEllipsis(command, 60)}',
          if (pathHint.isNotEmpty) 'path=$pathHint',
        ].join(' · ');
        lines.add('- $descriptor');
        if (snippet.isNotEmpty) {
          lines.add('  └─ $snippet');
        }
      }
    }

    final recentFileAnchors = _recentFileContextAnchors(historyMessages);
    if (recentFileAnchors.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('## Recent file anchors (post-compact restore candidates)');
      for (final item in recentFileAnchors) {
        final path = '${item['path'] ?? ''}'.trim();
        final source = '${item['source'] ?? ''}'.trim();
        final fileKind = '${item['file_kind'] ?? ''}'.trim();
        final renderMode = '${item['render_mode'] ?? ''}'.trim();
        final mutationKind = '${item['mutation_kind'] ?? ''}'.trim();
        final truncated = item['truncated'] == true;
        final details = <String>[
          if (source.isNotEmpty) 'source=$source',
          if (fileKind.isNotEmpty) 'kind=$fileKind',
          if (renderMode.isNotEmpty) 'mode=$renderMode',
          if (mutationKind.isNotEmpty) 'mutation=$mutationKind',
          if (truncated) 'truncated=true',
        ].join(' · ');
        lines.add(details.isEmpty ? '- $path' : '- $path · $details');
      }
    }

    // 最新用户消息的附件与路径。
    if (latestUserMessage != null) {
      final attachments = latestUserMessage.metadata['attachments'];
      if (attachments is List && attachments.isNotEmpty) {
        final descriptors = <String>[];
        for (final raw in attachments) {
          if (raw is! Map) continue;
          final entry = stringKeyedMapFromValue(raw);
          final kind = '${entry['kind'] ?? entry['type'] ?? ''}'.trim();
          final path = '${entry['path'] ?? entry['file_path'] ?? ''}'.trim();
          if (path.isEmpty) continue;
          descriptors.add(kind.isEmpty ? path : '$kind:$path');
        }
        if (descriptors.isNotEmpty) {
          if (lines.isNotEmpty) lines.add('');
          lines.add('## Latest user attachments');
          for (final d in descriptors) {
            lines.add('- $d');
          }
        }
      }
    }

    return lines.isEmpty ? '' : lines.join('\n');
  }

  List<Map<String, Object?>> _recentFileContextAnchors(
    List<AiSessionMessage> messages, {
    int maxFiles = _postCompactRestoreMaxFiles,
  }) {
    final anchors = <Map<String, Object?>>[];
    final seenPaths = <String>{};
    for (
      var i = messages.length - 1;
      i >= 0 && anchors.length < maxFiles;
      i--
    ) {
      final message = messages[i];
      if (message.kind != AiSessionMessageKind.tool &&
          message.kind != AiSessionMessageKind.mcp &&
          message.kind != AiSessionMessageKind.skill) {
        continue;
      }
      for (final anchor in _fileContextAnchorsForMessage(message)) {
        final path = '${anchor['path'] ?? ''}'.trim();
        if (path.isEmpty || !seenPaths.add(path)) {
          continue;
        }
        anchors.add(<String, Object?>{
          ...anchor,
          'message_id': message.id,
          'created_at': message.createdAt.toUtc().toIso8601String(),
        });
        if (anchors.length >= maxFiles) {
          break;
        }
      }
    }
    return anchors.reversed.toList(growable: false);
  }

  List<Map<String, Object?>> _fileContextAnchorsForMessage(
    AiSessionMessage message,
  ) {
    final metadata = message.metadata;
    final anchors = <Map<String, Object?>>[];
    final readPath = '${metadata['read_file_path'] ?? ''}'.trim();
    if (readPath.isNotEmpty) {
      anchors.add(<String, Object?>{
        'path': readPath,
        'source': 'read',
        if ('${metadata['read_file_kind'] ?? ''}'.trim().isNotEmpty)
          'file_kind': '${metadata['read_file_kind']}',
        if ('${metadata['read_render_mode'] ?? ''}'.trim().isNotEmpty)
          'render_mode': '${metadata['read_render_mode']}',
        if (metadata['read_truncated'] == true) 'truncated': true,
      });
    }

    final mutationKind = '${metadata['file_mutation_kind'] ?? ''}'.trim();
    final mutationPaths = <String>[];
    final singleMutationPath = '${metadata['file_mutation_path'] ?? ''}'.trim();
    if (singleMutationPath.isNotEmpty) {
      mutationPaths.add(singleMutationPath);
    }
    final rawMutationPaths = metadata['file_mutation_paths'];
    if (rawMutationPaths is List) {
      for (final item in rawMutationPaths) {
        final path = '$item'.trim();
        if (path.isNotEmpty) {
          mutationPaths.add(path);
        }
      }
    }
    final seenMutationPaths = <String>{};
    for (final path in mutationPaths) {
      if (!seenMutationPaths.add(path)) {
        continue;
      }
      anchors.add(<String, Object?>{
        'path': path,
        'source': 'mutation',
        if (mutationKind.isNotEmpty) 'mutation_kind': mutationKind,
      });
    }
    return anchors;
  }

  String _fileContextAnchorPathPreview(AiSessionMessage message) {
    final paths = <String>[];
    final seen = <String>{};
    for (final anchor in _fileContextAnchorsForMessage(message)) {
      final path = '${anchor['path'] ?? ''}'.trim();
      if (path.isNotEmpty && seen.add(path)) {
        paths.add(path);
      }
    }
    if (paths.isEmpty) {
      return '';
    }
    if (paths.length == 1) {
      return paths.first;
    }
    final preview = paths.take(2).join(', ');
    final omitted = paths.length - 2;
    return omitted > 0 ? '$preview, +$omitted more' : preview;
  }

  Future<String> _renderPostCompactRestoredFileContext({
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage? latestCompressionPoint,
  }) async {
    if (latestCompressionPoint == null) {
      return '';
    }
    final checkpointIndex = historyMessages.indexWhere(
      (message) => message.id == latestCompressionPoint.id,
    );
    if (checkpointIndex <= 0) {
      return '';
    }
    final preCheckpointMessages = historyMessages
        .take(checkpointIndex)
        .toList(growable: false);
    final anchors = _recentFileContextAnchors(preCheckpointMessages);
    if (anchors.isEmpty) {
      return '';
    }

    final sections = <String>[];
    var usedChars = 0;
    final readDeadline = MonotonicDeadline(
      _postCompactRestoreReadTotalTimeout,
      timeoutMessage: '压缩后文件上下文恢复超过总时限。',
    );
    for (final anchor in anchors) {
      if (usedChars >= _postCompactRestoreTotalChars) {
        break;
      }
      final path = '${anchor['path'] ?? ''}'.trim();
      if (path.isEmpty) {
        continue;
      }
      final readBudget = readDeadline.remainingOrNull();
      if (readBudget == null) break;
      final restored = await _tryReadPostCompactRestoredFile(
        path,
        totalTimeout: readBudget,
      );
      if (restored == null || restored.isEmpty) {
        continue;
      }
      final remainingBudget = _postCompactRestoreTotalChars - usedChars;
      final content = restored.length > remainingBudget
          ? _truncateRestoredFileContent(restored, remainingBudget)
          : restored;
      if (content.trim().isEmpty) {
        continue;
      }
      usedChars += content.length;
      final fileKind = '${anchor['file_kind'] ?? ''}'.trim();
      final renderMode = '${anchor['render_mode'] ?? ''}'.trim();
      final source = '${anchor['source'] ?? ''}'.trim();
      final mutationKind = '${anchor['mutation_kind'] ?? ''}'.trim();
      final metadata = <String>[
        if (source.isNotEmpty) 'source=$source',
        if (fileKind.isNotEmpty) 'kind=$fileKind',
        if (renderMode.isNotEmpty) 'last_read_mode=$renderMode',
        if (mutationKind.isNotEmpty) 'mutation=$mutationKind',
      ].join(' · ');
      sections.add('''## $path${metadata.isEmpty ? '' : ' · $metadata'}

```text
$content
```''');
    }
    readDeadline.stop();
    if (sections.isEmpty) {
      return '';
    }
    return 'Recent file snapshots restored after compaction. These bounded snapshots come from files previously read or mutated before the latest checkpoint.\n\n${sections.join('\n\n')}';
  }

  Future<String?> _tryReadPostCompactRestoredFile(
    String path, {
    required Duration totalTimeout,
  }) async {
    try {
      final restored = await _readPostCompactRestoreFile(
        File(path),
        totalTimeout: totalTimeout,
      );
      if (restored == null || restored.isEmpty) return null;
      return _truncateRestoredFileContent(
        restored,
        _postCompactRestoreMaxCharsPerFile,
      );
    } catch (error, stackTrace) {
      silentLog('ai_prompt_builder', '读取压缩后恢复的文件', error, stackTrace);
      return null;
    }
  }

  String _truncateRestoredFileContent(String content, int maxChars) {
    return _truncateRestoredContextContent(
      content,
      maxChars,
      'restored_file_truncated',
    );
  }

  String _truncateRestoredContextContent(
    String content,
    int maxChars,
    String marker,
  ) {
    if (maxChars <= 0) {
      return '';
    }
    if (content.length <= maxChars) {
      return content.trimRight();
    }
    final head = content
        .substring(0, safeUtf16PrefixCodeUnits(content, maxChars))
        .trimRight();
    final omitted = content.length - head.length;
    return '$head\n[$marker: omitted $omitted chars]';
  }

  Future<String> _renderPostCompactRestoredSkillContext({
    required List<AiSessionMessage> historyMessages,
    required AiSessionRuntimeContext runtimeContext,
    required AiSessionMessage? latestCompressionPoint,
  }) async {
    if (latestCompressionPoint == null) {
      return '';
    }
    final checkpointIndex = historyMessages.indexWhere(
      (message) => message.id == latestCompressionPoint.id,
    );
    if (checkpointIndex <= 0 || runtimeContext.availableSkills.isEmpty) {
      return '';
    }
    final preCheckpointMessages = historyMessages
        .take(checkpointIndex)
        .toList(growable: false);
    final anchors = _recentInvokedSkillAnchors(preCheckpointMessages);
    if (anchors.isEmpty) {
      return '';
    }
    final skillsByName = <String, LocalSkill>{
      for (final skill in runtimeContext.availableSkills)
        skill.name.trim().toLowerCase(): skill,
    };
    final sections = <String>[];
    var usedChars = 0;
    final readDeadline = MonotonicDeadline(
      _postCompactRestoreReadTotalTimeout,
      timeoutMessage: '压缩后技能上下文恢复超过总时限。',
    );
    for (final anchor in anchors) {
      if (sections.length >= _postCompactRestoreMaxSkills ||
          usedChars >= _postCompactRestoreTotalSkillChars) {
        break;
      }
      final name = '${anchor['name'] ?? ''}'.trim();
      final skill = skillsByName[name.toLowerCase()];
      if (skill == null) {
        continue;
      }
      final readBudget = readDeadline.remainingOrNull();
      if (readBudget == null) break;
      final restored = await _tryReadPostCompactRestoredSkill(
        skill,
        totalTimeout: readBudget,
      );
      if (restored == null || restored.trim().isEmpty) {
        continue;
      }
      final remainingBudget = _postCompactRestoreTotalSkillChars - usedChars;
      final content = restored.length > remainingBudget
          ? _truncateRestoredFileContent(restored, remainingBudget)
          : restored;
      if (content.trim().isEmpty) {
        continue;
      }
      usedChars += content.length;
      sections.add('''## ${skill.name}
description: ${skill.description}
directory: ${skill.directoryPath}
manifest_path: ${skill.manifestPath}

```text
$content
```''');
    }
    readDeadline.stop();
    if (sections.isEmpty) {
      return '';
    }
    return 'Skills restored after compaction. These are bounded snapshots of skills invoked before the latest checkpoint.\n\n${sections.join('\n\n')}';
  }

  Future<String?> _tryReadPostCompactRestoredSkill(
    LocalSkill skill, {
    required Duration totalTimeout,
  }) async {
    try {
      final manifestFile = File(skill.manifestPath);
      final manifest = await _readPostCompactRestoreFile(
        manifestFile,
        totalTimeout: totalTimeout,
      );
      if (manifest == null || manifest.isEmpty) return null;
      final buffer = StringBuffer();
      final defaultPrompt = (skill.defaultPrompt ?? '').trim();
      if (defaultPrompt.isNotEmpty) {
        buffer
          ..writeln('default_prompt:')
          ..writeln(defaultPrompt)
          ..writeln();
      }
      buffer
        ..writeln('manifest:')
        ..writeln(manifest.trimRight());
      return _truncateRestoredFileContent(
        buffer.toString().trimRight(),
        _postCompactRestoreMaxSkillChars,
      );
    } catch (error, stackTrace) {
      silentLog('ai_prompt_builder', '读取压缩后恢复的技能', error, stackTrace);
      return null;
    }
  }

  Future<String?> _readPostCompactRestoreFile(
    File file, {
    required Duration totalTimeout,
  }) async {
    if (totalTimeout <= Duration.zero) return null;
    final deadline = MonotonicDeadline(
      totalTimeout,
      timeoutMessage: '压缩后恢复文件读取超过总时限。',
    );
    try {
      final type = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      ).timeout(deadline.limit(_postCompactRestoreReadIdleTimeout));
      if (type != FileSystemEntityType.file) return null;
      return await readBoundedFileString(
        file,
        maxBytes: _postCompactRestoreMaxFileBytes,
        idleTimeout: deadline.limit(_postCompactRestoreReadIdleTimeout),
        totalTimeout: deadline.remaining(),
      );
    } finally {
      deadline.stop();
    }
  }

  List<Map<String, Object?>> _recentInvokedSkillAnchors(
    List<AiSessionMessage> messages, {
    int maxSkills = _postCompactRestoreMaxSkills,
  }) {
    final anchors = <Map<String, Object?>>[];
    final seenNames = <String>{};
    for (
      var i = messages.length - 1;
      i >= 0 && anchors.length < maxSkills;
      i--
    ) {
      final message = messages[i];
      final source = '${message.metadata['tool_source'] ?? ''}'.trim();
      final skillName = '${message.metadata['skill_name'] ?? ''}'.trim();
      if (message.kind != AiSessionMessageKind.skill &&
          source != 'skill' &&
          skillName.isEmpty) {
        continue;
      }
      final toolName = '${message.metadata['tool_name'] ?? ''}'.trim();
      final normalizedName = skillName.isNotEmpty
          ? skillName
          : toolName.startsWith('skill__')
          ? toolName.substring('skill__'.length)
          : toolName;
      if (normalizedName.isEmpty ||
          !seenNames.add(normalizedName.toLowerCase())) {
        continue;
      }
      anchors.add(<String, Object?>{
        'name': normalizedName,
        'message_id': message.id,
        'created_at': message.createdAt.toUtc().toIso8601String(),
        if ('${message.metadata['skill_manifest_path'] ?? ''}'
            .trim()
            .isNotEmpty)
          'manifest_path': '${message.metadata['skill_manifest_path']}',
      });
    }
    return anchors.reversed.toList(growable: false);
  }

  List<AiSessionMessage> _recentSessionStartHookAnchors({
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage? latestCompressionPoint,
    int maxHooks = _postCompactRestoreMaxSessionStartHooks,
  }) {
    if (latestCompressionPoint == null || maxHooks <= 0) {
      return const <AiSessionMessage>[];
    }
    final checkpointIndex = historyMessages.indexWhere(
      (message) => message.id == latestCompressionPoint.id,
    );
    final searchEnd = checkpointIndex == -1
        ? historyMessages.length
        : checkpointIndex;
    final hooks = <AiSessionMessage>[];
    for (var i = searchEnd - 1; i >= 0 && hooks.length < maxHooks; i--) {
      final message = historyMessages[i];
      if (_isSessionStartHookMessage(message)) {
        hooks.add(message);
      }
    }
    return hooks.reversed.toList(growable: false);
  }

  bool _isSessionStartHookMessage(AiSessionMessage message) {
    if (message.kind != AiSessionMessageKind.hook) {
      return false;
    }
    final eventName =
        <Object?>[
              message.metadata['hook_event'],
              message.metadata['hook_event_name'],
              message.metadata['hookEventName'],
              message.metadata['tool_name'],
            ]
            .map((value) => '$value'.trim().toLowerCase())
            .where((value) => value.isNotEmpty && value != 'null')
            .join(' ');
    return eventName.contains('session_start') ||
        eventName.contains('sessionstart');
  }

  bool _hasRestorablePlanContext(AiSession session) {
    return session.pendingPlan?.trim().isNotEmpty == true ||
        session.planHistory.isNotEmpty ||
        session.todoItems.isNotEmpty ||
        session.awaitingPlanApproval ||
        session.mode == AiSessionMode.plan;
  }

  String _renderPostCompactRestoredPlanContext({
    required AiSession session,
    required AiSessionMessage? latestCompressionPoint,
  }) {
    if (latestCompressionPoint == null || !_hasRestorablePlanContext(session)) {
      return '';
    }
    final buffer = StringBuffer()
      ..writeln(
        'Plan context restored after compaction. Treat this as the current plan state for continuing the task.',
      )
      ..writeln()
      ..writeln('mode: ${session.mode.storageValue}')
      ..writeln('awaiting_plan_approval: ${session.awaitingPlanApproval}');

    final pendingPlan = session.pendingPlan?.trim();
    if (pendingPlan != null && pendingPlan.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Pending Plan')
        ..writeln('```text')
        ..writeln(pendingPlan)
        ..writeln('```');
      final allowedPromptLines = _renderPlanAllowedPromptLines(
        session.pendingPlanAllowedPrompts,
      );
      if (allowedPromptLines.isNotEmpty) {
        buffer
          ..writeln('allowed_prompts:')
          ..writeln(allowedPromptLines);
      }
    }

    final recentPlanRecords = session.planHistory.reversed
        .take(3)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    if (recentPlanRecords.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Recent Plan Records');
      for (final record in recentPlanRecords) {
        buffer
          ..writeln()
          ..writeln('### ${record.id}')
          ..writeln('status: ${record.status.storageValue}')
          ..writeln(
            'updated_at: ${record.updatedAt.toUtc().toIso8601String()}',
          );
        final plan = record.plan.trim();
        if (plan.isNotEmpty) {
          buffer
            ..writeln('```text')
            ..writeln(plan)
            ..writeln('```');
        }
        final steps = _renderPlanTodoItems(record.steps);
        if (steps.isNotEmpty) {
          buffer
            ..writeln('steps:')
            ..writeln(steps);
        }
        final allowedPromptLines = _renderPlanAllowedPromptLines(
          record.allowedPrompts,
        );
        if (allowedPromptLines.isNotEmpty) {
          buffer
            ..writeln('allowed_prompts:')
            ..writeln(allowedPromptLines);
        }
      }
    }

    final currentTodos = _renderPlanTodoItems(session.todoItems);
    if (currentTodos.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Current Todos')
        ..writeln(currentTodos);
    }

    return _truncateRestoredContextContent(
      buffer.toString().trimRight(),
      _postCompactRestoreMaxPlanChars,
      'restored_plan_truncated',
    );
  }

  String _renderPlanTodoItems(List<AiSessionTodoItem> items) {
    final lines = <String>[];
    for (final item in items) {
      final content = item.content.trim();
      if (content.isEmpty) {
        continue;
      }
      final status = item.status.trim().isEmpty
          ? 'unknown'
          : item.status.trim();
      lines.add('- [$status] $content');
    }
    return lines.join('\n');
  }

  String _renderPlanAllowedPromptLines(
    List<AiSessionPlanAllowedPrompt> allowedPrompts,
  ) {
    final lines = <String>[];
    for (final item in allowedPrompts) {
      final tool = item.tool.trim();
      final prompt = item.prompt.trim();
      if (tool.isEmpty || prompt.isEmpty) {
        continue;
      }
      lines.add('- $tool: $prompt');
    }
    return lines.join('\n');
  }

  String _renderPostCompactRestoredAgentResultContext({
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage? latestCompressionPoint,
  }) {
    final agentResults = _recentAgentResultAnchors(
      historyMessages: historyMessages,
      latestCompressionPoint: latestCompressionPoint,
    );
    if (agentResults.isEmpty) {
      return '';
    }
    final buffer = StringBuffer()
      ..writeln(
        'Agent results restored after compaction. Treat these as prior Task/subagent or Hermes Agent tool observations that may no longer be present in the compressed transcript.',
      );
    for (final message in agentResults) {
      final metadata = message.metadata;
      final subagentType = '${metadata['subagent_type'] ?? ''}'.trim();
      final toolName = '${metadata['tool_name'] ?? ''}'.trim();
      final action = '${metadata['action'] ?? ''}'.trim();
      final agentId = '${metadata['agent_id'] ?? ''}'.trim();
      final taskId = '${metadata['task_id'] ?? ''}'.trim();
      final status =
          '${metadata['status'] ?? metadata['tool_execution_status'] ?? ''}'
              .trim();
      final command = '${metadata['command'] ?? ''}'.trim();
      final durationMs = metadata['duration_ms'];
      final content = _truncateRestoredContextContent(
        message.content.trim(),
        _postCompactRestoreMaxCharsPerAgentResult,
        'agent_result_truncated',
      );
      buffer
        ..writeln()
        ..writeln('## ${_restoredAgentResultTitle(metadata)}')
        ..writeln('- message_id: ${message.id}')
        ..writeln(
          '- created_at: ${message.createdAt.toUtc().toIso8601String()}',
        );
      if (toolName.isNotEmpty) {
        buffer.writeln('- tool: $toolName');
      }
      if (subagentType.isNotEmpty) {
        buffer.writeln('- subagent_type: $subagentType');
      }
      if (action.isNotEmpty) {
        buffer.writeln('- action: $action');
      }
      if (agentId.isNotEmpty) {
        buffer.writeln('- agent_id: $agentId');
      }
      if (taskId.isNotEmpty) {
        buffer.writeln('- task_id: $taskId');
      }
      if (status.isNotEmpty) {
        buffer.writeln('- status: $status');
      }
      if (command.isNotEmpty) {
        buffer.writeln('- command: ${clipTextWithEllipsis(command, 160)}');
      }
      if (durationMs != null) {
        buffer.writeln('- duration_ms: $durationMs');
      }
      if (content.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(content);
      }
    }
    return _truncateRestoredContextContent(
      buffer.toString().trimRight(),
      _postCompactRestoreMaxAgentResultChars,
      'restored_agent_results_truncated',
    );
  }

  List<AiSessionMessage> _recentAgentResultAnchors({
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage? latestCompressionPoint,
    int maxResults = _postCompactRestoreMaxAgentResults,
  }) {
    if (latestCompressionPoint == null || maxResults <= 0) {
      return const <AiSessionMessage>[];
    }
    final checkpointIndex = historyMessages.indexWhere(
      (message) => message.id == latestCompressionPoint.id,
    );
    final searchEnd = checkpointIndex == -1
        ? historyMessages.length
        : checkpointIndex;
    final results = <AiSessionMessage>[];
    for (var i = searchEnd - 1; i >= 0 && results.length < maxResults; i--) {
      final message = historyMessages[i];
      if (_isRestorableAgentResultMessage(message)) {
        results.add(message);
      }
    }
    return results.reversed.toList(growable: false);
  }

  bool _isRestorableAgentResultMessage(AiSessionMessage message) {
    if (message.kind != AiSessionMessageKind.tool) {
      return false;
    }
    final toolName = '${message.metadata['tool_name'] ?? ''}'.trim();
    final subagentType = '${message.metadata['subagent_type'] ?? ''}'.trim();
    final isolated = message.metadata['subagent_session_isolated'] == true;
    return toolName == 'Task' ||
        (subagentType.isNotEmpty && isolated) ||
        _isHermesAgentToolResult(toolName);
  }

  bool _isHermesAgentToolResult(String toolName) {
    if (!toolName.startsWith('Agent')) return false;
    if (toolName == 'Agent') return false;
    return true;
  }

  String _restoredAgentResultTitle(Map<String, Object?> metadata) {
    final subagentType = '${metadata['subagent_type'] ?? ''}'.trim();
    if (subagentType.isNotEmpty) return subagentType;
    final toolName = '${metadata['tool_name'] ?? ''}'.trim();
    if (_isHermesAgentToolResult(toolName)) {
      return 'Hermes Agent Tool: $toolName';
    }
    return 'Task Subagent';
  }

  String _renderPostCompactRestoredToolAgentContext({
    required List<AiToolDefinition> availableTools,
    required Map<String, AiResolvedTool> resolvedToolsByName,
    required AiSessionMessage? latestCompressionPoint,
  }) {
    if (latestCompressionPoint == null) {
      return '';
    }
    final availableToolNames = availableTools
        .map((tool) => tool.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final deferredTools = _postCompactDeferredBuiltinTools(resolvedToolsByName);
    final taskAgentTypes = _postCompactTaskAgentTypes(
      availableToolNames: availableToolNames,
      resolvedToolsByName: resolvedToolsByName,
    );
    if (deferredTools.isEmpty && taskAgentTypes.isEmpty) {
      return '';
    }

    final buffer = StringBuffer()
      ..writeln(
        'Tool and agent listing restored after compaction. The runtime tool catalog remains authoritative; this section re-announces deferred/lazy built-in tools and Task subagent choices that may have been summarized away.',
      );

    if (deferredTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Deferred or Lazy Built-in Tools');
      final renderedTools = deferredTools
          .take(_postCompactRestoreMaxDeferredTools)
          .toList(growable: false);
      for (final tool in renderedTools) {
        final config = tool.builtinConfig;
        final kind = tool.builtinKind?.name ?? 'builtin';
        final strategy = config?.loadStrategy.name ?? 'unknown';
        final description = _firstNonEmptyLine(
          tool.definition.description,
          240,
        );
        buffer.writeln(
          '- ${tool.name} (kind=$kind, load_strategy=$strategy)${description.isEmpty ? '' : ': $description'}',
        );
      }
      final omitted = deferredTools.length - renderedTools.length;
      if (omitted > 0) {
        buffer.writeln('- [deferred_tools_truncated: omitted $omitted tools]');
      }
    }

    if (taskAgentTypes.isNotEmpty) {
      final taskToolName = _postCompactTaskToolName(
        availableToolNames: availableToolNames,
        resolvedToolsByName: resolvedToolsByName,
      );
      buffer
        ..writeln()
        ..writeln('## Task Subagents');
      if (taskToolName.isNotEmpty) {
        buffer.writeln('- Task tool: $taskToolName');
      }
      for (final type in taskAgentTypes) {
        final description = AiTaskTool.subagentDescriptions[type]?.trim() ?? '';
        buffer.writeln('- $type${description.isEmpty ? '' : ': $description'}');
      }
    }

    return _truncateRestoredContextContent(
      buffer.toString().trimRight(),
      _postCompactRestoreMaxToolAgentChars,
      'restored_tool_agent_listing_truncated',
    );
  }

  List<AiResolvedTool> _postCompactDeferredBuiltinTools(
    Map<String, AiResolvedTool> resolvedToolsByName,
  ) {
    final byName = <String, AiResolvedTool>{};
    void addIfDeferredBuiltin(AiResolvedTool tool) {
      if (tool.source != AiRuntimeToolSource.builtin ||
          tool.name.trim().isEmpty ||
          tool.builtinConfig?.loadStrategy == null ||
          tool.builtinConfig!.loadStrategy == AiBuiltinToolLoadStrategy.eager) {
        return;
      }
      byName.putIfAbsent(tool.name, () => tool);
    }

    for (final tool in resolvedToolsByName.values) {
      addIfDeferredBuiltin(tool);
      for (final deferred in tool.toolSearchDeferredTools.values) {
        addIfDeferredBuiltin(deferred);
      }
    }
    final tools = byName.values.toList(growable: false);
    tools.sort((left, right) {
      final leftConfig = left.builtinConfig;
      final rightConfig = right.builtinConfig;
      final sortOrderCompare = (leftConfig?.sortOrder ?? 0).compareTo(
        rightConfig?.sortOrder ?? 0,
      );
      if (sortOrderCompare != 0) return sortOrderCompare;
      final priorityCompare = (leftConfig?.priority ?? 100).compareTo(
        rightConfig?.priority ?? 100,
      );
      if (priorityCompare != 0) return priorityCompare;
      return left.name.compareTo(right.name);
    });
    return tools;
  }

  List<String> _postCompactTaskAgentTypes({
    required List<String> availableToolNames,
    required Map<String, AiResolvedTool> resolvedToolsByName,
  }) {
    if (_postCompactTaskToolName(
      availableToolNames: availableToolNames,
      resolvedToolsByName: resolvedToolsByName,
    ).isEmpty) {
      return const <String>[];
    }
    return AiTaskTool.subagentDescriptions.keys.toList(growable: false);
  }

  String _postCompactTaskToolName({
    required List<String> availableToolNames,
    required Map<String, AiResolvedTool> resolvedToolsByName,
  }) {
    final resolvedTaskNames = resolvedToolsByName.values
        .where(
          (tool) =>
              tool.source == AiRuntimeToolSource.builtin &&
              tool.builtinKind == AiBuiltinToolKind.task,
        )
        .map((tool) => tool.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    resolvedTaskNames.sort(_comparePromptCatalogNames);
    if (resolvedTaskNames.isNotEmpty) {
      return resolvedTaskNames.first;
    }
    final availableTaskNames = availableToolNames
        .where((name) => name == 'Task')
        .toSet()
        .toList(growable: false);
    availableTaskNames.sort(_comparePromptCatalogNames);
    if (availableTaskNames.isNotEmpty) {
      return availableTaskNames.first;
    }
    return '';
  }

  String _renderPostCompactRestoredSessionStartHookContext({
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage? latestCompressionPoint,
  }) {
    final hooks = _recentSessionStartHookAnchors(
      historyMessages: historyMessages,
      latestCompressionPoint: latestCompressionPoint,
    );
    if (hooks.isEmpty) {
      return '';
    }
    final buffer = StringBuffer()
      ..writeln(
        'SessionStart hook context restored after compaction. Treat these hook outputs as supplemental runtime context emitted by startup/resume/compact hooks.',
      );
    for (final hook in hooks) {
      final label = '${hook.metadata['hook_name'] ?? 'SessionStart'}'.trim();
      final source = '${hook.metadata['hook_session_start_source'] ?? ''}'
          .trim();
      final status = '${hook.metadata['tool_execution_status'] ?? ''}'.trim();
      final content = _truncateRestoredContextContent(
        hook.content.trim(),
        _postCompactRestoreMaxSessionStartHookChars,
        'session_start_hook_truncated',
      );
      buffer
        ..writeln()
        ..writeln('## ${label.isEmpty ? 'SessionStart' : label}')
        ..writeln('- message_id: ${hook.id}')
        ..writeln('- created_at: ${hook.createdAt.toUtc().toIso8601String()}');
      if (source.isNotEmpty) {
        buffer.writeln('- source: $source');
      }
      if (status.isNotEmpty) {
        buffer.writeln('- status: $status');
      }
      if (content.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(content);
      }
    }
    return _truncateRestoredContextContent(
      buffer.toString().trimRight(),
      _postCompactRestoreMaxSessionStartHookChars,
      'restored_session_start_hooks_truncated',
    );
  }

  String _renderPostCompactRestoredMcpContext({
    required AiSessionRuntimeContext runtimeContext,
    required String templateId,
    required List<AiToolDefinition> availableTools,
    required Map<String, String> mcpServerInstructionsByName,
    required AiSessionMessage? latestCompressionPoint,
  }) {
    if (latestCompressionPoint == null) {
      return '';
    }
    final mcpTools =
        availableTools
            .where((tool) => tool.name.trim().startsWith('mcp__'))
            .toList(growable: false)
          ..sort(_compareToolDefinitionsForPromptCatalog);
    final servers =
        runtimeContext.availableMcpServers
            .where(
              (server) =>
                  server.enabled &&
                  server.isVisibleToTemplate(templateId) &&
                  nullIfBlank(server.name) != null,
            )
            .toList(growable: false)
          ..sort(
            (left, right) => _comparePromptCatalogNames(left.name, right.name),
          );
    final serverInstructionsByName = _mcpServerInstructionsForPrompt(
      mcpServerInstructionsByName,
    );
    if (mcpTools.isEmpty &&
        servers.isEmpty &&
        serverInstructionsByName.isEmpty) {
      return '';
    }

    final serverTokens = servers
        .map((server) => normalizeToolNameToken('mcp__${server.name}'))
        .toSet();
    final toolNamesByServerToken = <String, List<AiToolDefinition>>{};
    for (final tool in mcpTools) {
      final serverToken = _mcpServerTokenFromToolName(tool.name, serverTokens);
      if (serverToken.isEmpty) {
        continue;
      }
      toolNamesByServerToken.putIfAbsent(serverToken, () => []).add(tool);
    }

    final buffer = StringBuffer()
      ..writeln(
        'MCP context restored after compaction. The tool catalog remains authoritative; this section re-announces MCP servers and their currently visible tools.',
      );

    if (servers.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## MCP Servers');
      for (final server in servers) {
        final summary = server.summary.trim();
        buffer.writeln(
          '- ${server.name} (${server.type.storageValue}, enabled=${server.enabled})${summary.isEmpty ? '' : ': $summary'}',
        );
      }
    }

    if (mcpTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## MCP Tools');
      var renderedToolCount = 0;
      final renderedServerTokens = <String>{};
      for (final server in servers) {
        if (renderedToolCount >= _postCompactRestoreMaxMcpTools) {
          break;
        }
        final serverToken = normalizeToolNameToken('mcp__${server.name}');
        final tools = toolNamesByServerToken[serverToken];
        if (tools == null || tools.isEmpty) {
          continue;
        }
        renderedServerTokens.add(serverToken);
        buffer
          ..writeln()
          ..writeln('### ${server.name}');
        renderedToolCount += _renderMcpToolLines(
          buffer,
          tools,
          _postCompactRestoreMaxMcpTools - renderedToolCount,
        );
      }

      final ungroupedTools = <AiToolDefinition>[
        for (final entry in toolNamesByServerToken.entries)
          if (!renderedServerTokens.contains(entry.key)) ...entry.value,
      ];
      if (ungroupedTools.isNotEmpty &&
          renderedToolCount < _postCompactRestoreMaxMcpTools) {
        buffer
          ..writeln()
          ..writeln('### Other MCP Tools');
        renderedToolCount += _renderMcpToolLines(
          buffer,
          ungroupedTools,
          _postCompactRestoreMaxMcpTools - renderedToolCount,
        );
      }

      final omitted = mcpTools.length - renderedToolCount;
      if (omitted > 0) {
        buffer.writeln('- [mcp_tools_truncated: omitted $omitted tools]');
      }
    }

    if (serverInstructionsByName.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## MCP Server Instructions');
      final renderedNames = <String>{};
      for (final server in servers) {
        final instructions = serverInstructionsByName[server.name];
        if (instructions == null || instructions.isEmpty) {
          continue;
        }
        renderedNames.add(server.name);
        _writeMcpServerInstructionBlock(
          buffer: buffer,
          serverName: server.name,
          instructions: instructions,
        );
      }
      final extraEntries =
          serverInstructionsByName.entries
              .where((entry) => !renderedNames.contains(entry.key))
              .toList(growable: false)
            ..sort((left, right) => left.key.compareTo(right.key));
      for (final entry in extraEntries) {
        _writeMcpServerInstructionBlock(
          buffer: buffer,
          serverName: entry.key,
          instructions: entry.value,
        );
      }
    }

    return _truncateRestoredContextContent(
      buffer.toString().trimRight(),
      _postCompactRestoreMaxMcpChars,
      'restored_mcp_truncated',
    );
  }

  void _writeMcpServerInstructionBlock({
    required StringBuffer buffer,
    required String serverName,
    required String instructions,
  }) {
    final boundedInstructions = _truncateRestoredContextContent(
      instructions,
      _postCompactRestoreMaxMcpInstructionChars,
      'mcp_server_instructions_truncated',
    );
    buffer
      ..writeln()
      ..writeln('### $serverName')
      ..writeln(boundedInstructions);
  }

  int _renderMcpToolLines(
    StringBuffer buffer,
    List<AiToolDefinition> tools,
    int limit,
  ) {
    var rendered = 0;
    for (final tool in tools) {
      if (rendered >= limit) {
        break;
      }
      final description = _firstNonEmptyLine(tool.description, 240);
      buffer.writeln(
        '- ${tool.name}${description.isEmpty ? '' : ': $description'}',
      );
      rendered += 1;
    }
    return rendered;
  }

  String _mcpServerTokenFromToolName(
    String toolName,
    Iterable<String> knownServerTokens,
  ) {
    var bestMatch = '';
    for (final serverToken in knownServerTokens) {
      if (toolName.startsWith('${serverToken}__')) {
        if (serverToken.length > bestMatch.length) {
          bestMatch = serverToken;
        }
      }
    }
    if (bestMatch.isNotEmpty) {
      return bestMatch;
    }
    final parts = toolName.trim().split('__');
    if (parts.length < 3 || parts.first != 'mcp') {
      return '';
    }
    return 'mcp__${parts[1]}';
  }

  String _firstNonEmptyLine(String text, int maxChars) {
    for (final raw in text.split('\n')) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      return clipTextWithEllipsis(trimmed, maxChars);
    }
    return '';
  }

  String _promptHistoryStandaloneToolCallContent(AiSessionMessage message) {
    final toolCalls = _readToolCalls(message.metadata)
        .map(
          (toolCall) => _sanitizeToolCallForPromptHistory(
            toolCall,
            metadata: message.metadata,
          ),
        )
        .toList(growable: false);
    if (toolCalls.isEmpty) {
      final toolName = '${message.metadata['tool_name'] ?? ''}'.trim();
      return toolName.isEmpty ? '[tool_call]' : 'Tool call: $toolName';
    }
    return _promptHistoryToolCallAssistantContent(toolCalls);
  }

  String _promptHistoryToolCallAssistantContent(List<AiToolCall> toolCalls) {
    final lines = toolCalls
        .map(_toolCallLabelForPromptHistory)
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return '[tool_call]';
    }
    return lines.join('\n');
  }

  String _toolCallLabelForPromptHistory(AiToolCall toolCall) {
    final normalizedName = toolCall.name.trim();
    if (normalizedName.isEmpty) {
      return '[tool_call]';
    }
    final arguments = stringKeyedMapFromValueOrJsonText(toolCall.arguments);
    final targetPath = _toolCallTargetPath(arguments);
    // Bash 命令体必须保留；仅原生 Write/Edit 系列工具
    // 才标注 "payload omitted"。否则模型会以为自己执行的 shell 命令也被
    // 截断，产生不必要的"再写一次"重试。
    final writeLike = _isFileEditingToolName(normalizedName);
    if (targetPath != null) {
      return writeLike
          ? 'Tool call: $normalizedName -> $targetPath (payload omitted from prompt history)'
          : 'Tool call: $normalizedName -> $targetPath';
    }
    return writeLike
        ? 'Tool call: $normalizedName (write payload omitted from prompt history)'
        : 'Tool call: $normalizedName';
  }

  String _promptHistoryToolResultContent(
    AiSessionMessage message,
    _ToolCompressionConfig compressionConfig, {
    bool isFreshUnconsumedResult = false,
    bool inlineSystemReminders = false,
  }) {
    if (!compressionConfig.enabled || !compressionConfig.summarizeResults) {
      // 普通会话始终交付完整工具结果；摘要只用于生成压缩检查点。
      return _promptContentForMessage(
        message,
        inlineSystemReminders: inlineSystemReminders,
      );
    }
    final writeLikeToolResult = _isWriteLikeToolHistoryMessage(message);
    if (isFreshUnconsumedResult && !writeLikeToolResult) {
      final original = _promptContentForMessage(
        message,
        inlineSystemReminders: inlineSystemReminders,
      );
      final knowledgeResult = _compressKnowledgeToolResultContent(
        message,
        compressionConfig,
        originalOverride: original,
      );
      if (knowledgeResult != null) {
        return knowledgeResult;
      }
      if (!compressionConfig.guardsFreshToolResults ||
          original.length <= compressionConfig.thresholdChars) {
        return original;
      }
      // 首次与后续历史使用相同表示，避免工具循环改写前缀缓存位置。
      return _compressGenericToolResultContent(
        message,
        compressionConfig,
        inlineSystemReminders: inlineSystemReminders,
        originalOverride: original,
      );
    }
    if (!writeLikeToolResult) {
      final knowledgeResult = _compressKnowledgeToolResultContent(
        message,
        compressionConfig,
        inlineSystemReminders: inlineSystemReminders,
      );
      if (knowledgeResult != null) {
        return knowledgeResult;
      }
      // 通用工具调用结果压缩。当工具返回内容超过阈值时，
      // 提炼受影响文件路径 + 行号 + 工具自述目的（purpose/intent/goal/
      // description/reason），保留首尾片段作为结构性补充信息，避免
      // conversation history 被海量原文淹没。
      return _compressGenericToolResultContent(
        message,
        compressionConfig,
        inlineSystemReminders: inlineSystemReminders,
      );
    }
    final metadata = message.metadata;
    final toolName = '${metadata['tool_name'] ?? ''}'.trim();
    final status =
        '${metadata['status'] ?? metadata['tool_execution_status'] ?? ''}'
            .trim();
    final mutationKind = '${metadata['file_mutation_kind'] ?? ''}'.trim();
    final targetPaths = _fileMutationTargetPaths(metadata);
    final workingDirectory =
        '${metadata['working_directory'] ?? metadata['tool_execution_working_directory'] ?? ''}'
            .trim();
    final writeReason =
        '${metadata['file_mutation_write_reason'] ?? metadata['write_analysis_reason'] ?? metadata['tool_execution_write_analysis_reason'] ?? ''}'
            .trim();
    final resultText =
        '${metadata['result_text'] ?? metadata['tool_execution_result'] ?? ''}'
            .trim();
    final lines = <String>[
      '[write_result] ${toolName.isEmpty ? 'Tool' : toolName}',
      if (status.isNotEmpty) 'status: $status',
      ..._writeConfirmationSummaryLines(metadata),
      if (mutationKind.isNotEmpty) 'mutation: $mutationKind',
      if (targetPaths.isNotEmpty) 'targets: ${targetPaths.join(', ')}',
      if (workingDirectory.isNotEmpty) 'working_directory: $workingDirectory',
      if (writeReason.isNotEmpty) 'reason: $writeReason',
      if (resultText.isNotEmpty &&
          (compressionConfig.writeSummaryMaxChars <= 0
              ? resultText.length <= 280
              : resultText.length <= compressionConfig.writeSummaryMaxChars))
        'summary: $resultText',
      'note: Large write payloads and file contents were omitted from prompt history to save tokens. Inspect the local filesystem if exact contents are needed.',
    ];
    return lines.join('\n');
  }

  String _microCompactToolResultContent(
    AiSessionMessage message, {
    bool inlineSystemReminders = false,
  }) {
    final metadata = message.metadata;
    final toolName = '${metadata['tool_name'] ?? ''}'.trim();
    final status =
        '${metadata['status'] ?? metadata['tool_execution_status'] ?? ''}'
            .trim();
    final targetPaths = _fileMutationTargetPaths(metadata);
    final workingDirectory =
        '${metadata['working_directory'] ?? metadata['tool_execution_working_directory'] ?? ''}'
            .trim();
    final purpose = _extractToolCallPurpose(metadata);
    final original = _promptContentForMessage(
      message,
      inlineSystemReminders: inlineSystemReminders,
    );
    final lines = <String>[
      '[old_tool_result_cleared] ${toolName.isEmpty ? 'Tool' : toolName}',
      'original_chars: ${original.length}',
      if (status.isNotEmpty) 'status: $status',
      ..._toolStateSummaryLines(metadata),
      if (targetPaths.isNotEmpty) 'targets: ${targetPaths.join(', ')}',
      if (workingDirectory.isNotEmpty) 'working_directory: $workingDirectory',
      if (purpose != null && purpose.isNotEmpty) 'purpose: $purpose',
      _toolResultRecoveryNote(
        metadata,
        fallback:
            'Older consumed tool result content was cleared from prompt history. Re-run the tool or read local files if exact output is needed.',
      ),
    ];
    return lines.join('\n');
  }

  String _writeConfirmationDecision(Map<String, Object?> metadata) {
    return '${metadata['write_confirmation_decision'] ?? ''}'.trim();
  }

  List<String> _toolStateSummaryLines(Map<String, Object?> metadata) {
    return <String>[
      ..._writeConfirmationSummaryLines(metadata),
      ..._planGateSummaryLines(metadata),
      ..._planApprovalStateSummaryLines(metadata),
      ..._toolOutputBudgetSummaryLines(metadata),
    ];
  }

  List<String> _writeConfirmationSummaryLines(Map<String, Object?> metadata) {
    final decision = _writeConfirmationDecision(metadata);
    if (decision.isEmpty) return const <String>[];
    final lines = <String>['write_confirmation_decision: $decision'];
    for (final key in const <String>[
      'write_confirmation_rejected',
      'write_confirmation_dismissed',
      'write_confirmation_timed_out',
      'write_confirmation_cancelled',
      'write_confirmation_missing_callback',
    ]) {
      if (metadata[key] == true) {
        lines.add('$key: true');
      }
    }
    return lines;
  }

  List<String> _planGateSummaryLines(Map<String, Object?> metadata) {
    final lines = <String>[];
    if (metadata['ask_user_choice_blocked_plan_approval'] == true) {
      lines.add('plan_gate_block: ask_user_choice_plan_approval');
      final reason = '${metadata['ask_user_choice_block_reason'] ?? ''}'.trim();
      if (reason.isNotEmpty) lines.add('ask_user_choice_block_reason: $reason');
      final approvalTool = '${metadata['plan_approval_tool'] ?? ''}'.trim();
      if (approvalTool.isNotEmpty) {
        lines.add('plan_approval_tool: $approvalTool');
      }
    }
    if (metadata['task_blocked_plan_mode_subagent'] == true) {
      lines.add('plan_gate_block: task_subagent_execution_unapproved');
      final reason = '${metadata['task_block_reason'] ?? ''}'.trim();
      if (reason.isNotEmpty) lines.add('task_block_reason: $reason');
      final subagentType = '${metadata['subagent_type'] ?? ''}'.trim();
      if (subagentType.isNotEmpty) lines.add('subagent_type: $subagentType');
      final allowed = _readStringList(
        metadata['allowed_subagent_types_before_approval'],
      );
      if (allowed.isNotEmpty) {
        lines.add(
          'allowed_subagent_types_before_approval: ${allowed.join(', ')}',
        );
      }
    }
    final unsupportedTool = '${metadata['unsupported_tool_name'] ?? ''}'.trim();
    if (unsupportedTool.isNotEmpty) {
      lines.add('unsupported_tool_name: $unsupportedTool');
    }
    if (metadata['tool_catalog_empty'] == true) {
      lines.add('tool_catalog_empty: true');
    }
    for (final key in const <String>[
      'plan_mode_active',
      'awaiting_plan_approval',
      'plan_mode_execution_approved_for_send',
    ]) {
      if (metadata.containsKey(key) && metadata[key] is bool) {
        lines.add('$key: ${metadata[key]}');
      }
    }
    return lines;
  }

  List<String> _toolGateDescriptorParts(Map<String, Object?> metadata) {
    final parts = <String>[];
    if (metadata['ask_user_choice_blocked_plan_approval'] == true) {
      parts.add('plan_gate=ask_choice_requires_exit');
    }
    if (metadata['task_blocked_plan_mode_subagent'] == true) {
      parts.add('plan_gate=task_unapproved');
    }
    final unsupportedTool = '${metadata['unsupported_tool_name'] ?? ''}'.trim();
    if (unsupportedTool.isNotEmpty) {
      parts.add('unsupported_tool=$unsupportedTool');
    }
    if (metadata['tool_catalog_empty'] == true) {
      parts.add('catalog_empty=true');
    }
    if (metadata['plan_mode_awaiting_approval'] == true) {
      parts.add('plan_approval=pending');
      final allowedPromptCount = _metadataPositiveInt(
        metadata['plan_mode_allowed_prompt_count'],
      );
      if (allowedPromptCount != null) {
        parts.add('allowed_prompts=$allowedPromptCount');
      }
    }
    return parts;
  }

  List<String> _planApprovalStateSummaryLines(Map<String, Object?> metadata) {
    if (metadata['plan_mode_awaiting_approval'] != true) {
      return const <String>[];
    }
    final lines = <String>['plan_mode_awaiting_approval: true'];
    final allowedPrompts = _planAllowedPromptSummaryLines(
      metadata['plan_mode_allowed_prompts'],
    );
    if (allowedPrompts.isNotEmpty) {
      lines.add('plan_mode_allowed_prompt_count: ${allowedPrompts.length}');
      lines.addAll(allowedPrompts);
    }
    return lines;
  }

  List<String> _planAllowedPromptSummaryLines(Object? rawValue) {
    if (rawValue is! List) {
      return const <String>[];
    }
    final lines = <String>[];
    for (final item in rawValue) {
      if (item is! Map) {
        continue;
      }
      final tool = '${item['tool'] ?? ''}'.trim();
      final prompt = '${item['prompt'] ?? ''}'.trim();
      if (tool.isEmpty || prompt.isEmpty) {
        continue;
      }
      lines.add('plan_mode_allowed_prompt: $tool: $prompt');
    }
    return lines;
  }

  List<String> _toolOutputBudgetSummaryLines(Map<String, Object?> metadata) {
    if (metadata['tool_output_truncated'] != true) {
      return const <String>[];
    }
    final lines = <String>['tool_output_truncated: true'];
    for (final entry in const <({String key, String label})>[
      (
        key: 'tool_output_original_length',
        label: 'tool_output_original_length',
      ),
      (key: 'tool_output_budget_chars', label: 'tool_output_budget_chars'),
      (key: 'tool_output_included_chars', label: 'tool_output_included_chars'),
      (key: 'tool_output_omitted_chars', label: 'tool_output_omitted_chars'),
      (
        key: 'tool_output_persisted_chars',
        label: 'tool_output_persisted_chars',
      ),
    ]) {
      final value = _metadataPositiveInt(metadata[entry.key]);
      if (value != null) {
        lines.add('${entry.label}: $value');
      }
    }
    if (metadata['tool_output_persisted'] == true) {
      lines.add('tool_output_persisted: true');
    }
    final persistedPath = _metadataTrimmedString(
      metadata['tool_output_persisted_path'],
    );
    if (persistedPath.isNotEmpty) {
      lines.add('tool_output_persisted_path: $persistedPath');
    }
    final persistenceFormat = _metadataTrimmedString(
      metadata['tool_output_persistence_format'],
    );
    if (persistenceFormat.isNotEmpty) {
      lines.add('tool_output_persistence_format: $persistenceFormat');
    }
    final strategy = _metadataTrimmedString(
      metadata['tool_output_truncation_strategy'],
    );
    if (strategy.isNotEmpty) {
      lines.add('tool_output_truncation_strategy: $strategy');
    }
    final fullContentAvailable = metadata['tool_output_full_content_available'];
    if (fullContentAvailable is bool) {
      lines.add('tool_output_full_content_available: $fullContentAvailable');
    }
    final recoveryHint = _metadataTrimmedString(
      metadata['tool_output_recovery_hint'],
    );
    if (recoveryHint.isNotEmpty) {
      lines.add('tool_output_recovery_hint: $recoveryHint');
    }
    return lines;
  }

  List<String> _toolOutputDescriptorParts(Map<String, Object?> metadata) {
    if (metadata['tool_output_truncated'] != true) {
      return const <String>[];
    }
    final original = _metadataPositiveInt(
      metadata['tool_output_original_length'],
    );
    final budget = _metadataPositiveInt(metadata['tool_output_budget_chars']);
    final parts = <String>[];
    if (original != null && budget != null) {
      parts.add('output_truncated=$original/$budget');
    } else {
      parts.add('output_truncated=true');
    }
    final strategy = _metadataTrimmedString(
      metadata['tool_output_truncation_strategy'],
    );
    if (strategy.isNotEmpty) {
      parts.add('truncation=$strategy');
    }
    final fullContentAvailable = metadata['tool_output_full_content_available'];
    if (fullContentAvailable is bool) {
      parts.add('full_output=$fullContentAvailable');
    }
    final persistedPath = _metadataTrimmedString(
      metadata['tool_output_persisted_path'],
    );
    if (persistedPath.isNotEmpty) {
      parts.add('persisted_output=${clipTextWithEllipsis(persistedPath, 96)}');
    }
    final recoveryHint = _metadataTrimmedString(
      metadata['tool_output_recovery_hint'],
    );
    if (recoveryHint.isNotEmpty) {
      parts.add('recovery=$recoveryHint');
    }
    return parts;
  }

  int? _metadataPositiveInt(Object? raw) {
    return optionalPositiveIntFromValue(raw);
  }

  String _metadataTrimmedString(Object? raw) {
    return '${raw ?? ''}'.trim();
  }

  /// 仅在摘要检查点 prompt 内补做微压缩：为 [messages] 中
  /// 已被消费的旧工具结果计算 `[old_tool_result_cleared]` 摘要，返回
  /// messageId → 摘要的映射。
  ///
  /// 正常对话 history 不能使用这层清理：同一条工具结果一旦从
  /// `[tool_result_summary]` 被跨轮改写成 `[old_tool_result_cleared]`，provider
  /// prefix cache 会在该历史位置断裂，所有线程模板都会被影响。
  Map<String, String> _computeMicroCompactContentMap(
    List<AiSessionMessage> messages,
    _ToolCompressionConfig compressionConfig,
  ) {
    if (!compressionConfig.microCompressionEnabled) {
      return const <String, String>{};
    }
    final compactedMessages = _microCompactEligibleConsumedToolMessages(
      messages,
    );
    if (compactedMessages.isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{
      for (final message in compactedMessages)
        message.id: _microCompactToolResultContent(message),
    };
  }

  List<AiSessionMessage> _microCompactEligibleConsumedToolMessages(
    List<AiSessionMessage> messages,
  ) {
    var lastConsumerIndex = -1;
    for (var i = 0; i < messages.length; i++) {
      final kind = messages[i].kind;
      if (kind == AiSessionMessageKind.assistant ||
          kind == AiSessionMessageKind.toolCall) {
        lastConsumerIndex = i;
      }
    }
    if (lastConsumerIndex <= 0) {
      return const <AiSessionMessage>[];
    }
    final consumedToolMessages = <AiSessionMessage>[];
    for (var index = 0; index < lastConsumerIndex; index++) {
      final message = messages[index];
      if (message.kind == AiSessionMessageKind.tool && !message.isDeleted) {
        consumedToolMessages.add(message);
      }
    }
    final clearCount =
        consumedToolMessages.length - _microCompactKeepRecentToolResults;
    if (clearCount <= 0) {
      return const <AiSessionMessage>[];
    }
    return consumedToolMessages.take(clearCount).toList(growable: false);
  }

  AiToolCall _sanitizeToolCallForPromptHistory(
    AiToolCall toolCall, {
    required Map<String, Object?> metadata,
  }) {
    final sanitizedArguments = _summarizeToolCallArgumentsForHistory(
      toolCall,
      metadata: metadata,
    );
    return AiToolCall(
      id: toolCall.id,
      name: toolCall.name,
      arguments: sanitizedArguments,
    );
  }

  String _summarizeToolCallArgumentsForHistory(
    AiToolCall toolCall, {
    required Map<String, Object?> metadata,
  }) {
    final normalizedName = toolCall.name.trim();
    final arguments = stringKeyedMapFromValueOrJsonText(toolCall.arguments);
    if (arguments.isEmpty) {
      return toolCall.arguments;
    }
    final lowerName = normalizedName.toLowerCase();
    switch (lowerName) {
      case 'write':
        final filePath = '${arguments['file_path'] ?? ''}'.trim();
        final content = '${arguments['content'] ?? ''}';
        return jsonEncode(<String, Object?>{
          'file_path': filePath,
          'content': _omittedPayloadSummary(
            content.length,
            targetPath: filePath,
            action: 'write',
          ),
        });
      case 'edit':
        final filePath = '${arguments['file_path'] ?? ''}'.trim();
        final oldString = '${arguments['old_string'] ?? ''}';
        final newString = '${arguments['new_string'] ?? ''}';
        return jsonEncode(<String, Object?>{
          'file_path': filePath,
          'old_string': _omittedPayloadSummary(
            oldString.length,
            targetPath: filePath,
            action: 'replace_from',
          ),
          'new_string': _omittedPayloadSummary(
            newString.length,
            targetPath: filePath,
            action: 'replace_to',
          ),
          if (arguments.containsKey('replace_all'))
            'replace_all': arguments['replace_all'],
        });
      case 'multiedit':
        final filePath = '${arguments['file_path'] ?? ''}'.trim();
        final rawEdits = arguments['edits'];
        final editsSummary = rawEdits is List
            ? rawEdits
                  .map((item) {
                    if (item is! Map) {
                      return const <String, Object?>{'summary': 'invalid edit'};
                    }
                    final edit = stringKeyedMapFromValue(item);
                    final oldString = '${edit['old_string'] ?? ''}';
                    final newString = '${edit['new_string'] ?? ''}';
                    return <String, Object?>{
                      'old_string': _omittedPayloadSummary(
                        oldString.length,
                        targetPath: filePath,
                        action: 'replace_from',
                      ),
                      'new_string': _omittedPayloadSummary(
                        newString.length,
                        targetPath: filePath,
                        action: 'replace_to',
                      ),
                      if (edit.containsKey('replace_all'))
                        'replace_all': edit['replace_all'],
                    };
                  })
                  .toList(growable: false)
            : const <Map<String, Object?>>[];
        return jsonEncode(<String, Object?>{
          'file_path': filePath,
          'edit_count': editsSummary.length,
          'edits_summary': editsSummary,
        });
      case 'notebookedit':
        final notebookPath = '${arguments['notebook_path'] ?? ''}'.trim();
        final editMode = '${arguments['edit_mode'] ?? ''}'.trim();
        final newSource = '${arguments['new_source'] ?? ''}';
        return jsonEncode(<String, Object?>{
          'notebook_path': notebookPath,
          if ('${arguments['cell_id'] ?? ''}'.trim().isNotEmpty)
            'cell_id': '${arguments['cell_id'] ?? ''}'.trim(),
          if (editMode.isNotEmpty) 'edit_mode': editMode,
          if ('${arguments['cell_type'] ?? ''}'.trim().isNotEmpty)
            'cell_type': '${arguments['cell_type'] ?? ''}'.trim(),
          if (editMode.toLowerCase() != 'delete')
            'new_source': _omittedPayloadSummary(
              newSource.length,
              targetPath: notebookPath,
              action: 'notebook_edit',
            ),
        });
      case 'bash':
        // Bash 命令是"我做了什么"的语义载体，必须保留完整命令；只
        // 在命令体超大时（>8KB）做 head/tail 截断，并附上 stored locally
        // 提示便于审计。
        final command = '${arguments['cmd'] ?? arguments['command'] ?? ''}';
        const bashCommandPromptHistoryMaxChars = 8 * kBytesPerKiB;
        if (command.length <= bashCommandPromptHistoryMaxChars) {
          return toolCall.arguments;
        }
        final isWriteLikeBash =
            _looksLikeWriteLikeBashArguments(arguments) ||
            _isWriteLikeToolMetadata(metadata);
        const headTail = kBytesPerKiB;
        final headEnd = safeUtf16PrefixCodeUnits(command, headTail);
        final tailStart = safeUtf16SuffixStart(
          command,
          command.length - headTail,
        );
        final head = command.substring(0, headEnd);
        final tail = command.substring(tailStart);
        final summarizedCommand =
            '$head\n…[bash_command_truncated: dropped '
            '${tailStart - headEnd} chars; '
            'full command stored locally]…\n$tail';
        return jsonEncode(<String, Object?>{
          'cmd': summarizedCommand,
          if ('${arguments['working_directory'] ?? arguments['cwd'] ?? ''}'
              .trim()
              .isNotEmpty)
            'working_directory':
                '${arguments['working_directory'] ?? arguments['cwd'] ?? ''}'
                    .trim(),
          if (isWriteLikeBash &&
              metadata['tool_execution_write_analysis_reason'] != null)
            'write_reason':
                '${metadata['tool_execution_write_analysis_reason'] ?? ''}'
                    .trim(),
        });
      default:
        return toolCall.arguments;
    }
  }

  String _omittedPayloadSummary(
    int characterCount, {
    String? targetPath,
    required String action,
  }) {
    final normalizedTarget = targetPath?.trim() ?? '';
    final targetSuffix = normalizedTarget.isEmpty
        ? ''
        : ' -> $normalizedTarget';
    return '[omitted $characterCount chars; $action payload stored locally$targetSuffix]';
  }

  /// 知识库检索类工具结果压缩：超出提示词预算时按
  /// [_knowledgeToolPromptMaxChars] 截断，并以 `[knowledge_tool_result]`
  /// 标记压缩产物。
  String? _compressKnowledgeToolResultContent(
    AiSessionMessage message,
    _ToolCompressionConfig compressionConfig, {
    bool inlineSystemReminders = false,
    String? originalOverride,
  }) {
    final metadata = message.metadata;
    final toolName = '${metadata['tool_name'] ?? ''}'.trim();
    if (!_isKnowledgeToolName(toolName)) return null;
    final original =
        originalOverride ??
        _promptContentForMessage(
          message,
          inlineSystemReminders: inlineSystemReminders,
        );
    if (original.length <= compressionConfig.thresholdChars) return null;

    final kb = KnowledgeMessageMetadata.fromMessageMetadata(metadata);
    final results = stringKeyedMapListFromValue(
      kb?['results'] ?? metadata['results'],
    );
    final promptContext = KnowledgeMessageMetadata.promptAppendContent(
      metadata,
    );
    if (promptContext.isEmpty && results.isEmpty) return null;

    final status =
        '${metadata['status'] ?? metadata['tool_execution_status'] ?? kb?['status'] ?? ''}'
            .trim();
    final query = '${kb?['query'] ?? metadata['query'] ?? ''}'.trim();
    final lines = <String>[
      '[knowledge_tool_result] ${toolName.isEmpty ? 'KnowledgeTool' : toolName}',
      'original_chars: ${original.length}',
      if (status.isNotEmpty) 'status: $status',
      if (query.isNotEmpty) 'query: $query',
      'result_count: ${results.length}',
      'instruction: Use matching Knowledge Base rows as evidence. Ignore unrelated lower-ranked rows; do not claim no match when a relevant title, heading, preview, or content is present.',
    ];
    if (promptContext.isNotEmpty) {
      lines
        ..add('context:')
        ..add(
          clipTextWithEllipsis(promptContext, _knowledgeToolPromptMaxChars),
        );
    } else {
      lines
        ..add('results:')
        ..add(_knowledgeToolResultRowsForPrompt(results));
    }
    lines.add(
      'note: Call KnowledgeRead with chunk_id only when exact content beyond this context is needed.',
    );
    return lines.join('\n');
  }

  bool _isKnowledgeToolName(String toolName) {
    final normalized = toolName.trim().toLowerCase();
    return normalized == 'knowledgesearch' ||
        normalized == 'knowledge_search' ||
        normalized == 'knowledgeread' ||
        normalized == 'knowledge_read';
  }

  String _knowledgeToolResultRowsForPrompt(List<Map<String, Object?>> results) {
    final buffer = StringBuffer();
    for (
      var index = 0;
      index < results.length && index < _knowledgeToolPromptMaxResults;
      index++
    ) {
      final hit = results[index];
      final title =
          '${hit['source_title'] ?? hit['title'] ?? hit['chunk_title'] ?? ''}'
              .trim();
      final heading = '${hit['heading_path'] ?? ''}'.trim();
      final chunkId = '${hit['chunk_id'] ?? hit['id'] ?? ''}'.trim();
      final score = hit['final_score'] ?? hit['rerank_score'] ?? hit['score'];
      final content = '${hit['content'] ?? hit['preview'] ?? ''}'.trim();
      buffer.writeln('[KB-${index + 1}]');
      if (title.isNotEmpty) buffer.writeln('Title: $title');
      if (heading.isNotEmpty) buffer.writeln('Heading: $heading');
      if (chunkId.isNotEmpty) buffer.writeln('Chunk ID: $chunkId');
      if (score != null && '$score'.trim().isNotEmpty) {
        buffer.writeln('Score: $score');
      }
      if (content.isNotEmpty) {
        buffer
          ..writeln(hit['content'] == null ? 'Preview:' : 'Content:')
          ..writeln(
            clipTextWithEllipsis(content, _knowledgeToolPromptPreviewMaxChars),
          );
      }
      if (index < results.length - 1 &&
          index < _knowledgeToolPromptMaxResults - 1) {
        buffer.writeln();
      }
    }
    if (results.length > _knowledgeToolPromptMaxResults) {
      buffer.writeln(
        '\n[omitted ${results.length - _knowledgeToolPromptMaxResults} lower-ranked results]',
      );
    }
    return buffer.toString().trimRight();
  }

  /// 通用工具调用结果压缩。原文超过配置的压缩阈值（thresholdChars，调用方
  /// 可传阈值覆盖）时，把整段 raw 输出替换成结构化摘要：
  ///
  /// - 工具名称 + 状态
  /// - 工具调用自述目的（purpose / intent / goal / description / reason）
  /// - 受影响文件路径与行号（基于正则提取，去重保留前 12 条）
  /// - 首尾各 256 字符片段，保留语义钩子但杜绝海量正文进入 prompt
  ///
  /// 这样可以显著降低 conversation history 的 token 占比，让模型把注意力
  /// 集中在结构化线索上，避免被冗长 raw 输出淹没。
  String _compressGenericToolResultContent(
    AiSessionMessage message,
    _ToolCompressionConfig compressionConfig, {
    bool inlineSystemReminders = false,
    String? originalOverride,
    String summaryMarker = '[tool_result_summary]',
    int? thresholdOverride,
    int? headTailWindowOverride,
    String? recoveryFallback,
  }) {
    final original =
        originalOverride ??
        _promptContentForMessage(
          message,
          inlineSystemReminders: inlineSystemReminders,
        );
    final metadata = message.metadata;
    final toolStateLines = _toolStateSummaryLines(
      metadata,
    ).where((line) => !original.contains(line)).toList(growable: false);
    final threshold = thresholdOverride ?? compressionConfig.thresholdChars;
    if (original.length <= threshold) {
      if (toolStateLines.isEmpty) return original;
      return '$original\n${toolStateLines.join('\n')}';
    }
    final toolName = '${metadata['tool_name'] ?? ''}'.trim();
    final status =
        '${metadata['status'] ?? metadata['tool_execution_status'] ?? ''}'
            .trim();
    final purpose = _extractToolCallPurpose(metadata);
    final pathHits = compressionConfig.maxPathHits <= 0
        ? const <String>[]
        : _extractFilePathLineHits(
            original,
            maxHits: compressionConfig.maxPathHits,
          );
    final headTail =
        headTailWindowOverride ?? compressionConfig.headTailWindowChars;
    final head = headTail <= 0
        ? ''
        : original
              .substring(
                0,
                safeUtf16PrefixCodeUnits(
                  original,
                  math.min(original.length, headTail),
                ),
              )
              .trim();
    final tailStart = safeUtf16SuffixStart(
      original,
      math.max(0, original.length - headTail),
    );
    final tail = headTail <= 0 ? '' : original.substring(tailStart).trim();
    final lines = <String>[
      '$summaryMarker ${toolName.isEmpty ? 'Tool' : toolName}',
      'original_chars: ${original.length}',
      if (status.isNotEmpty) 'status: $status',
      ...toolStateLines,
      if (purpose != null && purpose.isNotEmpty) 'purpose: $purpose',
      if (pathHits.isNotEmpty)
        'affected:\n${pathHits.map((h) => '  - $h').join('\n')}',
      if (head.isNotEmpty) 'head:\n$head',
      if (tail.isNotEmpty && tail != head) 'tail:\n$tail',
      _toolResultRecoveryNote(
        metadata,
        fallback:
            recoveryFallback ??
            'Tool result exceeded $threshold chars and was condensed for the prompt history. Re-run the tool or read the local file directly if exact contents are needed.',
      ),
    ];
    return lines.join('\n');
  }

  String _toolResultRecoveryNote(
    Map<String, Object?> metadata, {
    required String fallback,
  }) {
    final persistedPath = _metadataTrimmedString(
      metadata['tool_output_persisted_path'],
    );
    if (persistedPath.isNotEmpty) {
      return 'note: Exact omitted output is available at tool_output_persisted_path. Read it before relying on cleared or condensed content.';
    }
    return 'note: $fallback';
  }

  String? _extractToolCallPurpose(Map<String, Object?> metadata) {
    const purposeKeys = <String>[
      'purpose',
      'intent',
      'goal',
      'description',
      'reason',
      'summary',
    ];
    for (final key in purposeKeys) {
      final value = '${metadata[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return clipTextByCodeUnitsWithEllipsis(value, 240);
      }
    }
    final argsRaw = metadata['arguments'] ?? metadata['tool_call_arguments'];
    if (argsRaw is String && argsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(argsRaw);
        if (decoded is Map<String, Object?>) {
          for (final key in purposeKeys) {
            final value = '${decoded[key] ?? ''}'.trim();
            if (value.isNotEmpty) {
              return clipTextByCodeUnitsWithEllipsis(value, 240);
            }
          }
        }
      } catch (_) {
        // 参数不是有效 JSON，无可提取内容。
      }
    }
    return null;
  }

  static final RegExp _filePathLineRegExp = RegExp(
    r'(?:[A-Za-z]:[\\/]|/|\.{1,2}/)?[\w./\\\-]+\.[A-Za-z0-9]{1,8}(?::\d+(?:[-:]\d+)?)?',
  );

  List<String> _extractFilePathLineHits(String text, {required int maxHits}) {
    final seen = <String>{};
    final hits = <String>[];
    for (final match in _filePathLineRegExp.allMatches(text)) {
      final raw = match.group(0)?.trim();
      if (raw == null || raw.isEmpty) {
        continue;
      }
      // 过滤纯版本号、数字等误报。
      if (raw.length < 4 || !raw.contains('.')) {
        continue;
      }
      if (seen.add(raw)) {
        hits.add(raw);
        if (hits.length >= maxHits) {
          break;
        }
      }
    }
    return hits;
  }

  String? _toolCallTargetPath(Map<String, Object?> arguments) {
    const candidateKeys = <String>[
      'file_path',
      'notebook_path',
      'path',
      'working_directory',
      'cwd',
    ];
    for (final key in candidateKeys) {
      final value = '${arguments[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  bool _looksLikeWriteLikeBashArguments(Map<String, Object?> arguments) {
    final command = '${arguments['cmd'] ?? arguments['command'] ?? ''}'.trim();
    if (command.isEmpty) {
      return false;
    }
    return _bashWriteAnalyzer.analyzeWriteCommand(command).isWrite;
  }

  bool _isWriteLikeToolMetadata(Map<String, Object?> metadata) {
    return metadata['tool_execution_is_write_command'] == true ||
        metadata['is_write_command'] == true;
  }

  bool _isWriteLikeToolHistoryMessage(AiSessionMessage message) {
    if (_isWriteLikeToolMetadata(message.metadata)) {
      return true;
    }
    return switch ('${message.metadata['tool_name'] ?? ''}'
        .trim()
        .toLowerCase()) {
      'write' || 'edit' || 'multiedit' || 'notebookedit' => true,
      _ => false,
    };
  }

  List<String> _fileMutationTargetPaths(Map<String, Object?> metadata) {
    final candidateValues = <Object?>[
      metadata['file_mutation_path'],
      metadata['file_path'],
      metadata['notebook_path'],
    ];
    final paths = <String>[];
    final seen = <String>{};
    for (final value in candidateValues) {
      final normalized = '$value'.trim();
      if (normalized.isNotEmpty &&
          normalized != 'null' &&
          seen.add(normalized)) {
        paths.add(normalized);
      }
    }
    final rawMutationPaths = metadata['file_mutation_paths'];
    if (rawMutationPaths is List) {
      for (final value in rawMutationPaths) {
        final normalized = '$value'.trim();
        if (normalized.isNotEmpty &&
            normalized != 'null' &&
            seen.add(normalized)) {
          paths.add(normalized);
        }
      }
    }
    return paths;
  }

  List<AiToolCall> _readToolCalls(Map<String, Object?> metadata) {
    final rawToolCalls = metadata['tool_calls'];
    if (rawToolCalls is! List) {
      return const <AiToolCall>[];
    }
    return rawToolCalls
        .map((item) {
          if (item is! Map) {
            return null;
          }
          final toolCall = stringKeyedMapFromValue(item);
          final id = '${toolCall['id'] ?? ''}'.trim();
          final name = '${toolCall['name'] ?? ''}'.trim();
          final arguments = '${toolCall['arguments'] ?? ''}';
          if (id.isEmpty || name.isEmpty) {
            return null;
          }
          return AiToolCall(id: id, name: name, arguments: arguments);
        })
        .whereType<AiToolCall>()
        .toList(growable: false);
  }

  String? _readToolCallId(Map<String, Object?> metadata) {
    final value = '${metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'
        .trim();
    return value.isEmpty ? null : value;
  }

  List<String> _readStringList(Object? rawValue) {
    return stringListFromValue(
      rawValue,
      separator: '',
      ignoreLiteralNull: true,
    );
  }

  AiRepositorySnapshot? _effectiveRepositorySnapshot({
    required AiSession session,
    required AiSessionRuntimeContext runtimeContext,
  }) {
    final previousSnapshot = session.lastPromptMetadata['repository_snapshot'];
    if (previousSnapshot is Map<String, Object?>) {
      return AiRepositorySnapshot.fromJson(previousSnapshot);
    }
    if (previousSnapshot is Map) {
      return AiRepositorySnapshot.fromJson(
        Map<String, Object?>.from(previousSnapshot),
      );
    }
    return runtimeContext.repositorySnapshot;
  }

  String? _buildPlanModeReminder({
    required AiSession session,
    required bool executionApprovedForSend,
    required bool recoveryInspectionRequired,
  }) {
    if (session.awaitingPlanApproval) {
      return AiPlanModeGuidance.pendingApprovalReminder(
        session.pendingPlan ?? '',
      );
    }
    if (session.mode != AiSessionMode.plan) {
      return null;
    }
    if (recoveryInspectionRequired) {
      final completedButNeedsReview = _hasCompletedTodoItemsOnly(
        session.todoItems,
      );
      final failedSteps = session.todoItems
          .where((item) {
            return AiSessionTodoState.isFailureStatus(item.status);
          })
          .map((item) => item.content.trim())
          .where((item) => item.isNotEmpty)
          .take(3)
          .toList(growable: false);
      final failedStepSummary = failedSteps.isEmpty
          ? ''
          : '\n\nFailed todo steps to review first: ${failedSteps.join('; ')}.';
      final completedTodoSummary = completedButNeedsReview
          ? ' The current todo list is already marked completed, but the user is still asking to continue, so treat that completion state as potentially stale until you verify what actually ran.'
          : '';
      return 'The previous plan run stopped after a failed, timed-out, otherwise interrupted step, or a stale todo state. Before retrying, first review the current todo list and inspect the workspace, generated artifacts, and recent tool results to see what already succeeded.$completedTodoSummary Then decide whether to fully retry the failed step or only retry the unfinished portion. Use TodoWrite to refresh the relevant todo entries before resuming heavy execution. If a failed or stale-completed step should be retried now, set that step back to in_progress so the timeline reflects the retry, and keep the todo list current as the retry progresses.$failedStepSummary';
    }
    if (executionApprovedForSend) {
      return _buildPlanApprovalExecutionReminder(session);
    }
    return AiPlanModeGuidance.planningReminder;
  }

  bool _isGoalPausedForQueuedMessages(AiSession session) {
    final goal = session.activeGoal;
    if (session.mode != AiSessionMode.chat ||
        goal == null ||
        goal.status != AiSessionGoalStatus.paused) {
      return false;
    }
    return (goal.statusReason ?? '').trim() ==
        aiSessionGoalPausedForQueueStatusReason;
  }

  bool _shouldOmitPausedGoalQueueMessageFromPrompt(
    AiSession session,
    AiSessionMessage message,
  ) {
    if (!_isGoalPausedForQueuedMessages(session)) {
      return false;
    }
    if (message.kind != AiSessionMessageKind.user) {
      return false;
    }
    final goalId = session.activeGoal?.id.trim();
    if (goalId == null || goalId.isEmpty) {
      return false;
    }
    final messageGoalId =
        '${message.metadata[aiSessionGoalIdMetadataKey] ?? ''}'.trim();
    if (messageGoalId != goalId) {
      return false;
    }
    return message.metadata[aiSessionGoalObjectiveMetadataKey] == true ||
        message.metadata[aiSessionGoalAutoFollowUpMetadataKey] == true ||
        message.metadata[aiSessionGoalEvaluationMessageMetadataKey] == true;
  }

  String? _buildGoalModeReminder(AiSession session) {
    final goal = session.activeGoal;
    if (goal == null) {
      return null;
    }
    if (_isGoalPausedForQueuedMessages(session)) {
      return 'A goal is paused for queued user messages. For this round, handle only the latest explicit user message. Do not continue, respond to, or evaluate the paused goal; the runtime will resume it after the queue drains.';
    }
    if (goal.status == AiSessionGoalStatus.paused) {
      return 'Goal mode is paused. Do not continue the goal until the runtime resumes it.';
    }
    if (goal.status != AiSessionGoalStatus.running) {
      return null;
    }
    return 'Goal mode is active. Use [3d] Dynamic Session State `goal` as the controlling objective. Work only toward that objective; when complete, report concrete evidence, otherwise continue with the next useful step.';
  }

  String _buildPlanApprovalExecutionReminder(AiSession session) {
    final record = session.latestActivePlanRecord;
    final plan = record?.plan.trim() ?? '';
    final allowedPrompts = record == null
        ? ''
        : _renderPlanAllowedPromptLines(record.allowedPrompts);
    final buffer = StringBuffer(AiPlanModeGuidance.approvalExecutionReminder);
    if (plan.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln()
        ..writeln('## Approved Plan')
        ..writeln('```text')
        ..writeln(plan)
        ..writeln('```');
    }
    if (allowedPrompts.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('allowed_prompts:')
        ..writeln(allowedPrompts);
    }
    return buffer.toString().trimRight();
  }

  bool _isFileEditingToolName(String toolName) {
    return switch (toolName.trim().toLowerCase()) {
      'edit' || 'multiedit' || 'write' || 'notebookedit' => true,
      _ => false,
    };
  }

  /// 检测 model id 是否属于 GPT 系列（OpenAI gpt-* / o-series / chatgpt-*）。
  /// 用于在 HTML 输出模式下追加 GPT 专属 chat_rules 提醒，纠正其默认散乱长清单陋习。
  bool _isGptSeriesModel(String modelId) {
    final id = modelId.trim().toLowerCase();
    if (id.isEmpty) return false;
    return id.startsWith('gpt-') ||
        id.startsWith('gpt') && RegExp(r'^gpt[-_]?[3-9]').hasMatch(id) ||
        id.startsWith('chatgpt-') ||
        id.startsWith('o1') ||
        id.startsWith('o3') ||
        id.startsWith('o4');
  }

  bool _hasCompletedTodoItemsOnly(List<AiSessionTodoItem> todoItems) {
    return AiSessionTodoState.allCompleted(todoItems);
  }
}

class _MappedToolExchange {
  const _MappedToolExchange({required this.turns, required this.nextIndex});

  final List<AiChatTurn> turns;
  final int nextIndex;
}

/// 工具调用结果压缩相关的运行期配置。从 [AiSessionRuntimeContext]
/// 派生，统一传入历史映射函数链，避免逐层传递一串独立参数。
class _ToolCompressionConfig {
  const _ToolCompressionConfig({
    required this.enabled,
    required this.summarizeResults,
    required this.thresholdChars,
    required this.headTailWindowChars,
    required this.maxPathHits,
    required this.writeSummaryMaxChars,
    required this.microCompressionEnabled,
  });

  factory _ToolCompressionConfig.forConversationHistory(
    AiSessionRuntimeContext runtimeContext,
  ) {
    final thresholdChars =
        runtimeContext.toolResultCompressionThresholdChars > 0
        ? runtimeContext.toolResultCompressionThresholdChars
        : 1024;
    final headTailWindowChars = runtimeContext
        .toolResultCompressionHeadTailWindowChars
        .clamp(0, 1 << 20);
    return _ToolCompressionConfig(
      enabled: runtimeContext.toolResultCompressionEnabled,
      summarizeResults: false,
      thresholdChars: thresholdChars,
      headTailWindowChars: headTailWindowChars,
      maxPathHits: runtimeContext.toolResultCompressionMaxPathHits.clamp(
        0,
        1 << 20,
      ),
      writeSummaryMaxChars: runtimeContext.writeToolSummaryMaxChars.clamp(
        0,
        1 << 20,
      ),
      // 普通会话保持原文与追加稳定；微压缩仅用于压缩检查点。
      microCompressionEnabled: false,
    );
  }

  factory _ToolCompressionConfig.forCompressionPrompt(
    AiSessionRuntimeContext runtimeContext,
  ) {
    final base = _ToolCompressionConfig.forConversationHistory(runtimeContext);
    return _ToolCompressionConfig(
      enabled: true,
      summarizeResults: true,
      thresholdChars: math.min(
        base.thresholdChars,
        AiPromptBuilder._compressionPromptToolResultThresholdChars,
      ),
      headTailWindowChars: math.min(
        base.headTailWindowChars,
        AiPromptBuilder._compressionPromptToolResultHeadTailChars,
      ),
      maxPathHits: base.maxPathHits,
      writeSummaryMaxChars: math.min(
        base.writeSummaryMaxChars,
        AiPromptBuilder._compressionPromptToolResultHeadTailChars,
      ),
      microCompressionEnabled: runtimeContext.microCompressionEnabled,
    );
  }

  final bool enabled;
  final bool summarizeResults;
  final int thresholdChars;
  final int headTailWindowChars;
  final int maxPathHits;
  final int writeSummaryMaxChars;
  final bool microCompressionEnabled;

  bool get guardsFreshToolResults => enabled && summarizeResults;
}

class _ExtractedReminderContent {
  const _ExtractedReminderContent({
    required this.content,
    required this.reminders,
  });

  final String content;
  final List<String> reminders;
}
