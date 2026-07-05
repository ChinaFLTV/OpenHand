import '../../../shared/util/input_value_parsing.dart';
import 'ai_token_usage.dart';

const String aiSessionGoalStateMetadataKey = 'goal_state';
const int aiSessionGoalStateSchemaVersion = 1;
const int aiSessionGoalObjectiveMaxCharacters = 4000;
const int aiSessionGoalDefaultMaxAutoTurns = 12;
const int aiSessionGoalHardMaxAutoTurns = 60;
const int aiSessionGoalMaxHistoryEntries = 20;
const int aiSessionGoalEvaluationMaxEvidenceItems = 8;
const String aiSessionGoalIdMetadataKey = 'goal_id';
const String aiSessionGoalObjectiveMetadataKey = 'goal_objective';
const String aiSessionGoalEvaluationIdMetadataKey = 'goal_evaluation_id';
const String aiSessionGoalAutoFollowUpMetadataKey = 'goal_auto_follow_up';
const String aiSessionGoalPausedForQueueStatusReason =
    'Paused for queued user messages.';

enum AiSessionGoalStatus {
  running('running'),
  paused('paused'),
  completed('completed'),
  terminated('terminated'),
  failed('failed'),
  roundLimitReached('round_limit_reached'),
  tokenBudgetReached('token_budget_reached');

  const AiSessionGoalStatus(this.storageValue);

  final String storageValue;

  bool get isActive =>
      this == AiSessionGoalStatus.running || this == AiSessionGoalStatus.paused;

  bool get isTerminal => !isActive;

  static AiSessionGoalStatus fromStorage(Object? value) {
    return enumByStorageValueOr(
      values,
      value,
      (status) => status.storageValue,
      fallback: AiSessionGoalStatus.running,
    );
  }
}

class AiSessionGoalEvaluationRecord {
  const AiSessionGoalEvaluationRecord({
    required this.id,
    required this.createdAt,
    required this.roundIndex,
    required this.passed,
    required this.summary,
    this.confidence,
    this.followUpPrompt,
    this.evidence = const <String>[],
    this.missing = const <String>[],
    this.rawResponse,
    this.providerConfigId,
    this.modelId,
    this.modelLabel,
    this.usage,
    this.error,
  });

  final String id;
  final DateTime createdAt;
  final int roundIndex;
  final bool passed;
  final String summary;
  final double? confidence;
  final String? followUpPrompt;
  final List<String> evidence;
  final List<String> missing;
  final String? rawResponse;
  final String? providerConfigId;
  final String? modelId;
  final String? modelLabel;
  final AiTokenUsage? usage;
  final String? error;

  AiSessionGoalEvaluationRecord copyWith({
    String? id,
    DateTime? createdAt,
    int? roundIndex,
    bool? passed,
    String? summary,
    double? confidence,
    bool clearConfidence = false,
    String? followUpPrompt,
    bool clearFollowUpPrompt = false,
    List<String>? evidence,
    List<String>? missing,
    String? rawResponse,
    bool clearRawResponse = false,
    String? providerConfigId,
    String? modelId,
    String? modelLabel,
    AiTokenUsage? usage,
    bool clearUsage = false,
    String? error,
    bool clearError = false,
  }) {
    return AiSessionGoalEvaluationRecord(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      roundIndex: roundIndex ?? this.roundIndex,
      passed: passed ?? this.passed,
      summary: summary ?? this.summary,
      confidence: clearConfidence ? null : confidence ?? this.confidence,
      followUpPrompt: clearFollowUpPrompt
          ? null
          : followUpPrompt ?? this.followUpPrompt,
      evidence: evidence ?? this.evidence,
      missing: missing ?? this.missing,
      rawResponse: clearRawResponse ? null : rawResponse ?? this.rawResponse,
      providerConfigId: providerConfigId ?? this.providerConfigId,
      modelId: modelId ?? this.modelId,
      modelLabel: modelLabel ?? this.modelLabel,
      usage: clearUsage ? null : usage ?? this.usage,
      error: clearError ? null : error ?? this.error,
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'id': id,
      'created_at': createdAt.toUtc().toIso8601String(),
      'round_index': roundIndex,
      'passed': passed,
      'summary': summary,
      if (confidence != null) 'confidence': confidence,
    };
    putIfNotBlank(json, 'follow_up_prompt', followUpPrompt);
    if (evidence.isNotEmpty) json['evidence'] = evidence;
    if (missing.isNotEmpty) json['missing'] = missing;
    putIfNotBlank(json, 'raw_response', rawResponse);
    putIfNotBlank(json, 'provider_config_id', providerConfigId);
    putIfNotBlank(json, 'model_id', modelId);
    putIfNotBlank(json, 'model_label', modelLabel);
    if (usage != null) json['usage'] = usage!.toJson();
    putIfNotBlank(json, 'error', error);
    return json;
  }

