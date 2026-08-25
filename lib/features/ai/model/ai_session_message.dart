import 'package:characters/characters.dart';

import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_normalization.dart';
import 'ai_attachment.dart';
import 'ai_session_goal.dart';
import 'ai_token_usage.dart';

enum AiSessionMessageKind {
  user('user'),
  assistant('assistant'),
  reasoning('reasoning'),
  toolCall('tool_call'),
  tool('tool'),
  compressionPoint('compression_point'),
  mcp('mcp'),
  skill('skill'),
  hook('hook'),
  selfLearning('self_learning'),
  fileMutationSummary('file_mutation_summary'),
  status('status');

  const AiSessionMessageKind(this.storageValue);

  final String storageValue;

  /// 是否为工具结果类消息（tool / mcp / skill / hook）。
  ///
  /// transcript 配对与提示词组装共用此判定；穷举 switch 保证新增
  /// kind 时编译期强制补充归类，避免两处漂移。
  bool get isToolResultKind => switch (this) {
    AiSessionMessageKind.tool ||
    AiSessionMessageKind.mcp ||
    AiSessionMessageKind.skill ||
    AiSessionMessageKind.hook => true,
    AiSessionMessageKind.user ||
    AiSessionMessageKind.assistant ||
    AiSessionMessageKind.reasoning ||
    AiSessionMessageKind.toolCall ||
    AiSessionMessageKind.compressionPoint ||
    AiSessionMessageKind.selfLearning ||
    AiSessionMessageKind.fileMutationSummary ||
    AiSessionMessageKind.status => false,
  };

  static AiSessionMessageKind fromStorage(String value) {
    return enumByStorageValueOr(
      values,
      value,
      (kind) => kind.storageValue,
      fallback: AiSessionMessageKind.user,
      normalize: (item) => item.toLowerCase(),
    );
  }
}

enum AiSessionMessageRole {
  system('system'),
  user('user'),
  assistant('assistant'),
  tool('tool');

  const AiSessionMessageRole(this.storageValue);

  final String storageValue;

  static AiSessionMessageRole fromStorage(String value) {
    return enumByStorageValueOr(
      values,
      value,
      (role) => role.storageValue,
      fallback: AiSessionMessageRole.user,
      normalize: (item) => item.toLowerCase(),
    );
  }
}

const String aiSessionMessageMetadataStreamingKey = 'streaming';
const String aiSessionMessageUsageEstimatedMetadataKey = 'usage_estimated';
const String aiSessionMessageToolCallIdMetadataKey = 'tool_call_id';
const String aiSessionMessageTelemetryInFlightMetadataKey =
    'telemetry_in_flight';
const String aiSessionMessageRequestStartedAtMetadataKey = 'request_started_at';
const String aiSessionMessageFirstTokenAtMetadataKey = 'first_token_at';
const String aiSessionMessageRequestEndedAtMetadataKey = 'ended_at';
const String aiSessionMessageGenerationEndedAtMetadataKey =
    'generation_finished_at';
const String aiSessionMessageTotalDurationMsMetadataKey = 'total_duration_ms';
const String aiSessionMessageTtftMsMetadataKey = 'ttft_ms';
const String aiSessionMessageGenerationDurationMsMetadataKey =
    'generation_duration_ms';
const String aiSessionMessageTokensPerSecondMetadataKey = 'tokens_per_second';
const String aiSessionMessageOutputCharactersMetadataKey = 'output_characters';
const String aiSessionMessageCharactersPerSecondMetadataKey =
    'characters_per_second';
const String aiSessionMessageStreamEventCountMetadataKey = 'stream_event_count';
const String aiSessionMessageStreamThroughputSamplesMetadataKey =
    'stream_throughput_chars_per_second';
const String aiSessionMessageStreamThroughputIntervalMetadataKey =
    'stream_throughput_sample_interval_ms';
const String aiSessionMessageTruncatedPlaceholder = '<已截断>';
const String aiSessionMessageDeferredTelemetryMetadataKey =
    '_openhand_deferred_telemetry';
const String aiSessionMessageContentPreviewMetadataKey =
    '_openhand_content_preview';
const List<String> aiSessionMessageDeferredTelemetryMetadataKeys = <String>[
  'request_payload',
  'response_raw',
  'composed_prompt_turns',
  'composed_prompt_text',
  'prompt_metadata',
  aiSessionMessageStreamThroughputSamplesMetadataKey,
];
final Set<String> _aiSessionMessageDeferredTelemetryMetadataKeySet =
    aiSessionMessageDeferredTelemetryMetadataKeys.toSet();
const String aiSessionMessageReasoningStartedAtKey = 'reasoning_started_at';
const String aiSessionMessageReasoningEndedAtKey = 'reasoning_ended_at';
const String aiSessionMessageReasoningElapsedMsKey = 'reasoning_elapsed_ms';
const String aiSessionMessageContentFormatKey = 'content_format';
const String aiSessionMessageSenderOriginExplicitUser = 'explicit_user';
const String aiSessionMessageSenderOriginOpenHandBackground =
    'openhand_background';
const String aiSessionMessageSenderOriginAiModel = 'ai_model';
const String aiSessionMessageSenderOriginOpenHandSystem = 'openhand_system';
const String aiSessionMessageConversationSideNonAi = 'non_ai';
const String aiSessionMessageConversationSideAi = 'ai';
const String aiSessionMessageConversationSideSystem = 'system';
const String aiSessionMessageSenderOriginJsonKey = 'sender_origin';
const String aiSessionMessageConversationSideJsonKey = 'conversation_side';
final RegExp _aiSessionMessageLineBreakPattern = RegExp(r'\r?\n');
final RegExp _aiSessionMessagePromptBulletPrefixPattern = RegExp(r'^[-*]\s*');
const String aiSessionMessageStartsConversationRoundJsonKey =
    'starts_conversation_round';
const String aiSessionGoalEvaluationMessageMetadataKey =
    'goal_evaluation_message';
const String aiSessionGoalEvaluationMessageTypeMetadataKey =
    'goal_evaluation_message_type';

bool aiSessionMessageHasDeferredTelemetryMetadata(
  Map<String, Object?> metadata,
) {
  return metadata[aiSessionMessageDeferredTelemetryMetadataKey] == true;
}

Map<String, Object?> aiSessionMessageTranscriptMetadata(
  Map<String, Object?> metadata,
) {
  final hasDeferredFields = aiSessionMessageDeferredTelemetryMetadataKeys.any(
    metadata.containsKey,
  );
  if (!hasDeferredFields) {
    return metadata;
  }
  return <String, Object?>{
    for (final entry in metadata.entries)
      if (!_aiSessionMessageDeferredTelemetryMetadataKeySet.contains(entry.key))
        entry.key: entry.value,
    aiSessionMessageDeferredTelemetryMetadataKey: true,
  };
}

Map<String, Object?> aiSessionMessageMetadataWithoutDeferredTelemetryMarker(
  Map<String, Object?> metadata,
) {
  if (!metadata.containsKey(aiSessionMessageDeferredTelemetryMetadataKey)) {
    return metadata;
  }
  return <String, Object?>{
    for (final entry in metadata.entries)
      if (entry.key != aiSessionMessageDeferredTelemetryMetadataKey)
        entry.key: entry.value,
  };
}

