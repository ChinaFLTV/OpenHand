import 'dart:convert';

import '../model/ai_session.dart';
import '../model/ai_session_message.dart';
import '../model/ai_session_runtime_context.dart';
import '../model/ai_thread_template.dart';
import '../../memory/model/user_memory_entry.dart';
import '../model/ai_model_config.dart';
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
      'current_prompt_system_message_count': 5,
      'current_prompt_history_message_count': historyTurns.length,
      'current_prompt_memory_entry_count': memoryEntries.length,
      'current_prompt_latest_user_message_id': latestUserMessage?.id,
      'environment': runtimeContext.toJson(),
    };

    final messages = <AiChatTurn>[
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# [0] System Instructions\n\n${templateBundle.systemInstructions}',
      ),
      AiChatTurn(
        role: AiChatRole.system,
        content:
            '# [1] Developer Instructions\n\n${templateBundle.developerInstructions}',
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
      if (latestUserMessage != null)
        AiChatTurn(
          role: AiChatRole.user,
          content: '# [6] Your latest message\n\n${latestUserMessage.content}',
        ),
    ];

    final promptCharacterCount = messages.fold<int>(
      0,
      (sum, item) => sum + item.content.length,
    );
    return AiPromptBuildResult(
      messages: messages,
      metadata: metadata,
      promptCharacterCount: promptCharacterCount,
      systemMessageCount: 5,
      historyMessageCount: historyTurns.length,
    );
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
      if (message.kind == AiSessionMessageKind.tool) {
        index += 1;
        continue;
      }
      turns.add(_mapNonToolHistoryMessage(message));
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
    final message = messages[startIndex];
    final toolCalls = _readToolCalls(message.metadata);
    if (toolCalls.isEmpty) {
      return _MappedToolExchange(
        turns: <AiChatTurn>[_mapNonToolHistoryMessage(message)],
        nextIndex: startIndex + 1,
      );
    }
    final expectedToolCallIds = toolCalls
        .map((item) => item.id.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (expectedToolCallIds.isEmpty) {
      return _MappedToolExchange(
        turns: const <AiChatTurn>[],
        nextIndex: startIndex + 1,
      );
    }
    final toolMessages = <AiSessionMessage>[];
    final seenToolCallIds = <String>{};
    var cursor = startIndex + 1;
    while (cursor < messages.length &&
        messages[cursor].kind == AiSessionMessageKind.tool) {
      final toolMessage = messages[cursor];
      final toolCallId = _readToolCallId(toolMessage.metadata);
      if (toolCallId != null &&
          expectedToolCallIds.contains(toolCallId) &&
          seenToolCallIds.add(toolCallId)) {
        toolMessages.add(toolMessage);
      }
      cursor += 1;
    }
    if (seenToolCallIds.length != expectedToolCallIds.length) {
      return _MappedToolExchange(
        turns: const <AiChatTurn>[],
        nextIndex: cursor,
      );
    }
    return _MappedToolExchange(
      turns: <AiChatTurn>[
        AiChatTurn(
          role: AiChatRole.assistant,
          content: message.content,
          toolCalls: toolCalls,
        ),
        ...toolMessages.map(
          (toolMessage) => AiChatTurn(
            role: AiChatRole.tool,
            toolCallId: _readToolCallId(toolMessage.metadata),
            content: toolMessage.content,
          ),
        ),
      ],
      nextIndex: cursor,
    );
  }

  AiChatTurn _mapNonToolHistoryMessage(AiSessionMessage message) {
    switch (message.kind) {
      case AiSessionMessageKind.user:
        return AiChatTurn(role: AiChatRole.user, content: message.content);
      case AiSessionMessageKind.assistant:
        return AiChatTurn(role: AiChatRole.assistant, content: message.content);
      case AiSessionMessageKind.toolCall:
      case AiSessionMessageKind.tool:
        return AiChatTurn(
          role: AiChatRole.assistant,
          content: '[${message.kind.storageValue}] ${message.content}',
        );
      case AiSessionMessageKind.mcp:
      case AiSessionMessageKind.skill:
        return AiChatTurn(
          role: AiChatRole.assistant,
          content: '[${message.kind.storageValue}] ${message.content}',
        );
      case AiSessionMessageKind.compressionPoint:
      case AiSessionMessageKind.reasoning:
      case AiSessionMessageKind.status:
        return AiChatTurn(
          role: AiChatRole.system,
          content: '[${message.kind.storageValue}] ${message.content}',
        );
    }
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
}

class _MappedToolExchange {
  const _MappedToolExchange({required this.turns, required this.nextIndex});

  final List<AiChatTurn> turns;
  final int nextIndex;
}
