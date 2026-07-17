import '../../l10n/app_localizations.dart';
import '../../shared/util/input_value_parsing.dart';

/// Hook lifecycle event types matching GitHub Copilot agent lifecycle stages.
enum HookEvent {
  sessionStart('session_start'),
  userPromptSubmit('user_prompt_submit'),
  preToolUse('pre_tool_use'),
  postToolUse('post_tool_use'),
  subagentStart('subagent_start'),
  subagentStop('subagent_stop'),
  stop('stop'),
  preCompact('pre_compact'),
  sessionEnd('session_end'),
  errorOccurred('error_occurred');

  const HookEvent(this.storageValue);

  final String storageValue;

  String label(AppLocalizations l10n) => switch (this) {
    HookEvent.sessionStart => l10n.hookEventSessionStart,
    HookEvent.userPromptSubmit => l10n.hookEventUserPromptSubmit,
    HookEvent.preToolUse => l10n.hookEventPreToolUse,
    HookEvent.postToolUse => l10n.hookEventPostToolUse,
    HookEvent.subagentStart => l10n.hookEventSubagentStart,
    HookEvent.subagentStop => l10n.hookEventSubagentStop,
    HookEvent.stop => l10n.hookEventStop,
    HookEvent.preCompact => l10n.hookEventPreCompact,
    HookEvent.sessionEnd => l10n.hookEventSessionEnd,
    HookEvent.errorOccurred => l10n.hookEventErrorOccurred,
  };

  static HookEvent? fromStorage(String? value) {
    return enumByStorageValue(values, value, (event) => event.storageValue);
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
    this.timeoutSeconds = defaultTimeoutSeconds,
  });

  factory HookEntry.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return HookEntry(
      id: stringFromValue(json['id']),
      event:
          HookEvent.fromStorage(stringFromValue(json['event'])) ??
          HookEvent.sessionStart,
      label: stringFromValue(json['label']),
      scriptPath: optionalStringFromValue(json['script_path']),
      scriptContent: optionalStringFromValue(json['script_content']),
      enabled: boolFromValue(json['enabled'], defaultValue: true),
      timeoutSeconds: timeoutSecondsFromValue(json['timeout_seconds']),
    );
  }

  static const int defaultTimeoutSeconds = 12;
  static const int minTimeoutSeconds = 1;
  static const int maxTimeoutSeconds = 60;
  static const IntValueRange _timeoutSecondsRange = IntValueRange(
    fallback: defaultTimeoutSeconds,
    min: minTimeoutSeconds,
    max: maxTimeoutSeconds,
  );

  static int timeoutSecondsFromValue(Object? value) {
    return _timeoutSecondsRange.fromValue(value);
  }

  static int normalizeTimeoutSeconds(int value) {
    return _timeoutSecondsRange.normalize(value);
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
      scriptContent: clearScriptContent
          ? null
          : (scriptContent ?? this.scriptContent),
      enabled: enabled ?? this.enabled,
      timeoutSeconds: normalizeTimeoutSeconds(
        timeoutSeconds ?? this.timeoutSeconds,
      ),
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
      'timeout_seconds': normalizeTimeoutSeconds(timeoutSeconds),
    };
  }
}
