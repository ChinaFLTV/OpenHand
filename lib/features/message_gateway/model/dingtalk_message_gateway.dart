import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../shared/util/input_value_parsing.dart';

enum DingTalkConversationType { group, direct }

enum DingTalkGatewayMessageRole { user, assistant }

enum DingTalkReminderMode { none, inApp, sound }

class DingTalkConversationTarget {
  const DingTalkConversationTarget({
    required this.id,
    required this.title,
    required this.type,
    this.subtitle = '',
  });

  final String id;
  final String title;
  final DingTalkConversationType type;
  final String subtitle;
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
  };

  static List<String> _stringList(Object? value) {
    return stringListFromValue(value)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .take(256)
        .toList(growable: false);
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
    this.fromSelf = false,
    this.failed = false,
  });

  final String id;
  final String conversationId;
  final DingTalkConversationType conversationType;
  final DingTalkGatewayMessageRole role;
  final String content;
  final DateTime createdAt;
  final String senderName;
  final String senderId;
  final String conversationTitle;
  final bool fromSelf;
  final bool failed;

  bool get isAssistant => role == DingTalkGatewayMessageRole.assistant;
}

class DingTalkConversation {
  DingTalkConversation({
    required this.id,
    required this.type,
    required this.title,
    List<DingTalkGatewayMessage> messages = const <DingTalkGatewayMessage>[],
  }) : messages = List<DingTalkGatewayMessage>.from(messages);

  final String id;
  final DingTalkConversationType type;
  String title;
  final List<DingTalkGatewayMessage> messages;
  String? aiSessionId;

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
