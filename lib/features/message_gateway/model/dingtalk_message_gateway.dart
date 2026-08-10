import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../shared/model/dingtalk_multimodal_capability.dart';
import '../../../shared/util/input_value_parsing.dart';

String _normalizedDingTalkString(Object? value) {
  if (value == null) return '';
  final text = value.toString().trim();
  return text.toLowerCase() == 'null' ? '' : text;
}

/// 统一清理钉钉媒体资源标识。
///
/// 历史消息内容可能以 `[图片消息](mediaId=...)` 的投影形式保存，
/// 旧版本会把 Markdown 右括号一并写入资源 ID。所有进入下载链路的
/// 资源都应经过此方法，避免同一资源产生多个缓存键或调用无效参数。
String normalizeDingTalkResourceId(Object? value) {
  var text = _normalizedDingTalkString(value);
  while (text.endsWith(')') || text.endsWith(']')) {
    text = text.substring(0, text.length - 1).trimRight();
  }
  return text;
}

enum DingTalkConversationType { group, direct }

enum DingTalkGatewayMessageRole { user, assistant }

enum DingTalkGatewayMessageFeedback {
  liked('liked'),
  needsImprovement('needs_improvement');

  const DingTalkGatewayMessageFeedback(this.storageValue);

  final String storageValue;

  static DingTalkGatewayMessageFeedback? fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    for (final item in values) {
      if (item.storageValue == normalized) return item;
    }
    return null;
  }
}

enum DingTalkGatewayEventType { message, read, recall, reaction }

@immutable
class DingTalkGatewayEvent {
  const DingTalkGatewayEvent({
    required this.type,
    required this.messageId,
    required this.conversationId,
    required this.conversationType,
    this.message,
    this.reaction = '',
    this.reactionRemoved = false,
  });

  final DingTalkGatewayEventType type;
  final String messageId;
  final String conversationId;
  final DingTalkConversationType conversationType;
  final DingTalkGatewayMessage? message;
  final String reaction;
  final bool reactionRemoved;
}

/// 钉钉消息中的媒体资源类型。file 覆盖钉钉文件、压缩包等非预览资源。
enum DingTalkMediaKind { image, video, audio, file }

enum DingTalkMediaResourceType { mediaId, fileId }

/// DWS 当前按单文件消息发送本地附件，应用侧将多附件拆分为连续文件消息。
const int kDingTalkMessageAttachmentLimit = 6;
const int kDingTalkMessageAttachmentMaxBytes = 512 * 1024 * 1024;

extension DingTalkMediaKindX on DingTalkMediaKind {
  String get storageValue => name;

