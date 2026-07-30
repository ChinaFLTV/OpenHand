import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import 'ai_token_usage.dart';

const String aiSessionGoalStateMetadataKey = 'goal_state';
const int aiSessionGoalStateSchemaVersion = 1;
const int aiSessionGoalObjectiveMaxCharacters = 4000;
const int aiSessionGoalDefaultMaxAutoTurns = 12;
const int aiSessionGoalHardMaxAutoTurns = 60;
const int aiSessionGoalMaxHistoryEntries = 20;
const int aiSessionGoalMaxEvaluationEntries = aiSessionGoalHardMaxAutoTurns;
const int aiSessionGoalEvaluationMaxEvidenceItems = 8;
const int aiSessionGoalReferenceIdMaxCharacters = 256;
const int aiSessionGoalModelFieldMaxCharacters = 512;
const int aiSessionGoalStatusReasonMaxCharacters = 800;
const int aiSessionGoalEvaluationSummaryMaxCharacters = 800;
const int aiSessionGoalEvaluationFollowUpMaxCharacters = 1600;
const int aiSessionGoalEvaluationEvidenceMaxCharacters = 300;
const int aiSessionGoalEvaluationRawResponseMaxCharacters = 800;
const int _aiSessionGoalEvaluationEvidenceScanLimit =
    aiSessionGoalEvaluationMaxEvidenceItems * 5;
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
    final json = optionalStringKeyedMapFromValue(raw);
    if (json == null) return null;
    final id = _goalString(json['id']);
    if (id.isEmpty || id.length > aiSessionGoalReferenceIdMaxCharacters) {
      return null;
    }
    final now = DateTime.now().toUtc();
    final usageJson = optionalStringKeyedMapFromValue(json['usage']);
    return AiSessionGoalEvaluationRecord(
      id: id,
      createdAt: utcDateTimeFromValue(json['created_at']) ?? now,
      roundIndex: nonNegativeIntFromValue(json['round_index'], fallback: 0),
      passed: json['passed'] == true,
      summary: _goalString(
        json['summary'],
        maxCharacters: aiSessionGoalEvaluationSummaryMaxCharacters,
      ),
      confidence: _goalDouble(json['confidence']),
      followUpPrompt: _goalNullableString(
        json['follow_up_prompt'],
        maxCharacters: aiSessionGoalEvaluationFollowUpMaxCharacters,
      ),
      evidence: _goalStringList(json['evidence']),
      missing: _goalStringList(json['missing']),
      rawResponse: _goalNullableString(
        json['raw_response'],
        maxCharacters: aiSessionGoalEvaluationRawResponseMaxCharacters,
      ),
      providerConfigId: _goalNullableString(
        json['provider_config_id'],
        maxCharacters: aiSessionGoalModelFieldMaxCharacters,
      ),
      modelId: _goalNullableString(
        json['model_id'],
        maxCharacters: aiSessionGoalModelFieldMaxCharacters,
      ),
      modelLabel: _goalNullableString(
        json['model_label'],
        maxCharacters: aiSessionGoalModelFieldMaxCharacters,
      ),
      usage: usageJson == null ? null : AiTokenUsage.fromJson(usageJson),
      error: _goalNullableString(
        json['error'],
        maxCharacters: aiSessionGoalStatusReasonMaxCharacters,
      ),
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
      evaluations: _retainRecentGoalItems(<AiSessionGoalEvaluationRecord>[
        ...evaluations,
        evaluation,
      ], aiSessionGoalMaxEvaluationEntries),
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
    json['evaluations'] = _retainRecentGoalItems(
      evaluations,
      aiSessionGoalMaxEvaluationEntries,
    ).map((item) => item.toJson()).toList(growable: false);
    return json;
  }

  static AiSessionGoalRecord? fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValue(raw);
    if (json == null) return null;
    final id = _goalString(json['id']);
    final objective = _goalString(
      json['objective'],
      maxCharacters: aiSessionGoalObjectiveMaxCharacters,
    );
    if (id.isEmpty ||
        id.length > aiSessionGoalReferenceIdMaxCharacters ||
        objective.isEmpty) {
      return null;
    }
    final now = DateTime.now().toUtc();
    final evaluationItems = _retainRecentGoalItems(
      _goalList(json['evaluations']),
      aiSessionGoalMaxEvaluationEntries,
    );
    return AiSessionGoalRecord(
      id: id,
      objective: objective,
      status: AiSessionGoalStatus.fromStorage(json['status']),
      createdAt: utcDateTimeFromValue(json['created_at']) ?? now,
      updatedAt: utcDateTimeFromValue(json['updated_at']) ?? now,
      evaluatorProviderConfigId: _goalString(
        json['evaluator_provider_config_id'],
        maxCharacters: aiSessionGoalModelFieldMaxCharacters,
      ),
      evaluatorModelId: _goalString(
        json['evaluator_model_id'],
        maxCharacters: aiSessionGoalModelFieldMaxCharacters,
      ),
      evaluatorModelLabel: _goalString(
        json['evaluator_model_label'],
        maxCharacters: aiSessionGoalModelFieldMaxCharacters,
      ),
      maxTurns: _positiveGoalInt(json['max_turns']),
      tokenBudget: _positiveGoalInt(json['token_budget']),
      turnCount: nonNegativeIntFromValue(json['turn_count'], fallback: 0),
      tokensUsed: nonNegativeIntFromValue(json['tokens_used'], fallback: 0),
      completedAt: utcDateTimeFromValue(json['completed_at']),
      pausedAt: utcDateTimeFromValue(json['paused_at']),
      terminatedAt: utcDateTimeFromValue(json['terminated_at']),
      statusReason: _goalNullableString(
        json['status_reason'],
        maxCharacters: aiSessionGoalStatusReasonMaxCharacters,
      ),
      lastAssistantMessageId: _goalNullableString(
        json['last_assistant_message_id'],
        maxCharacters: aiSessionGoalReferenceIdMaxCharacters,
      ),
      lastAutoUserMessageId: _goalNullableString(
        json['last_auto_user_message_id'],
        maxCharacters: aiSessionGoalReferenceIdMaxCharacters,
      ),
      evaluations: evaluationItems
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
    return AiSessionGoalState(
      history: _retainRecentGoalItems(<AiSessionGoalRecord>[
        ...history,
        goal,
      ], aiSessionGoalMaxHistoryEntries),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': aiSessionGoalStateSchemaVersion,
      'current': current?.toJson(),
      'history': _retainRecentGoalItems(
        history,
        aiSessionGoalMaxHistoryEntries,
      ).map((item) => item.toJson()).toList(growable: false),
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
    final json = optionalStringKeyedMapFromValue(raw);
    if (json == null) return empty;
    final historyItems = _retainRecentGoalItems(
      _goalList(json['history']),
      aiSessionGoalMaxHistoryEntries,
    );
    return AiSessionGoalState(
      current: AiSessionGoalRecord.fromJson(json['current']),
      history: historyItems
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
    final json = optionalStringKeyedMapFromValue(raw);
    if (json == null) return null;
    final evaluatorProviderConfigId = _goalString(
      json['evaluator_provider_config_id'] ?? json['provider_config_id'],
      maxCharacters: aiSessionGoalModelFieldMaxCharacters,
    );
    final evaluatorModelId = _goalString(
      json['evaluator_model_id'] ?? json['model_id'],
      maxCharacters: aiSessionGoalModelFieldMaxCharacters,
    );
    final evaluatorModelLabel = _goalString(
      json['evaluator_model_label'] ?? json['model_label'],
      maxCharacters: aiSessionGoalModelFieldMaxCharacters,
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

List<Object?> _goalList(Object? value) {
  if (value is List<Object?>) return value;
  if (value is List) return List<Object?>.from(value);
  return const <Object?>[];
}

String _goalString(Object? value, {int? maxCharacters}) {
  if (value == null) return '';
  final text = '$value'.trim();
  if (text == 'null') return '';
  return maxCharacters == null
      ? text
      : clipTextByCodeUnits(text, maxCharacters, suffix: '…');
}

String? _goalNullableString(Object? value, {int? maxCharacters}) {
  final text = _goalString(value, maxCharacters: maxCharacters);
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
  return optionalUnitIntervalFromValue(value);
}

List<String> _goalStringList(Object? value) {
  final items = <String>[];
  for (final item in _goalList(
    value,
  ).take(_aiSessionGoalEvaluationEvidenceScanLimit)) {
    final text = _goalString(
      item,
      maxCharacters: aiSessionGoalEvaluationEvidenceMaxCharacters,
    );
    if (text.isEmpty) continue;
    items.add(text);
    if (items.length >= aiSessionGoalEvaluationMaxEvidenceItems) break;
  }
  return items.toList(growable: false);
}

List<T> _retainRecentGoalItems<T>(List<T> items, int limit) {
  final start = items.length > limit ? items.length - limit : 0;
  return List<T>.unmodifiable(items.skip(start));
}
