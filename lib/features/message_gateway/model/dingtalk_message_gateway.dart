import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../shared/util/input_value_parsing.dart';

enum DingTalkConversationType { group, direct }

enum DingTalkGatewayMessageRole { user, assistant }

/// 钉钉消息中的媒体资源类型。file 覆盖钉钉文件、压缩包等非预览资源。
enum DingTalkMediaKind { image, video, audio, file }

enum DingTalkMediaResourceType { mediaId, fileId }

extension DingTalkMediaKindX on DingTalkMediaKind {
  String get storageValue => name;

  static DingTalkMediaKind fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    if (normalized.contains('image') ||
        normalized.contains('photo') ||
        normalized.contains('picture')) {
      return DingTalkMediaKind.image;
    }
    if (normalized.contains('video')) return DingTalkMediaKind.video;
    if (normalized.contains('audio') || normalized.contains('voice')) {
      return DingTalkMediaKind.audio;
    }
    return DingTalkMediaKind.file;
  }

  static DingTalkMediaKind fromFileName(String value) {
    return switch (p.extension(value).toLowerCase()) {
      '.png' ||
      '.jpg' ||
      '.jpeg' ||
      '.gif' ||
      '.webp' ||
      '.bmp' ||
      '.heic' ||
      '.svg' => DingTalkMediaKind.image,
      '.mp4' ||
      '.mov' ||
      '.m4v' ||
      '.webm' ||
      '.mkv' ||
      '.avi' => DingTalkMediaKind.video,
      '.mp3' ||
      '.wav' ||
      '.m4a' ||
      '.aac' ||
      '.ogg' ||
      '.opus' ||
      '.flac' => DingTalkMediaKind.audio,
      _ => DingTalkMediaKind.file,
    };
  }
}

@immutable
class DingTalkGatewayMedia {
  const DingTalkGatewayMedia({
    required this.resourceId,
    this.messageId = '',
    this.conversationId = '',
    this.resourceType = DingTalkMediaResourceType.mediaId,
    this.kind = DingTalkMediaKind.file,
    this.name = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.durationMs,
    this.localPath = '',
  });

  factory DingTalkGatewayMedia.fromJson(Map<String, Object?> json) {
    final resourceId =
        '${json['resource_id'] ?? json['media_id'] ?? json['file_id'] ?? ''}'
            .trim();
    if (resourceId.isEmpty) {
      throw const FormatException('钉钉媒体资源标识不完整。');
    }
    final rawType =
        '${json['resource_type'] ?? (json['file_id'] != null ? 'fileId' : 'mediaId')}'
            .trim()
            .toLowerCase();
    return DingTalkGatewayMedia(
      resourceId: resourceId,
      messageId: '${json['message_id'] ?? ''}'.trim(),
      conversationId: '${json['conversation_id'] ?? ''}'.trim(),
      resourceType: rawType == 'fileid'
          ? DingTalkMediaResourceType.fileId
          : DingTalkMediaResourceType.mediaId,
      kind: DingTalkMediaKindX.fromStorage(json['kind'] ?? json['media_type']),
      name: '${json['name'] ?? json['file_name'] ?? ''}'.trim(),
      mimeType: '${json['mime_type'] ?? json['mimeType'] ?? ''}'.trim(),
      sizeBytes: _nonNegativeInt(json['size_bytes'] ?? json['size']),
      durationMs: _nullableNonNegativeInt(
        json['duration_ms'] ?? json['duration'],
      ),
      localPath: '${json['local_path'] ?? ''}'.trim(),
    );
  }

  final String resourceId;
  final String messageId;
  final String conversationId;
  final DingTalkMediaResourceType resourceType;
  final DingTalkMediaKind kind;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final int? durationMs;
  final String localPath;

  bool get isCached => localPath.trim().isNotEmpty;

  String get displayName {
    final normalized = name.trim();
    if (normalized.isNotEmpty) return normalized;
    return switch (kind) {
      DingTalkMediaKind.image => '图片',
      DingTalkMediaKind.video => '视频',
      DingTalkMediaKind.audio => '语音',
      DingTalkMediaKind.file => '文件',
    };
  }

