import 'dart:ui';

import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';

/// Hook lifecycle event types matching GitHub Copilot agent lifecycle stages.
enum HookEvent {
  sessionStart(
    'session_start',
    'Session Start',
    '会话开始',
    zhHant: '會話開始',
    fr: 'Début de session',
    de: 'Sitzungsstart',
    ja: 'セッション開始',
  ),
  userPromptSubmit(
    'user_prompt_submit',
    'User Prompt Submit',
    '用户提交提示词',
    zhHant: '使用者提交提示詞',
    fr: 'Soumission du prompt',
    de: 'Prompt gesendet',
    ja: 'ユーザープロンプト送信',
  ),
  preToolUse(
    'pre_tool_use',
    'Pre-Tool Use',
    '工具调用前',
    zhHant: '工具呼叫前',
    fr: 'Avant outil',
    de: 'Vor Werkzeugnutzung',
    ja: 'ツール使用前',
  ),
  postToolUse(
    'post_tool_use',
    'Post-Tool Use',
    '工具调用后',
    zhHant: '工具呼叫後',
    fr: 'Après outil',
    de: 'Nach Werkzeugnutzung',
    ja: 'ツール使用後',
  ),
  subagentStart(
    'subagent_start',
    'Subagent Start',
    '子代理启动',
    zhHant: '子代理啟動',
    fr: 'Démarrage du sous-agent',
    de: 'Subagent gestartet',
    ja: 'サブエージェント開始',
  ),
  subagentStop(
    'subagent_stop',
    'Subagent Stop',
    '子代理停止',
    zhHant: '子代理停止',
    fr: 'Arrêt du sous-agent',
    de: 'Subagent gestoppt',
    ja: 'サブエージェント停止',
  ),
  stop(
    'stop',
    'Stop',
    '代理停止',
    zhHant: '代理停止',
    fr: 'Arrêt',
    de: 'Stopp',
    ja: '停止',
  ),
  preCompact(
    'pre_compact',
    'Pre-Compact',
    '上下文压缩前',
    zhHant: '上下文壓縮前',
    fr: 'Avant compactage',
    de: 'Vor Kompaktierung',
    ja: 'コンテキスト圧縮前',
  ),
  sessionEnd(
    'session_end',
    'Session End',
    '会话结束',
    zhHant: '會話結束',
    fr: 'Fin de session',
    de: 'Sitzungsende',
    ja: 'セッション終了',
  ),
  errorOccurred(
    'error_occurred',
    'Error Occurred',
    '发生错误',
    zhHant: '發生錯誤',
    fr: 'Erreur survenue',
    de: 'Fehler aufgetreten',
    ja: 'エラー発生',
  );

  const HookEvent(
    this.storageValue,
    this.labelEn,
    this.labelZh, {
    required this.zhHant,
    required this.fr,
    required this.de,
    required this.ja,
  });

  final String storageValue;
  final String labelEn;
  final String labelZh;
  final String zhHant;
  final String fr;
  final String de;
  final String ja;

  String labelForLocale(Locale locale) {
    return openHandLocalizedTextForLocale(
      locale,
      zh: labelZh,
      zhHant: zhHant,
      en: labelEn,
      fr: fr,
      de: de,
      ja: ja,
    );
  }

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
