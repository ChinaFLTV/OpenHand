import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../hardness/index.dart';
import '../../model/ai_attachment.dart';
import '../../model/ai_session.dart';
import '../../model/ai_session_message.dart';

const String _aiSessionJsonlSchema = 'openhand.ai_session.jsonl';
const int _aiSessionJsonlVersion = 2;
const int _maxJsonSanitizeDepth = 96;

/// A simple cooperative cancellation token for export operations.
class ExportCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() {
    _cancelled = true;
  }
}

/// Progress payload reported during an export operation.
class ExportProgress {
  const ExportProgress({required this.processed, required this.total});
  final int processed;
  final int total;
  double get fraction {
    if (total <= 0) return 0;
    final value = processed / total;
    if (value.isNaN || value.isInfinite) return 0;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }
}

/// Result enum for an export attempt.
enum ExportResultKind { success, cancelled, failure }

class ExportResult {
  const ExportResult({
    required this.kind,
    this.bytesWritten = 0,
    this.linesWritten = 0,
    this.error,
  });
  final ExportResultKind kind;
  final int bytesWritten;
  final int linesWritten;
  final Object? error;
}

/// Yield to the event loop so the UI thread stays responsive while exporting
/// a large session. Using `Future.delayed(Duration.zero)` rather than just
/// `Future(() {})` ensures we drain microtasks AND a render frame.
Future<void> _yieldToEventLoop() => Future<void>.delayed(Duration.zero);

/// Number of lines to write before flushing + yielding to the event loop.
const int _flushEvery = 32;

File _temporaryExportFile(File targetFile) {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return File('${targetFile.path}.openhand-$stamp.tmp');
}

Future<void> _prepareExportTempFile(File targetFile, File tempFile) async {
  final parent = targetFile.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }
  if (await tempFile.exists()) {
    await tempFile.delete();
  }
}

Future<void> _deleteExportTempFile(File tempFile) async {
  try {
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  } catch (error, stack) {
    silentLog('ai_session_jsonl_exporter', 'delete temp file', error, stack);
  }
}

Future<void> _commitExportTempFile(File tempFile, File targetFile) async {
  final backupFile = File('${targetFile.path}.bak');
  var movedExistingFile = false;
  try {
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    if (await targetFile.exists()) {
      await targetFile.rename(backupFile.path);
      movedExistingFile = true;
    }
    await tempFile.rename(targetFile.path);
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
  } catch (_) {
    await _deleteExportTempFile(tempFile);
    if (movedExistingFile && await backupFile.exists()) {
      try {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await backupFile.rename(targetFile.path);
      } catch (error, stack) {
        silentLog(
          'ai_session_jsonl_exporter',
          'restore backup after commit failure',
          error,
          stack,
        );
      }
    }
    rethrow;
  }
}

class _SelectedAiSessionMessage {
  const _SelectedAiSessionMessage({
    required this.message,
    required this.originalIndex,
    required this.exportIndex,
  });

  final AiSessionMessage message;

  /// Zero-based index in the full persisted session message order.
  final int originalIndex;

  /// Zero-based index inside the exported selection after filters are applied.
  final int exportIndex;
}

/// User-tunable configuration for an AI session export operation.
class AiSessionExportConfig {
  const AiSessionExportConfig({
    this.roles,
    this.kinds,
    this.includeDeleted = false,
    this.startIndex,
    this.endIndex,
  });

  /// When non-null, only messages whose [AiSessionMessageRole] is in this
  /// set will be exported. `null` means "all roles".
  final Set<AiSessionMessageRole>? roles;

  /// When non-null, only messages whose [AiSessionMessageKind] is in this
  /// set will be exported. `null` means "all kinds".
  final Set<AiSessionMessageKind>? kinds;

  /// When `true`, include messages where `isDeleted == true`.
  final bool includeDeleted;

  /// 1-based inclusive lower bound applied to the message ordering before
  /// any role/kind filter is run. `null` means "no lower bound".
  final int? startIndex;

  /// 1-based inclusive upper bound applied to the message ordering before
  /// any role/kind filter is run. `null` means "no upper bound".
  final int? endIndex;

  /// All-defaults configuration (every role, every kind, no range filter,
  /// skip deleted messages, single-line JSON).
  static const AiSessionExportConfig defaults = AiSessionExportConfig();

  Map<String, Object?> toJson() => <String, Object?>{
    'roles': roles?.map((role) => role.storageValue).toList(),
    'kinds': kinds?.map((kind) => kind.storageValue).toList(),
    'include_deleted': includeDeleted,
    'start_index': startIndex,
    'end_index': endIndex,
  };
}

/// User-tunable configuration for a Hardness session export operation.
class HardnessSessionExportConfig {
  const HardnessSessionExportConfig({this.startIndex, this.endIndex});