  DingTalkGatewayMedia copyWith({
    String? resourceId,
    String? messageId,
    String? conversationId,
    DingTalkMediaResourceType? resourceType,
    DingTalkMediaKind? kind,
    String? name,
    String? mimeType,
    int? sizeBytes,
    int? durationMs,
    String? localPath,
  }) {
    return DingTalkGatewayMedia(
      resourceId: resourceId ?? this.resourceId,
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      resourceType: resourceType ?? this.resourceType,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      durationMs: durationMs ?? this.durationMs,
      localPath: localPath ?? this.localPath,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'resource_id': resourceId,
    'message_id': messageId,
    'conversation_id': conversationId,
    'resource_type': resourceType.name,
    'kind': kind.storageValue,
    'name': name,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'duration_ms': durationMs,
    'local_path': localPath,
  };

  static int _nonNegativeInt(Object? value) =>
      _nullableNonNegativeInt(value) ?? 0;

  static int? _nullableNonNegativeInt(Object? value) {
    final parsed = int.tryParse('$value');
    return parsed != null && parsed >= 0 ? parsed : null;
  }
}

enum DingTalkReminderMode { none, inApp, sound }

/// 允许同步回显到钉钉的 AI 消息卡片类型。
enum DingTalkResponseEchoType {
  thinking('thinking'),
  process('process'),
  toolCall('tool_call'),
  finalResponse('final_response');

  const DingTalkResponseEchoType(this.storageValue);

  final String storageValue;

  static DingTalkResponseEchoType? fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    for (final item in values) {
      if (item.storageValue == normalized || item.name == normalized) {
        return item;
      }
    }
    return null;
  }
}

class DingTalkConversationTarget {
  const DingTalkConversationTarget({
    required this.id,
    required this.title,
    required this.type,
    this.subtitle = '',
    this.aliases = const <String>[],
    this.userId = '',
    this.openDingTalkId = '',
  });

  factory DingTalkConversationTarget.fromJson(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    if (id.isEmpty || title.isEmpty) {
      throw const FormatException('钉钉会话目标数据不完整。');
    }
    return DingTalkConversationTarget(
      id: id,
      title: title,
      type: DingTalkConversationType.values.firstWhere(
        (item) => item.name == '${json['type'] ?? ''}',
        orElse: () => DingTalkConversationType.direct,
      ),
      subtitle: '${json['subtitle'] ?? ''}'.trim(),
      aliases: _stringList(json['aliases']),
      userId: '${json['user_id'] ?? ''}'.trim(),
      openDingTalkId: '${json['open_dingtalk_id'] ?? ''}'.trim(),
    );
  }

  final String id;
  final String title;
  final DingTalkConversationType type;
  final String subtitle;
  final List<String> aliases;
  final String userId;
  final String openDingTalkId;

  Iterable<String> get identifiers sync* {
    yield id;
    if (userId.isNotEmpty) yield userId;
    if (openDingTalkId.isNotEmpty) yield openDingTalkId;
    yield* aliases;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'type': type.name,
    'subtitle': subtitle,
    'aliases': aliases,
    'user_id': userId,
    'open_dingtalk_id': openDingTalkId,
  };

  static List<String> _stringList(Object? value) => stringListFromValue(value)
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .take(8)
      .toList(growable: false);
}

class DingTalkGatewaySettings {
  const DingTalkGatewaySettings({
    this.pollIntervalSeconds = 3,
    this.reminderMode = DingTalkReminderMode.inApp,
    this.responseModelKey = '',
    this.workingDirectory = '',
    this.fullAccessPermission = false,
    this.templateId = 'default',
    this.allowedMcpServerNames = const <String>[],
    this.allowedSkillNames = const <String>[],
    this.allowedMemoryIds = const <String>[],
    this.allowedInstructionIds = const <String>[],
    this.allowedKnowledgeBaseSourceIds = const <String>[],
    this.allowedGroupTargets = const <DingTalkConversationTarget>[],
    this.allowedContactTargets = const <DingTalkConversationTarget>[],
    this.responseEchoTypes = const <DingTalkResponseEchoType>[
      DingTalkResponseEchoType.finalResponse,
    ],
  });

