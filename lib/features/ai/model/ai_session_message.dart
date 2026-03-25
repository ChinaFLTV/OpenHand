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

class AiSessionMessage {
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
      isDeleted: false,
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

  bool get isVisible => !isDeleted;

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
      AiSessionMessageKind.status => false,
    };
  }

  AiSessionMessage copyWith({
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
      id: id,
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
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
  }

  factory AiSessionMessage.fromJson(Map<String, Object?> json) {
    final createdAt = DateTime.parse('${json['created_at']}').toUtc();
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