const String aiSessionGoalEvaluationMessageTypeRequest = 'request';
const String aiSessionGoalEvaluationMessageTypeResponse = 'response';
const String aiSessionGoalEvaluationRoundIndexMetadataKey =
    'goal_evaluation_round_index';
const String aiSessionGoalEvaluationPassedMetadataKey =
    'goal_evaluation_passed';
const String aiSessionGoalTotalTokensMetadataKey = 'goal_total_tokens';
const String aiSessionGoalElapsedMsMetadataKey = 'goal_elapsed_ms';
const String aiSessionGoalStartedAtMetadataKey = 'goal_started_at';
const String aiSessionGoalCompletedAtMetadataKey = 'goal_completed_at';
const String aiSessionMessageFeedbackMetadataKey = 'message_feedback';
const String aiSessionMessageResponseVariantsMetadataKey = 'response_variants';
const String aiSessionMessageResponseVariantIndexMetadataKey =
    'response_variant_index';
const int aiSessionMessageMaxResponseVariants = 20;
const int aiSessionMessageMaxVariantIntermediateMessageIds = 1000;
const int _aiSessionMessageResponseVariantMetadataScanLimit =
    aiSessionMessageMaxResponseVariants * 5;
const int _aiSessionMessageMaxVariantReferenceIdCharacters = 256;
const String aiSessionMachineExpertRequestCardMetadataKey =
    'machine_expert_request_card';
const String aiSessionWebReverseRequestCardMetadataKey =
    'web_reverse_request_card';
const String aiSessionAndroidReverseRequestCardMetadataKey =
    'android_reverse_request_card';
const int aiSessionExpertRequestCardSchemaVersion = 1;
const int aiSessionExpertRequestCardMaxFieldCharacters = 1600;
const int aiSessionMachineExpertRequestCardSchemaVersion =
    aiSessionExpertRequestCardSchemaVersion;
const Set<String> _aiSessionTranscriptMediaMetadataKeys = <String>{
  'image_path',
  'image_paths',
  'generated_image_path',
  'generated_image_paths',
  'video_path',
  'video_paths',
  'generated_video_path',
  'generated_video_paths',
  'audio_path',
  'audio_paths',
  'generated_audio_path',
  'generated_audio_paths',
  'media_path',
  'media_paths',
};
const Set<String> _aiSessionTranscriptStructuredMetadataKeys = <String>{
  aiSessionMachineExpertRequestCardMetadataKey,
  aiSessionWebReverseRequestCardMetadataKey,
  aiSessionAndroidReverseRequestCardMetadataKey,
  aiSessionGoalIdMetadataKey,
  aiSessionGoalObjectiveMetadataKey,
  aiSessionGoalEvaluationIdMetadataKey,
  aiSessionGoalAutoFollowUpMetadataKey,
  aiSessionGoalEvaluationMessageMetadataKey,
};
const Set<String> _aiSessionTranscriptToolMetadataKeys = <String>{
  'tool_call_id',
  'tool_name',
  'tool_arguments',
  'tool_calls',
  'tool_arguments_streaming',
  'tool_preparing',
  'tool_execution_status',
  'tool_status',
  'status',
  'tool_execution_command',
  'tool_execution_stdout',
  'tool_execution_stderr',
  'tool_execution_result',
  'result_text',
};
const Set<String> _aiSessionTranscriptFileMutationMetadataKeys = <String>{
  'file_mutation_path',
  'file_mutation_paths',
  'file_mutation_kind',
  'round_summary_tool_call_ids',
  'round_summary_source_message_ids',
  'round_summary_record_count',
};

enum AiSessionMessageFeedback {
  liked('liked'),
  needsImprovement('needs_improvement');

  const AiSessionMessageFeedback(this.storageValue);

  final String storageValue;

  static AiSessionMessageFeedback? fromStorage(Object? value) {
    return enumByStorageValue(
      values,
      value,
      (feedback) => feedback.storageValue,
    );
  }
}

/// 判定 [AiSessionMessage.carriesRequestTelemetry] 时检查的 metadata key。
const List<String> _requestTelemetryMetadataKeys = <String>[
  'started_at',
  'request_url',
  'request_payload',
  'response_raw',
  'error',
  'telemetry',
];