  factory DingTalkGatewaySettings.fromJson(Map<String, Object?> json) {
    final mode = DingTalkReminderMode.values.firstWhere(
      (item) => item.name == '${json['reminder_mode'] ?? ''}',
      orElse: () => DingTalkReminderMode.inApp,
    );
    return DingTalkGatewaySettings(
      pollIntervalSeconds:
          int.tryParse('${json['poll_interval_seconds'] ?? 3}') ?? 3,
      reminderMode: mode,
      responseModelKey: '${json['response_model_key'] ?? ''}',
      workingDirectory: '${json['working_directory'] ?? ''}',
      fullAccessPermission: boolFromValue(json['full_access_permission']),
      templateId: '${json['template_id'] ?? 'default'}',
      allowedMcpServerNames: _stringList(json['allowed_mcp_server_names']),
      allowedSkillNames: _stringList(json['allowed_skill_names']),
      allowedMemoryIds: _stringList(json['allowed_memory_ids']),
      allowedInstructionIds: _stringList(json['allowed_instruction_ids']),
      allowedKnowledgeBaseSourceIds: _stringList(
        json['allowed_knowledge_base_source_ids'],
      ),
      allowedGroupTargets: _targetList(
        json['allowed_group_targets'],
        DingTalkConversationType.group,
      ),
      allowedContactTargets: _targetList(
        json['allowed_contact_targets'],
        DingTalkConversationType.direct,
      ),
      responseEchoTypes: _responseEchoTypeList(json['response_echo_types']),
    ).normalized();
  }

  final int pollIntervalSeconds;
  final DingTalkReminderMode reminderMode;
  final String responseModelKey;
  final String workingDirectory;
  final bool fullAccessPermission;
  final String templateId;
  final List<String> allowedMcpServerNames;
  final List<String> allowedSkillNames;
  final List<String> allowedMemoryIds;
  final List<String> allowedInstructionIds;
  final List<String> allowedKnowledgeBaseSourceIds;
  final List<DingTalkConversationTarget> allowedGroupTargets;
  final List<DingTalkConversationTarget> allowedContactTargets;
  final List<DingTalkResponseEchoType> responseEchoTypes;

  DingTalkGatewaySettings normalized({
    Iterable<String>? availableMcpServerNames,
    Iterable<String>? availableSkillNames,
    Iterable<String>? availableMemoryIds,
    Iterable<String>? availableInstructionIds,
    Iterable<String>? availableKnowledgeBaseSourceIds,
  }) => DingTalkGatewaySettings(
    pollIntervalSeconds: pollIntervalSeconds.clamp(3, 300).toInt(),
    reminderMode: reminderMode,
    responseModelKey: responseModelKey.trim(),
    workingDirectory: Directory(
      OpenHandPaths.normalizePath(
        workingDirectory,
        defaultPath: OpenHandPaths.applicationDirectoryPath(),
      ),
    ).absolute.path,
    fullAccessPermission: fullAccessPermission,
    templateId: templateId.trim().isEmpty ? 'default' : templateId.trim(),
    allowedMcpServerNames: _normalizeSelection(
      allowedMcpServerNames,
      availableMcpServerNames,
    ),
    allowedSkillNames: _normalizeSelection(
      allowedSkillNames,
      availableSkillNames,
    ),
    allowedMemoryIds: _normalizeSelection(allowedMemoryIds, availableMemoryIds),
    allowedInstructionIds: _normalizeSelection(
      allowedInstructionIds,
      availableInstructionIds,
    ),
    allowedKnowledgeBaseSourceIds: _normalizeSelection(
      allowedKnowledgeBaseSourceIds,
      availableKnowledgeBaseSourceIds,
    ),
    allowedGroupTargets: _normalizeTargets(allowedGroupTargets),
    allowedContactTargets: _normalizeTargets(allowedContactTargets),
    responseEchoTypes: _normalizeResponseEchoTypes(responseEchoTypes),
  );