  static AiSessionGoalEvaluationRecord? fromJson(Object? raw) {
    final json = _goalMap(raw);
    if (json == null) return null;
    final id = _goalString(json['id']);
    if (id.isEmpty) return null;
    final now = DateTime.now().toUtc();
    final usageJson = _goalMap(json['usage']);
    return AiSessionGoalEvaluationRecord(
      id: id,
      createdAt: utcDateTimeFromValue(json['created_at']) ?? now,
      roundIndex: _goalInt(json['round_index']) ?? 0,
      passed: json['passed'] == true,
      summary: _goalString(json['summary']),
      confidence: _goalDouble(json['confidence']),
      followUpPrompt: _goalNullableString(json['follow_up_prompt']),
      evidence: _goalStringList(json['evidence']),
      missing: _goalStringList(json['missing']),
      rawResponse: _goalNullableString(json['raw_response']),
      providerConfigId: _goalNullableString(json['provider_config_id']),
      modelId: _goalNullableString(json['model_id']),
      modelLabel: _goalNullableString(json['model_label']),
      usage: usageJson == null ? null : AiTokenUsage.fromJson(usageJson),
      error: _goalNullableString(json['error']),
    );
  }
}

class AiSessionGoalRecord {
  const AiSessionGoalRecord({
    required this.id,
    required this.objective,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.evaluatorProviderConfigId,
    required this.evaluatorModelId,
    required this.evaluatorModelLabel,
    this.maxTurns,
    this.tokenBudget,
    this.turnCount = 0,
    this.tokensUsed = 0,
    this.completedAt,
    this.pausedAt,
    this.terminatedAt,
    this.statusReason,
    this.lastAssistantMessageId,
    this.lastAutoUserMessageId,
    this.evaluations = const <AiSessionGoalEvaluationRecord>[],
  });

  final String id;
  final String objective;
  final AiSessionGoalStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String evaluatorProviderConfigId;
  final String evaluatorModelId;
  final String evaluatorModelLabel;
  final int? maxTurns;
  final int? tokenBudget;
  final int turnCount;
  final int tokensUsed;
  final DateTime? completedAt;
  final DateTime? pausedAt;
  final DateTime? terminatedAt;
  final String? statusReason;
  final String? lastAssistantMessageId;
  final String? lastAutoUserMessageId;
  final List<AiSessionGoalEvaluationRecord> evaluations;

  bool get isActive => status.isActive;
  bool get isRunning => status == AiSessionGoalStatus.running;
  bool get isPaused => status == AiSessionGoalStatus.paused;
  bool get hasTurnLimit => maxTurns != null && maxTurns! > 0;
  bool get hasTokenBudget => tokenBudget != null && tokenBudget! > 0;
  AiSessionGoalEvaluationRecord? get lastEvaluation =>
      evaluations.isEmpty ? null : evaluations.last;

  AiSessionGoalRecord copyWith({
    String? id,
    String? objective,
    AiSessionGoalStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? evaluatorProviderConfigId,
    String? evaluatorModelId,
    String? evaluatorModelLabel,
    int? maxTurns,
    bool clearMaxTurns = false,
    int? tokenBudget,
    bool clearTokenBudget = false,
    int? turnCount,
    int? tokensUsed,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? pausedAt,
    bool clearPausedAt = false,
    DateTime? terminatedAt,
    bool clearTerminatedAt = false,
    String? statusReason,
    bool clearStatusReason = false,
    String? lastAssistantMessageId,
    bool clearLastAssistantMessageId = false,
    String? lastAutoUserMessageId,
    bool clearLastAutoUserMessageId = false,
    List<AiSessionGoalEvaluationRecord>? evaluations,
  }) {
    return AiSessionGoalRecord(
      id: id ?? this.id,
      objective: objective ?? this.objective,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      evaluatorProviderConfigId:
          evaluatorProviderConfigId ?? this.evaluatorProviderConfigId,
      evaluatorModelId: evaluatorModelId ?? this.evaluatorModelId,
      evaluatorModelLabel: evaluatorModelLabel ?? this.evaluatorModelLabel,
      maxTurns: clearMaxTurns ? null : maxTurns ?? this.maxTurns,
      tokenBudget: clearTokenBudget ? null : tokenBudget ?? this.tokenBudget,
      turnCount: turnCount ?? this.turnCount,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      pausedAt: clearPausedAt ? null : pausedAt ?? this.pausedAt,
      terminatedAt: clearTerminatedAt
          ? null
          : terminatedAt ?? this.terminatedAt,
      statusReason: clearStatusReason
          ? null
          : statusReason ?? this.statusReason,
      lastAssistantMessageId: clearLastAssistantMessageId
          ? null
          : lastAssistantMessageId ?? this.lastAssistantMessageId,
      lastAutoUserMessageId: clearLastAutoUserMessageId
          ? null
          : lastAutoUserMessageId ?? this.lastAutoUserMessageId,
      evaluations: evaluations ?? this.evaluations,
    );
  }

