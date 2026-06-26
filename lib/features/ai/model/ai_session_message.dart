import 'package:characters/characters.dart';

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

  static AiSessionMessageKind fromStorage(String value) {
    return AiSessionMessageKind.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AiSessionMessageKind.user,
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
    return AiSessionMessageRole.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AiSessionMessageRole.user,
    );
  }
}

const String aiSessionMessageMetadataStreamingKey = 'streaming';
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
const String aiSessionMessageStartsConversationRoundJsonKey =
    'starts_conversation_round';
const String aiSessionGoalEvaluationMessageMetadataKey =
    'goal_evaluation_message';
const String aiSessionGoalEvaluationMessageTypeMetadataKey =
    'goal_evaluation_message_type';
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
const String aiSessionMachineExpertRequestCardMetadataKey =
    'machine_expert_request_card';
const int aiSessionMachineExpertRequestCardSchemaVersion = 1;
const int aiSessionMachineExpertRequestCardMaxFieldCharacters = 1600;

enum AiSessionMessageFeedback {
  liked('liked'),
  needsImprovement('needs_improvement');

  const AiSessionMessageFeedback(this.storageValue);

  final String storageValue;

  static AiSessionMessageFeedback? fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    if (normalized.isEmpty) return null;
    for (final feedback in AiSessionMessageFeedback.values) {
      if (feedback.storageValue == normalized) {
        return feedback;
      }
    }
    return null;
  }
}

class AiSessionMessage {
  factory AiSessionMessage.fromJson(Map<String, Object?> json) {
    final createdAt =
        DateTime.tryParse('${json['created_at']}')?.toUtc() ??
        DateTime.now().toUtc();
    final content = '${json['content'] ?? ''}';
    final usageJson = json['usage'];
    return AiSessionMessage(
      id: '${json['id'] ?? ''}',
      kind: AiSessionMessageKind.fromStorage('${json['kind'] ?? ''}'),
      role: AiSessionMessageRole.fromStorage('${json['role'] ?? ''}'),
      content: content,
      createdAt: createdAt,
      characterCount: json['character_count'] is int
          ? json['character_count'] as int
          : countCharacters(content),
      isDeleted: json['is_deleted'] is bool
          ? json['is_deleted'] as bool
          : false,
      modelId: _readNullableString(json['model_id']),
      modelLabel: _readNullableString(json['model_label']),
      usage: usageJson is Map<String, Object?>
          ? AiTokenUsage.fromJson(usageJson)
          : usageJson is Map
          ? AiTokenUsage.fromJson(Map<String, Object?>.from(usageJson))
          : null,
      metadata: json['metadata'] is Map<String, Object?>
          ? Map<String, Object?>.from(json['metadata'] as Map<String, Object?>)
          : json['metadata'] is Map
          ? Map<String, Object?>.from(json['metadata'] as Map)
          : const <String, Object?>{},
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

  List<AiSessionMessageResponseVariant> get responseVariants =>
      AiSessionMessageResponseVariant.listFromMessage(this);

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
      terminalApplication.trim().isEmpty &&
      terminalLocation.trim().isEmpty &&
      (appleScriptTarget ?? '').trim().isEmpty &&
      taskRequirement.trim().isEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': aiSessionMachineExpertRequestCardSchemaVersion,
      'terminal_application': terminalApplication,
      'terminal_location': terminalLocation,
      if ((appleScriptTarget ?? '').trim().isNotEmpty)
        'applescript_target': appleScriptTarget!.trim(),
      'task_requirement': taskRequirement,
      if (truncated) 'truncated': true,
    };
  }

  static AiMachineExpertRequestCard? fromMetadata(Object? raw) {
    final map = _object(raw);
    if (map == null) {
      return null;
    }
    final card = AiMachineExpertRequestCard(
      terminalApplication: _readString(map['terminal_application']),
      terminalLocation: _readString(map['terminal_location']),
      appleScriptTarget: _readString(map['applescript_target']).ifEmpty(null),
      taskRequirement: _readString(map['task_requirement']),
      truncated: map['truncated'] == true,
    );
    return card.isEmpty ? null : card;
  }

  static AiMachineExpertRequestCard? fromPrompt(String content) {
    final terminalApplication = _readPromptField(content, '终端应用');
    final terminalLocation = _readPromptField(content, '打开的终端位置');
    final appleScriptTarget = _readPromptField(content, 'AppleScript 精确定位');
    final taskRequirement = _readPromptField(content, '需求内容');
    final rawFields = <String>[
      terminalApplication,
      terminalLocation,
      appleScriptTarget,
      taskRequirement,
    ];
    if (taskRequirement.trim().isEmpty ||
        (terminalApplication.trim().isEmpty &&
            terminalLocation.trim().isEmpty) ||
        rawFields.every((field) => field.trim().isEmpty)) {
      return null;
    }
    final card = AiMachineExpertRequestCard(
      terminalApplication: _boundedDisplayField(terminalApplication),
      terminalLocation: _boundedDisplayField(terminalLocation),
      appleScriptTarget: _boundedDisplayField(appleScriptTarget).ifEmpty(null),
      taskRequirement: _boundedDisplayField(taskRequirement),
      truncated: rawFields.any(_fieldNeedsTruncation),
    );
    return card.isEmpty ? null : card;
  }