class AiSessionMessage {
  factory AiSessionMessage.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    final createdAt =
        utcDateTimeFromValue(json['created_at']) ?? DateTime.now().toUtc();
    final content = stripImageSummaryMarkup('${json['content'] ?? ''}');
    return AiSessionMessage(
      id: '${json['id'] ?? ''}',
      kind: AiSessionMessageKind.fromStorage('${json['kind'] ?? ''}'),
      role: AiSessionMessageRole.fromStorage('${json['role'] ?? ''}'),
      content: content,
      createdAt: createdAt,
      characterCount: nonNegativeIntFromValue(
        json['character_count'],
        fallback: countCharacters(content),
      ),
      isDeleted: boolFromValue(json['is_deleted']),
      modelId: _readNullableString(json['model_id']),
      modelLabel: _readNullableString(json['model_label']),
      usage: _readUsage(json['usage']),
      metadata: Map<String, Object?>.of(
        stringKeyedMapFromValue(json['metadata']),
      ),
    );
  }
  const AiSessionMessage({
    required this.id,
    required this.kind,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.characterCount,
    this.isDeleted = false,
    this.modelId,
    this.modelLabel,
    this.usage,
    this.metadata = const <String, Object?>{},
  });

  factory AiSessionMessage.user({
    required String id,
    required String content,
    required DateTime createdAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.user,
      role: AiSessionMessageRole.user,
      content: content.trim(),
      createdAt: createdAt.toUtc(),
      characterCount: countCharacters(content),
      metadata: metadata,
    );
  }

  factory AiSessionMessage.assistant({
    required String id,
    required String content,
    required DateTime createdAt,
    String? modelId,
    String? modelLabel,
    AiTokenUsage? usage,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.assistant,
      role: AiSessionMessageRole.assistant,
      content: content.trim(),
      createdAt: createdAt.toUtc(),
      characterCount: countCharacters(content),
      modelId: modelId,
      modelLabel: modelLabel,
      usage: usage,
      metadata: metadata,
    );
  }

  factory AiSessionMessage.reasoning({
    required String id,
    required String content,
    required DateTime createdAt,
    String? modelId,
    String? modelLabel,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.reasoning,
      role: AiSessionMessageRole.assistant,
      content: content.trim(),
      createdAt: createdAt.toUtc(),
      characterCount: countCharacters(content),
      modelId: modelId,
      modelLabel: modelLabel,
      metadata: metadata,
    );
  }

  factory AiSessionMessage.toolCall({
    required String id,
    required String content,
    required DateTime createdAt,
    required Map<String, Object?> metadata,
    String? modelId,
    String? modelLabel,
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.toolCall,
      role: AiSessionMessageRole.assistant,
      content: content.trim(),
      createdAt: createdAt.toUtc(),
      characterCount: countCharacters(content),
      modelId: modelId,
      modelLabel: modelLabel,
      metadata: metadata,
    );
  }

  factory AiSessionMessage.toolResult({
    required String id,
    required String content,
    required DateTime createdAt,
    required Map<String, Object?> metadata,
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.tool,
      role: AiSessionMessageRole.tool,
      content: content.trim(),
      createdAt: createdAt.toUtc(),
      characterCount: countCharacters(content),
      metadata: metadata,
    );
  }

  factory AiSessionMessage.mcpResult({
    required String id,
    required String content,
    required DateTime createdAt,
    required Map<String, Object?> metadata,
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.mcp,
      role: AiSessionMessageRole.tool,
      content: content.trim(),
      createdAt: createdAt.toUtc(),
      characterCount: countCharacters(content),
      metadata: metadata,
    );
  }

  factory AiSessionMessage.skillResult({
    required String id,
    required String content,
    required DateTime createdAt,
    required Map<String, Object?> metadata,
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.skill,
      role: AiSessionMessageRole.tool,
      content: content.trim(),
      createdAt: createdAt.toUtc(),
      characterCount: countCharacters(content),
      metadata: metadata,
    );
  }

  factory AiSessionMessage.hookResult({
    required String id,
    required String content,
    required DateTime createdAt,
    required Map<String, Object?> metadata,
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.hook,
      role: AiSessionMessageRole.tool,
      content: content.trim(),
      createdAt: createdAt.toUtc(),
      characterCount: countCharacters(content),
      metadata: metadata,
    );
  }

  factory AiSessionMessage.selfLearning({
    required String id,
    required String content,
    required DateTime createdAt,
    required Map<String, Object?> metadata,
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.selfLearning,
      role: AiSessionMessageRole.system,
      content: content.trim(),
      createdAt: createdAt.toUtc(),
      characterCount: countCharacters(content),
      metadata: metadata,
    );
  }

  factory AiSessionMessage.status({
    required String id,
    required String content,
    required DateTime createdAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.status,
      role: AiSessionMessageRole.system,
      content: content.trim(),
      createdAt: createdAt.toUtc(),
      characterCount: countCharacters(content),
      metadata: metadata,
    );
  }

  factory AiSessionMessage.fileMutationSummary({
    required String id,
    required DateTime createdAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.fileMutationSummary,
      role: AiSessionMessageRole.system,
      content: '',
      createdAt: createdAt.toUtc(),
      characterCount: 0,
      metadata: <String, Object?>{
        ...metadata,
        'round_file_mutation_summary': true,
      },
    );
  }

  factory AiSessionMessage.compressionPoint({
    required String id,
    required String content,
    required DateTime createdAt,
    required Map<String, Object?> metadata,
    String? modelId,
    String? modelLabel,
    AiTokenUsage? usage,
  }) {
    return AiSessionMessage(
      id: id,
      kind: AiSessionMessageKind.compressionPoint,
      role: AiSessionMessageRole.system,
      content: content.trim(),
      createdAt: createdAt.toUtc(),
      characterCount: countCharacters(content),
      metadata: metadata,
      modelId: modelId,
      modelLabel: modelLabel,
      usage: usage,
    );
  }

  final String id;
  final AiSessionMessageKind kind;
  final AiSessionMessageRole role;
  final String content;
  final DateTime createdAt;
  final int characterCount;
  final bool isDeleted;
  final String? modelId;
  final String? modelLabel;
  final AiTokenUsage? usage;
  final Map<String, Object?> metadata;

  bool get isOpenHandBackgroundInput {
    final senderOriginValue =
        '${metadata[aiSessionMessageSenderOriginJsonKey] ?? ''}'.trim();
    if (senderOriginValue == aiSessionMessageSenderOriginOpenHandBackground) {
      return true;
    }
    return kind == AiSessionMessageKind.tool ||
        kind == AiSessionMessageKind.mcp ||
        kind == AiSessionMessageKind.skill ||
        kind == AiSessionMessageKind.hook;
  }

  bool get startsConversationRound {
    if (isDeleted) {
      return false;
    }
    if (isGoalEvaluationMessage) {
      return false;
    }
    return kind == AiSessionMessageKind.user || isOpenHandBackgroundInput;
  }

  bool get isGoalEvaluationMessage {
    return metadata[aiSessionGoalEvaluationMessageMetadataKey] == true;
  }

  bool get isAiSideConversationMessage {
    if (isDeleted) {
      return false;
    }
    return kind == AiSessionMessageKind.assistant ||
        kind == AiSessionMessageKind.reasoning ||
        kind == AiSessionMessageKind.toolCall;
  }

  /// 该消息是否带有可供审计 / 缓存分析读取的调用遥测。
  ///
  /// 审计弹窗与缓存命中趋势此前各自内联了同一份判定；一旦某侧漏加
  /// metadata key，同一条消息会在两个界面里一个有详情一个没有。
  bool get carriesRequestTelemetry {
    if (modelId != null || usage != null) {
      return true;
    }
    return _requestTelemetryMetadataKeys.any(metadata.containsKey);
  }

  String get senderOrigin {
    final metadataSenderOrigin =
        '${metadata[aiSessionMessageSenderOriginJsonKey] ?? ''}'.trim();
    if (metadataSenderOrigin.isNotEmpty) {
      return metadataSenderOrigin;
    }
    if (kind == AiSessionMessageKind.user) {
      return aiSessionMessageSenderOriginExplicitUser;
    }
    if (isOpenHandBackgroundInput) {
      return aiSessionMessageSenderOriginOpenHandBackground;
    }
    if (kind == AiSessionMessageKind.assistant ||
        kind == AiSessionMessageKind.reasoning ||
        kind == AiSessionMessageKind.toolCall) {
      return aiSessionMessageSenderOriginAiModel;
    }
    return aiSessionMessageSenderOriginOpenHandSystem;
  }

  String get conversationSide {
    if (kind == AiSessionMessageKind.user || isOpenHandBackgroundInput) {
      return aiSessionMessageConversationSideNonAi;
    }
    if (kind == AiSessionMessageKind.assistant ||
        kind == AiSessionMessageKind.reasoning ||
        kind == AiSessionMessageKind.toolCall) {
      return aiSessionMessageConversationSideAi;
    }
    return aiSessionMessageConversationSideSystem;
  }

  Map<String, Object?> derivedConversationJson() {
    return <String, Object?>{
      aiSessionMessageSenderOriginJsonKey: senderOrigin,
      aiSessionMessageConversationSideJsonKey: conversationSide,
      aiSessionMessageStartsConversationRoundJsonKey: startsConversationRound,
    };
  }

  bool get isVisible =>
      !isDeleted &&
      (kind != AiSessionMessageKind.status ||
          metadata['round_file_mutation_summary'] == true);

  bool get isTranscriptRenderable {
    if (!isVisible) {
      return false;
    }
    if (content.trim().isNotEmpty) {
      return true;
    }
    if (_metadataHasRenderableValue(
      metadata[aiSessionMessageAttachmentsMetadataKey],
    )) {
      return true;
    }
    if (_metadataHasAnyRenderableValue(_aiSessionTranscriptMediaMetadataKeys)) {
      return true;
    }

    return switch (kind) {
      AiSessionMessageKind.toolCall ||
      AiSessionMessageKind.tool ||
      AiSessionMessageKind.mcp ||
      AiSessionMessageKind.skill ||
      AiSessionMessageKind.hook => _metadataHasAnyRenderableValue(
        _aiSessionTranscriptToolMetadataKeys,
      ),
      AiSessionMessageKind.fileMutationSummary =>
        _metadataHasAnyRenderableValue(
          _aiSessionTranscriptFileMutationMetadataKeys,
        ),
      AiSessionMessageKind.status =>
        metadata['round_file_mutation_summary'] == true &&
            _metadataHasAnyRenderableValue(
              _aiSessionTranscriptFileMutationMetadataKeys,
            ),
      AiSessionMessageKind.user ||
      AiSessionMessageKind.assistant ||
      AiSessionMessageKind.reasoning ||
      AiSessionMessageKind.compressionPoint ||
      AiSessionMessageKind.selfLearning => _metadataHasAnyRenderableValue(
        _aiSessionTranscriptStructuredMetadataKeys,
      ),
    };
  }

  bool _metadataHasAnyRenderableValue(Set<String> keys) {
    for (final key in keys) {
      if (_metadataHasRenderableValue(metadata[key])) {
        return true;
      }
    }
    return false;
  }

  static bool _metadataHasRenderableValue(Object? value) {
    if (value == null) {
      return false;
    }
    if (value is String) {
      return value.trim().isNotEmpty;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value > 0;
    }
    if (value is Iterable) {
      for (final item in value) {
        if (_metadataHasRenderableValue(item)) {
          return true;
        }
      }
      return false;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (_metadataHasRenderableValue(entry.value)) {
          return true;
        }
      }
      return false;
    }
    return true;
  }

  bool get isConversationTurn {
    if (isDeleted) {
      return false;
    }
    if (isGoalEvaluationMessage) {
      return false;
    }
    return switch (kind) {
      AiSessionMessageKind.user => true,
      AiSessionMessageKind.assistant => true,
      AiSessionMessageKind.toolCall => true,
      AiSessionMessageKind.tool => true,
      AiSessionMessageKind.compressionPoint => true,
      AiSessionMessageKind.reasoning => false,
      AiSessionMessageKind.mcp => true,
      AiSessionMessageKind.skill => true,
      AiSessionMessageKind.hook => true,
      AiSessionMessageKind.selfLearning => true,
      AiSessionMessageKind.fileMutationSummary => false,
      AiSessionMessageKind.status => false,
    };
  }

  AiSessionMessage copyWith({
    String? id,
    AiSessionMessageKind? kind,
    AiSessionMessageRole? role,
    String? content,
    DateTime? createdAt,
    int? characterCount,
    bool? isDeleted,
    String? modelId,
    String? modelLabel,
    AiTokenUsage? usage,
    Map<String, Object?>? metadata,
  }) {
    final nextContent = content ?? this.content;
    return AiSessionMessage(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      role: role ?? this.role,
      content: nextContent,
      createdAt: createdAt ?? this.createdAt,
      characterCount: characterCount ?? countCharacters(nextContent),
      isDeleted: isDeleted ?? this.isDeleted,
      modelId: modelId ?? this.modelId,
      modelLabel: modelLabel ?? this.modelLabel,
      usage: usage ?? this.usage,
      metadata: metadata ?? this.metadata,
    );
  }

  AiSessionMessageFeedback? get feedback =>
      _activeResponseVariantFeedback ?? metadataFeedback;

  AiSessionMessageFeedback? get metadataFeedback =>
      AiSessionMessageFeedback.fromStorage(
        metadata[aiSessionMessageFeedbackMetadataKey],
      );

  AiSessionMessageFeedback? get _activeResponseVariantFeedback {
    if (kind != AiSessionMessageKind.assistant) {
      return null;
    }
    final variants = responseVariants;
    final hasStoredVariants =
        metadata[aiSessionMessageResponseVariantsMetadataKey] is List;
    if (variants.isEmpty || (variants.length == 1 && !hasStoredVariants)) {
      return null;
    }
    return variants[responseVariantIndex].feedback;
  }

  /// 按消息对象缓存的响应变体列表。消息不可变，一次解析终身有效。
  static final Expando<List<AiSessionMessageResponseVariant>>
      _responseVariantsCache = Expando<List<AiSessionMessageResponseVariant>>(
    'responseVariants',
  );

  List<AiSessionMessageResponseVariant> get responseVariants {
    final cached = _responseVariantsCache[this];
    if (cached != null) return cached;
    final computed = AiSessionMessageResponseVariant.listFromMessage(this);
    _responseVariantsCache[this] = computed;
    return computed;
  }

  int get responseVariantIndex => AiSessionMessageResponseVariant.clampIndex(
    metadata[aiSessionMessageResponseVariantIndexMetadataKey],
    responseVariants.length,
  );

  Map<String, Object?> toJson({bool includeDerivedFields = false}) {
    final payload = <String, Object?>{
      'id': id,
      'kind': kind.storageValue,
      'role': role.storageValue,
      'content': content,
      'created_at': createdAt.toUtc().toIso8601String(),
      'character_count': characterCount,
      'is_deleted': isDeleted,
      'model_id': modelId,
      'model_label': modelLabel,
      'usage': usage?.toJson(),
      'metadata': metadata,
    };
    if (includeDerivedFields) {
      payload.addAll(derivedConversationJson());
    }
    return payload;
  }

  static int countCharacters(String input) {
    return input.trim().characters.length;
  }

  static String? _readNullableString(Object? value) {
    final text = '$value'.trim();
    if (value == null || text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  static AiTokenUsage? _readUsage(Object? value) {
    final json = optionalStringKeyedMapFromValueOrJsonText(value);
    if (json == null) return null;
    return AiTokenUsage.fromJson(json);
  }
}

const Set<String> _machineExpertRequestFieldLabels = <String>{
  '终端应用',
  '打开的终端位置',
  'AppleScript 精确定位',
  '需求内容',
};

const Set<String> _webReverseRequestFieldLabels = <String>{
  '目标 URL',
  '逆向目标',
  '触发动作',
  '登录态',
  '浏览器',
  'CDP 端口',
  'AI 侧 CDP MCP',
  '代理',
  '关键字',
  '取证纪律',
  '任务产物',
  '验收标准',
};

const Set<String> _androidReverseRequestFieldLabels = <String>{
  '逆向目标',
  '目标包名',
  'APK 路径',
  '设备',
  '设备序列号',
  '分析模式',
  '授权范围',
  'ADB MCP',
  'Frida MCP',
  '关键字',
  '备注',
  '取证纪律',
  '验收标准',
};

class _AiRequestCardCodec {
  const _AiRequestCardCodec._();

  static Map<String, Object?>? object(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return stringKeyedMapFromValue(value);
    }
    return null;
  }

  static String readString(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text == 'null') {
      return '';
    }
    return text;
  }

  static bool hasHeading(String content, String heading) {
    for (final line in content.split(_aiSessionMessageLineBreakPattern)) {
      final normalized = stripPromptBullet(line);
      if (normalized == heading ||
          normalized == '$heading：' ||
          normalized == '$heading:') {
        return true;
      }
    }
    return false;
  }

  static String readPromptField(
    String content,
    String label,
    Set<String> knownLabels,
  ) {
    final lines = content.split(_aiSessionMessageLineBreakPattern);
    for (var i = 0; i < lines.length; i++) {
      final normalized = stripPromptBullet(lines[i]);
      if (!isPromptFieldLabel(normalized, label)) {
        continue;
      }
      final buffer = <String>[normalized];
      for (var j = i + 1; j < lines.length; j++) {
        if (containsClosedCjkBracket(buffer.join('\n'))) {
          break;
        }
        final nextLine = lines[j];
        final nextNormalized = stripPromptBullet(nextLine);
        if (looksLikePromptField(nextNormalized, knownLabels)) {
          break;
        }
        buffer.add(nextLine);
      }
      final value = extractCjkBracketValue(buffer.join('\n'));
      if (value.isNotEmpty) {
        return value;
      }
      return readAfterSeparator(normalized);
    }
    return '';
  }

  static String stripPromptBullet(String line) {
    return line.trim().replaceFirst(
      _aiSessionMessagePromptBulletPrefixPattern,
      '',
    );
  }

  static bool looksLikePromptField(String line, Set<String> knownLabels) {
    for (final label in knownLabels) {
      if (isPromptFieldLabel(line, label)) {
        return true;
      }
    }
    return false;
  }

  static bool isPromptFieldLabel(String line, String label) {
    if (line == label) {
      return true;
    }
    return RegExp(
      '^${RegExp.escape(label)}(?:\\s*[:：]|\\s*[（(])',
    ).hasMatch(line);
  }

  static bool containsClosedCjkBracket(String value) {
    final separator = value.indexOf('：【');
    final start = separator >= 0 ? separator + 1 : value.indexOf('【');
    final end = value.lastIndexOf('】');
    return start >= 0 && end > start;
  }

  static String extractCjkBracketValue(String value) {
    final separator = value.indexOf('：【');
    final start = separator >= 0 ? separator + 1 : value.indexOf('【');
    final end = value.lastIndexOf('】');
    if (start < 0 || end <= start) {
      return '';
    }
    return value.substring(start + 1, end).trim();
  }

  static String readAfterSeparator(String value) {
    final colon = value.indexOf('：');
    final asciiColon = value.indexOf(':');
    final index = colon >= 0
        ? colon
        : asciiColon >= 0
        ? asciiColon
        : -1;
    if (index < 0 || index + 1 >= value.length) {
      return '';
    }
    return value.substring(index + 1).trim();
  }

  static bool fieldNeedsTruncation(String value) {
    return value.trim().characters.length >
        aiSessionExpertRequestCardMaxFieldCharacters;
  }

  static String boundedDisplayField(String value) {
    final normalized = value.trim();
    if (normalized.characters.length <=
        aiSessionExpertRequestCardMaxFieldCharacters) {
      return normalized;
    }
    return '${normalized.characters.take(aiSessionExpertRequestCardMaxFieldCharacters).toString().trimRight()}...';
  }
}

