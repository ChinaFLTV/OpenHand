import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/bounded_json_conversion.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/path_safety.dart';
import '../../../../shared/util/stable_hash.dart';
import '../../../harness/index.dart';
import '../../model/ai_attachment.dart';
import '../../model/ai_session.dart';
import '../../model/ai_session_message.dart';

const String _aiSessionJsonlSchema = 'openhand.ai_session.jsonl';
const int _aiSessionJsonlVersion = 2;
const BoundedJsonConversionConfig _jsonlConversionConfig =
    BoundedJsonConversionConfig(
      maxDepth: 96,
      maxContainerItems: 4096,
      maxTotalNodes: 32768,
      maxDepthPlaceholder: '<max_depth_exceeded>',
      cyclicMapPlaceholder: '<cyclic_map>',
      cyclicIterablePlaceholder: '<cyclic_iterable>',
    );
const String _jsonlExtension = '.jsonl';
const String _defaultJsonlExportFilename = 'session.jsonl';
final RegExp _jsonlExtensionPattern = RegExp(r'\.jsonl$', caseSensitive: false);
const int _exportTitleMaxCharacters = 80;
const int _exportTitleMaxUtf8Bytes = 100;
const int _exportSessionIdPrefixMaxCharacters = 115;
const int _exportSessionIdPrefixMaxUtf8Bytes = 115;
const int _exportSessionIdHashLength = 12;
int _exportTempFileSerial = 0;

typedef _JsonlExportSource = ({
  Map<String, Object?> header,
  int itemCount,
  Map<String, Object?> Function(int index) itemAt,
});

/// 导出任务使用的协作式取消令牌。
class ExportCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() {
    _cancelled = true;
  }
}

class ExportProgress {
  const ExportProgress({required this.processed, required this.total});
  final int processed;
  final int total;
  double get fraction => unitRatio(processed, total);
}

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

/// 大批量导出时让出事件循环，避免阻塞界面渲染。
Future<void> _yieldToEventLoop() => Future<void>.delayed(Duration.zero);

/// 每批写入行数。
const int _flushEvery = 32;
const Duration _exportFileIoTimeout = Duration(seconds: 10);

File _temporaryExportFile(File targetFile) {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final serial = _exportTempFileSerial++;
  return File('${targetFile.path}.openhand-$pid-$stamp-$serial.tmp');
}

Future<void> _prepareExportTempFile(File targetFile, File tempFile) async {
  final parent = targetFile.parent;
  if (!await parent.exists().timeout(_exportFileIoTimeout)) {
    await parent.create(recursive: true).timeout(_exportFileIoTimeout);
  }
  if (await tempFile.exists().timeout(_exportFileIoTimeout)) {
    await tempFile.delete().timeout(_exportFileIoTimeout);
  }
}

Future<void> _deleteExportTempFile(File tempFile) async {
  try {
    if (await tempFile.exists().timeout(_exportFileIoTimeout)) {
      await tempFile.delete().timeout(_exportFileIoTimeout);
    }
  } catch (error, stack) {
    silentLog('ai_session_jsonl_exporter', '删除临时文件', error, stack);
  }
}

Future<void> _commitExportTempFile(
  File tempFile,
  File targetFile,
  int maxBytes,
) async {
  try {
    await copyFileAtomically(tempFile, targetFile, maxBytes: maxBytes);
  } catch (_) {
    await _deleteExportTempFile(tempFile);
    rethrow;
  }
  await _deleteExportTempFile(tempFile);
}

class _SelectedAiSessionMessage {
  const _SelectedAiSessionMessage({
    required this.message,
    required this.originalIndex,
    required this.exportIndex,
  });

  final AiSessionMessage message;

  /// 消息在完整持久化会话中的零基索引。
  final int originalIndex;

  /// 消息在过滤后导出集合中的零基索引。
  final int exportIndex;
}