  /// 1-based inclusive lower bound on phase logs.
  final int? startIndex;

  /// 1-based inclusive upper bound on phase logs.
  final int? endIndex;

  static const HardnessSessionExportConfig defaults =
      HardnessSessionExportConfig();

  Map<String, Object?> toJson() => <String, Object?>{
    'start_index': startIndex,
    'end_index': endIndex,
  };
}

String _encodePayload(Map<String, Object?> payload) {
  return jsonEncode(_jsonSafeMap(payload));
}

Map<String, Object?> _jsonSafeMap(Map<String, Object?> value) {
  final seen = HashSet<Object>.identity();
  return Map<String, Object?>.from(
    _jsonSafeValue(value, depth: 0, seen: seen) as Map<String, Object?>,
  );
}

Object? _jsonSafeValue(
  Object? value, {
  required int depth,
  required Set<Object> seen,
}) {
  if (value == null || value is String || value is bool) {
    return value;
  }
  if (value is num) {
    return value.isFinite ? value : value.toString();
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  if (value is Duration) {
    return value.inMilliseconds;
  }
  if (value is Uri || value is BigInt) {
    return value.toString();
  }
  if (value is Enum) {
    return value.name;
  }
  if (depth >= _maxJsonSanitizeDepth) {
    return '<max_depth_exceeded>';
  }
  if (value is Map) {
    if (!seen.add(value)) {
      return '<cyclic_map>';
    }
    try {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        result['${entry.key}'] = _jsonSafeValue(
          entry.value,
          depth: depth + 1,
          seen: seen,
        );
      }
      return result;
    } finally {
      seen.remove(value);
    }
  }
  if (value is Iterable) {
    if (!seen.add(value)) {
      return '<cyclic_iterable>';
    }
    try {
      return value
          .map((item) => _jsonSafeValue(item, depth: depth + 1, seen: seen))
          .toList(growable: false);
    } finally {
      seen.remove(value);
    }
  }
  return value.toString();
}

({
  List<AiSessionMessage> fullMessages,
  List<_SelectedAiSessionMessage> messages,
})
_selectAiSessionMessages({
  required AiSession session,
  required AiSessionExportConfig config,
}) {
  // Apply range first (1-based inclusive bounds), then role / kind /
  // deleted filters. Range is interpreted against the full ordered
  // message list so users can reason about indices the same way the UI
  // shows them.
  final fullMessages = session.messages;
  final lower = (config.startIndex != null && config.startIndex! >= 1)
      ? config.startIndex! - 1
      : 0;
  final upperRaw = (config.endIndex != null && config.endIndex! >= 1)
      ? config.endIndex!
      : fullMessages.length;
  final upper = upperRaw > fullMessages.length ? fullMessages.length : upperRaw;
  final messages = <_SelectedAiSessionMessage>[];
  if (lower < upper) {
    for (var index = lower; index < upper; index += 1) {
      final message = fullMessages[index];
      if (!config.includeDeleted && message.isDeleted) continue;
      final roleFilter = config.roles;
      if (roleFilter != null && !roleFilter.contains(message.role)) {
        continue;
      }
      final kindFilter = config.kinds;
      if (kindFilter != null && !kindFilter.contains(message.kind)) {
        continue;
      }
      messages.add(
        _SelectedAiSessionMessage(
          message: message,
          originalIndex: index,
          exportIndex: messages.length,
        ),
      );
    }
  }
  return (fullMessages: fullMessages, messages: messages);
}