class AiMachineExpertRequestCard {
  const AiMachineExpertRequestCard({
    required this.terminalApplication,
    required this.terminalLocation,
    required this.taskRequirement,
    this.appleScriptTarget,
    this.truncated = false,
  });

  final String terminalApplication;
  final String terminalLocation;
  final String? appleScriptTarget;
  final String taskRequirement;
  final bool truncated;

  bool get isEmpty =>
      nullIfBlank(terminalApplication) == null &&
      nullIfBlank(terminalLocation) == null &&
      nullIfBlank(appleScriptTarget) == null &&
      nullIfBlank(taskRequirement) == null;

  Map<String, Object?> toJson() {
    final normalizedAppleScriptTarget = nullIfBlank(appleScriptTarget);
    return <String, Object?>{
      'schema_version': aiSessionMachineExpertRequestCardSchemaVersion,
      'terminal_application': terminalApplication,
      'terminal_location': terminalLocation,
      if (normalizedAppleScriptTarget != null)
        'applescript_target': normalizedAppleScriptTarget,
      'task_requirement': taskRequirement,
      if (truncated) 'truncated': true,
    };
  }

  static AiMachineExpertRequestCard? fromMetadata(Object? raw) {
    final map = _AiRequestCardCodec.object(raw);
    if (map == null) {
      return null;
    }
    final card = AiMachineExpertRequestCard(
      terminalApplication: _AiRequestCardCodec.readString(
        map['terminal_application'],
      ),
      terminalLocation: _AiRequestCardCodec.readString(
        map['terminal_location'],
      ),
      appleScriptTarget: _AiRequestCardCodec.readString(
        map['applescript_target'],
      ).ifEmpty(null),
      taskRequirement: _AiRequestCardCodec.readString(map['task_requirement']),
      truncated: map['truncated'] == true,
    );
    return card.isEmpty ? null : card;
  }