/// AI 会话导出配置。
class AiSessionExportConfig {
  const AiSessionExportConfig({
    this.roles,
    this.kinds,
    this.includeDeleted = false,
    this.startIndex,
    this.endIndex,
  });

  /// 要导出的消息角色；`null` 表示全部角色。
  final Set<AiSessionMessageRole>? roles;

  /// 要导出的消息类型；`null` 表示全部类型。
  final Set<AiSessionMessageKind>? kinds;

  /// 是否包含已删除消息。
  final bool includeDeleted;

  /// 角色和类型过滤前的一基闭区间下界；`null` 表示不限制。
  final int? startIndex;

  /// 角色和类型过滤前的一基闭区间上界；`null` 表示不限制。
  final int? endIndex;

  static const AiSessionExportConfig defaults = AiSessionExportConfig();

  Map<String, Object?> toJson() => <String, Object?>{
    'roles': roles?.map((role) => role.storageValue).toList(),
    'kinds': kinds?.map((kind) => kind.storageValue).toList(),
    'include_deleted': includeDeleted,
    'start_index': startIndex,
    'end_index': endIndex,
  };
}

/// Harness 会话导出配置。
class HarnessSessionExportConfig {
  const HarnessSessionExportConfig({this.startIndex, this.endIndex});

  /// 阶段日志的一基闭区间下界。
  final int? startIndex;

  /// 阶段日志的一基闭区间上界。
  final int? endIndex;

  static const HarnessSessionExportConfig defaults =
      HarnessSessionExportConfig();

  Map<String, Object?> toJson() => <String, Object?>{
    'start_index': startIndex,
    'end_index': endIndex,
  };
}

String _encodePayload(Map<String, Object?> payload) {
  return jsonEncode(
    convertToJsonSafeMap(payload, config: _jsonlConversionConfig),
  );
}