  DingTalkGatewaySettings copyWith({
    int? pollIntervalSeconds,
    DingTalkReminderMode? reminderMode,
    String? responseModelKey,
    String? workingDirectory,
    bool? fullAccessPermission,
    String? templateId,
    List<String>? allowedMcpServerNames,
    List<String>? allowedSkillNames,
    List<String>? allowedMemoryIds,
    List<String>? allowedInstructionIds,
    List<String>? allowedKnowledgeBaseSourceIds,
    List<DingTalkConversationTarget>? allowedGroupTargets,
    List<DingTalkConversationTarget>? allowedContactTargets,
    List<DingTalkResponseEchoType>? responseEchoTypes,
  }) => DingTalkGatewaySettings(
    pollIntervalSeconds: pollIntervalSeconds ?? this.pollIntervalSeconds,
    reminderMode: reminderMode ?? this.reminderMode,
    responseModelKey: responseModelKey ?? this.responseModelKey,
    workingDirectory: workingDirectory ?? this.workingDirectory,
    fullAccessPermission: fullAccessPermission ?? this.fullAccessPermission,
    templateId: templateId ?? this.templateId,
    allowedMcpServerNames: allowedMcpServerNames ?? this.allowedMcpServerNames,
    allowedSkillNames: allowedSkillNames ?? this.allowedSkillNames,
    allowedMemoryIds: allowedMemoryIds ?? this.allowedMemoryIds,
    allowedInstructionIds: allowedInstructionIds ?? this.allowedInstructionIds,
    allowedKnowledgeBaseSourceIds:
        allowedKnowledgeBaseSourceIds ?? this.allowedKnowledgeBaseSourceIds,
    allowedGroupTargets: allowedGroupTargets ?? this.allowedGroupTargets,
    allowedContactTargets: allowedContactTargets ?? this.allowedContactTargets,
    responseEchoTypes: responseEchoTypes ?? this.responseEchoTypes,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'poll_interval_seconds': pollIntervalSeconds,
    'reminder_mode': reminderMode.name,
    'response_model_key': responseModelKey,
    'working_directory': workingDirectory,
    'full_access_permission': fullAccessPermission,
    'template_id': templateId,
    'allowed_mcp_server_names': allowedMcpServerNames,
    'allowed_skill_names': allowedSkillNames,
    'allowed_memory_ids': allowedMemoryIds,
    'allowed_instruction_ids': allowedInstructionIds,
    'allowed_knowledge_base_source_ids': allowedKnowledgeBaseSourceIds,
    'allowed_group_targets': allowedGroupTargets
        .map((item) => item.toJson())
        .toList(growable: false),
    'allowed_contact_targets': allowedContactTargets
        .map((item) => item.toJson())
        .toList(growable: false),
    'response_echo_types': responseEchoTypes
        .map((item) => item.storageValue)
        .toList(growable: false),
  };

  static List<String> _stringList(Object? value) {
    return stringListFromValue(value)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .take(256)
        .toList(growable: false);
  }

  static List<DingTalkResponseEchoType> _responseEchoTypeList(Object? value) {
    final rawValues = value is List ? value : <Object?>[value];
    final result = <DingTalkResponseEchoType>[];
    final seen = <DingTalkResponseEchoType>{};
    for (final raw in rawValues.take(8)) {
      final type = DingTalkResponseEchoType.fromStorage(raw);
      if (type != null && seen.add(type)) result.add(type);
    }
    return result;
  }

  static List<DingTalkResponseEchoType> _normalizeResponseEchoTypes(
    Iterable<DingTalkResponseEchoType> values,
  ) {
    final result = <DingTalkResponseEchoType>[];
    final seen = <DingTalkResponseEchoType>{};
    for (final type in values) {
      if (seen.add(type)) result.add(type);
    }
    if (result.isEmpty) {
      result.add(DingTalkResponseEchoType.finalResponse);
    }
    return result.toList(growable: false);
  }