  static AiMachineExpertRequestCard? fromPrompt(String content) {
    final terminalApplication = _AiRequestCardCodec.readPromptField(
      content,
      '终端应用',
      _machineExpertRequestFieldLabels,
    );
    final terminalLocation = _AiRequestCardCodec.readPromptField(
      content,
      '打开的终端位置',
      _machineExpertRequestFieldLabels,
    );
    final appleScriptTarget = _AiRequestCardCodec.readPromptField(
      content,
      'AppleScript 精确定位',
      _machineExpertRequestFieldLabels,
    );
    final taskRequirement = _AiRequestCardCodec.readPromptField(
      content,
      '需求内容',
      _machineExpertRequestFieldLabels,
    );
    final rawFields = <String>[
      terminalApplication,
      terminalLocation,
      appleScriptTarget,
      taskRequirement,
    ];
    if (nullIfBlank(taskRequirement) == null ||
        (nullIfBlank(terminalApplication) == null &&
            nullIfBlank(terminalLocation) == null) ||
        rawFields.every((field) => nullIfBlank(field) == null)) {
      return null;
    }
    final card = AiMachineExpertRequestCard(
      terminalApplication: _AiRequestCardCodec.boundedDisplayField(
        terminalApplication,
      ),
      terminalLocation: _AiRequestCardCodec.boundedDisplayField(
        terminalLocation,
      ),
      appleScriptTarget: _AiRequestCardCodec.boundedDisplayField(
        appleScriptTarget,
      ).ifEmpty(null),
      taskRequirement: _AiRequestCardCodec.boundedDisplayField(taskRequirement),
      truncated: rawFields.any(_AiRequestCardCodec.fieldNeedsTruncation),
    );
    return card.isEmpty ? null : card;
  }
}

class AiWebReverseRequestCard {
  const AiWebReverseRequestCard({
    required this.targetUrl,
    required this.reverseTarget,
    this.triggerActions,
    required this.loginState,
    required this.browser,
    required this.cdpPort,
    required this.cdpMcp,
    this.proxy,
    this.keywords,
    required this.evidenceDiscipline,
    required this.deliverables,
    required this.acceptanceCriteria,
    this.truncated = false,
  });

  final String targetUrl;
  final String reverseTarget;
  final String? triggerActions;
  final String loginState;
  final String browser;
  final String cdpPort;
  final String cdpMcp;
  final String? proxy;
  final String? keywords;
  final String evidenceDiscipline;
  final String deliverables;
  final String acceptanceCriteria;
  final bool truncated;

  bool get isEmpty =>
      nullIfBlank(targetUrl) == null &&
      nullIfBlank(reverseTarget) == null &&
      nullIfBlank(loginState) == null &&
      nullIfBlank(browser) == null &&
      nullIfBlank(cdpPort) == null &&
      nullIfBlank(cdpMcp) == null &&
      nullIfBlank(evidenceDiscipline) == null &&
      nullIfBlank(deliverables) == null &&
      nullIfBlank(acceptanceCriteria) == null;