  AiSessionGoalRecord appendEvaluation(
    AiSessionGoalEvaluationRecord evaluation, {
    required DateTime updatedAt,
  }) {
    return copyWith(
      updatedAt: updatedAt,
      evaluations: <AiSessionGoalEvaluationRecord>[...evaluations, evaluation],
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'id': id,
      'objective': objective,
      'status': status.storageValue,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'evaluator_provider_config_id': evaluatorProviderConfigId,
      'evaluator_model_id': evaluatorModelId,
      'evaluator_model_label': evaluatorModelLabel,
      if (hasTurnLimit) 'max_turns': maxTurns,
      if (hasTokenBudget) 'token_budget': tokenBudget,
      'turn_count': turnCount,
      'tokens_used': tokensUsed,
      if (completedAt != null)
        'completed_at': completedAt!.toUtc().toIso8601String(),
      if (pausedAt != null) 'paused_at': pausedAt!.toUtc().toIso8601String(),
      if (terminatedAt != null)
        'terminated_at': terminatedAt!.toUtc().toIso8601String(),
    };
    putIfNotBlank(json, 'status_reason', statusReason);
    putIfNotBlank(json, 'last_assistant_message_id', lastAssistantMessageId);
    putIfNotBlank(json, 'last_auto_user_message_id', lastAutoUserMessageId);
    json['evaluations'] = evaluations.map((item) => item.toJson()).toList();
    return json;
  }

  static AiSessionGoalRecord? fromJson(Object? raw) {
    final json = _goalMap(raw);
    if (json == null) return null;
    final id = _goalString(json['id']);
    final objective = _goalString(json['objective']);
    if (id.isEmpty || objective.isEmpty) return null;
    final now = DateTime.now().toUtc();
    return AiSessionGoalRecord(
      id: id,
      objective: objective,
      status: AiSessionGoalStatus.fromStorage(json['status']),
      createdAt: utcDateTimeFromValue(json['created_at']) ?? now,
      updatedAt: utcDateTimeFromValue(json['updated_at']) ?? now,
      evaluatorProviderConfigId: _goalString(
        json['evaluator_provider_config_id'],
      ),
      evaluatorModelId: _goalString(json['evaluator_model_id']),
      evaluatorModelLabel: _goalString(json['evaluator_model_label']),
      maxTurns: _positiveGoalInt(json['max_turns']),
      tokenBudget: _positiveGoalInt(json['token_budget']),
      turnCount: _goalInt(json['turn_count']) ?? 0,
      tokensUsed: _goalInt(json['tokens_used']) ?? 0,
      completedAt: utcDateTimeFromValue(json['completed_at']),
      pausedAt: utcDateTimeFromValue(json['paused_at']),
      terminatedAt: utcDateTimeFromValue(json['terminated_at']),
      statusReason: _goalNullableString(json['status_reason']),
      lastAssistantMessageId: _goalNullableString(
        json['last_assistant_message_id'],
      ),
      lastAutoUserMessageId: _goalNullableString(
        json['last_auto_user_message_id'],
      ),
      evaluations: _goalList(json['evaluations'])
          .map(AiSessionGoalEvaluationRecord.fromJson)
          .whereType<AiSessionGoalEvaluationRecord>()
          .toList(growable: false),
    );
  }
}

class AiSessionGoalState {
  const AiSessionGoalState({
    this.current,
    this.history = const <AiSessionGoalRecord>[],
  });

  final AiSessionGoalRecord? current;
  final List<AiSessionGoalRecord> history;

  bool get hasActiveGoal => current?.isActive == true;
  bool get isRunning => current?.isRunning == true;
  bool get isPaused => current?.isPaused == true;

  AiSessionGoalState copyWith({
    AiSessionGoalRecord? current,
    bool clearCurrent = false,
    List<AiSessionGoalRecord>? history,
  }) {
    return AiSessionGoalState(
      current: clearCurrent ? null : current ?? this.current,
      history: history ?? this.history,
    );
  }

  AiSessionGoalState replaceCurrent(AiSessionGoalRecord goal) {
    return copyWith(current: goal);
  }