Map<String, Object?> _buildAiSessionHeaderPayload({
  required AiSession session,
  required List<AiSessionMessage> fullMessages,
  required List<_SelectedAiSessionMessage> messages,
  required AiSessionExportConfig config,
  required String exportedAt,
}) {
  final exportedMessages = messages
      .map((item) => item.message)
      .toList(growable: false);
  final latestCompressionPoint = session.latestCompressionPoint;
  return <String, Object?>{
    'type': 'session',
    'schema': _aiSessionJsonlSchema,
    'version': _aiSessionJsonlVersion,
    'id': session.id,
    'title': session.title,
    'template_id': session.templateId,
    'template_name': session.templateName,
    'template_icon_name': session.templateIconName,
    'template_internal_version': session.templateInternalVersion,
    'created_at': session.createdAt.toUtc().toIso8601String(),
    'updated_at': session.updatedAt.toUtc().toIso8601String(),
    'message_count': messages.length,
    'total_message_count': fullMessages.length,
    'message_total_count': session.messageTotalCount,
    'last_used_model_id': session.lastUsedModelId,
    'last_used_model_label': session.lastUsedModelLabel,
    'mode': session.mode.storageValue,
    'full_access_permission': session.fullAccessPermission,
    'exported_at': exportedAt,
    'export_config': config.toJson(),
    'selection': _buildSelectionPayload(
      session: session,
      fullMessages: fullMessages,
      messages: messages,
      config: config,
    ),
    'title_state': <String, Object?>{
      'is_title_manually_edited': session.isTitleManuallyEdited,
      'auto_title_acquired': session.autoTitleAcquired,
      'auto_title_retry_count': session.autoTitleRetryCount,
      'auto_title_first_user_content': session.autoTitleFirstUserContent,
      'auto_title_generated_at': session.autoTitleGeneratedAt
          ?.toUtc()
          .toIso8601String(),
      'auto_title_source_message_id': session.autoTitleSourceMessageId,
    },
    'compression_state': <String, Object?>{
      'latest_compression_checkpoint_message_id':
          session.latestCompressionCheckpointMessageId,
      'latest_compression_at': session.latestCompressionAt
          ?.toUtc()
          .toIso8601String(),
      'latest_compression_point_index': session.latestCompressionPointIndex,
      'latest_compression_point': latestCompressionPoint == null
          ? null
          : _buildAiSessionMessagePayload(
              _SelectedAiSessionMessage(
                message: latestCompressionPoint,
                originalIndex: session.latestCompressionPointIndex ?? -1,
                exportIndex: -1,
              ),
            ),
    },
    'plan_state': <String, Object?>{
      'awaiting_plan_approval': session.awaitingPlanApproval,
      'pending_plan': session.pendingPlan,
      'pending_plan_allowed_prompts': session.pendingPlanAllowedPrompts
          .map((item) => item.toJson())
          .toList(growable: false),
      'plan_history': session.planHistory
          .map((item) => item.toJson())
          .toList(growable: false),
      'latest_plan_record': session.latestPlanRecord?.toJson(),
      'latest_active_plan_record': session.latestActivePlanRecord?.toJson(),
      'todo_items': session.todoItems
          .map((item) => item.toJson())
          .toList(growable: false),
      'goal_state': session.goalState.toJson(),
      'active_goal': session.activeGoal?.toJson(),
      'has_active_goal': session.hasActiveGoal,
    },
    'message_load_state': <String, Object?>{
      'state': session.messageLoadState.name,
      'has_complete_messages': session.hasCompleteMessages,
      'has_partial_messages': session.hasPartialMessages,
      'has_loaded_messages': session.hasLoadedMessages,
      'has_more_historical_messages': session.hasMoreHistoricalMessages,
      'hidden_historical_message_count': session.hiddenHistoricalMessageCount,
      'message_window_start_index': session.messageWindowStartIndex,
      'message_total_count': session.messageTotalCount,
    },
    'message_breakdown': <String, Object?>{
      'all': _buildMessageBreakdown(fullMessages),
      'exported': _buildMessageBreakdown(exportedMessages),
      'visible_message_count': session.visibleMessages.length,
      'display_message_count': session.displayMessages.length,
      'active_conversation_message_count':
          session.activeConversationMessages.length,
      'active_prompt_message_count':
          session.activeConversationMessagesForPrompt.length,
    },
    'statistics': session.statistics.toJson(),
    'environment': session.environment.toJson(),
    'metadata': session.metadata,
    'last_prompt_metadata': session.lastPromptMetadata,
    'recent_errors': session.recentErrors
        .map((item) => item.toJson())
        .toList(growable: false),
    'session_snapshot': _buildSessionSnapshotPayload(session),
    'data_quality': <String, Object?>{
      'partial_export_warning': session.hasPartialMessages,
      'message_count_mismatch':
          session.messageTotalCount != fullMessages.length &&
          session.hasCompleteMessages,
      'statistics_total_message_count': session.statistics.totalMessageCount,
      'loaded_message_count': fullMessages.length,
    },
  };
}

Map<String, Object?> _buildSelectionPayload({
  required AiSession session,
  required List<AiSessionMessage> fullMessages,
  required List<_SelectedAiSessionMessage> messages,
  required AiSessionExportConfig config,
}) {
  final originalIndexes = messages.map((item) => item.originalIndex).toList();
  return <String, Object?>{
    'start_index': config.startIndex,
    'end_index': config.endIndex,
    'include_deleted': config.includeDeleted,
    'role_filter': config.roles
        ?.map((role) => role.storageValue)
        .toList(growable: false),
    'kind_filter': config.kinds
        ?.map((kind) => kind.storageValue)
        .toList(growable: false),
    'loaded_message_count': fullMessages.length,
    'session_message_total_count': session.messageTotalCount,
    'exported_message_count': messages.length,
    'excluded_message_count': fullMessages.length - messages.length,
    'first_original_index': originalIndexes.isEmpty
        ? null
        : originalIndexes.first + 1,
    'last_original_index': originalIndexes.isEmpty
        ? null
        : originalIndexes.last + 1,
  };
}