  bool get isPreviewable => this != DingTalkMediaKind.file;

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
    final resourceId = normalizeDingTalkResourceId(
      json['resource_id'] ?? json['media_id'] ?? json['file_id'],
    );
    if (resourceId.isEmpty) {
      throw const FormatException('钉钉媒体资源标识不完整。');
    }
    final rawType = _normalizedDingTalkString(
      json['resource_type'] ?? (json['file_id'] != null ? 'fileId' : 'mediaId'),
    ).toLowerCase();
    final name = _normalizedDingTalkString(json['name'] ?? json['file_name']);
    final mimeType = _normalizedDingTalkString(
      json['mime_type'] ?? json['mimeType'],
    );
    var kind = DingTalkMediaKindX.fromStorage(
      json['kind'] ?? json['media_type'],
    );
    if (kind == DingTalkMediaKind.file && name.isNotEmpty) {
      kind = DingTalkMediaKindX.fromFileName(name);
    }
    if (kind == DingTalkMediaKind.file && mimeType.isNotEmpty) {
      kind = DingTalkMediaKindX.fromStorage(mimeType);
    }
    return DingTalkGatewayMedia(
      resourceId: resourceId,
      messageId: _normalizedDingTalkString(json['message_id']),
      conversationId: _normalizedDingTalkString(json['conversation_id']),
      resourceType: rawType == 'fileid'
          ? DingTalkMediaResourceType.fileId
          : DingTalkMediaResourceType.mediaId,
      kind: kind,
      name: name,
      mimeType: mimeType,
      sizeBytes: _nonNegativeInt(json['size_bytes'] ?? json['size']),
      durationMs: _nullableNonNegativeInt(
        json['duration_ms'] ?? json['duration'],
      ),
      localPath: _normalizedDingTalkString(json['local_path']),
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
    final normalized = _normalizedDingTalkString(name);
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
    this.pollIntervalSeconds = defaultPollIntervalSeconds,
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
    this.allowedDingTalkDwsCommandIds = const <String>[],
    this.enabledMultimodalCapabilities =
        const <AiDingTalkMultimodalCapability>{},
    this.imageGenerationModelKey = '',
    this.videoGenerationModelKey = '',
    this.audioGenerationModelKey = '',
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
      pollIntervalSeconds: normalizePollIntervalSeconds(
        json['poll_interval_seconds'],
      ),
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
      allowedDingTalkDwsCommandIds: _stringList(
        json['allowed_dingtalk_dws_command_ids'],
        limit: 1024,
      ),
      enabledMultimodalCapabilities: _multimodalCapabilitySet(
        json['enabled_multimodal_capabilities'],
      ),
      imageGenerationModelKey: '${json['image_generation_model_key'] ?? ''}',
      videoGenerationModelKey: '${json['video_generation_model_key'] ?? ''}',
      audioGenerationModelKey: '${json['audio_generation_model_key'] ?? ''}',
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

  static const int defaultPollIntervalSeconds = 3;
  static const int minPollIntervalSeconds = 3;
  static const int maxPollIntervalSeconds = 300;

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
  final List<String> allowedDingTalkDwsCommandIds;
  final Set<AiDingTalkMultimodalCapability> enabledMultimodalCapabilities;
  final String imageGenerationModelKey;
  final String videoGenerationModelKey;
  final String audioGenerationModelKey;
  final List<DingTalkConversationTarget> allowedGroupTargets;
  final List<DingTalkConversationTarget> allowedContactTargets;
  final List<DingTalkResponseEchoType> responseEchoTypes;

  static int normalizePollIntervalSeconds(Object? value) {
    final parsed = optionalIntegralIntFromValue(value);
    return (parsed ?? defaultPollIntervalSeconds)
        .clamp(minPollIntervalSeconds, maxPollIntervalSeconds)
        .toInt();
  }

  Duration get pollInterval =>
      Duration(seconds: normalizePollIntervalSeconds(pollIntervalSeconds));

  DingTalkGatewaySettings normalized({
    Iterable<String>? availableMcpServerNames,
    Iterable<String>? availableSkillNames,
    Iterable<String>? availableMemoryIds,
    Iterable<String>? availableInstructionIds,
    Iterable<String>? availableKnowledgeBaseSourceIds,
    Iterable<String>? availableDingTalkDwsCommandIds,
  }) => DingTalkGatewaySettings(
    pollIntervalSeconds: normalizePollIntervalSeconds(pollIntervalSeconds),
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
    allowedDingTalkDwsCommandIds: _normalizeSelection(
      allowedDingTalkDwsCommandIds,
      availableDingTalkDwsCommandIds,
      limit: 1024,
    ),
    enabledMultimodalCapabilities:
        Set<AiDingTalkMultimodalCapability>.unmodifiable(
          enabledMultimodalCapabilities,
        ),
    imageGenerationModelKey: imageGenerationModelKey.trim(),
    videoGenerationModelKey: videoGenerationModelKey.trim(),
    audioGenerationModelKey: audioGenerationModelKey.trim(),
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
    List<String>? allowedDingTalkDwsCommandIds,
    Set<AiDingTalkMultimodalCapability>? enabledMultimodalCapabilities,
    String? imageGenerationModelKey,
    String? videoGenerationModelKey,
    String? audioGenerationModelKey,
    List<DingTalkConversationTarget>? allowedGroupTargets,
    List<DingTalkConversationTarget>? allowedContactTargets,
    List<DingTalkResponseEchoType>? responseEchoTypes,
  }) => DingTalkGatewaySettings(
    pollIntervalSeconds: normalizePollIntervalSeconds(
      pollIntervalSeconds ?? this.pollIntervalSeconds,
    ),
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
    allowedDingTalkDwsCommandIds:
        allowedDingTalkDwsCommandIds ?? this.allowedDingTalkDwsCommandIds,
    enabledMultimodalCapabilities:
        enabledMultimodalCapabilities ?? this.enabledMultimodalCapabilities,
    imageGenerationModelKey:
        imageGenerationModelKey ?? this.imageGenerationModelKey,
    videoGenerationModelKey:
        videoGenerationModelKey ?? this.videoGenerationModelKey,
    audioGenerationModelKey:
        audioGenerationModelKey ?? this.audioGenerationModelKey,
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
    'allowed_dingtalk_dws_command_ids': allowedDingTalkDwsCommandIds,
    'enabled_multimodal_capabilities': enabledMultimodalCapabilities
        .map((item) => item.storageValue)
        .toList(growable: false),
    'image_generation_model_key': imageGenerationModelKey,
    'video_generation_model_key': videoGenerationModelKey,
    'audio_generation_model_key': audioGenerationModelKey,
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

  static List<String> _stringList(Object? value, {int limit = 256}) {
    return stringListFromValue(value)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .take(limit)
        .toList(growable: false);
  }

  static Set<AiDingTalkMultimodalCapability> _multimodalCapabilitySet(
    Object? value,
  ) {
    final rawValues = value is List ? value : <Object?>[value];
    return <AiDingTalkMultimodalCapability>{
      for (final raw in rawValues.take(
        AiDingTalkMultimodalCapability.values.length,
      ))
        if (AiDingTalkMultimodalCapability.fromStorage(raw) case final item?)
          item,
    };
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
    Iterable<String>? available, {
    int limit = 256,
  }) {
    final normalized = _stringList(values, limit: limit);
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

@immutable
class DingTalkMessageEditRecord {
  const DingTalkMessageEditRecord({
    required this.content,
    required this.editedAt,
  });

  factory DingTalkMessageEditRecord.fromJson(Map<String, Object?> json) {
    final content = '${json['content'] ?? ''}';
    final editedAt = DateTime.tryParse('${json['edited_at'] ?? ''}');
    if (content.isEmpty || editedAt == null) {
      throw const FormatException('钉钉消息编辑历史数据不完整。');
    }
    return DingTalkMessageEditRecord(content: content, editedAt: editedAt);
  }

  final String content;
  final DateTime editedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'content': content,
    'edited_at': editedAt.toIso8601String(),
  };
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
    this.readByPeer = false,
    this.recalled = false,
    this.reactions = const <String>[],
    this.editHistory = const <DingTalkMessageEditRecord>[],
    this.sourceAiMessageId = '',
    this.feedback,
  });

