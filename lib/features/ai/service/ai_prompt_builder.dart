import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../instructions/model/user_instruction_entry.dart';
import '../../memory/model/user_memory_entry.dart';
import '../model/ai_attachment.dart';
import '../model/ai_model_config.dart';
import '../model/ai_session.dart';
import '../model/ai_session_message.dart';
import '../model/ai_session_runtime_context.dart';
import '../model/ai_thread_template.dart';
import 'ai_bash_tool_service.dart';
import 'ai_claude_hook_service.dart';
import 'ai_prompt_template_repository.dart';
import 'ai_protocol_adapter.dart';

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

  AiPromptBuildResult buildConversationPrompt({
    required AiPromptTemplateBundle templateBundle,
    required AiSession session,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
    required List<UserMemoryEntry> memoryEntries,
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage latestUserMessage,
    List<AiToolDefinition> availableTools = const <AiToolDefinition>[],
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
      _mapHistoryMessages(historyMessages, session, model),
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
            todoReminder: todoReminder,
            planModeReminder: planModeReminder,
          )
        : metadata;

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
            '# [2] Tool Catalog\n\n${_renderRuntimeToolCatalog(availableTools, compact: isCompactTemplate, templateId: templateBundle.template.id, awaitingPlanApproval: session.awaitingPlanApproval)}',
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
        content: isCompactTemplate
            ? '# [4] User Memory\n\n'
                  'Integrate memory facts naturally — do not hint at their source.\n\n'
                  '${_renderUserProfileSection(memoryEntries, runtimeContext.memoryEnabled, compact: true)}'
                  '${_renderUserMemory(memoryEntries, runtimeContext.memoryEnabled)}'
            : '# [4] User Memory (long-term facts)\n\n'
                  'IMPORTANT: Integrate memory facts naturally into your responses. '
                  'Do NOT explicitly state or hint that information comes from memory, '
                  'saved notes, or prior records. Use memory content as if it is common '
                  'knowledge you already possess.\n\n'
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
          content: '# [4.5] User Instructions\n\n'
              'The following are user-defined reusable prompt fragments. Treat each '
              'block as authoritative project guidance: follow its directives unless '
              'they directly contradict higher-priority system or developer '
              'instructions above.\n\n'
              '${_renderUserInstructionsBody(runtimeContext.userInstructions, runtimeContext.skippedInstructionIds)}',
        ),
      AiChatTurn(
        role: AiChatRole.system,
        content: isCompactTemplate
            ? '# [5] Conversation Context\n\n${_renderCompressionSummary(session, latestCompressionPoint)}'
            : '# [5] Recent Conversations Summary (past chats, titles + snippets)\n\n${_renderCompressionSummary(session, latestCompressionPoint)}',
      ),
      ...historyTurns,
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

  String _renderRuntimeEnvironmentSnapshot(
    AiSessionRuntimeContext runtimeContext,
    AiRepositorySnapshot? repositorySnapshot,
  ) {
    final workingDirectory = runtimeContext.workingDirectory.trim().isEmpty
        ? '${runtimeContext.toJson()['application_directory'] ?? ''}'.trim()
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
    String? todoReminder,
    String? planModeReminder,
  }) {
    final workingDirectory = runtimeContext.workingDirectory.trim().isEmpty
        ? '${runtimeContext.toJson()['application_directory'] ?? ''}'.trim()
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
  }) {
    final visibleTools = availableTools
        .where((tool) => tool.name.trim().isNotEmpty)
        .toList(growable: false);
    if (visibleTools.isEmpty) {
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
    final skillTools = visibleTools
        .where((tool) => tool.name.startsWith('skill__'))
        .toList(growable: false);
    final mcpTools = visibleTools
        .where((tool) => tool.name.startsWith('mcp__'))
        .toList(growable: false);
    final builtinTools = visibleTools
        .where(
          (tool) =>
              !tool.name.startsWith('skill__') &&
              !tool.name.startsWith('mcp__'),
        )
        .toList(growable: false);

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
        _renderToolEntry(
          buffer,
          tool,
          compact: compact,
        );
      }
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
    };
    final transcript = messagesToCompress
        .map(
          (message) =>
              '- [${message.createdAt.toIso8601String()}][${message.role.storageValue}][${message.kind.storageValue}] ${_renderMessageForCompression(message)}',
        )
        .join('\n');
    final previousCheckpointText = previousCompressionPoint == null
        ? 'No earlier checkpoint.'
        : previousCompressionPoint.content;
    // For programming_expert, use a minimal system identity instead of the
    // full system_instructions to save ~500 tokens per compression.  The
    // compression task only needs summarization guidance, not tool policies,
    // search strategy, Git rules, etc.
    final compressionSystemContent = isProgrammingExpert
        ? 'You are OpenHand Programming Expert. Summarize the conversation transcript for a long-running coding session checkpoint.'
        : templateBundle.systemInstructions;
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
            '# Compression Task Payload\n\n```json\n${const JsonEncoder.withIndent('  ').convert(payload)}\n```\n\n## Previous Checkpoint\n\n$previousCheckpointText\n\n## Messages To Compress\n\n$transcript',
      ),
    ];
  }

  List<AiChatTurn> _mapHistoryMessages(
    List<AiSessionMessage> messages,
    AiSession session,
    AiModelConfig model,
  ) {
    final turns = <AiChatTurn>[];
    var index = 0;
    while (index < messages.length) {
      final message = messages[index];
      if (message.kind == AiSessionMessageKind.toolCall) {
        final mappedGroup = _mapToolExchange(messages, index, session, model);
        if (mappedGroup.turns.isNotEmpty) {
          turns.addAll(mappedGroup.turns);
        }
        index = mappedGroup.nextIndex;
        continue;
      }
      if (_isToolResultKind(message.kind)) {
        index += 1;
        continue;
      }
      turns.addAll(_mapNonToolHistoryMessage(message, session, model));
      index += 1;
    }
    return turns;
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
  ) {
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
            turns: _mapNonToolHistoryMessage(toolCallMessage, session, model),
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
        turns: _mapNonToolHistoryMessage(firstMessage, session, model),
        nextIndex: startIndex + 1,
      );
    }
    final toolMessagesByCallId = <String, AiSessionMessage>{};
    while (cursor < messages.length &&
        _isToolResultKind(messages[cursor].kind)) {
      final toolMessage = messages[cursor];
      final toolCallId = _readToolCallId(toolMessage.metadata);
      if (toolCallId != null &&
          expectedToolCallIds.contains(toolCallId) &&
          !toolMessagesByCallId.containsKey(toolCallId)) {
        toolMessagesByCallId[toolCallId] = toolMessage;
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
      turns.addAll(
        _mapMessageContent(
          role: AiChatRole.tool,
          toolCallId: toolCall.id,
          content: _promptHistoryToolResultContent(toolMessage),
        ),
      );
    }
    return _MappedToolExchange(turns: turns, nextIndex: cursor);
  }

  List<AiChatTurn> _mapNonToolHistoryMessage(
    AiSessionMessage message,
    AiSession session,
    AiModelConfig model,
  ) {
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
          content: _promptHistoryToolResultContent(message),
        );
      case AiSessionMessageKind.mcp:
      case AiSessionMessageKind.skill:
      case AiSessionMessageKind.hook:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: '[${message.kind.storageValue}] $promptContent',
        );
      case AiSessionMessageKind.compressionPoint:
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
        if (detailText.isNotEmpty) {
          parts.add(AiChatContentPart.text('[Attachment]\n$detailText'));
        }
        if (!hasLocalImageFile) {
          if (detailText.isEmpty) {
            parts.add(
              AiChatContentPart.text(
                '[Attachment]\nImage attachment: ${attachment.name} is unavailable in local storage.',
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
                '[Attachment]\nImage attachment: ${attachment.name}.\n$modelWarning',
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
      final detail = attachment.isImage
          ? attachment.summaryText.trim()
          : attachment.promptText.trim();
      if (detail.isNotEmpty) {
        buffer.writeln('- $detail');
        continue;
      }
      buffer.writeln('- ${attachment.name} (${attachment.kind.storageValue})');
    }
    return buffer.toString().trim();
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
      final name = entry.name.trim().isEmpty ? 'Instruction' : entry.name.trim();
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
    return '### Thread\n- ${session.title}\n\n${latestCompressionPoint.content}';
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
    final writeLike =
        _isFileEditingToolName(normalizedName) ||
        (normalizedName.toLowerCase() == 'bash' &&
            _looksLikeWriteLikeBashArguments(arguments));
    if (targetPath != null) {
      return writeLike
          ? 'Tool call: $normalizedName -> $targetPath (payload omitted from prompt history)'
          : 'Tool call: $normalizedName -> $targetPath';
    }
    return writeLike
        ? 'Tool call: $normalizedName (write payload omitted from prompt history)'
        : 'Tool call: $normalizedName';
  }

  String _promptHistoryToolResultContent(AiSessionMessage message) {
    if (!_isWriteLikeToolHistoryMessage(message)) {
      // 2026-04-27: 通用工具调用结果压缩。当工具返回内容超过阈值时，
      // 提炼受影响文件路径 + 行号 + 工具自述目的（purpose/intent/goal/
      // description/reason），保留首尾片段作为结构性补充信息，避免
      // conversation history 被海量原文淹没。
      return _compressGenericToolResultContent(message);
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
      if (resultText.isNotEmpty && resultText.length <= 280)
        'summary: $resultText',
      'note: Large write payloads and file contents were omitted from prompt history to save tokens. Inspect the local filesystem if exact contents are needed.',
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
        if (_looksLikeWriteLikeBashArguments(arguments) ||
            _isWriteLikeToolMetadata(metadata)) {
          final command = '${arguments['cmd'] ?? arguments['command'] ?? ''}';
          return jsonEncode(<String, Object?>{
            'cmd': _omittedPayloadSummary(
              command.length,
              action: 'write_like_shell_command',
            ),
            if ('${arguments['working_directory'] ?? arguments['cwd'] ?? ''}'
                .trim()
                .isNotEmpty)
              'working_directory':
                  '${arguments['working_directory'] ?? arguments['cwd'] ?? ''}'
                      .trim(),
            if (metadata['tool_execution_write_analysis_reason'] != null)
              'write_reason':
                  '${metadata['tool_execution_write_analysis_reason'] ?? ''}'
                      .trim(),
          });
        }
        return toolCall.arguments;
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
  static const int _genericToolResultCompressionThreshold = 1024;
  static const int _genericToolResultHeadTailWindow = 256;
  static const int _genericToolResultMaxPathHits = 12;

  String _compressGenericToolResultContent(AiSessionMessage message) {
    final original = _promptContentForMessage(message);
    if (original.length <= _genericToolResultCompressionThreshold) {
      return original;
    }
    final metadata = message.metadata;
    final toolName = '${metadata['tool_name'] ?? ''}'.trim();
    final status =
        '${metadata['status'] ?? metadata['tool_execution_status'] ?? ''}'
            .trim();
    final purpose = _extractToolCallPurpose(metadata);
    final pathHits = _extractFilePathLineHits(
      original,
      maxHits: _genericToolResultMaxPathHits,
    );
    final head = original
        .substring(
          0,
          math.min(original.length, _genericToolResultHeadTailWindow),
        )
        .trim();
    final tailStart = math.max(
      0,
      original.length - _genericToolResultHeadTailWindow,
    );
    final tail = original.substring(tailStart).trim();
    final lines = <String>[
      '[tool_result_summary] ${toolName.isEmpty ? 'Tool' : toolName}',
      'original_chars: ${original.length}',
      if (status.isNotEmpty) 'status: $status',
      if (purpose != null && purpose.isNotEmpty) 'purpose: $purpose',
      if (pathHits.isNotEmpty)
        'affected:\n${pathHits.map((h) => '  - $h').join('\n')}',
      'head:\n$head',
      if (tail != head) 'tail:\n$tail',
      'note: Tool result exceeded $_genericToolResultCompressionThreshold'
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
              return value.length > 240
                  ? '${value.substring(0, 240)}…'
                  : value;
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

  List<String> _extractFilePathLineHits(
    String text, {
    required int maxHits,
  }) {
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

  bool _looksLikePlanApproval(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final compactReply = normalized.replaceAll(
      RegExp(r'[\s!！。．\.,，、;；:：~～?？]+'),
      '',
    );
    if (compactReply == '确认') {
      return true;
    }
    const approvalPhrases = <String>[
      'approve',
      'approved',
      'go ahead',
      'go for it',
      'proceed',
      'start implementing',
      'begin implementation',
      'continue implementation',
      'confirm execution',
      "let's go",
      "let's do it",
      "let's start",
      'do it',
      'ship it',
      'start now',
      'make it so',
      '确认执行',
      '确认开始',
      '开始执行',
      '继续实施',
      '继续执行',
      '开始吧',
      '执行吧',
      '可以执行',
      '可以开始',
      '去写吧',
      '去做吧',
      '去搞吧',
      '去实现',
      '去实现吧',
      '去干吧',
      '动手吧',
      '写吧',
      '做吧',
      '搞吧',
      '干吧',
      '上吧',
      '撸起来',
      '动手',
    ];
    return approvalPhrases.any((phrase) => normalized.contains(phrase));
  }

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

class _ExtractedReminderContent {
  const _ExtractedReminderContent({
    required this.content,
    required this.reminders,
  });

  final String content;
  final List<String> reminders;
}