Map<String, Object?> _buildSessionSnapshotPayload(AiSession session) {
  return <String, Object?>{
    'schema_version': AiSession.schemaVersion,
    'session': <String, Object?>{
      'id': session.id,
      'title': session.title,
      'template_id': session.templateId,
      'template_name': session.templateName,
      'template_icon_name': session.templateIconName,
      'template_internal_version': session.templateInternalVersion,
      'created_at': session.createdAt.toUtc().toIso8601String(),
      'updated_at': session.updatedAt.toUtc().toIso8601String(),
      'last_used_model_id': session.lastUsedModelId,
      'last_used_model_label': session.lastUsedModelLabel,
      'is_title_manually_edited': session.isTitleManuallyEdited,
      'auto_title_acquired': session.autoTitleAcquired,
      'auto_title_retry_count': session.autoTitleRetryCount,
      'auto_title_first_user_content': session.autoTitleFirstUserContent,
      'auto_title_generated_at': session.autoTitleGeneratedAt
          ?.toUtc()
          .toIso8601String(),
      'auto_title_source_message_id': session.autoTitleSourceMessageId,
      'latest_compression_checkpoint_message_id':
          session.latestCompressionCheckpointMessageId,
      'latest_compression_at': session.latestCompressionAt
          ?.toUtc()
          .toIso8601String(),
      'mode': session.mode.storageValue,
      'awaiting_plan_approval': session.awaitingPlanApproval,
      'pending_plan': session.pendingPlan,
      'pending_plan_allowed_prompts': session.pendingPlanAllowedPrompts
          .map((item) => item.toJson())
          .toList(growable: false),
      'full_access_permission': session.fullAccessPermission,
    },
    'metadata': session.metadata,
    'environment': session.environment.toJson(),
    'statistics': session.statistics.toJson(),
    'last_prompt_metadata': session.lastPromptMetadata,
    'plan_history': session.planHistory
        .map((item) => item.toJson())
        .toList(growable: false),
    'todo_items': session.todoItems
        .map((item) => item.toJson())
        .toList(growable: false),
    'recent_errors': session.recentErrors
        .map((item) => item.toJson())
        .toList(growable: false),
    'messages_omitted_from_snapshot': true,
    'messages_are_streamed_as_jsonl_records': true,
    'message_load_state': session.messageLoadState.name,
    'message_window_start_index': session.messageWindowStartIndex,
    'message_total_count': session.messageTotalCount,
  };
}

Map<String, Object?> _buildMessageBreakdown(
  Iterable<AiSessionMessage> messages,
) {
  final byKind = <String, int>{
    for (final kind in AiSessionMessageKind.values) kind.storageValue: 0,
  };
  final byRole = <String, int>{
    for (final role in AiSessionMessageRole.values) role.storageValue: 0,
  };
  final bySenderOrigin = <String, int>{};
  final byConversationSide = <String, int>{};
  final toolSources = <String, int>{};
  final toolStatuses = <String, int>{};
  final metadataKeys = <String>{};
  var count = 0;
  var deleted = 0;
  var visible = 0;
  var conversationTurns = 0;
  var aiSideMessages = 0;
  var backgroundInputs = 0;
  var goalEvaluationMessages = 0;
  var attachmentCount = 0;
  var messagesWithAttachments = 0;
  var generatedMediaPathCount = 0;
  var responseVariantCount = 0;
  var messagesWithFeedback = 0;
  for (final message in messages) {
    count += 1;
    byKind[message.kind.storageValue] =
        (byKind[message.kind.storageValue] ?? 0) + 1;
    byRole[message.role.storageValue] =
        (byRole[message.role.storageValue] ?? 0) + 1;
    bySenderOrigin[message.senderOrigin] =
        (bySenderOrigin[message.senderOrigin] ?? 0) + 1;
    byConversationSide[message.conversationSide] =
        (byConversationSide[message.conversationSide] ?? 0) + 1;
    if (message.isDeleted) deleted += 1;
    if (message.isVisible) visible += 1;
    if (message.isConversationTurn) conversationTurns += 1;
    if (message.isAiSideConversationMessage) aiSideMessages += 1;
    if (message.isOpenHandBackgroundInput) backgroundInputs += 1;
    if (message.isGoalEvaluationMessage) goalEvaluationMessages += 1;
    metadataKeys.addAll(message.metadata.keys);

    final source = _metadataString(message.metadata['tool_source']);
    if (source.isNotEmpty) {
      toolSources[source] = (toolSources[source] ?? 0) + 1;
    }
    final status = _metadataString(
      message.metadata['tool_execution_status'] ?? message.metadata['status'],
    );
    if (status.isNotEmpty) {
      toolStatuses[status] = (toolStatuses[status] ?? 0) + 1;
    }

    final attachments = AiMessageAttachment.listFromMetadata(
      message.metadata[aiSessionMessageAttachmentsMetadataKey],
    );
    final explicitAttachmentCount = _metadataInt(
      message.metadata['attachment_count'],
    );
    final resolvedAttachmentCount = attachments.isNotEmpty
        ? attachments.length
        : explicitAttachmentCount;
    if (resolvedAttachmentCount > 0) {
      messagesWithAttachments += 1;
      attachmentCount += resolvedAttachmentCount;
    }
    generatedMediaPathCount +=
        _metadataListLength(message.metadata['generated_image_paths']) +
        _metadataListLength(message.metadata['generated_video_paths']) +
        _metadataListLength(message.metadata['generated_audio_paths']);
    if (message.kind == AiSessionMessageKind.assistant) {
      responseVariantCount += message.responseVariants.length;
    }
    if (message.feedback != null) {
      messagesWithFeedback += 1;
    }
  }

  final sortedMetadataKeys = metadataKeys.toList(growable: false)..sort();
  return <String, Object?>{
    'count': count,
    'deleted_count': deleted,
    'visible_count': visible,
    'conversation_turn_count': conversationTurns,
    'ai_side_message_count': aiSideMessages,
    'openhand_background_input_count': backgroundInputs,
    'goal_evaluation_message_count': goalEvaluationMessages,
    'by_kind': byKind,
    'by_role': byRole,
    'by_sender_origin': bySenderOrigin,
    'by_conversation_side': byConversationSide,
    'tool_sources': toolSources,
    'tool_statuses': toolStatuses,
    'attachment_count': attachmentCount,
    'messages_with_attachments': messagesWithAttachments,
    'generated_media_path_count': generatedMediaPathCount,
    'response_variant_count': responseVariantCount,
    'messages_with_feedback': messagesWithFeedback,
    'metadata_key_count': sortedMetadataKeys.length,
    'metadata_keys': sortedMetadataKeys,
  };
}

