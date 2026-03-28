import 'dart:io';
import 'dart:convert';

import '../model/ai_session.dart';
import '../model/ai_attachment.dart';
import '../model/ai_session_message.dart';
import '../model/ai_session_runtime_context.dart';
import '../model/ai_thread_template.dart';
import '../../memory/model/user_memory_entry.dart';
import '../model/ai_model_config.dart';
import 'ai_bash_tool_service.dart';
import 'ai_claude_hook_service.dart';
import 'ai_protocol_adapter.dart';
import 'ai_prompt_template_repository.dart';

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
      _mapHistoryMessages(historyMessages, model),
    );
    final latestUserTurns = latestUserMessage == null
        ? const <AiChatTurn>[]
        : _mapUserMessage(
            latestUserMessage,
            model: model,
            content:
                '# [6] Your latest message\n\n${_promptContentForMessage(latestUserMessage)}',
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

    final messages = <AiChatTurn>[
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# [0] System Instructions\n\n${templateBundle.systemInstructions}${_renderWorkspaceInstructions(runtimeContext)}${_renderRuntimeEnvironmentSnapshot(runtimeContext, repositorySnapshot)}',
      ),
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# [1] Developer Instructions\n\n${templateBundle.developerInstructions}',
      ),
      if (todoReminder != null)
        AiChatTurn(
          role: AiChatRole.system,
          content: '# System Reminder\n\n$todoReminder',
        ),
      if (planModeReminder != null)
        AiChatTurn(
          role: AiChatRole.system,
          content: '# Plan Mode Reminder\n\n$planModeReminder',
        ),
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# [2] Session Metadata (ephemeral)\n\n```json\n${const JsonEncoder.withIndent('  ').convert(metadata)}\n```',
      ),
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# [3] User Memory (long-term facts)\n\n${_renderUserMemory(memoryEntries, runtimeContext.memoryEnabled)}',
      ),
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# [4] Recent Conversations Summary (past chats, titles + snippets)\n\n${_renderCompressionSummary(session, latestCompressionPoint)}',
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
    final payload = <String, Object?>{
      'session_id': session.id,
      'session_title': session.title,
      'template_id': template.id,
      'template_name': template.name,
      'locale_tag': runtimeContext.localeTag,
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
    return <AiChatTurn>[
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# Compression System Instructions\n\n${templateBundle.systemInstructions}',
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
    AiModelConfig model,
  ) {
    final turns = <AiChatTurn>[];
    var index = 0;
    while (index < messages.length) {
      final message = messages[index];
      if (message.kind == AiSessionMessageKind.toolCall) {
        final mappedGroup = _mapToolExchange(messages, index, model);
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
      turns.addAll(_mapNonToolHistoryMessage(message, model));
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
            turns: _mapNonToolHistoryMessage(toolCallMessage, model),
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
        turns: _mapNonToolHistoryMessage(firstMessage, model),
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
    AiModelConfig model,
  ) {
    final promptContent = _promptContentForMessage(message);
    switch (message.kind) {
      case AiSessionMessageKind.user:
        return _mapUserMessage(message, model: model, content: promptContent);
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
      case AiSessionMessageKind.reasoning:
        return const <AiChatTurn>[];
    }
  }

  List<AiChatTurn> _mapUserMessage(
    AiSessionMessage message, {
    required AiModelConfig model,
    required String content,
  }) {
    return _mapMessageContent(
      role: AiChatRole.user,
      content: content,
      parts: _attachmentPartsForMessage(message, model),
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
    AiModelConfig model,
  ) {
    final attachments = _readAttachments(message.metadata);
    if (attachments.isEmpty) {
      return const <AiChatContentPart>[];
    }
    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    if (!adapter.supportsAttachmentsForModel(model)) {
      return const <AiChatContentPart>[];
    }
    final parts = <AiChatContentPart>[];
    for (final attachment in attachments) {
      if (attachment.isImage) {
        final summaryText = attachment.summaryText.trim();
        final promptText = attachment.promptText.trim();
        final storagePath = attachment.storagePath.trim();
        final mimeType = attachment.mimeType.trim();
        final hasLocalImageFile =
            storagePath.isNotEmpty &&
            mimeType.isNotEmpty &&
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
    if (memoryEntries.isEmpty) {
      return 'No saved user memory entries.';
    }
    return memoryEntries
        .map((entry) {
          final tags = entry.tags.isEmpty
              ? ''
              : ' (tags: ${entry.tags.join(', ')})';
          return '- ${entry.content}$tags';
        })
        .join('\n');
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
      return _promptContentForMessage(message);
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
        kind == AiSessionMessageKind.skill;
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
      return 'The user is approving the existing plan. Do not call ExitPlanMode again or restate the plan. Start executing it now, use TodoWrite to track concrete implementation steps, and keep the todo list current as work progresses.';
    }
    return 'This session is in Plan mode. When the request needs more than one concrete step, first inspect the problem, use TodoWrite to create or refresh a structured todo list, and complete planning before implementation. Do not call editing, write-oriented, or execution-heavy tools until the plan is approved. Once the plan is ready, call ExitPlanMode with a concise actionable numbered or bulleted execution step list and wait for explicit user approval before making changes.';
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
    const approvalPhrases = <String>[
      'approve',
      'approved',
      'go ahead',
      'proceed',
      'start implementing',
      'begin implementation',
      'continue implementation',
      'confirm execution',
      '确认执行',
      '确认开始',
      '开始执行',
      '继续实施',
      '继续执行',
      '开始吧',
      '执行吧',
      '可以执行',
      '可以开始',
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