  Map<String, Object?> toJson() {
    final normalizedTriggerActions = nullIfBlank(triggerActions);
    final normalizedProxy = nullIfBlank(proxy);
    final normalizedKeywords = nullIfBlank(keywords);
    return <String, Object?>{
      'schema_version': aiSessionExpertRequestCardSchemaVersion,
      'target_url': targetUrl,
      'reverse_target': reverseTarget,
      if (normalizedTriggerActions != null)
        'trigger_actions': normalizedTriggerActions,
      'login_state': loginState,
      'browser': browser,
      'cdp_port': cdpPort,
      'cdp_mcp': cdpMcp,
      if (normalizedProxy != null) 'proxy': normalizedProxy,
      if (normalizedKeywords != null) 'keywords': normalizedKeywords,
      'evidence_discipline': evidenceDiscipline,
      'deliverables': deliverables,
      'acceptance_criteria': acceptanceCriteria,
      if (truncated) 'truncated': true,
    };
  }

  static AiWebReverseRequestCard? fromMetadata(Object? raw) {
    final map = _AiRequestCardCodec.object(raw);
    if (map == null) {
      return null;
    }
    final card = AiWebReverseRequestCard(
      targetUrl: _AiRequestCardCodec.readString(map['target_url']),
      reverseTarget: _AiRequestCardCodec.readString(map['reverse_target']),
      triggerActions: _AiRequestCardCodec.readString(
        map['trigger_actions'],
      ).ifEmpty(null),
      loginState: _AiRequestCardCodec.readString(map['login_state']),
      browser: _AiRequestCardCodec.readString(map['browser']),
      cdpPort: _AiRequestCardCodec.readString(map['cdp_port']),
      cdpMcp: _AiRequestCardCodec.readString(map['cdp_mcp']),
      proxy: _AiRequestCardCodec.readString(map['proxy']).ifEmpty(null),
      keywords: _AiRequestCardCodec.readString(map['keywords']).ifEmpty(null),
      evidenceDiscipline: _AiRequestCardCodec.readString(
        map['evidence_discipline'],
      ),
      deliverables: _AiRequestCardCodec.readString(map['deliverables']),
      acceptanceCriteria: _AiRequestCardCodec.readString(
        map['acceptance_criteria'],
      ),
      truncated: map['truncated'] == true,
    );
    return card.isEmpty ? null : card;
  }

  static AiWebReverseRequestCard? fromPrompt(String content) {
    if (!_AiRequestCardCodec.hasHeading(content, '请求模板')) {
      return null;
    }
    final targetUrl = _AiRequestCardCodec.readPromptField(
      content,
      '目标 URL',
      _webReverseRequestFieldLabels,
    );
    final reverseTarget = _AiRequestCardCodec.readPromptField(
      content,
      '逆向目标',
      _webReverseRequestFieldLabels,
    );
    final triggerActions = _AiRequestCardCodec.readPromptField(
      content,
      '触发动作',
      _webReverseRequestFieldLabels,
    );
    final loginState = _AiRequestCardCodec.readPromptField(
      content,
      '登录态',
      _webReverseRequestFieldLabels,
    );
    final browser = _AiRequestCardCodec.readPromptField(
      content,
      '浏览器',
      _webReverseRequestFieldLabels,
    );
    final cdpPort = _AiRequestCardCodec.readPromptField(
      content,
      'CDP 端口',
      _webReverseRequestFieldLabels,
    );
    final cdpMcp = _AiRequestCardCodec.readPromptField(
      content,
      'AI 侧 CDP MCP',
      _webReverseRequestFieldLabels,
    );
    final proxy = _AiRequestCardCodec.readPromptField(
      content,
      '代理',
      _webReverseRequestFieldLabels,
    );
    final keywords = _AiRequestCardCodec.readPromptField(
      content,
      '关键字',
      _webReverseRequestFieldLabels,
    );
    final evidenceDiscipline = _AiRequestCardCodec.readPromptField(
      content,
      '取证纪律',
      _webReverseRequestFieldLabels,
    );
    final deliverables = _AiRequestCardCodec.readPromptField(
      content,
      '任务产物',
      _webReverseRequestFieldLabels,
    );
    final acceptanceCriteria = _AiRequestCardCodec.readPromptField(
      content,
      '验收标准',
      _webReverseRequestFieldLabels,
    );
    final rawFields = <String>[
      targetUrl,
      reverseTarget,
      triggerActions,
      loginState,
      browser,
      cdpPort,
      cdpMcp,
      proxy,
      keywords,
      evidenceDiscipline,
      deliverables,
      acceptanceCriteria,
    ];
    if (nullIfBlank(targetUrl) == null ||
        nullIfBlank(reverseTarget) == null ||
        (nullIfBlank(browser) == null &&
            nullIfBlank(cdpPort) == null &&
            nullIfBlank(cdpMcp) == null)) {
      return null;
    }
    final card = AiWebReverseRequestCard(
      targetUrl: _AiRequestCardCodec.boundedDisplayField(targetUrl),
      reverseTarget: _AiRequestCardCodec.boundedDisplayField(reverseTarget),
      triggerActions: _AiRequestCardCodec.boundedDisplayField(
        triggerActions,
      ).ifEmpty(null),
      loginState: _AiRequestCardCodec.boundedDisplayField(loginState),
      browser: _AiRequestCardCodec.boundedDisplayField(browser),
      cdpPort: _AiRequestCardCodec.boundedDisplayField(cdpPort),
      cdpMcp: _AiRequestCardCodec.boundedDisplayField(cdpMcp),
      proxy: _AiRequestCardCodec.boundedDisplayField(proxy).ifEmpty(null),
      keywords: _AiRequestCardCodec.boundedDisplayField(keywords).ifEmpty(null),
      evidenceDiscipline: _AiRequestCardCodec.boundedDisplayField(
        evidenceDiscipline,
      ),
      deliverables: _AiRequestCardCodec.boundedDisplayField(deliverables),
      acceptanceCriteria: _AiRequestCardCodec.boundedDisplayField(
        acceptanceCriteria,
      ),
      truncated: rawFields.any(_AiRequestCardCodec.fieldNeedsTruncation),
    );
    return card.isEmpty ? null : card;
  }
}

class AiAndroidReverseRequestCard {
  const AiAndroidReverseRequestCard({
    required this.reverseTarget,
    this.packageName,
    this.apkPath,
    this.device,
    this.deviceSerial,
    required this.analysisMode,
    required this.authorizationScope,
    required this.adbMcp,
    required this.fridaMcp,
    this.keywords,
    this.notes,
    required this.evidenceDiscipline,
    required this.acceptanceCriteria,
    this.truncated = false,
  });

  final String reverseTarget;
  final String? packageName;
  final String? apkPath;
  final String? device;
  final String? deviceSerial;
  final String analysisMode;
  final String authorizationScope;
  final String adbMcp;
  final String fridaMcp;
  final String? keywords;
  final String? notes;
  final String evidenceDiscipline;
  final String acceptanceCriteria;
  final bool truncated;

  String get deviceDisplay => nullIfBlank(deviceSerial) ?? device ?? '';

