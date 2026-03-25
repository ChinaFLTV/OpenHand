import 'dart:convert';

import '../model/ai_session.dart';
import '../model/ai_session_message.dart';
import '../model/ai_session_runtime_context.dart';
import '../model/ai_thread_template.dart';
import '../../memory/model/user_memory_entry.dart';
import '../model/ai_model_config.dart';
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

  AiPromptBuildResult buildConversationPrompt({
    required AiPromptTemplateBundle templateBundle,
    required AiSession session,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
    required List<UserMemoryEntry> memoryEntries,
    required List<AiSessionMessage> historyMessages,
    required AiSessionMessage latestUserMessage,
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
      _mapHistoryMessages(historyMessages),
    );
    final latestUserTurns = latestUserMessage == null
        ? const <AiChatTurn>[]
        : _mapMessageContent(
            role: AiChatRole.user,
            content:
                '# [6] Your latest message\n\n${_promptContentForMessage(latestUserMessage)}',
          );
    final todoReminder = _buildTodoWriteReminder(
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
      'current_todo_count': session.todoItems.length,
      'current_todos': session.todoItems
          .map((item) => item.toJson())
          .toList(growable: false),
      'todo_write_recommended': todoReminder != null,
      'todo_write_reason': todoReminder,
      'awaiting_plan_approval': session.awaitingPlanApproval,
      'pending_plan': session.pendingPlan,
      'workspace_instruction_document_count':
          runtimeContext.workspaceInstructionDocuments.length,
      'workspace_instruction_paths': runtimeContext
          .workspaceInstructionDocuments
          .map((item) => item.path)
          .toList(growable: false),
      'working_directory': runtimeContext.workingDirectory,
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
      (sum, item) => sum + item.content.length,
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
        'Write command confirmation required: ${runtimeContext.writeCommandConfirmationEnabled ? 'Yes' : 'No'}',
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
              '- [${message.createdAt.toIso8601String()}][${message.role.storageValue}][${message.kind.storageValue}] ${message.content}',
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

  List<AiChatTurn> _mapHistoryMessages(List<AiSessionMessage> messages) {
    final turns = <AiChatTurn>[];
    var index = 0;
    while (index < messages.length) {
      final message = messages[index];
      if (message.kind == AiSessionMessageKind.toolCall) {
        final mappedGroup = _mapToolExchange(messages, index);
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
      turns.addAll(_mapNonToolHistoryMessage(message));
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
            turns: _mapNonToolHistoryMessage(toolCallMessage),
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
        groupedToolCalls.add(toolCall);
      }
      cursor += 1;
    }
    if (groupedToolCalls.isEmpty) {
      return _MappedToolExchange(
        turns: _mapNonToolHistoryMessage(firstMessage),
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
    final groupedToolContent = groupedToolCallMessages
        .map((message) => message.content.trim())
        .where((content) => content.isNotEmpty)
        .join('\n\n');
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
          content: _promptContentForMessage(toolMessage),
        ),
      );
    }
    return _MappedToolExchange(turns: turns, nextIndex: cursor);
  }

  List<AiChatTurn> _mapNonToolHistoryMessage(AiSessionMessage message) {
    final promptContent = _promptContentForMessage(message);
    switch (message.kind) {
      case AiSessionMessageKind.user:
        return _mapMessageContent(
          role: AiChatRole.user,
          content: promptContent,
        );
      case AiSessionMessageKind.assistant:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: promptContent,
        );
      case AiSessionMessageKind.toolCall:
      case AiSessionMessageKind.tool:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: '[${message.kind.storageValue}] $promptContent',
        );
      case AiSessionMessageKind.mcp:
      case AiSessionMessageKind.skill:
        return _mapMessageContent(
          role: AiChatRole.assistant,
          content: '[${message.kind.storageValue}] $promptContent',
        );
      case AiSessionMessageKind.compressionPoint:
      case AiSessionMessageKind.reasoning:
      case AiSessionMessageKind.status:
        return _mapMessageContent(
          role: AiChatRole.system,
          content: '[${message.kind.storageValue}] $promptContent',
        );
    }
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
