import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../instructions/model/user_instruction_entry.dart';
import '../../memory/model/user_memory_entry.dart';
import '../../skills/model/local_skill.dart';
import '../model/ai_attachment.dart';
import '../model/ai_builtin_tool_config.dart' show AiBuiltinToolLoadStrategy;
import '../model/ai_model_config.dart';
import '../model/ai_session.dart';
import '../model/ai_session_message.dart';
import '../model/ai_session_runtime_context.dart';
import '../model/ai_thread_template.dart';
import '../tools/ai_task_tool.dart';
import 'ai_bash_tool_service.dart';
import 'ai_claude_hook_service.dart';
import 'ai_plan_approval_detector.dart';
import 'ai_prompt_template_repository.dart';
import 'ai_protocol_adapter.dart';
import 'ai_tool_runtime_service.dart';

class AiPromptBuildResult {
  const AiPromptBuildResult({
    required this.messages,
    required this.metadata,
    required this.promptCharacterCount,
    required this.systemMessageCount,
    required this.historyMessageCount,
  });

  final List<AiChatTurn> messages;
  final Map<String, Object?> metadata;
  final int promptCharacterCount;
  final int systemMessageCount;
  final int historyMessageCount;
}

class AiPromptBuilder {
  const AiPromptBuilder();

  static final AiBashToolService _bashWriteAnalyzer = AiBashToolService();
  static const int _microCompactKeepRecentToolResults = 5;
  static const int _contextBudgetEstimatedCharsPerToken = 4;
  static const int _contextBudgetSummaryReserveTokens = 20000;
  static const int _contextBudgetAutoCompactBufferTokens = 13000;
  static const int _contextBudgetWarningBufferTokens = 20000;
  static const int _contextBudgetErrorBufferTokens = 20000;
  static const int _contextBudgetManualCompactBufferTokens = 3000;
  static const int _checkpointPromptMaxChars = 40000;
  static const int _checkpointPromptEdgeChars = 18000;
  static const int _compressionAttachmentDetailMaxChars = 2000;
  static const int _postCompactRestoreMaxFiles = 5;
  static const int _postCompactRestoreMaxFileBytes = 256 * 1024;
  static const int _postCompactRestoreMaxCharsPerFile = 12000;
  static const int _postCompactRestoreTotalChars = 30000;
  static const int _postCompactRestoreMaxSkills = 3;
  static const int _postCompactRestoreMaxSkillChars = 8000;
  static const int _postCompactRestoreTotalSkillChars = 20000;
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

  AiPromptBuildResult buildConversationPrompt({
    required AiPromptTemplateBundle templateBundle,
    required AiSession session,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
    required List<UserMemoryEntry> memoryEntries,
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage latestUserMessage,
    List<AiToolDefinition> availableTools = const <AiToolDefinition>[],
    Map<String, AiResolvedTool> resolvedToolsByName =
        const <String, AiResolvedTool>{},
    Map<String, String> mcpServerInstructionsByName = const <String, String>{},
    bool useDsmlToolCalls = false,
  }) {
    final sessionMessages = <AiSessionMessage>[
      ...historyMessages,
      latestUserMessage,
    ];
    return buildSessionPrompt(
      templateBundle: templateBundle,
      session: session,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: memoryEntries,
      sessionMessages: sessionMessages,
      latestUserMessageId: latestUserMessage.id,
      availableTools: availableTools,
      resolvedToolsByName: resolvedToolsByName,
      mcpServerInstructionsByName: mcpServerInstructionsByName,
      useDsmlToolCalls: useDsmlToolCalls,
    );
  }

  AiPromptBuildResult buildSessionPrompt({
    required AiPromptTemplateBundle templateBundle,
    required AiSession session,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
    required List<UserMemoryEntry> memoryEntries,
    required List<AiSessionMessage> sessionMessages,
    String? latestUserMessageId,
    List<AiToolDefinition> availableTools = const <AiToolDefinition>[],
    Map<String, AiResolvedTool> resolvedToolsByName =
        const <String, AiResolvedTool>{},
    Map<String, String> mcpServerInstructionsByName = const <String, String>{},
    bool useDsmlToolCalls = false,
  }) {
    final repositorySnapshot = _effectiveRepositorySnapshot(
      session: session,
      runtimeContext: runtimeContext,
    );
    final latestCompressionPoint = session.latestCompressionPoint;
    final visibleSessionMessages = sessionMessages
        .where((item) => !item.isDeleted)
        .toList(growable: false);
    AiSessionMessage? latestUserMessage;
    final historyMessages = <AiSessionMessage>[];
    for (final message in visibleSessionMessages) {
      if (message.id == latestUserMessageId &&
          message.kind == AiSessionMessageKind.user) {
        latestUserMessage = message;
        continue;
      }
      historyMessages.add(message);
    }
    final historyTurns = _sanitizeToolSequence(
      _mapHistoryMessages(
        historyMessages,
        session,
        model,
        _ToolCompressionConfig.fromRuntimeContext(runtimeContext),
      ),
    );
    final latestUserTurns = latestUserMessage == null
        ? const <AiChatTurn>[]
        : _mapUserMessage(
            latestUserMessage,
            session: session,
            model: model,
            content:
                '# [6] Your latest message\n\n${_promptContentForMessage(latestUserMessage)}',
            isLatestUserMessage: true,
          );
    final todoReminder = _buildTodoWriteReminder(
      session: session,
      latestUserMessage: latestUserMessage,
    );
    final planModeReminder = _buildPlanModeReminder(
      session: session,
      latestUserMessage: latestUserMessage,
    );
    final failedTodos = session.todoItems
        .where((item) {
          final status = item.status.trim().toLowerCase();
          return status == 'failed' ||
              status == 'blocked' ||
              status == 'cancelled';
        })
        .map((item) => item.toJson())
        .toList(growable: false);
    final availableToolNames = availableTools
        .map((tool) => tool.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final currentFileEditingToolNames = availableToolNames
        .where(_isFileEditingToolName)
        .toList(growable: false);
    final postCompactRehydration = _buildPostCompactRehydrationSnapshot(
      session: session,
      historyMessages: historyMessages,
      runtimeContext: runtimeContext,
      memoryEntries: memoryEntries,
      repositorySnapshot: repositorySnapshot,
      availableToolNames: availableToolNames,
      resolvedToolsByName: resolvedToolsByName,
      mcpServerInstructionsByName: mcpServerInstructionsByName,
      latestCompressionPoint: latestCompressionPoint,
    );
    final planRecoveryRequired =
        latestUserMessage != null &&
        _shouldUsePlanRecoveryReminder(
          session: session,
          latestUserMessage: latestUserMessage,
        );
    final metadata = <String, Object?>{
      'session_title': session.title,
      'session_created_at': session.createdAt.toUtc().toIso8601String(),
      'session_updated_at': session.updatedAt.toUtc().toIso8601String(),
      'session_id': session.id,
      'session_template_id': session.templateId,
      'session_template_name': session.templateName,
      'session_template_version': session.templateInternalVersion,
      'session_total_token_count': session.statistics.totalTokens,
      'session_prompt_token_count': session.statistics.totalPromptTokens,
      'session_completion_token_count':
          session.statistics.totalCompletionTokens,
      'session_message_counts': <String, Object?>{
        'user': session.statistics.userMessageCount,
        'assistant': session.statistics.assistantMessageCount,
        'tool': session.statistics.toolMessageCount,
        'mcp': session.statistics.mcpMessageCount,
        'skill': session.statistics.skillMessageCount,
        'compression_point': session.statistics.compressionPointCount,
      },
      'current_model_id': model.modelId,
      'current_model_label': model.displayName,
      'session_mode': session.mode.storageValue,
      'plan_mode_active': session.mode == AiSessionMode.plan,
      'current_todo_count': session.todoItems.length,
      'current_todos': session.todoItems
          .map((item) => item.toJson())
          .toList(growable: false),
      'failed_todo_count': failedTodos.length,
      'failed_todos': failedTodos,
      'recent_plan_tool_failure': _hasRecentPlanToolFailure(session),
      'plan_recovery_required': planRecoveryRequired,
      'todo_write_recommended': todoReminder != null,
      'todo_write_reason': todoReminder,
      'tool_catalog_authoritative': true,
      'current_tool_count': availableToolNames.length,
      'current_tool_names': availableToolNames,
      'current_file_editing_tool_names': currentFileEditingToolNames,
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
      'today_local_date': runtimeContext.todayLocalDate,
      'time_zone_name': runtimeContext.timeZoneName,
      'write_command_confirmation_enabled':
          runtimeContext.writeCommandConfirmationEnabled,
      'allow_command_rule_count': runtimeContext.allowCommandRules.length,
      'allow_command_rules': runtimeContext.allowCommandRules
          .map((item) => item.toJson())
          .toList(growable: false),
      'repository_snapshot': repositorySnapshot?.toJson(),
      'current_prompt_history_message_count': historyTurns.length,
      'current_prompt_memory_entry_count': memoryEntries.length,
      'current_prompt_latest_user_message_id': latestUserMessage?.id,
      'post_compact_rehydration': postCompactRehydration,
      'environment': runtimeContext.toJson(),
    };

    // 2026-04-13: default template also uses compact metadata format to reduce
    // token overhead by ~40%. This follows the refactoring proposal.
    final isCompactTemplate =
        templateBundle.template.id == 'default' ||
        templateBundle.template.id == 'programming_expert';
    final promptMetadata = isCompactTemplate
        ? _buildCompactPromptMetadata(
            session: session,
            runtimeContext: runtimeContext,
            repositorySnapshot: repositorySnapshot,
            availableToolNames: availableToolNames,
            model: model,
            postCompactRehydration: postCompactRehydration,
            todoReminder: todoReminder,
            planModeReminder: planModeReminder,
          )
        : metadata;
    final focusContext = _renderFocusContext(
      historyMessages: historyMessages,
      latestUserMessage: latestUserMessage,
    );
    final restoredFileContext = _renderPostCompactRestoredFileContext(
      historyMessages: historyMessages,
      latestCompressionPoint: latestCompressionPoint,
    );
    final restoredSkillContext = _renderPostCompactRestoredSkillContext(
      historyMessages: historyMessages,
      runtimeContext: runtimeContext,
      latestCompressionPoint: latestCompressionPoint,
    );
    final restoredPlanContext = _renderPostCompactRestoredPlanContext(
      session: session,
      latestCompressionPoint: latestCompressionPoint,
    );
    final restoredMcpContext = _renderPostCompactRestoredMcpContext(
      runtimeContext: runtimeContext,
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

    final messages = <AiChatTurn>[
      AiChatTurn(
        role: AiChatRole.system,
        content: isCompactTemplate
            ? '# [0] System Instructions\n\n${templateBundle.systemInstructions}${_renderWorkspaceInstructions(runtimeContext)}'
            : '# [0] System Instructions\n\n${templateBundle.systemInstructions}${_renderWorkspaceInstructions(runtimeContext)}${_renderRuntimeEnvironmentSnapshot(runtimeContext, repositorySnapshot)}',
      ),
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# [1] Developer Instructions\n\n${templateBundle.developerInstructions}',
      ),
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# [2] Tool Catalog\n\n${_renderRuntimeToolCatalog(availableTools, compact: isCompactTemplate, templateId: templateBundle.template.id, awaitingPlanApproval: session.awaitingPlanApproval, useDsmlToolCalls: useDsmlToolCalls)}',
      ),
      // For compact templates, reminders are folded into the metadata JSON
      // to reduce system message count and API overhead.
      if (todoReminder != null && !isCompactTemplate)
        AiChatTurn(
          role: AiChatRole.system,
          content: '# System Reminder\n\n$todoReminder',
        ),
      if (planModeReminder != null && !isCompactTemplate)
        AiChatTurn(
          role: AiChatRole.system,
          content: '# Plan Mode Reminder\n\n$planModeReminder',
        ),
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# [3] Session State\n\n```json\n${const JsonEncoder.withIndent('  ').convert(promptMetadata)}\n```',
      ),
      AiChatTurn(
        role: AiChatRole.system,
        // 注：记忆口吻政策（"自然融入、不外露记忆来源"）已由
        // AiPromptTemplateRepository 通过 _appendMemoryTonePolicyIfAbsent
        // 注入到 [0] System Instructions，此处不再重复长篇大论，仅留一句
        // 双语提醒兜底。
        content: isCompactTemplate
            ? '# [4] User Memory\n\n'
                  '记忆事实自然融入回答；不要外露其来源 / Integrate memory facts naturally; do not hint at their source.\n\n'
                  '${_renderUserProfileSection(memoryEntries, runtimeContext.memoryEnabled, compact: true)}'
                  '${_renderUserMemory(memoryEntries, runtimeContext.memoryEnabled)}'
            : '# [4] User Memory (long-term facts)\n\n'
                  '将下列记忆事实自然融入回答；不要在回答中提到"记忆 / 笔记 / 此前记录"等来源元叙述，把它们当作你早已掌握的常识 / '
                  'Integrate the memory facts below naturally; never mention "memory / saved notes / prior records" as a source — treat them as knowledge you already possess.\n\n'
                  '${_renderUserProfileSection(memoryEntries, runtimeContext.memoryEnabled, compact: false)}'
                  '${_renderUserMemory(memoryEntries, runtimeContext.memoryEnabled)}',
      ),
      // 2026-04-25 — 【指令】模块注入。仅在存在 enabled 且未被本轮临时
      // 取消的指令时才追加这条 system turn，避免对既有提示词布局造成
      // 任何 token 影响。
      if (_renderUserInstructionsBody(
        runtimeContext.userInstructions,
        runtimeContext.skippedInstructionIds,
      ).isNotEmpty)
        AiChatTurn(
          role: AiChatRole.system,
          content:
              '# [4.5] User Instructions\n\n'
              '以下是用户预设的可复用指令片段，视为权威项目级指引：除非与上方更高优先级的系统 / 开发者指令直接冲突，否则必须遵循。 / '
              'The blocks below are user-defined reusable prompt fragments. Treat them as authoritative project guidance — follow them unless they directly conflict with higher-priority system or developer instructions above.\n\n'
              '${_renderUserInstructionsBody(runtimeContext.userInstructions, runtimeContext.skippedInstructionIds)}',
        ),
      AiChatTurn(
        role: AiChatRole.system,
        content: isCompactTemplate
            ? '# [5] Conversation Context\n\n${_renderCompressionSummary(session, latestCompressionPoint)}'
            : '# [5] Recent Conversations Summary (past chats, titles + snippets)\n\n${_renderCompressionSummary(session, latestCompressionPoint)}',
      ),
      ...historyTurns,
      // [5.5] Focus Context — last few tool outcomes + latest-user attachments,
      // 仅在有信号时注入；用于在主 transcript 之外提供"刚才发生了什么"的高
      // 优先级简报，等价于 Warp 的 block_context（命令 + 输出 + cwd）。
      if (focusContext.isNotEmpty)
        AiChatTurn(
          role: AiChatRole.system,
          content: '# [5.5] Focus Context\n\n$focusContext',
        ),
      if (restoredFileContext.isNotEmpty)
        AiChatTurn(
          role: AiChatRole.system,
          content: '# [5.6] Restored File Context\n\n$restoredFileContext',
        ),
      if (restoredSkillContext.isNotEmpty)
        AiChatTurn(
          role: AiChatRole.system,
          content: '# [5.7] Restored Skill Context\n\n$restoredSkillContext',
        ),
      if (restoredPlanContext.isNotEmpty)
        AiChatTurn(
          role: AiChatRole.system,
          content: '# [5.8] Restored Plan Context\n\n$restoredPlanContext',
        ),
      if (restoredMcpContext.isNotEmpty)
        AiChatTurn(
          role: AiChatRole.system,
          content: '# [5.9] Restored MCP Context\n\n$restoredMcpContext',
        ),
      if (restoredSessionStartHookContext.isNotEmpty)
        AiChatTurn(
          role: AiChatRole.system,
          content:
              '# [5.10] Restored SessionStart Hook Context\n\n$restoredSessionStartHookContext',
        ),
      if (restoredToolAgentContext.isNotEmpty)
        AiChatTurn(
          role: AiChatRole.system,
          content:
              '# [5.11] Restored Tool and Agent Listing\n\n$restoredToolAgentContext',
        ),
      if (restoredAgentResultContext.isNotEmpty)
        AiChatTurn(
          role: AiChatRole.system,
          content:
              '# [5.12] Restored Agent Result Context\n\n$restoredAgentResultContext',
        ),
      ...latestUserTurns,
    ];
    final systemMessageCount = messages
        .where((item) => item.role == AiChatRole.system)
        .length;
    metadata['current_prompt_system_message_count'] = systemMessageCount;