  bool get isEmpty =>
      nullIfBlank(reverseTarget) == null &&
      nullIfBlank(packageName) == null &&
      nullIfBlank(apkPath) == null &&
      nullIfBlank(deviceDisplay) == null &&
      nullIfBlank(analysisMode) == null &&
      nullIfBlank(authorizationScope) == null &&
      nullIfBlank(adbMcp) == null &&
      nullIfBlank(fridaMcp) == null &&
      nullIfBlank(evidenceDiscipline) == null &&
      nullIfBlank(acceptanceCriteria) == null;

  Map<String, Object?> toJson() {
    final normalizedPackageName = nullIfBlank(packageName);
    final normalizedApkPath = nullIfBlank(apkPath);
    final normalizedDevice = nullIfBlank(device);
    final normalizedDeviceSerial = nullIfBlank(deviceSerial);
    final normalizedKeywords = nullIfBlank(keywords);
    final normalizedNotes = nullIfBlank(notes);
    return <String, Object?>{
      'schema_version': aiSessionExpertRequestCardSchemaVersion,
      'reverse_target': reverseTarget,
      if (normalizedPackageName != null) 'package_name': normalizedPackageName,
      if (normalizedApkPath != null) 'apk_path': normalizedApkPath,
      if (normalizedDevice != null) 'device': normalizedDevice,
      if (normalizedDeviceSerial != null)
        'device_serial': normalizedDeviceSerial,
      'analysis_mode': analysisMode,
      'authorization_scope': authorizationScope,
      'adb_mcp': adbMcp,
      'frida_mcp': fridaMcp,
      if (normalizedKeywords != null) 'keywords': normalizedKeywords,
      if (normalizedNotes != null) 'notes': normalizedNotes,
      'evidence_discipline': evidenceDiscipline,
      'acceptance_criteria': acceptanceCriteria,
      if (truncated) 'truncated': true,
    };
  }

  static AiAndroidReverseRequestCard? fromMetadata(Object? raw) {
    final map = _AiRequestCardCodec.object(raw);
    if (map == null) {
      return null;
    }
    final card = AiAndroidReverseRequestCard(
      reverseTarget: _AiRequestCardCodec.readString(map['reverse_target']),
      packageName: _AiRequestCardCodec.readString(
        map['package_name'],
      ).ifEmpty(null),
      apkPath: _AiRequestCardCodec.readString(map['apk_path']).ifEmpty(null),
      device: _AiRequestCardCodec.readString(map['device']).ifEmpty(null),
      deviceSerial: _AiRequestCardCodec.readString(
        map['device_serial'],
      ).ifEmpty(null),
      analysisMode: _AiRequestCardCodec.readString(map['analysis_mode']),
      authorizationScope: _AiRequestCardCodec.readString(
        map['authorization_scope'],
      ),
      adbMcp: _AiRequestCardCodec.readString(map['adb_mcp']),
      fridaMcp: _AiRequestCardCodec.readString(map['frida_mcp']),
      keywords: _AiRequestCardCodec.readString(map['keywords']).ifEmpty(null),
      notes: _AiRequestCardCodec.readString(map['notes']).ifEmpty(null),
      evidenceDiscipline: _AiRequestCardCodec.readString(
        map['evidence_discipline'],
      ),
      acceptanceCriteria: _AiRequestCardCodec.readString(
        map['acceptance_criteria'],
      ),
      truncated: map['truncated'] == true,
    );
    return card.isEmpty ? null : card;
  }

  static AiAndroidReverseRequestCard? fromPrompt(String content) {
    if (!_AiRequestCardCodec.hasHeading(content, 'Android 逆向请求')) {
      return null;
    }
    final reverseTarget = _AiRequestCardCodec.readPromptField(
      content,
      '逆向目标',
      _androidReverseRequestFieldLabels,
    );
    final packageName = _AiRequestCardCodec.readPromptField(
      content,
      '目标包名',
      _androidReverseRequestFieldLabels,
    );
    final apkPath = _AiRequestCardCodec.readPromptField(
      content,
      'APK 路径',
      _androidReverseRequestFieldLabels,
    );
    final device = _AiRequestCardCodec.readPromptField(
      content,
      '设备',
      _androidReverseRequestFieldLabels,
    );
    final deviceSerial = _AiRequestCardCodec.readPromptField(
      content,
      '设备序列号',
      _androidReverseRequestFieldLabels,
    );
    final analysisMode = _AiRequestCardCodec.readPromptField(
      content,
      '分析模式',
      _androidReverseRequestFieldLabels,
    );
    final authorizationScope = _AiRequestCardCodec.readPromptField(
      content,
      '授权范围',
      _androidReverseRequestFieldLabels,
    );
    final adbMcp = _AiRequestCardCodec.readPromptField(
      content,
      'ADB MCP',
      _androidReverseRequestFieldLabels,
    );
    final fridaMcp = _AiRequestCardCodec.readPromptField(
      content,
      'Frida MCP',
      _androidReverseRequestFieldLabels,
    );
    final keywords = _AiRequestCardCodec.readPromptField(
      content,
      '关键字',
      _androidReverseRequestFieldLabels,
    );
    final notes = _AiRequestCardCodec.readPromptField(
      content,
      '备注',
      _androidReverseRequestFieldLabels,
    );
    final evidenceDiscipline = _AiRequestCardCodec.readPromptField(
      content,
      '取证纪律',
      _androidReverseRequestFieldLabels,
    );
    final acceptanceCriteria = _AiRequestCardCodec.readPromptField(
      content,
      '验收标准',
      _androidReverseRequestFieldLabels,
    );
    final rawFields = <String>[
      reverseTarget,
      packageName,
      apkPath,
      device,
      deviceSerial,
      analysisMode,
      authorizationScope,
      adbMcp,
      fridaMcp,
      keywords,
      notes,
      evidenceDiscipline,
      acceptanceCriteria,
    ];
    if (nullIfBlank(reverseTarget) == null ||
        (nullIfBlank(packageName) == null &&
            nullIfBlank(apkPath) == null &&
            nullIfBlank(device) == null &&
            nullIfBlank(deviceSerial) == null &&
            nullIfBlank(analysisMode) == null)) {
      return null;
    }
    final card = AiAndroidReverseRequestCard(
      reverseTarget: _AiRequestCardCodec.boundedDisplayField(reverseTarget),
      packageName: _AiRequestCardCodec.boundedDisplayField(
        packageName,
      ).ifEmpty(null),
      apkPath: _AiRequestCardCodec.boundedDisplayField(apkPath).ifEmpty(null),
      device: _AiRequestCardCodec.boundedDisplayField(device).ifEmpty(null),
      deviceSerial: _AiRequestCardCodec.boundedDisplayField(
        deviceSerial,
      ).ifEmpty(null),
      analysisMode: _AiRequestCardCodec.boundedDisplayField(analysisMode),
      authorizationScope: _AiRequestCardCodec.boundedDisplayField(
        authorizationScope,
      ),
      adbMcp: _AiRequestCardCodec.boundedDisplayField(adbMcp),
      fridaMcp: _AiRequestCardCodec.boundedDisplayField(fridaMcp),
      keywords: _AiRequestCardCodec.boundedDisplayField(keywords).ifEmpty(null),
      notes: _AiRequestCardCodec.boundedDisplayField(notes).ifEmpty(null),
      evidenceDiscipline: _AiRequestCardCodec.boundedDisplayField(
        evidenceDiscipline,
      ),
      acceptanceCriteria: _AiRequestCardCodec.boundedDisplayField(
        acceptanceCriteria,
      ),
      truncated: rawFields.any(_AiRequestCardCodec.fieldNeedsTruncation),
    );
    return card.isEmpty ? null : card;
  }
}