  factory DingTalkGatewayMessage.fromJson(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final conversationId = '${json['conversation_id'] ?? ''}'.trim();
    final rawContent = '${json['content'] ?? ''}';
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
    final rawEditHistory = json['edit_history'];
    final editHistory = rawEditHistory is List
        ? rawEditHistory
              .take(32)
              .whereType<Map>()
              .map((item) {
                try {
                  return DingTalkMessageEditRecord.fromJson(
                    stringKeyedMapFromValue(item),
                  );
                } catch (_) {
                  return null;
                }
              })
              .whereType<DingTalkMessageEditRecord>()
              .toList(growable: false)
        : const <DingTalkMessageEditRecord>[];
    final media = _mediaList(json['media']);
    final content =
        rawContent.trim().toLowerCase() == '[null]' && media.isNotEmpty
        ? media.map((item) => '[${item.displayName}]').join(' ')
        : rawContent;
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
      media: media,
      fromSelf: boolFromValue(json['from_self']),
      failed: boolFromValue(json['failed']),
      mentionedCurrentUser: boolFromValue(json['mentioned_current_user']),
      readByPeer: boolFromValue(
        json['read_by_peer'] ?? json['is_read'] ?? json['read'],
      ),
      recalled: boolFromValue(
        json['recalled'] ?? json['is_recalled'] ?? json['recall'],
      ),
      reactions: _reactionList(json['reactions'] ?? json['reaction']),
      editHistory: editHistory,
      sourceAiMessageId: '${json['source_ai_message_id'] ?? ''}'.trim(),
      feedback: DingTalkGatewayMessageFeedback.fromStorage(json['feedback']),
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
  final bool readByPeer;
  final bool recalled;
  final List<String> reactions;
  final List<DingTalkMessageEditRecord> editHistory;
  final String sourceAiMessageId;
  final DingTalkGatewayMessageFeedback? feedback;

  bool get isAssistant => role == DingTalkGatewayMessageRole.assistant;
  bool get isEdited => editHistory.isNotEmpty;

  DingTalkGatewayMessage copyWith({
    String? id,
    String? content,
    List<DingTalkGatewayMedia>? media,
    bool? mentionedCurrentUser,
    bool? readByPeer,
    bool? recalled,
    List<String>? reactions,
    List<DingTalkMessageEditRecord>? editHistory,
    String? sourceAiMessageId,
    DingTalkGatewayMessageFeedback? feedback,
    bool clearFeedback = false,
  }) {
    return DingTalkGatewayMessage(
      id: id ?? this.id,
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
      mentionedCurrentUser: mentionedCurrentUser ?? this.mentionedCurrentUser,
      readByPeer: readByPeer ?? this.readByPeer,
      recalled: recalled ?? this.recalled,
      reactions: reactions ?? this.reactions,
      editHistory: editHistory ?? this.editHistory,
      sourceAiMessageId: sourceAiMessageId ?? this.sourceAiMessageId,
      feedback: clearFeedback ? null : feedback ?? this.feedback,
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
    'read_by_peer': readByPeer,
    'recalled': recalled,
    'reactions': reactions,
    'edit_history': editHistory
        .map((item) => item.toJson())
        .toList(growable: false),
    'source_ai_message_id': sourceAiMessageId,
    'feedback': feedback?.storageValue,
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

  static List<String> _reactionList(Object? raw) {
    final result = <String>[];

    void visit(Object? value) {
      if (value is List) {
        for (final item in value) {
          visit(item);
        }
        return;
      }
      if (value is Map) {
        final map = stringKeyedMapFromValue(value);
        for (final key in const <String>[
          'emoji',
          'emoji_code',
          'emojiCode',
          'reaction',
          'reaction_text',
          'reactionText',
          'reaction_name',
          'reactionName',
          'reaction_type',
          'reactionType',
          'type',
          'value',
          'content',
        ]) {
          final candidate = map[key];
          if (candidate is String && candidate.trim().isNotEmpty) {
            visit(candidate);
            return;
          }
        }
        return;
      }
      final text = '$value'.trim();
      if (text.isNotEmpty && text != 'null' && !result.contains(text)) {
        result.add(text);
      }
    }

    visit(raw);
    return result.take(12).toList(growable: false);
  }
}

class DingTalkConversation {
  DingTalkConversation({
    required this.id,
    required this.type,
    required this.title,
    List<DingTalkGatewayMessage> messages = const <DingTalkGatewayMessage>[],
    DateTime? createdAt,
    this.openConversationId,
    this.directUserId,
    this.directOpenDingTalkId,
  }) : createdAt = createdAt ?? DateTime.now(),
       messages = List<DingTalkGatewayMessage>.from(messages);

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
      createdAt:
          DateTime.tryParse('${json['created_at'] ?? ''}') ??
          (messages.isEmpty ? DateTime.now() : messages.first.createdAt),
      openConversationId: nullIfBlank(
        '${json['open_conversation_id'] ?? json['openConversationId'] ?? ''}',
      ),
      directUserId: nullIfBlank('${json['direct_user_id'] ?? ''}'),
      directOpenDingTalkId: nullIfBlank(
        '${json['direct_open_dingtalk_id'] ?? ''}',
      ),
    );
    final sessionId = '${json['ai_session_id'] ?? ''}'.trim();
    conversation.aiSessionId = sessionId.isEmpty ? null : sessionId;
    final checkpointId = '${json['ai_context_checkpoint_message_id'] ?? ''}'
        .trim();
    conversation.aiContextCheckpointMessageId = checkpointId.isEmpty
        ? null
        : checkpointId;
    return conversation;
  }

  final String id;
  final DingTalkConversationType type;
  String title;
  final List<DingTalkGatewayMessage> messages;
  final DateTime createdAt;

  /// DWS 编辑消息所需的 openConversationId。直聊在首次收到事件后补齐。
  String? openConversationId;
  String? aiSessionId;
  String? aiContextCheckpointMessageId;
  String? directUserId;
  String? directOpenDingTalkId;

  String get dwsConversationId {
    final remoteId = openConversationId?.trim() ?? '';
    if (remoteId.isNotEmpty) return remoteId;
    return type == DingTalkConversationType.group ? id : '';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type.name,
    'title': title,
    'created_at': createdAt.toIso8601String(),
    'open_conversation_id': openConversationId,
    'ai_session_id': aiSessionId,
    'ai_context_checkpoint_message_id': aiContextCheckpointMessageId,
    'direct_user_id': directUserId,
    'direct_open_dingtalk_id': directOpenDingTalkId,
    'messages': messages.map((item) => item.toJson()).toList(growable: false),
  };

  DateTime get updatedAt =>
      messages.isEmpty ? createdAt : messages.last.createdAt;

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