({
  List<AiSessionMessage> fullMessages,
  List<_SelectedAiSessionMessage> messages,
})
_selectAiSessionMessages({
  required AiSession session,
  required AiSessionExportConfig config,
}) {
  // 先按完整消息顺序应用一基闭区间，再过滤角色、类型和删除状态。
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
    ...session.toJson(includeMessages: false),
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
    if (value is String && nullIfBlank(value) == null) return;
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
    aiSessionMessageToolCallIdMetadataKey,
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

/// 逐行编码会话，避免 Web 下载期间额外保留完整会话字符串。
Stream<List<int>> encodeAiSessionToJsonlByteStream({
  required AiSession session,
  AiSessionExportConfig config = AiSessionExportConfig.defaults,
}) async* {
  var emittedLines = 0;
  for (final line in _encodeAiSessionJsonlLines(
    session: session,
    config: config,
  )) {
    yield utf8.encode('$line\n');
    emittedLines += 1;
    if (emittedLines % _flushEvery == 0) {
      await _yieldToEventLoop();
    }
  }
}

Iterable<String> _encodeAiSessionJsonlLines({
  required AiSession session,
  required AiSessionExportConfig config,
}) sync* {
  final selection = _selectAiSessionMessages(session: session, config: config);
  final exportedAt = DateTime.now().toUtc().toIso8601String();
  yield _encodePayload(
    _buildAiSessionHeaderPayload(
      session: session,
      fullMessages: selection.fullMessages,
      messages: selection.messages,
      config: config,
      exportedAt: exportedAt,
    ),
  );
  for (final selected in selection.messages) {
    yield _encodePayload(_buildAiSessionMessagePayload(selected));
  }
}

String normalizeJsonlExportFilename(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return _defaultJsonlExportFilename;

  final trailingSuffixMatch = _jsonlExtensionPattern.firstMatch(trimmed);
  if (trailingSuffixMatch == null) {
    return '$trimmed$_jsonlExtension';
  }

  final suffix = trailingSuffixMatch.group(0)!;
  var base = trimmed.substring(0, trimmed.length - suffix.length);
  while (base.toLowerCase().endsWith(_jsonlExtension)) {
    base = base.substring(0, base.length - _jsonlExtension.length);
  }
  return '${base.isEmpty ? 'session' : base}$suffix';
}

/// 生成长度受控且可跨平台使用的会话导出文件名。
String buildJsonlExportFilename({
  required String title,
  required String sessionId,
}) {
  final normalizedTitle = sanitizePortableFileNamePart(
    title,
    fallback: 'session',
    maxCharacters: _exportTitleMaxCharacters,
    maxUtf8Bytes: _exportTitleMaxUtf8Bytes,
    allowWhitespace: true,
    collapseReplacement: true,
  );
  final rawSessionId = sessionId.trim();
  var normalizedSessionId = sanitizePortableFileNamePart(
    rawSessionId,
    fallback: 'session',
    maxCharacters: _exportSessionIdPrefixMaxCharacters,
    maxUtf8Bytes: _exportSessionIdPrefixMaxUtf8Bytes,
    allowWhitespace: true,
    collapseReplacement: true,
    trimBoundaryReplacement: true,
  );
  if (normalizedSessionId != rawSessionId) {
    normalizedSessionId =
        '${normalizedSessionId}_'
        '${stableSha256Hex(rawSessionId, length: _exportSessionIdHashLength)}';
  }
  return '${normalizedTitle}_$normalizedSessionId$_jsonlExtension';
}

String jsonlExportPickerSuggestedName(String input) {
  final normalized = normalizeJsonlExportFilename(input);
  final trailingSuffixMatch = _jsonlExtensionPattern.firstMatch(normalized);
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

/// 将 [AiSession] 导出为 JSONL；取消或失败时删除临时文件。
Future<ExportResult> exportAiSessionToJsonl({
  required AiSession session,
  required String destinationPath,
  required ExportCancelToken cancelToken,
  AiSessionExportConfig config = AiSessionExportConfig.defaults,
  void Function(ExportProgress progress)? onProgress,
}) {
  return _writeJsonlExport(
    destinationPath: destinationPath,
    cancelToken: cancelToken,
    logLabel: 'AI 会话',
    onProgress: onProgress,
    sourceBuilder: () {
      final selection = _selectAiSessionMessages(
        session: session,
        config: config,
      );
      final messages = selection.messages;
      return (
        header: _buildAiSessionHeaderPayload(
          session: session,
          fullMessages: selection.fullMessages,
          messages: messages,
          config: config,
          exportedAt: DateTime.now().toUtc().toIso8601String(),
        ),
        itemCount: messages.length,
        itemAt: (index) => _buildAiSessionMessagePayload(messages[index]),
      );
    },
  );
}

/// 将 [HarnessSessionRecord] 导出为 JSONL；首行为会话信息，后续每行为一条阶段日志。
Future<ExportResult> exportHarnessSessionToJsonl({
  required HarnessSessionRecord record,
  required String destinationPath,
  required ExportCancelToken cancelToken,
  HarnessSessionExportConfig config = HarnessSessionExportConfig.defaults,
  void Function(ExportProgress progress)? onProgress,
}) {
  return _writeJsonlExport(
    destinationPath: destinationPath,
    cancelToken: cancelToken,
    logLabel: 'Harness 会话',
    onProgress: onProgress,
    sourceBuilder: () {
      final fullLogs = record.phaseLogs;
      final lower = (config.startIndex != null && config.startIndex! >= 1)
          ? config.startIndex! - 1
          : 0;
      final upperRaw = (config.endIndex != null && config.endIndex! >= 1)
          ? config.endIndex!
          : fullLogs.length;
      final upper = upperRaw > fullLogs.length ? fullLogs.length : upperRaw;
      final logs = lower >= upper
          ? const <HarnessPhaseLogSnapshot>[]
          : fullLogs.sublist(lower, upper);
      final fullJson = record.toJson()..remove('phase_logs');
      return (
        header: <String, Object?>{
          'type': 'harness_session',
          'version': 1,
          'phase_log_count': logs.length,
          'total_phase_log_count': fullLogs.length,
          'exported_at': DateTime.now().toUtc().toIso8601String(),
          'export_config': config.toJson(),
          ...fullJson,
        },
        itemCount: logs.length,
        itemAt: (index) => <String, Object?>{
          'type': 'phase_log',
          'sort_order': index,
          ...logs[index].toJson(),
        },
      );
    },
  );
}

Future<ExportResult> _writeJsonlExport({
  required String destinationPath,
  required ExportCancelToken cancelToken,
  required String logLabel,
  required _JsonlExportSource Function() sourceBuilder,
  required void Function(ExportProgress progress)? onProgress,
}) async {
  final targetFile = File(destinationPath);
  final tempFile = _temporaryExportFile(targetFile);
  BoundedRandomAccessFileLease? output;
  var deleteOnRelease = false;
  var lines = 0;
  var bytes = 0;
  try {
    await _prepareExportTempFile(targetFile, tempFile);
    final openedOutput = await openBoundedRandomAccessFileLease(
      tempFile,
      mode: FileMode.write,
      timeout: _exportFileIoTimeout,
      deleteIfOpenCompletesLate: true,
      release: (file) async {
        await file.close();
        if (deleteOnRelease) await _deleteExportTempFile(tempFile);
      },
    );
    output = openedOutput;
    final source = sourceBuilder();
    final total = source.itemCount + 1;
    final buffer = StringBuffer();

    void emit(Map<String, Object?> payload) {
      final encoded = _encodePayload(payload);
      buffer.writeln(encoded);
      bytes += utf8.encode(encoded).length + 1;
      lines += 1;
    }

    emit(source.header);
    onProgress?.call(ExportProgress(processed: lines, total: total));

    for (var i = 0; i < source.itemCount; i++) {
      if (cancelToken.isCancelled) {
        deleteOnRelease = true;
        await openedOutput.close(timeout: _exportFileIoTimeout);
        output = null;
        await _deleteExportTempFile(tempFile);
        return ExportResult(
          kind: ExportResultKind.cancelled,
          bytesWritten: bytes,
          linesWritten: lines,
        );
      }
      emit(source.itemAt(i));
      if ((i + 1) % _flushEvery == 0) {
        await _writeExportBuffer(openedOutput, buffer);
        onProgress?.call(ExportProgress(processed: lines, total: total));
        await _yieldToEventLoop();
      }
    }

    await _writeExportBuffer(openedOutput, buffer);
    await openedOutput.close(timeout: _exportFileIoTimeout);
    output = null;
    await _commitExportTempFile(tempFile, targetFile, bytes);
    onProgress?.call(ExportProgress(processed: lines, total: total));
    return ExportResult(
      kind: ExportResultKind.success,
      bytesWritten: bytes,
      linesWritten: lines,
    );
  } catch (error, stack) {
    silentLog('ai_session_jsonl_exporter', '导出 $logLabel', error, stack);
    deleteOnRelease = true;
    await output?.cleanup();
    output = null;
    await _deleteExportTempFile(tempFile);
    return ExportResult(
      kind: ExportResultKind.failure,
      bytesWritten: bytes,
      linesWritten: lines,
      error: error,
    );
  } finally {
    deleteOnRelease = true;
    await output?.cleanup();
  }
}

Future<void> _writeExportBuffer(
  BoundedRandomAccessFileLease output,
  StringBuffer buffer,
) async {
  if (buffer.isEmpty) return;
  final chunk = utf8.encode(buffer.toString());
  buffer.clear();
  await output.run<void>((file) async {
    await file.writeFrom(chunk);
    await file.flush();
  }, timeout: _exportFileIoTimeout);
}
