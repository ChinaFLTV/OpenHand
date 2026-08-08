import 'package:flutter/foundation.dart';

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
    ).normalized();
  }

  final int pollIntervalSeconds;
  final DingTalkReminderMode reminderMode;
  final String responseModelKey;

  DingTalkGatewaySettings normalized() => DingTalkGatewaySettings(
    pollIntervalSeconds: pollIntervalSeconds.clamp(3, 300).toInt(),
    reminderMode: reminderMode,
    responseModelKey: responseModelKey.trim(),
  );

  DingTalkGatewaySettings copyWith({
    int? pollIntervalSeconds,
    DingTalkReminderMode? reminderMode,
    String? responseModelKey,
  }) => DingTalkGatewaySettings(
    pollIntervalSeconds: pollIntervalSeconds ?? this.pollIntervalSeconds,
    reminderMode: reminderMode ?? this.reminderMode,
    responseModelKey: responseModelKey ?? this.responseModelKey,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'poll_interval_seconds': pollIntervalSeconds,
    'reminder_mode': reminderMode.name,
    'response_model_key': responseModelKey,
  };
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