  static List<String> _normalizeSelection(
    Iterable<String> values,
    Iterable<String>? available,
  ) {
    final normalized = _stringList(values);
    if (available == null) return normalized;
    final allowed = available
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    return normalized.where(allowed.contains).toList(growable: false);
  }

  static List<DingTalkConversationTarget> _targetList(
    Object? value,
    DingTalkConversationType expectedType,
  ) {
    if (value is! List) return const <DingTalkConversationTarget>[];
    final result = <DingTalkConversationTarget>[];
    final seen = <String>{};
    for (final item in value.take(128)) {
      if (item is! Map) continue;
      try {
        final target = DingTalkConversationTarget.fromJson(
          stringKeyedMapFromValue(item),
        );
        if (target.type == expectedType && seen.add(target.id)) {
          result.add(target);
        }
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  static List<DingTalkConversationTarget> _normalizeTargets(
    Iterable<DingTalkConversationTarget> values,
  ) {
    final result = <DingTalkConversationTarget>[];
    final seen = <String>{};
    for (final target in values.take(128)) {
      final id = target.id.trim();
      final title = target.title.trim();
      if (id.isEmpty || title.isEmpty || !seen.add('${target.type.name}:$id')) {
        continue;
      }
      final aliases = target.aliases
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty && item != id)
          .toSet()
          .take(8)
          .toList(growable: false);
      result.add(
        DingTalkConversationTarget(
          id: id,
          title: title,
          type: target.type,
          subtitle: target.subtitle.trim(),
          aliases: aliases,
          userId: target.userId.trim(),
          openDingTalkId: target.openDingTalkId.trim(),
        ),
      );
    }
    return result;
  }
}

class DingTalkIdentity {
  const DingTalkIdentity({this.profile = '', this.userId = '', this.name = ''});

  final String profile;
  final String userId;
  final String name;

  String get label => name.trim().isEmpty ? userId : name;
}

class DingTalkGatewayMessage {
  const DingTalkGatewayMessage({
    required this.id,
    required this.conversationId,
    required this.conversationType,
    required this.role,
    required this.content,
    required this.createdAt,
    this.senderName = '',
    this.senderId = '',
    this.conversationTitle = '',
    this.media = const <DingTalkGatewayMedia>[],
    this.fromSelf = false,
    this.failed = false,
    this.mentionedCurrentUser = false,
  });

  factory DingTalkGatewayMessage.fromJson(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final conversationId = '${json['conversation_id'] ?? ''}'.trim();
    final content = '${json['content'] ?? ''}';
    final createdAt = DateTime.tryParse('${json['created_at'] ?? ''}');
    if (id.isEmpty || conversationId.isEmpty || createdAt == null) {
      throw const FormatException('钉钉消息数据不完整。');
    }
    final type = DingTalkConversationType.values.firstWhere(
      (item) => item.name == '${json['conversation_type'] ?? ''}',
      orElse: () => DingTalkConversationType.direct,
    );
    final role = DingTalkGatewayMessageRole.values.firstWhere(
      (item) => item.name == '${json['role'] ?? ''}',
      orElse: () => DingTalkGatewayMessageRole.user,
    );
    return DingTalkGatewayMessage(
      id: id,
      conversationId: conversationId,
      conversationType: type,
      role: role,
      content: content,
      createdAt: createdAt,
      senderName: '${json['sender_name'] ?? ''}',
      senderId: '${json['sender_id'] ?? ''}',
      conversationTitle: '${json['conversation_title'] ?? ''}',
      media: _mediaList(json['media']),
      fromSelf: boolFromValue(json['from_self']),
      failed: boolFromValue(json['failed']),
      mentionedCurrentUser: boolFromValue(json['mentioned_current_user']),
    );
  }

  final String id;
  final String conversationId;
  final DingTalkConversationType conversationType;
  final DingTalkGatewayMessageRole role;
  final String content;
  final DateTime createdAt;
  final String senderName;
  final String senderId;
  final String conversationTitle;
  final List<DingTalkGatewayMedia> media;
  final bool fromSelf;
  final bool failed;
  final bool mentionedCurrentUser;

  bool get isAssistant => role == DingTalkGatewayMessageRole.assistant;

  DingTalkGatewayMessage copyWith({
    String? content,
    List<DingTalkGatewayMedia>? media,
  }) {
    return DingTalkGatewayMessage(
      id: id,
      conversationId: conversationId,
      conversationType: conversationType,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      senderName: senderName,
      senderId: senderId,
      conversationTitle: conversationTitle,
      media: media ?? this.media,
      fromSelf: fromSelf,
      failed: failed,
      mentionedCurrentUser: mentionedCurrentUser,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'conversation_id': conversationId,
    'conversation_type': conversationType.name,
    'role': role.name,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'sender_name': senderName,
    'sender_id': senderId,
    'conversation_title': conversationTitle,
    'media': media.map((item) => item.toJson()).toList(growable: false),
    'from_self': fromSelf,
    'failed': failed,
    'mentioned_current_user': mentionedCurrentUser,
  };

  static List<DingTalkGatewayMedia> _mediaList(Object? raw) {
    if (raw is! List) return const <DingTalkGatewayMedia>[];
    final result = <DingTalkGatewayMedia>[];
    final seen = <String>{};
    for (final item in raw.take(12)) {
      if (item is! Map) continue;
      try {
        final media = DingTalkGatewayMedia.fromJson(
          stringKeyedMapFromValue(item),
        );
        if (seen.add('${media.resourceType.name}:${media.resourceId}')) {
          result.add(media);
        }
      } on FormatException {
        continue;
      }
    }
    return result.toList(growable: false);
  }
}

class DingTalkConversation {
  DingTalkConversation({
    required this.id,
    required this.type,
    required this.title,
    List<DingTalkGatewayMessage> messages = const <DingTalkGatewayMessage>[],
    this.directUserId,
    this.directOpenDingTalkId,
  }) : messages = List<DingTalkGatewayMessage>.from(messages);

  factory DingTalkConversation.fromJson(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    if (id.isEmpty || title.isEmpty) {
      throw const FormatException('钉钉会话数据不完整。');
    }
    final type = DingTalkConversationType.values.firstWhere(
      (item) => item.name == '${json['type'] ?? ''}',
      orElse: () => DingTalkConversationType.direct,
    );
    final rawMessages = json['messages'];
    final messages = rawMessages is List
        ? rawMessages
              .whereType<Map>()
              .map((item) {
                try {
                  return DingTalkGatewayMessage.fromJson(
                    stringKeyedMapFromValue(item),
                  );
                } catch (_) {
                  return null;
                }
              })
              .whereType<DingTalkGatewayMessage>()
              .toList(growable: false)
        : const <DingTalkGatewayMessage>[];
    final conversation = DingTalkConversation(
      id: id,
      type: type,
      title: title,
      messages: messages,
      directUserId: nullIfBlank('${json['direct_user_id'] ?? ''}'),
      directOpenDingTalkId: nullIfBlank(
        '${json['direct_open_dingtalk_id'] ?? ''}',
      ),
    );
    final sessionId = '${json['ai_session_id'] ?? ''}'.trim();
    conversation.aiSessionId = sessionId.isEmpty ? null : sessionId;
    return conversation;
  }

  final String id;
  final DingTalkConversationType type;
  String title;
  final List<DingTalkGatewayMessage> messages;
  String? aiSessionId;
  String? directUserId;
  String? directOpenDingTalkId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type.name,
    'title': title,
    'ai_session_id': aiSessionId,
    'direct_user_id': directUserId,
    'direct_open_dingtalk_id': directOpenDingTalkId,
    'messages': messages.map((item) => item.toJson()).toList(growable: false),
  };

  DateTime get updatedAt => messages.isEmpty
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : messages.last.createdAt;

  String get preview => messages.isEmpty ? '' : messages.last.content;
}

@immutable
class DingTalkAuthStatus {
  const DingTalkAuthStatus({
    required this.authenticated,
    this.identity = const DingTalkIdentity(),
  });

  final bool authenticated;
  final DingTalkIdentity identity;
}