Map<String, Object?> _buildAiSessionMessagePayload(
  _SelectedAiSessionMessage selected,
) {
  final message = selected.message;
  final variants = message.kind == AiSessionMessageKind.assistant
      ? message.responseVariants
      : const <AiSessionMessageResponseVariant>[];
  return <String, Object?>{
    'type': 'message',
    'export_index': selected.exportIndex < 0 ? null : selected.exportIndex + 1,
    'original_index': selected.originalIndex < 0
        ? null
        : selected.originalIndex + 1,
    'sort_order': selected.originalIndex < 0 ? null : selected.originalIndex,
    ...message.toJson(includeDerivedFields: true),
    'visibility': <String, Object?>{
      'is_visible': message.isVisible,
      'is_conversation_turn': message.isConversationTurn,
      'is_ai_side_conversation_message': message.isAiSideConversationMessage,
      'is_openhand_background_input': message.isOpenHandBackgroundInput,
      'is_goal_evaluation_message': message.isGoalEvaluationMessage,
    },
    'feedback': message.feedback?.storageValue,
    'response_variant_index': variants.isEmpty
        ? null
        : message.responseVariantIndex,
    'response_variant_count': variants.length,
    'response_variants': variants
        .map((variant) => variant.toJson())
        .toList(growable: false),
    'cards': _buildMessageCardsPayload(message),
    'tool': _buildMessageToolPayload(message),
    'media': _buildMessageMediaPayload(message),
    'diagnostics': <String, Object?>{
      'metadata_key_count': message.metadata.length,
      'metadata_keys': (message.metadata.keys.toList(growable: false)..sort()),
      'content_character_count_actual': AiSessionMessage.countCharacters(
        message.content,
      ),
      'content_character_count_recorded': message.characterCount,
    },
  };
}

