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
const String aiSessionMessageFeedbackMetadataKey = 'message_feedback';
const String aiSessionMessageResponseVariantsMetadataKey = 'response_variants';
const String aiSessionMessageResponseVariantIndexMetadataKey =
    'response_variant_index';

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
    return kind == AiSessionMessageKind.tool ||
        kind == AiSessionMessageKind.mcp ||
        kind == AiSessionMessageKind.skill ||
        kind == AiSessionMessageKind.hook;
  }

  bool get startsConversationRound {
    if (isDeleted) {
      return false;
    }
    return kind == AiSessionMessageKind.user || isOpenHandBackgroundInput;
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
      AiSessionMessageFeedback.fromStorage(
        metadata[aiSessionMessageFeedbackMetadataKey],
      );

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

class AiSessionMessageResponseVariant {
  const AiSessionMessageResponseVariant({
    required this.content,
    required this.createdAt,
    this.id,
    this.modelId,
    this.modelLabel,
    this.usage,
  });

  factory AiSessionMessageResponseVariant.fromMessage(
    AiSessionMessage message, {
    String? id,
    DateTime? createdAt,
  }) {
    return AiSessionMessageResponseVariant(
      id: id ?? message.id,
      content: message.content,
      createdAt: (createdAt ?? message.createdAt).toUtc(),
      modelId: message.modelId,
      modelLabel: message.modelLabel,
      usage: message.usage,
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
    );
  }

  final String? id;
  final String content;
  final DateTime createdAt;
  final String? modelId;
  final String? modelLabel;
  final AiTokenUsage? usage;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (id != null && id!.trim().isNotEmpty) 'id': id,
      'content': content,
      'created_at': createdAt.toUtc().toIso8601String(),
      if (modelId != null && modelId!.trim().isNotEmpty) 'model_id': modelId,
      if (modelLabel != null && modelLabel!.trim().isNotEmpty)
        'model_label': modelLabel,
      if (usage != null && !usage!.isEmpty) 'usage': usage!.toJson(),
    };
  }

  static List<AiSessionMessageResponseVariant> listFromMessage(
    AiSessionMessage message,
  ) {
    final parsed = listFromMetadata(
      message.metadata[aiSessionMessageResponseVariantsMetadataKey],
    );
    if (parsed.isNotEmpty) {
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
}