    final promptCharacterCount = messages.fold<int>(
      0,
      (sum, item) => sum + item.promptCharacterCount,
    );
    metadata
      ..['current_prompt_character_count'] = promptCharacterCount
      ..addAll(
        _buildContextBudgetMetadata(
          model: model,
          promptCharacterCount: promptCharacterCount,
        ),
      );
    return AiPromptBuildResult(
      messages: messages,
      metadata: metadata,
      promptCharacterCount: promptCharacterCount,
      systemMessageCount: systemMessageCount,
      historyMessageCount: historyTurns.length,
    );
  }

  String _renderWorkspaceInstructions(AiSessionRuntimeContext runtimeContext) {
    final documents = runtimeContext.workspaceInstructionDocuments;
    if (documents.isEmpty) {
      return '';
    }
    final buffer = StringBuffer()
      ..writeln()
      ..writeln()
      ..writeln('# Workspace Instructions')
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
  }) {
    final estimatedPromptTokens = math.max(
      1,
      (promptCharacterCount / _contextBudgetEstimatedCharsPerToken).ceil(),
    );
    // 用户未在模型配置里填 maxContextTokens 时，回退到 128k 默认，避免
    // TopBar 上下文胶囊永远显示 “0% · 未知”。回退值仅用于 UI 估算，
    // 不影响实际拼装；通过 context_budget_window_inferred 标识。
    const int inferredMaxContextTokens = 128000;
    final configuredMaxContextTokens = model.maxContextTokens;
    final bool windowInferred =
        configuredMaxContextTokens == null || configuredMaxContextTokens <= 0;
    final int maxContextTokens = windowInferred
        ? inferredMaxContextTokens
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
      'context_budget_estimated_chars_per_token':
          _contextBudgetEstimatedCharsPerToken,
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
    final skillToolCount = availableToolNames
        .where((name) => name.startsWith('skill__'))
        .length;
    final mcpToolCount = availableToolNames
        .where((name) => name.startsWith('mcp__'))
        .length;
    final builtinToolCount =
        availableToolNames.length - skillToolCount - mcpToolCount;
    final mcpServerInstructionNames = mcpServerInstructionsByName.entries
        .where(
          (entry) =>
              entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
        )
        .map((entry) => entry.key.trim())
        .toList(growable: false);
    final sidecarMarkdownPath = _sessionCompactMemoryMarkdownPath(
      session,
      latestCompressionPoint,
    );
    final recentReadFiles = _recentReadFileAnchors(historyMessages);
    final recentInvokedSkills = _recentInvokedSkillAnchors(historyMessages);
    final recentSessionStartHooks = _recentSessionStartHookAnchors(
      historyMessages: historyMessages,
      latestCompressionPoint: latestCompressionPoint,
    );
    final recentAgentResults = _recentTaskAgentResultAnchors(
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
        runtimeContext.skippedInstructionIds,
      ).isNotEmpty)
        'user_instructions',
      if (repositorySnapshot != null) 'repository_snapshot',
      if (session.todoItems.isNotEmpty) 'todos',
      if (session.pendingPlan?.trim().isNotEmpty == true) 'pending_plan',
      if (session.planHistory.isNotEmpty) 'plan_history',
      if (_hasRestorablePlanContext(session)) 'plan_context',
      if (mcpToolCount > 0 ||
          runtimeContext.availableMcpServers.isNotEmpty ||
          mcpServerInstructionNames.isNotEmpty)
        'mcp_context',
      if (mcpServerInstructionNames.isNotEmpty) 'mcp_instructions',
      if (recentReadFiles.isNotEmpty) 'recent_read_files',
      if (recentInvokedSkills.isNotEmpty) 'invoked_skills',
      if (recentSessionStartHooks.isNotEmpty) 'session_start_hooks',
      if (recentAgentResults.isNotEmpty) 'agent_results',
      if (deferredTools.isNotEmpty) 'deferred_builtin_tools',
      if (taskAgentTypes.isNotEmpty) 'agent_listing',
    ];
    return <String, Object?>{
      'active': latestCompressionPoint != null,
      'checkpoint_message_id': latestCompressionPoint?.id,
      'checkpoint_created_at': latestCompressionPoint?.createdAt
          .toUtc()
          .toIso8601String(),
      'session_memory_sidecar_present': sidecarMarkdownPath != null,
      'session_memory_sidecar_path': sidecarMarkdownPath,
      'restored_channels': restoredChannels,
      'runtime_tool_count': availableToolNames.length,
      'builtin_tool_count': builtinToolCount,
      'skill_tool_count': skillToolCount,
      'mcp_tool_count': mcpToolCount,
      'mcp_server_count': runtimeContext.availableMcpServers.length,
      'mcp_server_instruction_count': mcpServerInstructionNames.length,
      if (runtimeContext.availableMcpServers.isNotEmpty)
        'mcp_server_names': runtimeContext.availableMcpServers
            .map((server) => server.name)
            .toList(growable: false),
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
      'recent_read_file_count': recentReadFiles.length,
      'session_start_hook_count': recentSessionStartHooks.length,
      'agent_result_count': recentAgentResults.length,
      if (recentAgentResults.isNotEmpty)
        'agent_results': recentAgentResults
            .map(
              (message) => <String, Object?>{
                'message_id': message.id,
                'created_at': message.createdAt.toUtc().toIso8601String(),
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
      if (recentReadFiles.isNotEmpty) 'recent_read_files': recentReadFiles,
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

  String _renderRuntimeEnvironmentSnapshot(
    AiSessionRuntimeContext runtimeContext,
    AiRepositorySnapshot? repositorySnapshot,
  ) {
    final workingDirectory = runtimeContext.workingDirectory.trim().isEmpty
        ? OpenHandPaths.applicationDirectoryPath()
        : runtimeContext.workingDirectory.trim();
    final buffer = StringBuffer()
      ..writeln()
      ..writeln()
      ..writeln('# Runtime Environment Snapshot')
      ..writeln()
      ..writeln('Working directory: $workingDirectory')
      ..writeln('Platform: ${runtimeContext.platformName}')
      ..writeln('Today local date: ${runtimeContext.todayLocalDate}')
      ..writeln('Time zone: ${runtimeContext.timeZoneName}')
      ..writeln(
        'Per-response tool call limit: ${runtimeContext.singleRoundToolCallLimit}',
      )
      ..writeln(
        'Sequential tool round limit: ${runtimeContext.sequentialToolRoundLimit}',
      )
      ..writeln(
        'Write command confirmation for write-like bash commands: ${runtimeContext.writeCommandConfirmationEnabled ? 'Yes - OpenHand handles the approval dialog automatically; do not ask in chat for generic shell permission first.' : 'No'}',
      );
    if (runtimeContext.allowCommandRules.isEmpty) {
      buffer.writeln('Allowed command patterns: none');
    } else {
      buffer
        ..writeln()
        ..writeln('Allowed command patterns:');
      for (final rule in runtimeContext.allowCommandRules) {
        final note = rule.note.trim();
        final noteSuffix = note.isEmpty ? '' : ' ($note)';
        buffer.writeln(
          '- ${rule.matchMode.storageValue}: ${rule.pattern}$noteSuffix',
        );
      }
    }
    final sandbox = runtimeContext.sandboxSettings;
    buffer
      ..writeln()
      ..writeln('Sandbox: ${sandbox.enabled ? 'Enabled' : 'Disabled'}');
    if (sandbox.enabled) {
      buffer
        ..writeln(
          'Sandboxed built-ins: ${sandbox.sandboxedBuiltinTools.isEmpty ? 'none' : sandbox.sandboxedBuiltinTools.join(', ')}',
        )
        ..writeln(
          'Sandbox fail-if-unavailable: ${sandbox.failIfUnavailable ? 'Yes' : 'No'}',
        )
        ..writeln(
          'Sandbox unsandboxed exclusions allowed: ${sandbox.allowUnsandboxedCommands ? 'Yes' : 'No'}',
        )
        ..writeln(
          'Sandbox auto-allow Bash writes: ${sandbox.autoAllowBashIfSandboxed ? 'Yes' : 'No'}',
        )
        ..writeln(
          'Sandbox file rules: ${sandbox.filesystemRules.map((rule) => '${rule.accessMode.storageValue}:${rule.matchMode.storageValue}:${rule.path}').join('; ')}',
        )
        ..writeln(
          'Sandbox excluded commands: ${sandbox.excludedCommands.isEmpty ? 'none' : sandbox.excludedCommands.map((rule) => '${rule.matchMode.storageValue}:${rule.pattern}').join('; ')}',
        )
        ..writeln(
          'Sandbox allowed domains: ${sandbox.allowedDomains.isEmpty ? 'none' : sandbox.allowedDomains.map((rule) => '${rule.matchMode.storageValue}:${rule.pattern}').join('; ')}',
        )
        ..writeln(
          'Sandbox denied domains: ${sandbox.deniedDomains.isEmpty ? 'none' : sandbox.deniedDomains.map((rule) => '${rule.matchMode.storageValue}:${rule.pattern}').join('; ')}',
        )
        ..writeln(
          'Sandbox proxy ports: http=${sandbox.httpProxyPort}, socks=${sandbox.socksProxyPort}',
        )
        ..writeln(
          'Sandbox domain rules use an OpenHand local filtering proxy for sandboxed commands; http=0 means an automatic temporary HTTP proxy port, socks=0 means no SOCKS entry point. On macOS, direct network access is blocked while the proxy is active. On Linux, strict mode blocks domain rules that cannot be enforced yet; if degraded execution is allowed, proxy variables are best-effort and metadata will say the domain filter is not enforced.',
        )
        ..writeln(
          'If a command is sandboxed, do not try to bypass it. Treat sandbox denial, timeout, or unavailable-dependency output as authoritative and report the exact blocker.',
        );
    }
    if (repositorySnapshot == null) {
      return buffer.toString().trimRight();
    }
    buffer.writeln(
      'Is directory a git repo: ${repositorySnapshot.isGitRepository ? 'Yes' : 'No'}',
    );
    if (!repositorySnapshot.isGitRepository) {
      return buffer.toString().trimRight();
    }
    if (repositorySnapshot.repositoryRootPath.trim().isNotEmpty) {
      buffer.writeln(
        'Repository root: ${repositorySnapshot.repositoryRootPath}',
      );
    }
    if (repositorySnapshot.currentBranch.trim().isNotEmpty) {
      buffer.writeln('Current branch: ${repositorySnapshot.currentBranch}');
    }
    if (repositorySnapshot.mainBranch.trim().isNotEmpty) {
      buffer.writeln('Main branch: ${repositorySnapshot.mainBranch}');
    }
    if (repositorySnapshot.statusSnapshot.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Status:')
        ..writeln(repositorySnapshot.statusSnapshot.trimRight());
    }
    if (repositorySnapshot.recentCommits.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Recent commits:');
      for (final commit in repositorySnapshot.recentCommits) {
        buffer.writeln('- $commit');
      }
    }
    return buffer.toString().trimRight();
  }

  /// Builds a compact metadata dict for the programming_expert template.
  ///
  /// This reduces token overhead by ~40% compared to the full metadata format:
  /// - Eliminates the `environment` duplication
  /// - Removes debug/internal fields (session timestamps, IDs, token counts)
  /// - Removes computable fields (tool count, prompt message counts)
  /// - Conditionally includes fields only when populated (git, todos, plan)
  /// - Folds system reminders (todo, plan) into metadata instead of separate
  ///   system messages, reducing per-message API overhead.
  ///
  /// 2026-04-13: Enhanced clarity for working_directory/project_root:
  /// - Renamed 'cwd' to 'working_directory' for clarity
  /// - Added 'project_root' as alias for tool path resolution context
  Map<String, Object?> _buildCompactPromptMetadata({
    required AiSession session,
    required AiSessionRuntimeContext runtimeContext,
    required AiRepositorySnapshot? repositorySnapshot,
    required List<String> availableToolNames,
    required AiModelConfig model,
    required Map<String, Object?> postCompactRehydration,
    String? todoReminder,
    String? planModeReminder,
  }) {
    final workingDirectory = runtimeContext.workingDirectory.trim().isEmpty
        ? OpenHandPaths.applicationDirectoryPath()
        : runtimeContext.workingDirectory.trim();

    final compact = <String, Object?>{
      'session': <String, Object?>{
        'title': session.title,
        'mode': session.mode.storageValue,
      },
      // 2026-04-13: Use explicit field names for AI clarity
      'context': <String, Object?>{
        'working_directory': workingDirectory,
        'project_root': workingDirectory, // Alias for tool path resolution
        'platform': runtimeContext.platformName,
        'date': runtimeContext.todayLocalDate,
        'timezone': runtimeContext.timeZoneName,
      },
      'limits': <String, Object?>{
        'tools_per_round': runtimeContext.singleRoundToolCallLimit,
        'rounds': runtimeContext.sequentialToolRoundLimit,
      },
      'tools': availableToolNames,
      'rehydration': postCompactRehydration,
      if (runtimeContext.writeCommandConfirmationEnabled)
        'write_cmd_confirm': true,
    };

    if (repositorySnapshot != null && repositorySnapshot.isGitRepository) {
      final gitInfo = <String, Object?>{};
      if (repositorySnapshot.currentBranch.trim().isNotEmpty) {
        gitInfo['branch'] = repositorySnapshot.currentBranch;
      }
      if (repositorySnapshot.mainBranch.trim().isNotEmpty) {
        gitInfo['main'] = repositorySnapshot.mainBranch;
      }
      if (repositorySnapshot.statusSnapshot.trim().isNotEmpty) {
        gitInfo['status'] = repositorySnapshot.statusSnapshot.trim();
      }
      if (repositorySnapshot.recentCommits.isNotEmpty) {
        gitInfo['recent_commits'] = repositorySnapshot.recentCommits;
      }
      if (gitInfo.isNotEmpty) {
        compact['git'] = gitInfo;
      }
    }

    if (session.todoItems.isNotEmpty) {
      compact['todos'] = session.todoItems
          .map((item) => item.toJson())
          .toList(growable: false);
    }

    if (session.mode == AiSessionMode.plan || session.awaitingPlanApproval) {
      compact['plan'] = <String, Object?>{
        'active': session.mode == AiSessionMode.plan,
        'awaiting_approval': session.awaitingPlanApproval,
        if (session.pendingPlan != null &&
            session.pendingPlan!.trim().isNotEmpty)
          'pending_plan': session.pendingPlan!.trim(),
      };
    }

    if (runtimeContext.allowCommandRules.isNotEmpty) {
      compact['allow_cmd_rules'] = runtimeContext.allowCommandRules
          .map((rule) {
            final note = rule.note.trim();
            return note.isEmpty
                ? '${rule.matchMode.storageValue}:${rule.pattern}'
                : '${rule.matchMode.storageValue}:${rule.pattern} ($note)';
          })
          .toList(growable: false);
    }

    if (runtimeContext.workspaceInstructionDocuments.isNotEmpty) {
      compact['workspace_instructions'] = runtimeContext
          .workspaceInstructionDocuments
          .map((item) => item.path)
          .toList(growable: false);
    }

    // Fold system reminders into metadata so they don't require separate
    // system messages, saving per-turn API overhead.
    if (todoReminder != null && todoReminder.isNotEmpty) {
      compact['system_reminder'] = todoReminder;
    }
    if (planModeReminder != null && planModeReminder.isNotEmpty) {
      compact['plan_reminder'] = planModeReminder;
    }

    return compact;
  }

  String _renderRuntimeToolCatalog(
    List<AiToolDefinition> availableTools, {
    bool compact = false,
    String? templateId,
    bool awaitingPlanApproval = false,
    bool useDsmlToolCalls = false,
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
    final visibleToolCount =
        skillTools.length + mcpTools.length + builtinTools.length;
    if (visibleToolCount == 0) {
      // 2026-04-27: 在计划模式待批准的轮次，工具目录被主动清空。
      // 原状下模型容易以为“什么工具都没有”而拒绝实现。
      // 为该场景提供明确提示，避免模型谎称工具缺失。
      if (awaitingPlanApproval) {
        return 'Tool catalog is intentionally empty for this turn because the system is waiting for the user to approve your plan. Present the captured plan and ask for confirmation. As soon as the user endorses it (English or Chinese, e.g. "do it", "ship it", "去写吧", "去做吧"), the next turn will restore the full execution toolkit (Write, Edit, MultiEdit, Bash, etc.) automatically. Never tell the user that Write/Edit do not exist — the tools simply have not been re-enabled yet.';
      }
      return 'No runtime tools are available in this response. Do not invent tool names or assume a tool exists because it existed in an earlier turn.';
    }
    // 2026-04-08 工具目录按能力优先级分组呈现：Skill > MCP > Builtin
    // resolveCatalog 已按此顺序注册，definitions 列表天然有序。
    // 此处进一步添加分组标题，让模型在阅读时明确优先级语义。
    // 2026-04-21 对机器专家线程模板，内建终端交互主流程拥有绝对最高优先级；
    // 外部 Skill / MCP 仅可作为辅助知识来源，不得替代目标终端执行入口。
    final isMachineExpert = templateId == 'machine_expert';
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
      } else {
        buffer.writeln(
          'Capability invocation priority: Skill > MCP > Builtin. '
          'When a task matches an available skill, use the skill tool first. '
          'If no skill matches but a relevant MCP tool exists, prefer the MCP tool. '
          'Fall back to builtin tools only when neither a matching skill nor a suitable MCP tool is available.',
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
                    : '## Skill Tools (highest priority)'),
        );
      for (final tool in skillTools) {
        _renderToolEntry(buffer, tool, compact: compact);
      }
    }
    // MCP lazy loading banner: when ToolSearch carries a "## Deferred MCP
    // tools (N)" subsection in its description, surface a one-line notice so
    // the model knows MCP descriptions are intentionally folded.
    final toolSearch = builtinTools.firstWhere(
      (tool) => tool.name == 'ToolSearch',
      orElse: () => const AiToolDefinition(
        name: '',
        description: '',
        parameters: <String, Object?>{},
      ),
    );
    final deferredMatch = toolSearch.name.isEmpty
        ? null
        : RegExp(
            r'## Deferred MCP tools \((\d+)\)',
          ).firstMatch(toolSearch.description);
    if (deferredMatch != null) {
      buffer
        ..writeln()
        ..writeln(
          compact
              ? '## MCP (lazy)'
              : '## MCP Tools (lazy-loaded — descriptions deferred)',
        )
        ..writeln(
          'MCP tool descriptions for ${deferredMatch.group(1)} tool(s) are '
          'folded to save context. Names + one-line summaries live inside the '
          '`ToolSearch` tool description below. To use any deferred MCP tool, '
          'first call `ToolSearch` with `select:<exact_name>` (multi-select '
          'supported, e.g. `select:mcp__a__b mcp__c__d`) or with a keyword '
          'query — the runtime will inject full JSONSchema and the tool '
          'becomes callable from the next turn onward. Do NOT invent MCP '
          'tool names; pick from the deferred list.',
        );
    }
    if (mcpTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(compact ? '## MCP' : '## MCP Tools (medium priority)');
      for (final tool in mcpTools) {
        _renderToolEntry(buffer, tool, compact: compact);
      }
    }
    if (builtinTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(compact ? '## Builtin' : '## Builtin Tools (baseline)');
      for (final tool in builtinTools) {
        // 2026-04-26: Render builtin tools with their full description and
        // required-args list even in compact mode. Some reasoner models
        // (e.g. deepseek-expert-reasoner) ignore the API-level tools array
        // and rely solely on the system-prompt catalog; the previous
        // ultra-compact 80-char form caused the model to deny the existence
        // of tools like Write/Edit on the very first turn.
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
    final normalized = description
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\.\s*\.'), '.');
    if (normalized.length <= maxCharacters) {
      return normalized;
    }
    return '${normalized.substring(0, maxCharacters).trimRight()}...';
  }

  List<String> _toolArgumentNames(
    Map<String, Object?> parameters, {
    required bool requiredOnly,
  }) {
    final propertiesValue = parameters['properties'];
    if (propertiesValue is! Map && propertiesValue is! Map<String, Object?>) {
      return const <String>[];
    }
    final properties = propertiesValue is Map<String, Object?>
        ? propertiesValue
        : Map<String, Object?>.from(propertiesValue as Map);
    final requiredValue = parameters['required'];
    final requiredNames = requiredValue is List
        ? requiredValue
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
        : const <String>{};
    return properties.keys
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .where(
          (item) => requiredOnly
              ? requiredNames.contains(item)
              : !requiredNames.contains(item),
        )
        .toList(growable: false);
  }

  List<AiChatTurn> _mapMessageContent({
    required AiChatRole role,
    required String content,
    String? toolCallId,
    List<AiToolCall> toolCalls = const <AiToolCall>[],
    List<AiChatContentPart> parts = const <AiChatContentPart>[],
    String? reasoningContent,
  }) {
    final extracted = _extractSystemReminders(content);
    final turns = extracted.reminders
        .map(
          (reminder) => AiChatTurn(
            role: AiChatRole.system,
            content: '# System Reminder\n\n$reminder',
          ),
        )
        .toList(growable: true);
    if (extracted.content.trim().isEmpty && toolCalls.isEmpty) {
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

  _ExtractedReminderContent _extractSystemReminders(String content) {
    final reminderPattern = RegExp(
      r'<system-reminder>([\s\S]*?)</system-reminder>',
      caseSensitive: false,
    );
    final reminders = reminderPattern
        .allMatches(content)
        .map((match) => (match.group(1) ?? '').trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final stripped = content
        .replaceAll(reminderPattern, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
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
    final isProgrammingExpert = template.id == 'programming_expert';
    final payload = <String, Object?>{
      'session_title': session.title,
      'template_name': template.name,
      if (!isProgrammingExpert) 'session_id': session.id,
      if (!isProgrammingExpert) 'template_id': template.id,
      'locale_tag': runtimeContext.localeTag,
      if (!isProgrammingExpert)
        'compression_threshold_chars': runtimeContext.compressionThresholdChars,
      'previous_checkpoint_present': previousCompressionPoint != null,
      'messages_to_compress_count': messagesToCompress.length,
      'user_message_count': messagesToCompress
          .where((message) => message.kind == AiSessionMessageKind.user)
          .length,
    };
    final userMessageManifest = _renderCompressionUserMessageManifest(
      messagesToCompress,
    );
    final resourceManifest = _renderCompressionResourceManifest(
      messagesToCompress,
    );
    final transcript = messagesToCompress
        .map(
          (message) =>
              '- [${message.createdAt.toIso8601String()}][${message.role.storageValue}][${message.kind.storageValue}] ${_renderMessageForCompression(message)}',
        )
        .join('\n');
    final previousCheckpointText = previousCompressionPoint == null
        ? 'No earlier checkpoint.'
        : _boundedCheckpointPromptView(previousCompressionPoint.content);
    final compressionSystemContent = _compressionSystemInstructionsForTemplate(
      template,
    );
    return <AiChatTurn>[
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# Compression System Instructions\n\n$compressionSystemContent',
      ),
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# Compression Developer Instructions\n\n${templateBundle.compressionSummaryInstructions}',
      ),
      AiChatTurn(
        role: AiChatRole.user,
        content:
            '# Compression Task Payload\n\n```json\n${const JsonEncoder.withIndent('  ').convert(payload)}\n```\n\n## Previous Checkpoint\n\n$previousCheckpointText${userMessageManifest.isEmpty ? '' : '\n\n## User Messages Manifest\n\n$userMessageManifest'}${resourceManifest.isEmpty ? '' : '\n\n## Resource Recovery Manifest\n\n$resourceManifest'}\n\n## Messages To Compress\n\n$transcript',
      ),
    ];
  }

  String _compressionSystemInstructionsForTemplate(AiThreadTemplate template) {
    final identity = switch (template.id) {
      'machine_expert' =>
        'You are OpenHand Machine Expert. Produce a relay-safe terminal interaction checkpoint.',
      'hardness_engineering' =>
        'You are OpenHand Hardness Engineering. Produce a relay-safe orchestration checkpoint.',
      'programming_expert' =>
        'You are OpenHand Programming Expert. Produce a relay-safe coding checkpoint.',
      'hermes_talker' =>
        'You are OpenHand Hermes Talker. Produce a relay-safe assistant checkpoint.',
      _ => 'You are OpenHand. Produce a relay-safe conversation checkpoint.',
    };
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
    _ToolCompressionConfig compressionConfig,
  ) {
    final turns = <AiChatTurn>[];
    var index = 0;
    String? roundReasoning;
    // 2026-04-27 (修复): 找出"已被模型消费"的边界。任何 assistant /
    // toolCall 消息都意味着模型已经基于之前的工具结果产出了下一步动作；
    // 因此 index 大于 `lastConsumerIndex` 的 tool 结果属于尚未被消费的
    // 最新一轮，需在 prompt 中保留原文，避免被压缩成 head/tail 摘要后
    // 让模型在"首次看到该结果"时就丢掉关键信息。
    var lastConsumerIndex = -1;
    for (var i = 0; i < messages.length; i++) {
      final kind = messages[i].kind;
      if (kind == AiSessionMessageKind.assistant ||
          kind == AiSessionMessageKind.toolCall) {
        lastConsumerIndex = i;
      }
    }
    final microCompactMessageIds = _microCompactToolMessageIds(
      messages,
      lastConsumerIndex,
    );
    while (index < messages.length) {
      final message = messages[index];
      if (message.kind == AiSessionMessageKind.reasoning) {
        // A new reasoning block starts a new "thinking round". Buffer it
        // and attach to every assistant / toolCall turn that follows
        // until either the next reasoning block or the next user message
        // closes the round. This is required by thinking-mode gateways
        // (e.g. `deepseek-v4-pro`) that reject follow-up requests when
        // the prior chain-of-thought is dropped from any assistant
        // message in the round (content message AND tool_calls message
        // both need it because we split a single API response into two
        // session entries).
        final trimmed = message.content.trim();
        roundReasoning = trimmed.isEmpty ? null : trimmed;
        index += 1;
        continue;
      }
      if (message.kind == AiSessionMessageKind.user) {
        // User message ends the previous thinking round.
        roundReasoning = null;
      }
      if (message.kind == AiSessionMessageKind.toolCall) {
        final mappedGroup = _mapToolExchange(
          messages,
          index,
          session,
          model,
          compressionConfig,
          lastConsumerIndex: lastConsumerIndex,
          microCompactMessageIds: microCompactMessageIds,
        );
        if (mappedGroup.turns.isNotEmpty) {
          turns.addAll(
            _attachReasoningToAssistantTurns(mappedGroup.turns, roundReasoning),
          );
        }
        index = mappedGroup.nextIndex;
        continue;
      }
      if (_isToolResultKind(message.kind)) {
        index += 1;
        continue;
      }
      final mapped = _mapNonToolHistoryMessage(
        message,
        session,
        model,
        compressionConfig,
        messageIndex: index,
        lastConsumerIndex: lastConsumerIndex,
        microCompactMessageIds: microCompactMessageIds,
      );
      if (mapped.isNotEmpty) {
        turns.addAll(_attachReasoningToAssistantTurns(mapped, roundReasoning));
      }
      index += 1;
    }
    return turns;
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
    required Set<String> microCompactMessageIds,
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
              microCompactMessageIds: microCompactMessageIds,
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
          microCompactMessageIds: microCompactMessageIds,
        ),
        nextIndex: startIndex + 1,
      );
    }
    final toolMessagesByCallId = <String, AiSessionMessage>{};
    final toolMessageIndexByCallId = <String, int>{};
    while (cursor < messages.length &&
        _isToolResultKind(messages[cursor].kind)) {
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
    for (final toolCall in groupedToolCalls) {
      final toolMessage = toolMessagesByCallId[toolCall.id]!;
      final toolMessageIndex = toolMessageIndexByCallId[toolCall.id]!;
      turns.addAll(
        _mapMessageContent(
          role: AiChatRole.tool,
          toolCallId: toolCall.id,
          content: _promptHistoryToolResultContent(
            toolMessage,
            compressionConfig,
            isFreshUnconsumedResult: toolMessageIndex > lastConsumerIndex,
            isMicroCompactCleared: microCompactMessageIds.contains(
              toolMessage.id,
            ),
          ),
        ),
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
    required Set<String> microCompactMessageIds,
  }) {
    final promptContent = _promptContentForMessage(message);
    switch (message.kind) {
      case AiSessionMessageKind.user:
        return _mapUserMessage(
          message,
          session: session,
          model: model,
          content: promptContent,
        );
      case AiSessionMessageKind.assistant:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: promptContent,
        );
      case AiSessionMessageKind.toolCall:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: _promptHistoryStandaloneToolCallContent(message),
        );
      case AiSessionMessageKind.tool:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: _promptHistoryToolResultContent(
            message,
            compressionConfig,
            isFreshUnconsumedResult: messageIndex > lastConsumerIndex,
            isMicroCompactCleared: microCompactMessageIds.contains(message.id),
          ),
        );
      case AiSessionMessageKind.mcp:
      case AiSessionMessageKind.skill:
      case AiSessionMessageKind.hook:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: '[${message.kind.storageValue}] $promptContent',
        );
      case AiSessionMessageKind.compressionPoint:
      case AiSessionMessageKind.fileMutationSummary:
      case AiSessionMessageKind.status:
        return _mapMessageContent(
          role: AiChatRole.system,
          content: '[${message.kind.storageValue}] $promptContent',
        );
      case AiSessionMessageKind.selfLearning:
        // Self-learning cards are audit artefacts produced AFTER the fact by
        // the background runner; their content is not intended as context
        // for the main model (it bloats the prompt and can confuse the
        // assistant into talking about the self-learning process). Drop
        // them from history entirely.
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
  }) {
    return _mapMessageContent(
      role: AiChatRole.user,
      content: content,
      parts: _attachmentPartsForMessage(
        message,
        session,
        model,
        isLatestUserMessage: isLatestUserMessage,
      ),
    );
  }

  String _promptContentForMessage(AiSessionMessage message) {
    final buffer = StringBuffer(message.content.trim());
    final hookReminders = _readStringList(
      message.metadata[aiHookSystemRemindersMetadataKey],
    );
    for (final reminder in hookReminders) {
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
    return buffer.toString().trim();
  }

  List<AiChatContentPart> _attachmentPartsForMessage(
    AiSessionMessage message,
    AiSession session,
    AiModelConfig model, {
    bool isLatestUserMessage = false,
  }) {
    final attachments = _readAttachments(message.metadata);
    if (attachments.isEmpty) {
      return const <AiChatContentPart>[];
    }
    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    final supportsInlineImages = adapter.supportsAttachmentsForModel(model);
    final parts = <AiChatContentPart>[];
    for (final attachment in attachments) {
      if (attachment.isImage) {
        // For non-latest historical user messages we replace the inline
        // image with a structured text placeholder. This keeps token usage
        // bounded while preserving the metadata + AI-generated summary so
        // later turns can reason about the image.
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
            FileSystemEntity.typeSync(storagePath, followLinks: false) ==
                FileSystemEntityType.file &&
            File(storagePath).existsSync();
        final detailText = summaryText.isNotEmpty ? summaryText : promptText;
        // Always expose the attachment id so the assistant can emit a matching
        // <image_summary attachment_id="..."> block per the prompt contract.
        // The `id=...` token mirrors the format used inside historical
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
          // The current model does not support inline image content.
          // Provide a clear note so the AI does not hallucinate about the
          // image and the user can understand why the response is off.
          const modelWarning =
              '[⚠️ 当前模型不支持直接查看图片内容，无法分析此图片。'
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
      final promptText = attachment.promptText.trim();
      if (promptText.isEmpty) {
        continue;
      }
      parts.add(AiChatContentPart.text(promptText));
    }
    return parts;
  }

  /// Builds the textual placeholder used for image attachments on
  /// historical (non-latest) user messages.
  ///
  /// Format (matches the user-facing spec):
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
    // Legacy layout: {sessionsDir}/attachments/{sessionId}/{messageId}/file
    final legacyRoot = p.normalize(
      p.join(sessionsDirectoryPath, 'attachments', sessionId),
    );
    if (p.isWithin(legacyRoot, normalizedStoragePath)) {
      return true;
    }
    // Modern layout: {sessionsDir}/{sessionId}/attachments/file
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
      final readPath = '${metadata['read_file_path'] ?? ''}'.trim();
      if (lines.length < _compressionResourceManifestMaxItems &&
          readPath.isNotEmpty &&
          seen.add('file:$readPath')) {
        final attributes = <String>[
          'file',
          'message_id=${message.id}',
          if ('${metadata['read_file_kind'] ?? ''}'.trim().isNotEmpty)
            'kind=${metadata['read_file_kind']}',
          if ('${metadata['read_render_mode'] ?? ''}'.trim().isNotEmpty)
            'render=${metadata['read_render_mode']}',
          if (metadata['read_truncated'] == true) 'truncated=true',
        ];
        lines.add('- ${attributes.join(' · ')} · $readPath');
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
      final readPath = '${metadata['read_file_path'] ?? ''}'.trim();
      if (readPath.isNotEmpty) {
        seen.add('file:$readPath');
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
    final head = content.substring(0, maxChars).trimRight();
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
        .substring(0, _compressionAttachmentDetailMaxChars)
        .trimRight();
    final omitted = trimmed.length - head.length;
    return '$head\n[attachment_content_truncated: omitted $omitted chars]';
  }

  List<AiMessageAttachment> _readAttachments(Map<String, Object?> metadata) {
    return AiMessageAttachment.listFromMetadata(
      metadata[aiSessionMessageAttachmentsMetadataKey],
    );
  }

  String _renderUserMemory(
    List<UserMemoryEntry> memoryEntries,
    bool memoryEnabled,
  ) {
    if (!memoryEnabled) {
      return 'Memory is disabled for the current runtime request.';
    }
    // 2026-04-25: 用户画像由专门的 [User Profile] 段单独渲染（见
    // [_renderUserProfileSection]），此处需要排除掉 user_profile 条目，
    // 以免在系统提示中重复出现同一段画像内容。
    final filtered = memoryEntries
        .where((e) => e.type != UserMemoryEntry.userProfileType)
        .toList(growable: false);
    if (filtered.isEmpty) {
      return 'No saved user memory entries.';
    }
    return filtered
        .map((entry) {
          final tags = entry.tags.isEmpty
              ? ''
              : ' (tags: ${entry.tags.join(', ')})';
          return '- ${entry.content}$tags';
        })
        .join('\n');
  }

  /// 渲染用户画像独立子段。当 user_profile 为空 / memory 被关闭时返回空字符串
  /// （连同后续 `_renderUserMemory` 一起就只剩通用记忆段，不破坏原有结构）。
  ///
  /// 紧凑模板下省略冗长的解释性文字以节省 token；完整模板下提供更明确的指
  /// 引，告知模型该段是稳定的长期画像，应当无痕融入回复风格。
  String _renderUserProfileSection(
    List<UserMemoryEntry> memoryEntries,
    bool memoryEnabled, {
    required bool compact,
  }) {
    if (!memoryEnabled) return '';
    UserMemoryEntry? profile;
    for (final entry in memoryEntries) {
      if (entry.type == UserMemoryEntry.userProfileType) {
        profile = entry;
        break;
      }
    }
    final content = profile?.content.trim() ?? '';
    if (content.isEmpty) return '';
    if (compact) {
      return '## User Profile\n$content\n\n';
    }
    return '## User Profile\n'
        'The following describes the user\'s stable long-term preferences, '
        'communication style, and focus areas. Treat this as the baseline '
        'persona context for the entire conversation: every reply should '
        'feel naturally aligned with this profile (tone, depth, vocabulary, '
        'topics of interest), without ever paraphrasing or referencing the '
        'profile itself.\n\n'
        '$content\n\n';
  }

  /// 渲染【指令】模块正文。仅返回正文，不包含 section header / 提示文本，
  /// 用于在 system turn 模板里被原位 interpolated。返回空串表示当前没有
  /// 任何应当注入的指令（外层会跳过整个 turn）。
  String _renderUserInstructionsBody(
    List<UserInstructionEntry> instructions,
    Set<String> skippedIds,
  ) {
    if (instructions.isEmpty) return '';
    final visible = instructions
        .where((entry) => entry.enabled && !skippedIds.contains(entry.id))
        .toList(growable: false);
    if (visible.isEmpty) return '';
    final buf = StringBuffer();
    for (int i = 0; i < visible.length; i++) {
      final entry = visible[i];
      final body = entry.body.trim();
      if (body.isEmpty) continue;
      final name = entry.name.trim().isEmpty
          ? 'Instruction'
          : entry.name.trim();
      buf.writeln('## ${i + 1}. $name (v${entry.version})');
      if (entry.description.trim().isNotEmpty) {
        buf.writeln('_${entry.description.trim()}_');
      }
      if (entry.applyTo.trim().isNotEmpty) {
        buf.writeln('- applyTo: ${entry.applyTo.trim()}');
      }
      if (entry.taskTypes.isNotEmpty) {
        buf.writeln('- taskTypes: ${entry.taskTypes.join(", ")}');
      }
      if (entry.keywords.isNotEmpty) {
        buf.writeln('- keywords: ${entry.keywords.join(", ")}');
      }
      buf
        ..writeln()
        ..writeln(body)
        ..writeln();
    }
    return buf.toString();
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
    final head = trimmed.substring(0, _checkpointPromptEdgeChars).trimRight();
    final tail = trimmed
        .substring(trimmed.length - _checkpointPromptEdgeChars)
        .trimLeft();
    final omitted = trimmed.length - head.length - tail.length;
    return '''$head

[checkpoint_middle_omitted]
This durable checkpoint is ${trimmed.length} characters. The middle $omitted characters were omitted from this prompt view to keep post-compact context bounded. Preserve concrete facts from the visible head/tail; if exact omitted detail is needed, inspect the persisted session checkpoint.

$tail''';
  }

  /// Builds a compact "what just happened" digest for the LLM:
  /// - the last up-to-3 tool / skill / mcp result messages from history
  /// - any file paths and image attachments on the latest user message
  ///
  /// Returns an empty string when there is nothing salient to surface, so the
  /// caller can skip injecting the system turn entirely.
  String _renderFocusContext({
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage? latestUserMessage,
  }) {
    final lines = <String>[];

    // Recent tool outcomes (most recent last).
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
        final pathHint =
            '${message.metadata['file_mutation_path'] ?? message.metadata['read_file_path'] ?? ''}'
                .trim();
        final snippet = _firstNonEmptyLine(message.content, 160);
        final descriptor = <String>[
          toolName,
          if (status.isNotEmpty) 'status=$status',
          if (command.isNotEmpty) 'cmd=${_truncate(command, 60)}',
          if (pathHint.isNotEmpty) 'path=$pathHint',
        ].join(' · ');
        lines.add('- $descriptor');
        if (snippet.isNotEmpty) {
          lines.add('  └─ $snippet');
        }
      }
    }

    final recentReadFiles = _recentReadFileAnchors(historyMessages);
    if (recentReadFiles.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('## Recent read files (post-compact restore anchors)');
      for (final item in recentReadFiles) {
        final path = '${item['path'] ?? ''}'.trim();
        final fileKind = '${item['file_kind'] ?? ''}'.trim();
        final renderMode = '${item['render_mode'] ?? ''}'.trim();
        final truncated = item['truncated'] == true;
        final details = <String>[
          if (fileKind.isNotEmpty) 'kind=$fileKind',
          if (renderMode.isNotEmpty) 'mode=$renderMode',
          if (truncated) 'truncated=true',
        ].join(' · ');
        lines.add(details.isEmpty ? '- $path' : '- $path · $details');
      }
    }

    // Latest user message attachments / referenced paths.
    if (latestUserMessage != null) {
      final attachments = latestUserMessage.metadata['attachments'];
      if (attachments is List && attachments.isNotEmpty) {
        final descriptors = <String>[];
        for (final raw in attachments) {
          if (raw is! Map) continue;
          final entry = Map<String, Object?>.from(raw);
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

  List<Map<String, Object?>> _recentReadFileAnchors(
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
      final path = '${message.metadata['read_file_path'] ?? ''}'.trim();
      if (path.isEmpty || !seenPaths.add(path)) {
        continue;
      }
      anchors.add(<String, Object?>{
        'path': path,
        'message_id': message.id,
        'created_at': message.createdAt.toUtc().toIso8601String(),
        if ('${message.metadata['read_file_kind'] ?? ''}'.trim().isNotEmpty)
          'file_kind': '${message.metadata['read_file_kind']}',
        if ('${message.metadata['read_render_mode'] ?? ''}'.trim().isNotEmpty)
          'render_mode': '${message.metadata['read_render_mode']}',
        if (message.metadata['read_truncated'] == true) 'truncated': true,
      });
    }
    return anchors.reversed.toList(growable: false);
  }

  String _renderPostCompactRestoredFileContext({
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage? latestCompressionPoint,
  }) {
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
    final anchors = _recentReadFileAnchors(preCheckpointMessages);
    if (anchors.isEmpty) {
      return '';
    }

    final sections = <String>[];
    var usedChars = 0;
    for (final anchor in anchors) {
      if (usedChars >= _postCompactRestoreTotalChars) {
        break;
      }
      final path = '${anchor['path'] ?? ''}'.trim();
      if (path.isEmpty) {
        continue;
      }
      final restored = _tryReadPostCompactRestoredFile(path);
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
      final metadata = <String>[
        if (fileKind.isNotEmpty) 'kind=$fileKind',
        if (renderMode.isNotEmpty) 'last_read_mode=$renderMode',
      ].join(' · ');
      sections.add('''## $path${metadata.isEmpty ? '' : ' · $metadata'}

```text
$content
```''');
    }
    if (sections.isEmpty) {
      return '';
    }
    return 'Recent files restored after compaction. These are bounded snapshots of files previously read before the latest checkpoint.\n\n${sections.join('\n\n')}';
  }

  String? _tryReadPostCompactRestoredFile(String path) {
    try {
      final file = File(path);
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file ||
          stat.size <= 0 ||
          stat.size > _postCompactRestoreMaxFileBytes) {
        return null;
      }
      return _truncateRestoredFileContent(
        file.readAsStringSync(),
        _postCompactRestoreMaxCharsPerFile,
      );
    } catch (error, stackTrace) {
      silentLog(
        'AiPromptBuilder',
        'tryReadPostCompactRestoredFile',
        error,
        stackTrace,
      );
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
    final head = content.substring(0, maxChars).trimRight();
    final omitted = content.length - head.length;
    return '$head\n[$marker: omitted $omitted chars]';
  }

  String _renderPostCompactRestoredSkillContext({
    required List<AiSessionMessage> historyMessages,
    required AiSessionRuntimeContext runtimeContext,
    required AiSessionMessage? latestCompressionPoint,
  }) {
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
      final restored = _tryReadPostCompactRestoredSkill(skill);
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
    if (sections.isEmpty) {
      return '';
    }
    return 'Skills restored after compaction. These are bounded snapshots of skills invoked before the latest checkpoint.\n\n${sections.join('\n\n')}';
  }

  String? _tryReadPostCompactRestoredSkill(LocalSkill skill) {
    try {
      final manifestFile = File(skill.manifestPath);
      final stat = manifestFile.statSync();
      if (stat.type != FileSystemEntityType.file ||
          stat.size <= 0 ||
          stat.size > _postCompactRestoreMaxFileBytes) {
        return null;
      }
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
        ..writeln(manifestFile.readAsStringSync().trimRight());
      return _truncateRestoredFileContent(
        buffer.toString().trimRight(),
        _postCompactRestoreMaxSkillChars,
      );
    } catch (error, stackTrace) {
      silentLog(
        'AiPromptBuilder',
        'tryReadPostCompactRestoredSkill',
        error,
        stackTrace,
      );
      return null;
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

  String _renderPostCompactRestoredAgentResultContext({
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage? latestCompressionPoint,
  }) {
    final agentResults = _recentTaskAgentResultAnchors(
      historyMessages: historyMessages,
      latestCompressionPoint: latestCompressionPoint,
    );
    if (agentResults.isEmpty) {
      return '';
    }
    final buffer = StringBuffer()
      ..writeln(
        'Background agent results restored after compaction. Treat these as completed Task/subagent observations that may no longer be present in the compressed transcript.',
      );
    for (final message in agentResults) {
      final metadata = message.metadata;
      final subagentType = '${metadata['subagent_type'] ?? ''}'.trim();
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
        ..writeln('## ${subagentType.isEmpty ? 'Task Subagent' : subagentType}')
        ..writeln('- message_id: ${message.id}')
        ..writeln(
          '- created_at: ${message.createdAt.toUtc().toIso8601String()}',
        );
      if (status.isNotEmpty) {
        buffer.writeln('- status: $status');
      }
      if (command.isNotEmpty) {
        buffer.writeln('- command: ${_truncate(command, 160)}');
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

  List<AiSessionMessage> _recentTaskAgentResultAnchors({
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
      if (_isTaskAgentResultMessage(message)) {
        results.add(message);
      }
    }
    return results.reversed.toList(growable: false);
  }

  bool _isTaskAgentResultMessage(AiSessionMessage message) {
    if (message.kind != AiSessionMessageKind.tool) {
      return false;
    }
    final toolName = '${message.metadata['tool_name'] ?? ''}'.trim();
    final subagentType = '${message.metadata['subagent_type'] ?? ''}'.trim();
    final isolated = message.metadata['subagent_session_isolated'] == true;
    return toolName == 'Task' || (subagentType.isNotEmpty && isolated);
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
    final tools = resolvedToolsByName.values
        .where(
          (tool) =>
              tool.source == AiRuntimeToolSource.builtin &&
              tool.name.trim().isNotEmpty &&
              tool.builtinConfig?.loadStrategy != null &&
              tool.builtinConfig!.loadStrategy !=
                  AiBuiltinToolLoadStrategy.eager,
        )
        .toList(growable: false);
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
    for (final tool in resolvedToolsByName.values) {
      if (tool.source == AiRuntimeToolSource.builtin &&
          tool.builtinKind == AiBuiltinToolKind.task &&
          tool.name.trim().isNotEmpty) {
        return tool.name.trim();
      }
    }
    for (final name in availableToolNames) {
      if (name == 'Task') {
        return name;
      }
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
    required List<AiToolDefinition> availableTools,
    required Map<String, String> mcpServerInstructionsByName,
    required AiSessionMessage? latestCompressionPoint,
  }) {
    if (latestCompressionPoint == null) {
      return '';
    }
    final mcpTools = availableTools
        .where((tool) => tool.name.trim().startsWith('mcp__'))
        .toList(growable: false);
    final servers = runtimeContext.availableMcpServers
        .where((server) => server.name.trim().isNotEmpty)
        .toList(growable: false);
    final serverInstructionsByName = <String, String>{
      for (final entry in mcpServerInstructionsByName.entries)
        if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
          entry.key.trim(): entry.value.trim(),
    };
    if (mcpTools.isEmpty &&
        servers.isEmpty &&
        serverInstructionsByName.isEmpty) {
      return '';
    }

    final serverTokens = servers
        .map((server) => _normalizeMcpToolToken('mcp__${server.name}'))
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
        final serverToken = _normalizeMcpToolToken('mcp__${server.name}');
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
    for (final serverToken in knownServerTokens) {
      if (toolName.startsWith('${serverToken}__')) {
        return serverToken;
      }
    }
    final parts = toolName.trim().split('__');
    if (parts.length < 3 || parts.first != 'mcp') {
      return '';
    }
    return 'mcp__${parts[1]}';
  }

  String _normalizeMcpToolToken(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? 'tool' : sanitized;
  }

  String _firstNonEmptyLine(String text, int maxChars) {
    for (final raw in text.split('\n')) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      return _truncate(trimmed, maxChars);
    }
    return '';
  }

  String _truncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}…';
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
    final arguments = _decodeToolArgumentsMap(toolCall.arguments);
    final targetPath = _toolCallTargetPath(arguments);
    // 2026-04-27 (修复): Bash 命令体不再被丢弃；仅原生 Write/Edit 系列工具
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
    bool isMicroCompactCleared = false,
  }) {
    if (!compressionConfig.enabled) {
      // 2026-04-27: 总开关关闭时直接返回原始内容，不作压缩。
      return _promptContentForMessage(message);
    }
    if (isFreshUnconsumedResult) {
      // 2026-04-27 (修复): 最新一轮工具调用的结果是即将交给模型 *首次*
      // 消费的内容（例如它刚 Read 完一个文件，准备据此回答）。这一轮的
      // 内容若被压缩成 head/tail 摘要，模型就拿不到必要的原始数据，
      // 会被迫凭空猜测或反复重试。仅对"已被模型消费过"的历史轮次
      // 启用压缩，未消费的最新一轮始终保留原文。
      return _promptContentForMessage(message);
    }
    if (isMicroCompactCleared) {
      return _microCompactToolResultContent(message);
    }
    if (!_isWriteLikeToolHistoryMessage(message)) {
      // 2026-04-27: 通用工具调用结果压缩。当工具返回内容超过阈值时，
      // 提炼受影响文件路径 + 行号 + 工具自述目的（purpose/intent/goal/
      // description/reason），保留首尾片段作为结构性补充信息，避免
      // conversation history 被海量原文淹没。
      return _compressGenericToolResultContent(message, compressionConfig);
    }
    final metadata = message.metadata;
    final toolName = '${metadata['tool_name'] ?? ''}'.trim();
    final status =
        '${metadata['status'] ?? metadata['tool_execution_status'] ?? ''}'
            .trim();
    final mutationKind = '${metadata['file_mutation_kind'] ?? ''}'.trim();
    final targetPath = _fileMutationTargetPath(metadata);
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
      if (mutationKind.isNotEmpty) 'mutation: $mutationKind',
      if (targetPath != null) 'target: $targetPath',
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

  Set<String> _microCompactToolMessageIds(
    List<AiSessionMessage> messages,
    int lastConsumerIndex,
  ) {
    if (lastConsumerIndex <= 0) {
      return const <String>{};
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
      return const <String>{};
    }
    return consumedToolMessages
        .take(clearCount)
        .map((message) => message.id)
        .toSet();
  }

  String _microCompactToolResultContent(AiSessionMessage message) {
    final metadata = message.metadata;
    final toolName = '${metadata['tool_name'] ?? ''}'.trim();
    final status =
        '${metadata['status'] ?? metadata['tool_execution_status'] ?? ''}'
            .trim();
    final targetPath = _fileMutationTargetPath(metadata);
    final workingDirectory =
        '${metadata['working_directory'] ?? metadata['tool_execution_working_directory'] ?? ''}'
            .trim();
    final purpose = _extractToolCallPurpose(metadata);
    final original = _promptContentForMessage(message);
    final lines = <String>[
      '[old_tool_result_cleared] ${toolName.isEmpty ? 'Tool' : toolName}',
      'original_chars: ${original.length}',
      if (status.isNotEmpty) 'status: $status',
      if (targetPath != null) 'target: $targetPath',
      if (workingDirectory.isNotEmpty) 'working_directory: $workingDirectory',
      if (purpose != null && purpose.isNotEmpty) 'purpose: $purpose',
      'note: Older consumed tool result content was cleared from prompt history. Re-run the tool or read local files if exact output is needed.',
    ];
    return lines.join('\n');
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
    final arguments = _decodeToolArgumentsMap(toolCall.arguments);
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
                    final edit = Map<String, Object?>.from(item);
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
        final newSource = '${arguments['new_source'] ?? ''}';
        return jsonEncode(<String, Object?>{
          'notebook_path': notebookPath,
          if ('${arguments['cell_id'] ?? ''}'.trim().isNotEmpty)
            'cell_id': '${arguments['cell_id'] ?? ''}'.trim(),
          if ('${arguments['edit_mode'] ?? ''}'.trim().isNotEmpty)
            'edit_mode': '${arguments['edit_mode'] ?? ''}'.trim(),
          if ('${arguments['cell_type'] ?? ''}'.trim().isNotEmpty)
            'cell_type': '${arguments['cell_type'] ?? ''}'.trim(),
          'new_source': _omittedPayloadSummary(
            newSource.length,
            targetPath: notebookPath,
            action: 'notebook_edit',
          ),
        });
      case 'bash':
        // 2026-04-27 (修复): 之前对"写文件类 Bash"完全省略命令体，导致模型
        // 在后续轮次完全忘记自己执行了什么 shell（heredoc 内容、脚本逻辑都
        // 被丢弃），从而把"我刚写过的小文件"误判为被截断。Bash 命令本身
        // 即"我做了什么"的语义载体，不能丢。这里改为：保留完整命令；只
        // 在命令体超大时（>8KB）做 head/tail 截断，并附上 stored locally
        // 提示便于审计。
        final command = '${arguments['cmd'] ?? arguments['command'] ?? ''}';
        const bashCommandPromptHistoryMaxChars = 8192;
        if (command.length <= bashCommandPromptHistoryMaxChars) {
          return toolCall.arguments;
        }
        final isWriteLikeBash =
            _looksLikeWriteLikeBashArguments(arguments) ||
            _isWriteLikeToolMetadata(metadata);
        const headTail = 1024;
        final head = command.substring(0, headTail);
        final tail = command.substring(command.length - headTail);
        final summarizedCommand =
            '$head\n…[bash_command_truncated: dropped '
            '${command.length - headTail * 2} chars; '
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

  Map<String, Object?> _decodeToolArgumentsMap(String arguments) {
    final trimmed = arguments.trim();
    if (trimmed.isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      return const <String, Object?>{};
    }
    return const <String, Object?>{};
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

  /// 通用工具调用结果压缩。当 [aiGenericToolResultCompressionThreshold] 阈值
  /// 被超过时，把整段 raw 输出替换成结构化摘要：
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
    _ToolCompressionConfig compressionConfig,
  ) {
    final original = _promptContentForMessage(message);
    final threshold = compressionConfig.thresholdChars;
    if (original.length <= threshold) {
      return original;
    }
    final metadata = message.metadata;
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
    final headTail = compressionConfig.headTailWindowChars;
    final head = headTail <= 0
        ? ''
        : original.substring(0, math.min(original.length, headTail)).trim();
    final tailStart = math.max(0, original.length - headTail);
    final tail = headTail <= 0 ? '' : original.substring(tailStart).trim();
    final lines = <String>[
      '[tool_result_summary] ${toolName.isEmpty ? 'Tool' : toolName}',
      'original_chars: ${original.length}',
      if (status.isNotEmpty) 'status: $status',
      if (purpose != null && purpose.isNotEmpty) 'purpose: $purpose',
      if (pathHits.isNotEmpty)
        'affected:\n${pathHits.map((h) => '  - $h').join('\n')}',
      if (head.isNotEmpty) 'head:\n$head',
      if (tail.isNotEmpty && tail != head) 'tail:\n$tail',
      'note: Tool result exceeded $threshold'
          ' chars and was condensed for the prompt history. Re-run the tool'
          ' or read the local file directly if exact contents are needed.',
    ];
    return lines.join('\n');
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
        return value.length > 240 ? '${value.substring(0, 240)}…' : value;
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
              return value.length > 240 ? '${value.substring(0, 240)}…' : value;
            }
          }
        }
      } catch (_) {
        // Argument string was not valid JSON; nothing to extract.
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
      // Filter trivial false-positives: pure version strings, numbers, etc.
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

  String? _fileMutationTargetPath(Map<String, Object?> metadata) {
    final candidateValues = <Object?>[
      metadata['file_mutation_path'],
      metadata['file_path'],
      metadata['notebook_path'],
    ];
    for (final value in candidateValues) {
      final normalized = '$value'.trim();
      if (normalized.isNotEmpty && normalized != 'null') {
        return normalized;
      }
    }
    return null;
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
          final toolCall = Map<String, Object?>.from(item);
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
    final value = '${metadata['tool_call_id'] ?? ''}'.trim();
    return value.isEmpty ? null : value;
  }

  bool _isToolResultKind(AiSessionMessageKind kind) {
    return kind == AiSessionMessageKind.tool ||
        kind == AiSessionMessageKind.mcp ||
        kind == AiSessionMessageKind.skill ||
        kind == AiSessionMessageKind.hook;
  }

  List<String> _readStringList(Object? rawValue) {
    if (rawValue is List) {
      return rawValue
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final single = '$rawValue'.trim();
    if (single.isEmpty || single == 'null') {
      return const <String>[];
    }
    return <String>[single];
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

  String? _buildTodoWriteReminder({
    required AiSession session,
    required AiSessionMessage? latestUserMessage,
  }) {
    final message = latestUserMessage;
    if (message == null || message.kind != AiSessionMessageKind.user) {
      return null;
    }
    if (session.awaitingPlanApproval) {
      return null;
    }
    final hasIncompleteTodo = session.todoItems.any(
      (item) => item.status.trim().toLowerCase() != 'completed',
    );
    final normalizedContent = message.content.trim().toLowerCase();
    const continuationOnlySignals = <String>{
      'continue',
      'continue.',
      'go on',
      'keep going',
      '继续',
      '继续吧',
      '接着做',
      '接着',
    };
    if (continuationOnlySignals.contains(normalizedContent)) {
      return null;
    }
    if (hasIncompleteTodo || !_looksLikeNonTrivialTask(message.content)) {
      return null;
    }
    return 'This looks like a non-trivial multi-step task. Use TodoWrite now to create or refresh a structured todo list before continuing, and keep it updated as steps complete.';
  }

  String? _buildPlanModeReminder({
    required AiSession session,
    required AiSessionMessage? latestUserMessage,
  }) {
    if (session.awaitingPlanApproval) {
      final pendingPlan = (session.pendingPlan ?? '').trim();
      if (pendingPlan.isEmpty) {
        return 'A plan is pending user approval. Present the captured plan clearly, ask for explicit approval, and wait before implementation. Do not call editing or write-oriented tools until approval is granted.';
      }
      return 'A plan is pending user approval. Present the captured plan below, ask for explicit approval, and wait before implementation. Do not call editing or write-oriented tools until approval is granted.\n\n$pendingPlan';
    }
    if (session.mode != AiSessionMode.plan || latestUserMessage == null) {
      return null;
    }
    if (_shouldUsePlanRecoveryReminder(
      session: session,
      latestUserMessage: latestUserMessage,
    )) {
      final completedButNeedsReview =
          _hasCompletedTodoItemsOnly(session.todoItems) &&
          _looksLikePlanRecoveryContinuation(latestUserMessage.content);
      final failedSteps = session.todoItems
          .where((item) {
            final status = item.status.trim().toLowerCase();
            return status == 'failed' ||
                status == 'blocked' ||
                status == 'cancelled';
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
    if (_looksLikePlanApproval(latestUserMessage.content)) {
      return 'The user is approving the existing plan. Do not call ExitPlanMode again or restate the plan. Start executing it now, use TodoWrite to track concrete implementation steps, and keep the todo list current as work progresses. Your tool catalog now includes Write/Edit/MultiEdit/Bash — use them directly. Never apologise for missing tools or ask the user to copy-paste code: re-check the tool list, and if a write tool is genuinely absent (e.g. you are still in planning phase), call ExitPlanMode first instead of giving up.';
    }
    return 'This session is in Plan mode. When the request needs more than one concrete step, first inspect the problem, use TodoWrite to create or refresh a structured todo list, and complete planning before implementation. Do not call editing, write-oriented, or execution-heavy tools until the plan is approved. Once the plan is ready, call ExitPlanMode with a concise actionable numbered or bulleted execution step list and wait for explicit user approval before making changes. IMPORTANT: if the user has already endorsed the plan in any phrasing (English or Chinese, e.g. "去写吧", "去做吧", "do it", "ship it"), treat that turn as approval and call ExitPlanMode at once — never claim Write/Edit are unavailable as an excuse to dump code into chat.';
  }

  bool _shouldUsePlanRecoveryReminder({
    required AiSession session,
    required AiSessionMessage latestUserMessage,
  }) {
    if (session.mode != AiSessionMode.plan || session.awaitingPlanApproval) {
      return false;
    }
    if (!_looksLikePlanRecoveryContinuation(latestUserMessage.content)) {
      return false;
    }
    if (_hasCompletedTodoItemsOnly(session.todoItems)) {
      return true;
    }
    return session.todoItems.any((item) {
          final status = item.status.trim().toLowerCase();
          return status == 'failed' ||
              status == 'blocked' ||
              status == 'cancelled';
        }) ||
        _hasRecentPlanToolFailure(session);
  }

  bool _isFileEditingToolName(String toolName) {
    return switch (toolName.trim().toLowerCase()) {
      'edit' || 'multiedit' || 'write' || 'notebookedit' => true,
      _ => false,
    };
  }

  bool _hasCompletedTodoItemsOnly(List<AiSessionTodoItem> todoItems) {
    return todoItems.isNotEmpty &&
        todoItems.every(
          (item) => item.status.trim().toLowerCase() == 'completed',
        );
  }

  bool _hasRecentPlanToolFailure(AiSession session) {
    for (var index = session.messages.length - 1; index >= 0; index -= 1) {
      final message = session.messages[index];
      if (message.isDeleted || message.kind != AiSessionMessageKind.toolCall) {
        continue;
      }
      final status = '${message.metadata['tool_execution_status'] ?? ''}'
          .trim()
          .toLowerCase();
      if (status.isEmpty || status == 'running') {
        continue;
      }
      return status == 'failed' ||
          status == 'cancelled' ||
          status == 'denied' ||
          status == 'rejected' ||
          status == 'timed_out' ||
          status == 'invalid_arguments';
    }
    return false;
  }

  bool _looksLikePlanApproval(String content) =>
      AiPlanApprovalDetector.looksLikePlanApproval(content);

  bool _looksLikePlanRecoveryContinuation(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    const recoveryPhrases = <String>[
      'continue',
      'continue.',
      'go on',
      'keep going',
      'continue implementation',
      'finish it',
      'retry',
      'retry it',
      'retry the step',
      'retry the failed step',
      'resume',
      '继续',
      '继续吧',
      '继续做',
      '继续完成',
      '继续实施',
      '继续执行',
      '接着',
      '接着做',
      '重试',
      '重试一下',
      '重新执行',
      '重新试',
      '恢复执行',
    ];
    return recoveryPhrases.any((phrase) => normalized.contains(phrase));
  }

  bool _looksLikeNonTrivialTask(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final normalized = trimmed.toLowerCase();
    final bulletCount = RegExp(
      r'^\s*(?:[-*]|\d+\.)\s+',
      multiLine: true,
    ).allMatches(trimmed).length;
    if (bulletCount >= 2) {
      return true;
    }
    const taskSignals = <String>[
      'fix',
      'implement',
      'add',
      'integrate',
      'refactor',
      'debug',
      'investigate',
      'migrate',
      'optimize',
      'update',
      'patch',
      'support',
      'test',
      'verify',
      'review',
      'audit',
      'analyze',
      'analyse',
      'compare',
      'trace',
      'walk through',
      '排查',
      '审查',
      '评审',
      '分析',
      '对比',
      '梳理',
      '修复',
      '实现',
      '新增',
      '集成',
      '迁移',
      '优化',
      '改进',
      '完善',
      '调整',
      '检查',
      '补齐',
      '支持',
      '测试',
      '验证',
    ];
    if (!taskSignals.any(normalized.contains)) {
      return false;
    }
    const informationalSignals = <String>[
      'what is',
      'what are',
      'what does',
      'why is',
      'why does',
      'how does claude code',
      'how do claude code',
      'can claude code',
      'does claude code',
      '什么是',
      '为什么',
      'claude code',
    ];
    final hasQuestionMark =
        normalized.contains('?') || normalized.contains('？');
    if (hasQuestionMark &&
        informationalSignals.any(normalized.contains) &&
        bulletCount == 0) {
      return false;
    }
    const multiStepSignals = <String>[
      ' and ',
      ' then ',
      ' after ',
      ' before ',
      ' also ',
      ' first ',
      ' next ',
      '同时',
      '然后',
      '先',
      '再',
      '并且',
      '以及',
      '另外',
      '顺便',
      '继续',
      '一次性',
      '全面',
      '彻底',
    ];
    final multiStepSignalCount = multiStepSignals
        .where(normalized.contains)
        .length;
    final sentenceBreakCount = RegExp(
      r'[.!?。！？]\s*|\n',
    ).allMatches(trimmed).length;
    if (multiStepSignalCount >= 1 &&
        (trimmed.length >= 80 || sentenceBreakCount >= 2)) {
      return true;
    }
    return trimmed.length >= 140 || sentenceBreakCount >= 3;
  }
}

class _MappedToolExchange {
  const _MappedToolExchange({required this.turns, required this.nextIndex});

  final List<AiChatTurn> turns;
  final int nextIndex;
}

/// 2026-04-27 — 工具调用结果压缩相关的运行期配置。从 [AiSessionRuntimeContext]
/// 派生，统一传入历史映射函数链，避免逐层传递 5 个独立参数。
class _ToolCompressionConfig {
  const _ToolCompressionConfig({
    required this.enabled,
    required this.thresholdChars,
    required this.headTailWindowChars,
    required this.maxPathHits,
    required this.writeSummaryMaxChars,
  });

  factory _ToolCompressionConfig.fromRuntimeContext(
    AiSessionRuntimeContext runtimeContext,
  ) {
    return _ToolCompressionConfig(
      enabled: runtimeContext.toolResultCompressionEnabled,
      thresholdChars: runtimeContext.toolResultCompressionThresholdChars > 0
          ? runtimeContext.toolResultCompressionThresholdChars
          : 1024,
      headTailWindowChars: runtimeContext
          .toolResultCompressionHeadTailWindowChars
          .clamp(0, 1 << 20),
      maxPathHits: runtimeContext.toolResultCompressionMaxPathHits.clamp(
        0,
        1 << 20,
      ),
      writeSummaryMaxChars: runtimeContext.writeToolSummaryMaxChars.clamp(
        0,
        1 << 20,
      ),
    );
  }

  final bool enabled;
  final int thresholdChars;
  final int headTailWindowChars;
  final int maxPathHits;
  final int writeSummaryMaxChars;
}

class _ExtractedReminderContent {
  const _ExtractedReminderContent({
    required this.content,
    required this.reminders,
  });

  final String content;
  final List<String> reminders;
}