Map<String, Object?> _buildMessageCardsPayload(AiSessionMessage message) {
  final metadata = message.metadata;
  final cards = <String, Object?>{};
  void put(String key, Object? value) {
    if (value == null) return;
    if (value is String && value.trim().isEmpty) return;
    if (value is Iterable && value.isEmpty) return;
    if (value is Map && value.isEmpty) return;
    cards[key] = value;
  }

  put(
    aiSessionMachineExpertRequestCardMetadataKey,
    (AiMachineExpertRequestCard.fromMetadata(
              metadata[aiSessionMachineExpertRequestCardMetadataKey],
            ) ??
            AiMachineExpertRequestCard.fromPrompt(message.content))
        ?.toJson(),
  );
  put(
    aiSessionWebReverseRequestCardMetadataKey,
    (AiWebReverseRequestCard.fromMetadata(
              metadata[aiSessionWebReverseRequestCardMetadataKey],
            ) ??
            AiWebReverseRequestCard.fromPrompt(message.content))
        ?.toJson(),
  );
  put(
    aiSessionAndroidReverseRequestCardMetadataKey,
    (AiAndroidReverseRequestCard.fromMetadata(
              metadata[aiSessionAndroidReverseRequestCardMetadataKey],
            ) ??
            AiAndroidReverseRequestCard.fromPrompt(message.content))
        ?.toJson(),
  );
  put('knowledge_base', metadata['knowledge_base']);
  put('creation_request', metadata['creation_request']);
  put('user_skill_selection', metadata['user_skill_selection']);
  put('selected_skill', metadata['selected_skill']);
  put('round_file_mutation_summary', metadata['round_file_mutation_summary']);
  put('message_feedback', message.feedback?.storageValue);
  put(
    'goal_evaluation',
    message.isGoalEvaluationMessage
        ? <String, Object?>{
            'type': metadata[aiSessionGoalEvaluationMessageTypeMetadataKey],
            'round_index':
                metadata[aiSessionGoalEvaluationRoundIndexMetadataKey],
            'passed': metadata[aiSessionGoalEvaluationPassedMetadataKey],
            'total_tokens': metadata[aiSessionGoalTotalTokensMetadataKey],
            'elapsed_ms': metadata[aiSessionGoalElapsedMsMetadataKey],
          }
        : null,
  );
  return cards;
}

Map<String, Object?> _buildMessageToolPayload(AiSessionMessage message) {
  final metadata = message.metadata;
  const toolKeys = <String>[
    'tool_call_id',
    'tool_name',
    'tool_source',
    'mcp_server_name',
    'mcp_tool_name',
    'skill_name',
    'skill_manifest_path',
    'hook_name',
    'hook_event',
    'tool_execution_started_at',
    'tool_execution_finished_at',
    'tool_execution_status',
    'tool_execution_command',
    'tool_execution_working_directory',
    'tool_execution_elapsed_ms',
    'tool_execution_duration_ms',
    'tool_execution_exit_code',
    'tool_execution_stdout_file',
    'tool_execution_stderr_file',
    'tool_execution_matched_rule_id',
    'tool_execution_matched_rule_pattern',
    'tool_execution_is_write_command',
    'tool_execution_write_analysis_reason',
    'tool_execution_stall_warning',
  ];
  final tool = <String, Object?>{};
  for (final key in toolKeys) {
    if (metadata.containsKey(key)) {
      tool[key] = metadata[key];
    }
  }
  final stdout = _metadataString(metadata['tool_execution_stdout']);
  final stderr = _metadataString(metadata['tool_execution_stderr']);
  final result = _metadataString(
    metadata['tool_execution_result'] ?? metadata['result_text'],
  );
  if (stdout.isNotEmpty) {
    tool['tool_execution_stdout_characters'] = stdout.length;
  }
  if (stderr.isNotEmpty) {
    tool['tool_execution_stderr_characters'] = stderr.length;
  }
  if (result.isNotEmpty) {
    tool['tool_execution_result_characters'] = result.length;
  }
  return tool;
}

Map<String, Object?> _buildMessageMediaPayload(AiSessionMessage message) {
  final metadata = message.metadata;
  final attachments = AiMessageAttachment.listFromMetadata(
    metadata[aiSessionMessageAttachmentsMetadataKey],
  );
  final media = <String, Object?>{};
  if (attachments.isNotEmpty) {
    media['attachments'] = attachments
        .map((attachment) => attachment.toJson())
        .toList(growable: false);
    media['attachment_count'] = attachments.length;
    media['attachment_total_size_bytes'] = attachments.fold<int>(
      0,
      (sum, attachment) => sum + attachment.sizeBytes,
    );
  } else {
    final count = _metadataInt(metadata['attachment_count']);
    if (count > 0) media['attachment_count'] = count;
  }
  for (final key in const <String>[
    'generated_image_paths',
    'generated_video_paths',
    'generated_audio_paths',
  ]) {
    final value = metadata[key];
    if (_metadataListLength(value) > 0) {
      media[key] = value;
    }
  }
  return media;
}

String _metadataString(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text == 'null') return '';
  return text;
}

int _metadataInt(Object? value) {
  if (value is num) {
    final parsed = optionalRoundedIntFromValue(value);
    if (parsed == null) return 0;
    return parsed < 0 ? 0 : parsed;
  }
  return optionalNonNegativeIntFromValue(_metadataString(value)) ?? 0;
}

int _metadataListLength(Object? value) {
  if (value is List) return value.length;
  if (value is Iterable && value is! String) return value.length;
  return 0;
}

String encodeAiSessionToJsonlText({
  required AiSession session,
  AiSessionExportConfig config = AiSessionExportConfig.defaults,
}) {
  final selection = _selectAiSessionMessages(session: session, config: config);
  final exportedAt = DateTime.now().toUtc().toIso8601String();
  final buffer = StringBuffer();
  buffer.writeln(
    _encodePayload(
      _buildAiSessionHeaderPayload(
        session: session,
        fullMessages: selection.fullMessages,
        messages: selection.messages,
        config: config,
        exportedAt: exportedAt,
      ),
    ),
  );
  for (final selected in selection.messages) {
    buffer.writeln(_encodePayload(_buildAiSessionMessagePayload(selected)));
  }
  return buffer.toString();
}

