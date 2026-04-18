/// Hook lifecycle event types matching GitHub Copilot agent lifecycle stages.
enum HookEvent {
  sessionStart('session_start', 'Session Start', '会话开始'),
  userPromptSubmit('user_prompt_submit', 'User Prompt Submit', '用户提交提示词'),
  preToolUse('pre_tool_use', 'Pre-Tool Use', '工具调用前'),
  postToolUse('post_tool_use', 'Post-Tool Use', '工具调用后'),
  subagentStart('subagent_start', 'Subagent Start', '子代理启动'),
  subagentStop('subagent_stop', 'Subagent Stop', '子代理停止'),
  stop('stop', 'Stop', '代理停止'),
  preCompact('pre_compact', 'Pre-Compact', '上下文压缩前'),
  sessionEnd('session_end', 'Session End', '会话结束'),
  errorOccurred('error_occurred', 'Error Occurred', '发生错误');

  const HookEvent(this.storageValue, this.labelEn, this.labelZh);

  final String storageValue;
  final String labelEn;
  final String labelZh;

  String label(bool isZh) => isZh ? labelZh : labelEn;

  static HookEvent? fromStorage(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final event in values) {
      if (event.storageValue == value) return event;
    }
    return null;
  }
}

/// A single hook entry that maps a lifecycle event to a script.
class HookEntry {
  const HookEntry({
    required this.id,
    required this.event,
    required this.label,
    this.scriptPath,
    this.scriptContent,
    this.enabled = true,
    this.timeoutSeconds = 12,
  });

  factory HookEntry.fromJson(Map<String, Object?> json) {
    return HookEntry(
      id: '${json['id'] ?? ''}'.trim(),
      event: HookEvent.fromStorage('${json['event'] ?? ''}') ??
          HookEvent.sessionStart,
      label: '${json['label'] ?? ''}'.trim(),
      scriptPath: _nullIfEmpty('${json['script_path'] ?? ''}'),
      scriptContent: _nullIfEmpty('${json['script_content'] ?? ''}'),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      timeoutSeconds: (json['timeout_seconds'] as num?)?.toInt() ?? 12,
    );
  }

  final String id;
  final HookEvent event;
  final String label;
  final String? scriptPath;
  final String? scriptContent;
  final bool enabled;
  final int timeoutSeconds;

  /// Whether this entry has a valid executable source.
  bool get hasScript =>
      (scriptPath != null && scriptPath!.isNotEmpty) ||
      (scriptContent != null && scriptContent!.isNotEmpty);

  HookEntry copyWith({
    String? id,
    HookEvent? event,
    String? label,
    String? scriptPath,
    String? scriptContent,
    bool? enabled,
    int? timeoutSeconds,
    bool clearScriptPath = false,
    bool clearScriptContent = false,
  }) {
    return HookEntry(
      id: id ?? this.id,
      event: event ?? this.event,
      label: label ?? this.label,
      scriptPath: clearScriptPath ? null : (scriptPath ?? this.scriptPath),
      scriptContent:
          clearScriptContent ? null : (scriptContent ?? this.scriptContent),
      enabled: enabled ?? this.enabled,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'event': event.storageValue,
      'label': label,
      'script_path': scriptPath ?? '',
      'script_content': scriptContent ?? '',
      'enabled': enabled,
      'timeout_seconds': timeoutSeconds,
    };
  }
}

String? _nullIfEmpty(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