  AiSessionGoalState archiveCurrent(AiSessionGoalRecord goal) {
    final retained = <AiSessionGoalRecord>[...history, goal];
    final overflow = retained.length - aiSessionGoalMaxHistoryEntries;
    return AiSessionGoalState(
      history: List<AiSessionGoalRecord>.unmodifiable(
        overflow > 0 ? retained.skip(overflow) : retained,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': aiSessionGoalStateSchemaVersion,
      'current': current?.toJson(),
      'history': history.map((item) => item.toJson()).toList(),
    };
  }

  Map<String, Object?> toMetadataPatch() {
    return <String, Object?>{aiSessionGoalStateMetadataKey: toJson()};
  }

  static const AiSessionGoalState empty = AiSessionGoalState();

  static AiSessionGoalState fromMetadata(Map<String, Object?> metadata) {
    return fromJson(metadata[aiSessionGoalStateMetadataKey]);
  }

  static AiSessionGoalState fromJson(Object? raw) {
    final json = _goalMap(raw);
    if (json == null) return empty;
    return AiSessionGoalState(
      current: AiSessionGoalRecord.fromJson(json['current']),
      history: _goalList(json['history'])
          .map(AiSessionGoalRecord.fromJson)
          .whereType<AiSessionGoalRecord>()
          .toList(growable: false),
    );
  }
}

class AiSessionGoalStartOptions {
  const AiSessionGoalStartOptions({
    required this.evaluatorProviderConfigId,
    required this.evaluatorModelId,
    required this.evaluatorModelLabel,
    this.maxTurns,
    this.tokenBudget,
  });

  final String evaluatorProviderConfigId;
  final String evaluatorModelId;
  final String evaluatorModelLabel;
  final int? maxTurns;
  final int? tokenBudget;

  bool get hasTurnLimit => maxTurns != null && maxTurns! > 0;
  bool get hasTokenBudget => tokenBudget != null && tokenBudget! > 0;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'evaluator_provider_config_id': evaluatorProviderConfigId,
      'evaluator_model_id': evaluatorModelId,
      'evaluator_model_label': evaluatorModelLabel,
      if (hasTurnLimit) 'max_turns': maxTurns,
      if (hasTokenBudget) 'token_budget': tokenBudget,
    };
  }

  static AiSessionGoalStartOptions? fromJson(Object? raw) {
    final json = _goalMap(raw);
    if (json == null) return null;
    final evaluatorProviderConfigId = _goalString(
      json['evaluator_provider_config_id'] ?? json['provider_config_id'],
    );
    final evaluatorModelId = _goalString(
      json['evaluator_model_id'] ?? json['model_id'],
    );
    final evaluatorModelLabel = _goalString(
      json['evaluator_model_label'] ?? json['model_label'],
    );
    if (evaluatorProviderConfigId.isEmpty || evaluatorModelId.isEmpty) {
      return null;
    }
    return AiSessionGoalStartOptions(
      evaluatorProviderConfigId: evaluatorProviderConfigId,
      evaluatorModelId: evaluatorModelId,
      evaluatorModelLabel: evaluatorModelLabel.isEmpty
          ? evaluatorModelId
          : evaluatorModelLabel,
      maxTurns: _positiveGoalInt(json['max_turns'] ?? json['maxTurns']),
      tokenBudget: _positiveGoalInt(
        json['token_budget'] ?? json['tokenBudget'],
      ),
    );
  }
}

bool aiSessionGoalModeAllowedForTemplate(String templateId) {
  return !const <String>{
    'machine_expert',
    'harness_engineering',
    'web_reverse_expert',
    'android_reverse_expert',
  }.contains(templateId.trim());
}

Map<String, Object?>? _goalMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return stringKeyedMapFromValue(value);
  }
  return null;
}

List<Object?> _goalList(Object? value) {
  if (value is List<Object?>) return value;
  if (value is List) return List<Object?>.from(value);
  return const <Object?>[];
}

String _goalString(Object? value) {
  if (value == null) return '';
  final text = '$value'.trim();
  return text == 'null' ? '' : text;
}

String? _goalNullableString(Object? value) {
  final text = _goalString(value);
  return text.isEmpty ? null : text;
}

int? _goalInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.round() : null;
  return optionalIntFromValue(_goalString(value));
}

int? _positiveGoalInt(Object? value) {
  final parsed = _goalInt(value);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

double? _goalDouble(Object? value) {
  return optionalDoubleFromValue(value);
}

List<String> _goalStringList(Object? value) {
  return _goalList(value)
      .map((item) => _goalString(item))
      .where((item) => item.isNotEmpty)
      .take(aiSessionGoalEvaluationMaxEvidenceItems)
      .toList(growable: false);
}