String normalizeJsonlExportFilename(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return 'session.jsonl';

  final trailingSuffixMatch = RegExp(
    r'\.jsonl$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (trailingSuffixMatch == null) {
    return '$trimmed.jsonl';
  }

  final suffix = trailingSuffixMatch.group(0)!;
  var base = trimmed.substring(0, trimmed.length - suffix.length);
  while (base.toLowerCase().endsWith('.jsonl')) {
    base = base.substring(0, base.length - '.jsonl'.length);
  }
  return '${base.isEmpty ? 'session' : base}$suffix';
}

String jsonlExportPickerSuggestedName(String input) {
  final normalized = normalizeJsonlExportFilename(input);
  final trailingSuffixMatch = RegExp(
    r'\.jsonl$',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (trailingSuffixMatch == null) {
    return normalized;
  }
  final base = normalized.substring(
    0,
    normalized.length - trailingSuffixMatch.group(0)!.length,
  );
  return base.isEmpty ? 'session' : base;
}

String normalizeJsonlExportPath(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return normalizeJsonlExportFilename(input);
  }
  final separators = <String>['/', '\\'];
  var splitIndex = -1;
  for (final separator in separators) {
    final candidate = trimmed.lastIndexOf(separator);
    if (candidate > splitIndex) {
      splitIndex = candidate;
    }
  }
  if (splitIndex == -1) {
    return normalizeJsonlExportFilename(trimmed);
  }
  final directory = trimmed.substring(0, splitIndex + 1);
  final basename = trimmed.substring(splitIndex + 1);
  return '$directory${normalizeJsonlExportFilename(basename)}';
}