  static Map<String, Object?>? _object(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    return null;
  }

  static String _readString(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text == 'null') {
      return '';
    }
    return text;
  }

  static String _readPromptField(String content, String label) {
    final lines = content.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final normalized = _stripPromptBullet(lines[i]);
      if (!normalized.startsWith(label)) {
        continue;
      }
      final buffer = <String>[normalized];
      for (var j = i + 1; j < lines.length; j++) {
        if (_containsClosedCjkBracket(buffer.join('\n'))) {
          break;
        }
        final nextLine = lines[j];
        final nextNormalized = _stripPromptBullet(nextLine);
        if (_looksLikeMachinePromptField(nextNormalized)) {
          break;
        }
        buffer.add(nextLine);
      }
      final value = _extractCjkBracketValue(buffer.join('\n'));
      if (value.isNotEmpty) {
        return value;
      }
      return _readAfterSeparator(normalized);
    }
    return '';
  }

  static String _stripPromptBullet(String line) {
    return line.trim().replaceFirst(RegExp(r'^[-*]\s*'), '');
  }

  static bool _looksLikeMachinePromptField(String line) {
    return line.startsWith('终端应用') ||
        line.startsWith('打开的终端位置') ||
        line.startsWith('AppleScript 精确定位') ||
        line.startsWith('需求内容');
  }

  static bool _containsClosedCjkBracket(String value) {
    final separator = value.indexOf('：【');
    final start = separator >= 0 ? separator + 1 : value.indexOf('【');
    final end = value.lastIndexOf('】');
    return start >= 0 && end > start;
  }

  static String _extractCjkBracketValue(String value) {
    final separator = value.indexOf('：【');
    final start = separator >= 0 ? separator + 1 : value.indexOf('【');
    final end = value.lastIndexOf('】');
    if (start < 0 || end <= start) {
      return '';
    }
    return value.substring(start + 1, end).trim();
  }

  static String _readAfterSeparator(String value) {
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

  static bool _fieldNeedsTruncation(String value) {
    return value.trim().characters.length >
        aiSessionMachineExpertRequestCardMaxFieldCharacters;
  }

  static String _boundedDisplayField(String value) {
    final normalized = value.trim();
    if (normalized.characters.length <=
        aiSessionMachineExpertRequestCardMaxFieldCharacters) {
      return normalized;
    }
    return '${normalized.characters.take(aiSessionMachineExpertRequestCardMaxFieldCharacters).toString().trimRight()}...';
  }
}

extension _AiMachineExpertRequestCardString on String {
  String? ifEmpty(String? fallback) => trim().isEmpty ? fallback : this;
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

  factory AiSessionMessageResponseVariant.fromJson(Map<String, Object?> json) {
    final usageJson = json['usage'];
    return AiSessionMessageResponseVariant(
      id: AiSessionMessage._readNullableString(json['id']),
      content: '${json['content'] ?? ''}',
      createdAt:
          DateTime.tryParse('${json['created_at'] ?? ''}')?.toUtc() ??
          DateTime.now().toUtc(),
      modelId: AiSessionMessage._readNullableString(json['model_id']),
      modelLabel: AiSessionMessage._readNullableString(json['model_label']),
      usage: usageJson is Map<String, Object?>
          ? AiTokenUsage.fromJson(usageJson)
          : usageJson is Map
          ? AiTokenUsage.fromJson(Map<String, Object?>.from(usageJson))
          : null,
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
    return <String, Object?>{
      if (id != null && id!.trim().isNotEmpty) 'id': id,
      'content': content,
      'created_at': createdAt.toUtc().toIso8601String(),
      if (modelId != null && modelId!.trim().isNotEmpty) 'model_id': modelId,
      if (modelLabel != null && modelLabel!.trim().isNotEmpty)
        'model_label': modelLabel,
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
    for (final item in raw) {
      final map = item is Map<String, Object?>
          ? item
          : item is Map
          ? Map<String, Object?>.from(item)
          : null;
      if (map == null) {
        continue;
      }
      final variant = AiSessionMessageResponseVariant.fromJson(map);
      if (variant.content.trim().isNotEmpty) {
        variants.add(variant);
      }
    }
    return List<AiSessionMessageResponseVariant>.unmodifiable(variants);
  }

  static int clampIndex(Object? raw, int length) {
    if (length <= 0) return 0;
    final parsed = raw is int ? raw : int.tryParse('${raw ?? ''}'.trim()) ?? 0;
    return parsed.clamp(0, length - 1).toInt();
  }

  static List<String> _normalizeMessageIds(Object? raw) {
    if (raw is! Iterable) {
      return const <String>[];
    }
    final ids = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final id = '$item'.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      ids.add(id);
    }
    return List<String>.unmodifiable(ids);
  }
}
