import 'package:flutter/foundation.dart';

import '../../shared/core/managed_change_notifier.dart';
import '../../shared/util/input_value_parsing.dart';

class TemplateRuntimeCapabilityState {
  const TemplateRuntimeCapabilityState({
    required this.capabilityId,
    required this.enabled,
    required this.status,
    this.serverName,
    this.toolCount,
    this.message,
  });

  final String capabilityId;
  final bool enabled;
  final String status;
  final String? serverName;
  final int? toolCount;
  final String? message;

  Map<String, Object?> toJson() {
    final normalizedServerName = nullIfBlank(serverName);
    final normalizedMessage = nullIfBlank(message);
    return <String, Object?>{
      'capability_id': capabilityId,
      'enabled': enabled,
      'status': status,
      if (normalizedServerName != null) 'server_name': normalizedServerName,
      if (toolCount != null) 'tool_count': toolCount,
      if (normalizedMessage != null) 'message': normalizedMessage,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TemplateRuntimeCapabilityState &&
            capabilityId == other.capabilityId &&
            enabled == other.enabled &&
            status == other.status &&
            serverName == other.serverName &&
            toolCount == other.toolCount &&
            message == other.message;
  }

  @override
  int get hashCode => Object.hash(
    capabilityId,
    enabled,
    status,
    serverName,
    toolCount,
    message,
  );
}

class TemplateRuntimeSessionLinkage {
  const TemplateRuntimeSessionLinkage({
    required this.sessionId,
    required this.templateId,
    required this.updatedAt,
    required this.capabilities,
  });

  final String sessionId;
  final String templateId;
  final DateTime updatedAt;
  final Map<String, TemplateRuntimeCapabilityState> capabilities;

  TemplateRuntimeCapabilityState? capability(String capabilityId) {
    final normalizedCapabilityId = nullIfBlank(capabilityId);
    if (normalizedCapabilityId == null) return null;
    return capabilities[normalizedCapabilityId];
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'session_id': sessionId,
    'template_id': templateId,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'capabilities': <String, Object?>{
      for (final entry in capabilities.entries) entry.key: entry.value.toJson(),
    },
  };
}

class TemplateRuntimeLinkageController extends ManagedChangeNotifier {
  final Map<String, TemplateRuntimeSessionLinkage> _sessions =
      <String, TemplateRuntimeSessionLinkage>{};

  TemplateRuntimeCapabilityState? latestCapabilityState(
    String templateId,
    String capabilityId,
  ) {
    final normalizedTemplateId = nullIfBlank(templateId);
    final normalizedCapabilityId = nullIfBlank(capabilityId);
    if (normalizedTemplateId == null || normalizedCapabilityId == null) {
      return null;
    }
    TemplateRuntimeSessionLinkage? latest;
    for (final session in _sessions.values) {
      if (session.templateId != normalizedTemplateId ||
          !session.capabilities.containsKey(normalizedCapabilityId)) {
        continue;
      }
      if (latest == null || session.updatedAt.isAfter(latest.updatedAt)) {
        latest = session;
      }
    }
    return latest?.capability(capabilityId);
  }

  int enabledSessionCount(String templateId, String capabilityId) {
    final normalizedTemplateId = nullIfBlank(templateId);
    final normalizedCapabilityId = nullIfBlank(capabilityId);
    if (normalizedTemplateId == null || normalizedCapabilityId == null) {
      return 0;
    }
    var count = 0;
    for (final session in _sessions.values) {
      if (session.templateId != normalizedTemplateId) continue;
      if (session.capability(normalizedCapabilityId)?.enabled == true) {
        count++;
      }
    }
    return count;
  }

  void upsertSession({
    required String sessionId,
    required String templateId,
    required Iterable<TemplateRuntimeCapabilityState> capabilities,
  }) {
    if (isDisposed) return;
    final normalizedSessionId = nullIfBlank(sessionId);
    final normalizedTemplateId = nullIfBlank(templateId);
    if (normalizedSessionId == null || normalizedTemplateId == null) return;
    final capabilityMap = <String, TemplateRuntimeCapabilityState>{};
    for (final item in capabilities) {
      final normalizedCapabilityId = nullIfBlank(item.capabilityId);
      if (normalizedCapabilityId == null) continue;
      capabilityMap[normalizedCapabilityId] = TemplateRuntimeCapabilityState(
        capabilityId: normalizedCapabilityId,
        enabled: item.enabled,
        status: item.status,
        serverName: nullIfBlank(item.serverName),
        toolCount: item.toolCount,
        message: nullIfBlank(item.message),
      );
    }
    final existing = _sessions[normalizedSessionId];
    if (existing?.templateId == normalizedTemplateId &&
        mapEquals(existing?.capabilities, capabilityMap)) {
      return;
    }
    _sessions[normalizedSessionId] = TemplateRuntimeSessionLinkage(
      sessionId: normalizedSessionId,
      templateId: normalizedTemplateId,
      updatedAt: DateTime.now().toUtc(),
      capabilities: Map<String, TemplateRuntimeCapabilityState>.unmodifiable(
        capabilityMap,
      ),
    );
    notifyListeners();
  }

  void removeSession(String sessionId) {
    if (isDisposed) return;
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId != null &&
        _sessions.remove(normalizedSessionId) != null) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (isDisposed) return;
    _sessions.clear();
    super.dispose();
  }
}