/// Exports an [AiSession] to a JSONL file at [destinationPath].
///
/// The format mirrors the Hugging Face dataset card layout used by `pi-mono`:
/// the first line is a `{"type":"session", ...}` header, followed by one
/// `{"type":"message", ...}` line per [AiSessionMessage].
///
/// All non-deleted messages are exported regardless of [AiSessionMessageKind]
/// (user / assistant / reasoning / tool_call / tool / mcp / skill / hook /
/// self_learning / status / compression_point).
///
/// Reports incremental progress through [onProgress] and honours
/// [cancelToken]. On cancellation or error, the partial file is removed.
Future<ExportResult> exportAiSessionToJsonl({
  required AiSession session,
  required String destinationPath,
  required ExportCancelToken cancelToken,
  AiSessionExportConfig config = AiSessionExportConfig.defaults,
  void Function(ExportProgress progress)? onProgress,
}) async {
  final targetFile = File(destinationPath);
  final tempFile = _temporaryExportFile(targetFile);
  IOSink? sink;
  var lines = 0;
  var bytes = 0;
  try {
    await _prepareExportTempFile(targetFile, tempFile);
    final localSink = tempFile.openWrite();
    sink = localSink;

    final selection = _selectAiSessionMessages(
      session: session,
      config: config,
    );
    final fullMessages = selection.fullMessages;
    final messages = selection.messages;
    final total = messages.length + 1; // +1 for the session header line.

    Future<void> emit(Map<String, Object?> payload) async {
      final encoded = _encodePayload(payload);
      localSink.write(encoded);
      localSink.write('\n');
      bytes += utf8.encode(encoded).length + 1;
      lines += 1;
    }

    final headerPayload = _buildAiSessionHeaderPayload(
      session: session,
      fullMessages: fullMessages,
      messages: messages,
      config: config,
      exportedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await emit(headerPayload);
    onProgress?.call(ExportProgress(processed: lines, total: total));

    for (var i = 0; i < messages.length; i++) {
      if (cancelToken.isCancelled) {
        await localSink.flush();
        await localSink.close();
        sink = null;
        await _deleteExportTempFile(tempFile);
        return ExportResult(
          kind: ExportResultKind.cancelled,
          bytesWritten: bytes,
          linesWritten: lines,
        );
      }
      await emit(_buildAiSessionMessagePayload(messages[i]));
      if ((i + 1) % _flushEvery == 0) {
        await localSink.flush();
        onProgress?.call(ExportProgress(processed: lines, total: total));
        await _yieldToEventLoop();
      }
    }

    await localSink.flush();
    await localSink.close();
    sink = null;
    await _commitExportTempFile(tempFile, targetFile);
    onProgress?.call(ExportProgress(processed: lines, total: total));
    return ExportResult(
      kind: ExportResultKind.success,
      bytesWritten: bytes,
      linesWritten: lines,
    );
  } catch (error, stack) {
    silentLog('ai_session_jsonl_exporter', 'export', error, stack);
    try {
      await sink?.close();
    } catch (closeError, closeStack) {
      silentLog(
        'ai_session_jsonl_exporter',
        'sink close after failure',
        closeError,
        closeStack,
      );
    }
    sink = null;
    await _deleteExportTempFile(tempFile);
    return ExportResult(
      kind: ExportResultKind.failure,
      bytesWritten: bytes,
      linesWritten: lines,
      error: error,
    );
  } finally {
    // `sink` was set to null whenever it's been closed. Defensive close in
    // case an unexpected return path reaches `finally` with a live sink.
    if (sink != null) {
      try {
        await sink.close();
      } catch (closeError, closeStack) {
        silentLog(
          'ai_session_jsonl_exporter',
          'sink close in finally',
          closeError,
          closeStack,
        );
      }
    }
  }
}

/// Exports a [HardnessSessionRecord] to a JSONL file at [destinationPath].
///
/// Layout:
///   line 1   : `{"type":"hardness_session", ...}` header (sans phase_logs).
///   line 2..N: one `{"type":"phase_log", ...}` per [HardnessPhaseLogSnapshot].
Future<ExportResult> exportHardnessSessionToJsonl({
  required HardnessSessionRecord record,
  required String destinationPath,
  required ExportCancelToken cancelToken,
  HardnessSessionExportConfig config = HardnessSessionExportConfig.defaults,
  void Function(ExportProgress progress)? onProgress,
}) async {
  final targetFile = File(destinationPath);
  final tempFile = _temporaryExportFile(targetFile);
  IOSink? sink;
  var lines = 0;
  var bytes = 0;
  try {
    await _prepareExportTempFile(targetFile, tempFile);
    final localSink = tempFile.openWrite();
    sink = localSink;
    final fullLogs = record.phaseLogs;
    final lower = (config.startIndex != null && config.startIndex! >= 1)
        ? config.startIndex! - 1
        : 0;
    final upperRaw = (config.endIndex != null && config.endIndex! >= 1)
        ? config.endIndex!
        : fullLogs.length;
    final upper = upperRaw > fullLogs.length ? fullLogs.length : upperRaw;
    final logs = (lower >= upper) ? const [] : fullLogs.sublist(lower, upper);
    final total = logs.length + 1;

    Future<void> emit(Map<String, Object?> payload) async {
      final encoded = _encodePayload(payload);
      localSink.write(encoded);
      localSink.write('\n');
      bytes += utf8.encode(encoded).length + 1;
      lines += 1;
    }

    final fullJson = record.toJson();
    fullJson.remove('phase_logs');
    await emit(<String, Object?>{
      'type': 'hardness_session',
      'version': 1,
      'phase_log_count': logs.length,
      'total_phase_log_count': fullLogs.length,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'export_config': config.toJson(),
      ...fullJson,
    });
    onProgress?.call(ExportProgress(processed: lines, total: total));

    for (var i = 0; i < logs.length; i++) {
      if (cancelToken.isCancelled) {
        await localSink.flush();
        await localSink.close();
        sink = null;
        await _deleteExportTempFile(tempFile);
        return ExportResult(
          kind: ExportResultKind.cancelled,
          bytesWritten: bytes,
          linesWritten: lines,
        );
      }
      await emit(<String, Object?>{
        'type': 'phase_log',
        'sort_order': i,
        ...logs[i].toJson(),
      });
      if ((i + 1) % _flushEvery == 0) {
        await localSink.flush();
        onProgress?.call(ExportProgress(processed: lines, total: total));
        await _yieldToEventLoop();
      }
    }

    await localSink.flush();
    await localSink.close();
    sink = null;
    await _commitExportTempFile(tempFile, targetFile);
    onProgress?.call(ExportProgress(processed: lines, total: total));
    return ExportResult(
      kind: ExportResultKind.success,
      bytesWritten: bytes,
      linesWritten: lines,
    );
  } catch (error, stack) {
    silentLog('ai_session_jsonl_exporter', 'export hardness', error, stack);
    try {
      await sink?.close();
    } catch (closeError, closeStack) {
      silentLog(
        'ai_session_jsonl_exporter',
        'sink close after hardness failure',
        closeError,
        closeStack,
      );
    }
    sink = null;
    await _deleteExportTempFile(tempFile);
    return ExportResult(
      kind: ExportResultKind.failure,
      bytesWritten: bytes,
      linesWritten: lines,
      error: error,
    );
  } finally {
    if (sink != null) {
      try {
        await sink.close();
      } catch (closeError, closeStack) {
        silentLog(
          'ai_session_jsonl_exporter',
          'sink close in hardness finally',
          closeError,
          closeStack,
        );
      }
    }
  }
}
