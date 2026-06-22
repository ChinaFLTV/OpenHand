import 'dart:convert';

import 'package:flutter/foundation.dart';

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

  Map<String, Object?> toJson() => <String, Object?>{
    'capability_id': capabilityId,
    'enabled': enabled,
    'status': status,
    if (serverName != null) 'server_name': serverName,
    if (toolCount != null) 'tool_count': toolCount,
    if (message != null && message!.trim().isNotEmpty)
      'message': message!.trim(),
  };
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
    return capabilities[capabilityId];
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

class TemplateRuntimeLinkageController extends ChangeNotifier {
  final Map<String, TemplateRuntimeSessionLinkage> _sessions =
      <String, TemplateRuntimeSessionLinkage>{};
  String _signature = '';

  List<TemplateRuntimeSessionLinkage> get sessions =>
      List<TemplateRuntimeSessionLinkage>.unmodifiable(_sessions.values);

  List<TemplateRuntimeSessionLinkage> sessionsForTemplate(String templateId) {
    return _sessions.values
        .where((session) => session.templateId == templateId)
        .toList(growable: false);
  }

  TemplateRuntimeCapabilityState? latestCapabilityState(
    String templateId,
    String capabilityId,
  ) {
    TemplateRuntimeSessionLinkage? latest;
    for (final session in _sessions.values) {
      if (session.templateId != templateId ||
          !session.capabilities.containsKey(capabilityId)) {
        continue;
      }
      if (latest == null || session.updatedAt.isAfter(latest.updatedAt)) {
        latest = session;
      }
    }
    return latest?.capability(capabilityId);
  }

  int enabledSessionCount(String templateId, String capabilityId) {
    var count = 0;
    for (final session in _sessions.values) {
      if (session.templateId != templateId) continue;
      if (session.capability(capabilityId)?.enabled == true) count++;
    }
    return count;
  }

  void upsertSession({
    required String sessionId,
    required String templateId,
    required Iterable<TemplateRuntimeCapabilityState> capabilities,
  }) {
    final normalizedSessionId = sessionId.trim();
    final normalizedTemplateId = templateId.trim();
    if (normalizedSessionId.isEmpty || normalizedTemplateId.isEmpty) return;
    final capabilityMap = <String, TemplateRuntimeCapabilityState>{
      for (final item in capabilities)
        if (item.capabilityId.trim().isNotEmpty) item.capabilityId: item,
    };
    _sessions[normalizedSessionId] = TemplateRuntimeSessionLinkage(
      sessionId: normalizedSessionId,
      templateId: normalizedTemplateId,
      updatedAt: DateTime.now().toUtc(),
      capabilities: Map<String, TemplateRuntimeCapabilityState>.unmodifiable(
        capabilityMap,
      ),
    );
    _notifyIfChanged();
  }

  void removeSession(String sessionId) {
    if (_sessions.remove(sessionId.trim()) != null) {
      _notifyIfChanged();
    }
  }

  void _notifyIfChanged() {
    final nextSignature = jsonEncode(
      _sessions.values
          .map((session) => session.toJson())
          .toList(growable: false)
        ..sort((a, b) => '${a['session_id']}'.compareTo('${b['session_id']}')),
    );
    if (nextSignature == _signature) return;
    _signature = nextSignature;
    notifyListeners();
  }
}