extension _AiRequestCardString on String {
  String? ifEmpty(String? fallback) =>
      nullIfBlank(this) == null ? fallback : this;
}

class AiSessionMessageResponseVariant {
  const AiSessionMessageResponseVariant({
    required this.content,
    required this.createdAt,
    this.id,
    this.modelId,
    this.modelLabel,
    this.usage,
    this.feedback,
    this.intermediateMessageIds = const <String>[],
  });

  factory AiSessionMessageResponseVariant.fromMessage(
    AiSessionMessage message, {
    String? id,
    DateTime? createdAt,
    AiSessionMessageFeedback? feedback,
    List<String> intermediateMessageIds = const <String>[],
  }) {
    return AiSessionMessageResponseVariant(
      id: id ?? message.id,
      content: message.content,
      createdAt: (createdAt ?? message.createdAt).toUtc(),
      modelId: message.modelId,
      modelLabel: message.modelLabel,
      usage: message.usage,
      feedback: feedback ?? message.metadataFeedback,
      intermediateMessageIds: _normalizeMessageIds(intermediateMessageIds),
    );
  }

  factory AiSessionMessageResponseVariant.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return AiSessionMessageResponseVariant(
      id: AiSessionMessage._readNullableString(json['id']),
      content: stripImageSummaryMarkup('${json['content'] ?? ''}'),
      createdAt:
          utcDateTimeFromValue(json['created_at']) ?? DateTime.now().toUtc(),
      modelId: AiSessionMessage._readNullableString(json['model_id']),
      modelLabel: AiSessionMessage._readNullableString(json['model_label']),
      usage: AiSessionMessage._readUsage(json['usage']),
      feedback: AiSessionMessageFeedback.fromStorage(
        json[aiSessionMessageFeedbackMetadataKey],
      ),
      intermediateMessageIds: _normalizeMessageIds(
        json['intermediate_message_ids'],
      ),
    );
  }

  final String? id;
  final String content;
  final DateTime createdAt;
  final String? modelId;
  final String? modelLabel;
  final AiTokenUsage? usage;
  final AiSessionMessageFeedback? feedback;
  final List<String> intermediateMessageIds;

  AiSessionMessageResponseVariant copyWith({
    String? id,
    String? content,
    DateTime? createdAt,
    String? modelId,
    String? modelLabel,
    AiTokenUsage? usage,
    AiSessionMessageFeedback? feedback,
    bool clearFeedback = false,
    List<String>? intermediateMessageIds,
  }) {
    return AiSessionMessageResponseVariant(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      modelId: modelId ?? this.modelId,
      modelLabel: modelLabel ?? this.modelLabel,
      usage: usage ?? this.usage,
      feedback: clearFeedback ? null : feedback ?? this.feedback,
      intermediateMessageIds: intermediateMessageIds == null
          ? this.intermediateMessageIds
          : _normalizeMessageIds(intermediateMessageIds),
    );
  }

  Map<String, Object?> toJson() {
    final normalizedId = nullIfBlank(id);
    final normalizedModelId = nullIfBlank(modelId);
    final normalizedModelLabel = nullIfBlank(modelLabel);
    return <String, Object?>{
      if (normalizedId != null) 'id': normalizedId,
      'content': content,
      'created_at': createdAt.toUtc().toIso8601String(),
      if (normalizedModelId != null) 'model_id': normalizedModelId,
      if (normalizedModelLabel != null) 'model_label': normalizedModelLabel,
      if (usage != null && !usage!.isEmpty) 'usage': usage!.toJson(),
      if (feedback != null)
        aiSessionMessageFeedbackMetadataKey: feedback!.storageValue,
      if (intermediateMessageIds.isNotEmpty)
        'intermediate_message_ids': intermediateMessageIds,
    };
  }

  static List<AiSessionMessageResponseVariant> listFromMessage(
    AiSessionMessage message,
  ) {
    final parsed = listFromMetadata(
      message.metadata[aiSessionMessageResponseVariantsMetadataKey],
    );
    if (parsed.isNotEmpty) {
      final legacyFeedback = message.metadataFeedback;
      if (legacyFeedback != null &&
          parsed.every((variant) => variant.feedback == null)) {
        final legacyIndex = clampIndex(
          message.metadata[aiSessionMessageResponseVariantIndexMetadataKey],
          parsed.length,
        );
        return List<AiSessionMessageResponseVariant>.unmodifiable(
          <AiSessionMessageResponseVariant>[
            for (var index = 0; index < parsed.length; index++)
              index == legacyIndex
                  ? parsed[index].copyWith(feedback: legacyFeedback)
                  : parsed[index],
          ],
        );
      }
      return parsed;
    }
    return <AiSessionMessageResponseVariant>[
      AiSessionMessageResponseVariant.fromMessage(message),
    ];
  }

  static List<AiSessionMessageResponseVariant> listFromMetadata(Object? raw) {
    if (raw is! List) {
      return const <AiSessionMessageResponseVariant>[];
    }
    final variants = <AiSessionMessageResponseVariant>[];
    final scanStart =
        raw.length > _aiSessionMessageResponseVariantMetadataScanLimit
        ? raw.length - _aiSessionMessageResponseVariantMetadataScanLimit
        : 0;
    for (final item in raw.skip(scanStart)) {
      final map = item is Map<String, Object?>
          ? item
          : item is Map
          ? stringKeyedMapFromValue(item)
          : null;
      if (map == null) {
        continue;
      }
      final variant = AiSessionMessageResponseVariant.fromJson(map);
      if (nullIfBlank(variant.content) != null) {
        variants.add(variant);
        if (variants.length > aiSessionMessageMaxResponseVariants) {
          variants.removeAt(0);
        }
      }
    }
    return List<AiSessionMessageResponseVariant>.unmodifiable(variants);
  }

  static List<AiSessionMessageResponseVariant> retainRecent(
    List<AiSessionMessageResponseVariant> variants,
  ) {
    final start = variants.length > aiSessionMessageMaxResponseVariants
        ? variants.length - aiSessionMessageMaxResponseVariants
        : 0;
    return List<AiSessionMessageResponseVariant>.unmodifiable(
      variants.skip(start),
    );
  }

  static int clampIndex(Object? raw, int length) {
    if (length <= 0) return 0;
    return clampedIntFromValue(
      raw is int ? raw : stringFromValue(raw),
      fallback: 0,
      min: 0,
      max: length - 1,
    );
  }

  static List<String> _normalizeMessageIds(Object? raw) {
    final ids = <String>[];
    final seen = <String>{};
    for (final id in stringListFromValueOrJsonText(
      raw,
      limit: aiSessionMessageMaxVariantIntermediateMessageIds,
    )) {
      if (id.length > _aiSessionMessageMaxVariantReferenceIdCharacters) {
        continue;
      }
      if (!seen.add(id)) continue;
      ids.add(id);
    }
    return List<String>.unmodifiable(ids);
  }
}
