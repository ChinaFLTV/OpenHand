import '../../../shared/util/input_value_parsing.dart';
import 'ai_session_goal.dart';
import 'ai_session_message.dart';
import 'ai_token_usage.dart';
import 'ai_tool_call_limit_policy.dart';

int _max3(int a, int b, int c) {
  var result = a > b ? a : b;
  if (c > result) {
    result = c;
  }
  return result;
}

int _resolveMessageTotalCount(
  int? explicitCount,
  int statisticsCount,
  int loadedCount,
) {
  return _max3(explicitCount ?? 0, statisticsCount, loadedCount);
}

enum AiSessionMode {
  chat('chat'),
  plan('plan'),
  goal('goal');

  const AiSessionMode(this.storageValue);

  final String storageValue;

  static AiSessionMode fromStorage(String value) {
    return enumByStorageValueOr(
      values,
      value,
      (mode) => mode.storageValue,
      fallback: AiSessionMode.chat,
    );
  }
}

enum AiSessionMessageLoadState { complete, header, windowed }

class AiSessionTodoItem {
  const AiSessionTodoItem({
    required this.id,
    required this.content,
    required this.status,
    this.activeForm = '',
  });

  final String id;
  final String content;
  final String status;
  final String activeForm;

  AiSessionTodoItem copyWith({
    String? id,
    String? content,
    String? status,
    String? activeForm,
  }) {
    return AiSessionTodoItem(
      id: id ?? this.id,
      content: content ?? this.content,
      status: status ?? this.status,
      activeForm: activeForm ?? this.activeForm,
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'id': id,
      'content': content,
      'status': status,
    };
    putIfNotBlank(json, 'activeForm', activeForm);
    return json;
  }

  static AiSessionTodoItem fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return AiSessionTodoItem(
      id: '${json['id'] ?? ''}',
      content: '${json['content'] ?? ''}',
      status: '${json['status'] ?? ''}',
      activeForm: '${json['activeForm'] ?? json['active_form'] ?? ''}'.trim(),
    );
  }
}

abstract final class AiSessionTodoState {
  static const String pending = 'pending';
  static const String inProgress = 'in_progress';
  static const String completed = 'completed';
  static const String failed = 'failed';
  static const String blocked = 'blocked';
  static const String cancelled = 'cancelled';

  static String normalizeStatus(String value) =>
      lowercaseStringFromValue(value);

  static bool isCompletedStatus(String value) {
    return normalizeStatus(value) == completed;
  }

  static bool isIncompleteStatus(String value) {
    return !isCompletedStatus(value);
  }

  static bool isFailureStatus(String value) {
    return switch (normalizeStatus(value)) {
      failed || blocked || cancelled => true,
      _ => false,
    };
  }

  static bool hasIncomplete(Iterable<AiSessionTodoItem> todoItems) {
    return todoItems.any((item) => isIncompleteStatus(item.status));
  }

  static bool allCompleted(Iterable<AiSessionTodoItem> todoItems) {
    var sawItem = false;
    for (final item in todoItems) {
      sawItem = true;
      if (!isCompletedStatus(item.status)) {
        return false;
      }
    }
    return sawItem;
  }

  static bool hasFailure(Iterable<AiSessionTodoItem> todoItems) {
    return todoItems.any((item) => isFailureStatus(item.status));
  }
}

enum AiSessionPlanStatus {
  pendingApproval('pending_approval'),
  inProgress('in_progress'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const AiSessionPlanStatus(this.storageValue);

  final String storageValue;

  bool get isActive {
    return this == AiSessionPlanStatus.pendingApproval ||
        this == AiSessionPlanStatus.inProgress ||
        this == AiSessionPlanStatus.failed;
  }

  static AiSessionPlanStatus fromStorage(String value) {
    return enumByStorageValueOr(
      values,
      value,
      (status) => status.storageValue,
      fallback: AiSessionPlanStatus.inProgress,
    );
  }
}

class AiSessionPlanAllowedPrompt {
  const AiSessionPlanAllowedPrompt({required this.tool, required this.prompt});

  final String tool;
  final String prompt;

  Map<String, Object?> toJson() {
    return <String, Object?>{'tool': tool, 'prompt': prompt};
  }

  static AiSessionPlanAllowedPrompt? fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return null;
    final tool = stringFromValue(json['tool']).trim();
    final prompt = stringFromValue(json['prompt']).trim();
    if (tool.isEmpty || prompt.isEmpty) {
      return null;
    }
    return AiSessionPlanAllowedPrompt(tool: tool, prompt: prompt);
  }

  static List<AiSessionPlanAllowedPrompt> listFromJson(Object? rawValue) {
    return stringKeyedMapListFromValueOrJsonText(rawValue)
        .map(AiSessionPlanAllowedPrompt.fromJson)
        .whereType<AiSessionPlanAllowedPrompt>()
        .toList(growable: false);
  }
}

class AiSessionPlanRecord {
  const AiSessionPlanRecord({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.plan = '',
    this.steps = const <AiSessionTodoItem>[],
    this.allowedPrompts = const <AiSessionPlanAllowedPrompt>[],
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final AiSessionPlanStatus status;
  final String plan;
  final List<AiSessionTodoItem> steps;
  final List<AiSessionPlanAllowedPrompt> allowedPrompts;

  AiSessionPlanRecord copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    AiSessionPlanStatus? status,
    String? plan,
    List<AiSessionTodoItem>? steps,
    List<AiSessionPlanAllowedPrompt>? allowedPrompts,
  }) {
    return AiSessionPlanRecord(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      plan: plan ?? this.plan,
      steps: steps ?? this.steps,
      allowedPrompts: allowedPrompts ?? this.allowedPrompts,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'status': status.storageValue,
      'plan': plan,
      'steps': steps.map((item) => item.toJson()).toList(growable: false),
      'allowed_prompts': allowedPrompts
          .map((item) => item.toJson())
          .toList(growable: false),
    };
  }

  static AiSessionPlanRecord fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    final now = DateTime.now().toUtc();
    return AiSessionPlanRecord(
      id: '${json['id'] ?? ''}',
      createdAt: utcDateTimeFromValue(json['created_at']) ?? now,
      updatedAt: utcDateTimeFromValue(json['updated_at']) ?? now,
      status: AiSessionPlanStatus.fromStorage('${json['status'] ?? ''}'),
      plan: '${json['plan'] ?? ''}'.trim(),
      steps: stringKeyedMapListFromValueOrJsonText(
        json['steps'],
      ).map(AiSessionTodoItem.fromJson).toList(growable: false),
      allowedPrompts: AiSessionPlanAllowedPrompt.listFromJson(
        json['allowed_prompts'],
      ),
    );
  }
}

class AiSession {
  factory AiSession.fromJson(Map<String, Object?> json) {
    final sessionJson = _requireMap(json['session'], 'session');
    final messagesJson = _requireList(json['messages'], 'messages');
    final errorsJson = json['recent_errors'];
    final todoItemsJson = json['todo_items'];
    final planHistoryJson = json['plan_history'];
    final environmentJson = _requireMap(json['environment'], 'environment');
    final statisticsJson = _requireMap(json['statistics'], 'statistics');
    final now = DateTime.now().toUtc();
    final createdAt = _parseDateTime(
      sessionJson['created_at'],
      fallback: () => now,
    );
    final updatedAt = _parseDateTime(
      sessionJson['updated_at'],
      fallback: () => now,
    );
    return AiSession(
      id: '${sessionJson['id'] ?? ''}',
      title: '${sessionJson['title'] ?? ''}',
      templateId: '${sessionJson['template_id'] ?? ''}',
      templateName: '${sessionJson['template_name'] ?? ''}',
      templateIconName: '${sessionJson['template_icon_name'] ?? ''}',
      templateInternalVersion:
          '${sessionJson['template_internal_version'] ?? ''}',
      createdAt: createdAt,
      updatedAt: updatedAt,
      messages: messagesJson
          .map(
            (item) => AiSessionMessage.fromJson(_requireMap(item, 'message')),
          )
          .toList(growable: false),
      environment: AiSessionEnvironment.fromJson(environmentJson),
      statistics: AiSessionStatistics.fromJson(statisticsJson),
      recentErrors: errorsJson is List
          ? errorsJson
                .map(
                  (item) => AiSessionErrorRecord.fromJson(
                    _requireMap(item, 'recent_errors'),
                  ),
                )
                .toList(growable: false)
          : const <AiSessionErrorRecord>[],
      lastUsedModelId: _readNullableString(sessionJson['last_used_model_id']),
      lastUsedModelLabel: _readNullableString(
        sessionJson['last_used_model_label'],
      ),
      isTitleManuallyEdited: sessionJson['is_title_manually_edited'] is bool
          ? sessionJson['is_title_manually_edited'] as bool
          : false,
      autoTitleAcquired: boolFromValue(sessionJson['auto_title_acquired']),
      autoTitleRetryCount: nonNegativeIntFromValue(
        sessionJson['auto_title_retry_count'],
        fallback: 0,
      ),
      autoTitleFirstUserContent: _readNullableString(
        sessionJson['auto_title_first_user_content'],
      ),
      autoTitleGeneratedAt: _parseNullableDateTime(
        sessionJson['auto_title_generated_at'],
      ),
      autoTitleSourceMessageId: _readNullableString(
        sessionJson['auto_title_source_message_id'],
      ),
      latestCompressionCheckpointMessageId: _readNullableString(
        sessionJson['latest_compression_checkpoint_message_id'],
      ),
      latestCompressionAt: _parseNullableDateTime(
        sessionJson['latest_compression_at'],
      ),
      mode: AiSessionMode.fromStorage('${sessionJson['mode'] ?? 'chat'}'),
      awaitingPlanApproval: sessionJson['awaiting_plan_approval'] is bool
          ? sessionJson['awaiting_plan_approval'] as bool
          : false,
      pendingPlan: _readNullableString(sessionJson['pending_plan']),
      pendingPlanAllowedPrompts: AiSessionPlanAllowedPrompt.listFromJson(
        sessionJson['pending_plan_allowed_prompts'],
      ),
      fullAccessPermission: sessionJson['full_access_permission'] is bool
          ? sessionJson['full_access_permission'] as bool
          : false,
      planHistory: planHistoryJson is List
          ? planHistoryJson
                .map(
                  (item) => AiSessionPlanRecord.fromJson(
                    _requireMap(item, 'plan_history'),
                  ),
                )
                .toList(growable: false)
          : const <AiSessionPlanRecord>[],
      metadata: Map<String, Object?>.of(
        stringKeyedMapFromValue(json['metadata']),
      ),
      lastPromptMetadata: Map<String, Object?>.of(
        stringKeyedMapFromValue(json['last_prompt_metadata']),
      ),
      todoItems: todoItemsJson is List
          ? todoItemsJson
                .map(
                  (item) => AiSessionTodoItem.fromJson(
                    _requireMap(item, 'todo_items'),
                  ),
                )
                .toList(growable: false)
          : const <AiSessionTodoItem>[],
      messageLoadState: AiSessionMessageLoadState.complete,
      messageWindowStartIndex: 0,
      messageTotalCount: messagesJson.length,
    );
  }
  AiSession({
    required this.id,
    required this.title,
    required this.templateId,
    required this.templateName,
    required this.templateIconName,
    required this.templateInternalVersion,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    required this.environment,
    required this.statistics,
    required this.recentErrors,
    this.lastUsedModelId,
    this.lastUsedModelLabel,
    this.isTitleManuallyEdited = false,
    this.autoTitleAcquired = false,
    this.autoTitleRetryCount = 0,
    this.autoTitleFirstUserContent,
    this.autoTitleGeneratedAt,
    this.autoTitleSourceMessageId,
    this.latestCompressionCheckpointMessageId,
    this.latestCompressionAt,
    this.lastPromptMetadata = const <String, Object?>{},
    this.todoItems = const <AiSessionTodoItem>[],
    this.mode = AiSessionMode.chat,
    this.awaitingPlanApproval = false,
    this.pendingPlan,
    this.pendingPlanAllowedPrompts = const <AiSessionPlanAllowedPrompt>[],
    this.planHistory = const <AiSessionPlanRecord>[],
    this.fullAccessPermission = false,
    this.metadata = const <String, Object?>{},
    AiSessionMessageLoadState? messageLoadState,
    int? messageWindowStartIndex,
    int? messageTotalCount,
  }) : messageLoadState =
           messageLoadState ??
           (messages.isEmpty && statistics.totalMessageCount > 0
               ? AiSessionMessageLoadState.header
               : AiSessionMessageLoadState.complete),
       messageWindowStartIndex = nonNegativeIntFromValue(
         messageWindowStartIndex,
         fallback: 0,
       ),
       messageTotalCount = _resolveMessageTotalCount(
         messageTotalCount,
         statistics.totalMessageCount,
         messages.length,
       );

  static const int schemaVersion = 6;

  final String id;
  final String title;
  final String templateId;
  final String templateName;
  final String templateIconName;
  final String templateInternalVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AiSessionMessage> messages;
  final AiSessionEnvironment environment;
  final AiSessionStatistics statistics;
  final List<AiSessionErrorRecord> recentErrors;
  final String? lastUsedModelId;
  final String? lastUsedModelLabel;
  final bool isTitleManuallyEdited;

  /// 是否已成功获取过 AI 生成的线程标题。false 表示标题仍为回退值，
  /// 下次打开会话时应尝试重新请求总结标题。
  final bool autoTitleAcquired;

  /// 已尝试重新获取标题的次数。超过全局设置中的最大重试次数后不再重试。
  final int autoTitleRetryCount;

  /// 首条用户消息的文本内容快照，用于重试时携带给标题总结接口。
  final String? autoTitleFirstUserContent;

  final DateTime? autoTitleGeneratedAt;
  final String? autoTitleSourceMessageId;
  final String? latestCompressionCheckpointMessageId;
  final DateTime? latestCompressionAt;
  final Map<String, Object?> lastPromptMetadata;
  final List<AiSessionTodoItem> todoItems;
  final AiSessionMode mode;
  final bool awaitingPlanApproval;
  final String? pendingPlan;
  final List<AiSessionPlanAllowedPrompt> pendingPlanAllowedPrompts;
  final List<AiSessionPlanRecord> planHistory;
  final bool fullAccessPermission;
  final Map<String, Object?> metadata;
  final AiSessionMessageLoadState messageLoadState;
  final int messageWindowStartIndex;
  final int messageTotalCount;
  late final int? _latestCompressionPointIndexCache =
      _computeLatestCompressionPointIndex();
  late final List<AiSessionMessage> _visibleMessagesCache = messages
      .where((item) => item.isVisible)
      .toList(growable: false);
  late final List<AiSessionMessage> _displayMessagesCache =
      _computeDisplayMessages();

  AiSession copyWith({
    String? title,
    String? templateName,
    String? templateIconName,
    String? templateInternalVersion,
    DateTime? updatedAt,
    List<AiSessionMessage>? messages,
    AiSessionEnvironment? environment,
    AiSessionStatistics? statistics,
    List<AiSessionErrorRecord>? recentErrors,
    String? lastUsedModelId,
    String? lastUsedModelLabel,
    bool? isTitleManuallyEdited,
    bool? autoTitleAcquired,
    int? autoTitleRetryCount,
    String? autoTitleFirstUserContent,
    bool clearAutoTitleFirstUserContent = false,
    DateTime? autoTitleGeneratedAt,
    String? autoTitleSourceMessageId,
    String? latestCompressionCheckpointMessageId,
    DateTime? latestCompressionAt,
    bool clearLatestCompressionAt = false,
    Map<String, Object?>? lastPromptMetadata,
    List<AiSessionTodoItem>? todoItems,
    AiSessionMode? mode,
    bool? awaitingPlanApproval,
    String? pendingPlan,
    List<AiSessionPlanAllowedPrompt>? pendingPlanAllowedPrompts,
    List<AiSessionPlanRecord>? planHistory,
    bool clearPendingPlan = false,
    bool? fullAccessPermission,
    Map<String, Object?>? metadata,
    AiSessionMessageLoadState? messageLoadState,
    int? messageWindowStartIndex,
    int? messageTotalCount,
  }) {
    final nextMessages = messages ?? this.messages;
    final nextStatistics = statistics ?? this.statistics;
    final nextLoadState =
        messageLoadState ??
        (messages == null
            ? this.messageLoadState
            : AiSessionMessageLoadState.complete);
    final nextWindowStartIndex =
        messageWindowStartIndex ??
        switch (nextLoadState) {
          AiSessionMessageLoadState.complete ||
          AiSessionMessageLoadState.header => 0,
          AiSessionMessageLoadState.windowed => this.messageWindowStartIndex,
        };
    final nextTotalCount =
        messageTotalCount ??
        switch (nextLoadState) {
          AiSessionMessageLoadState.complete => nextMessages.length,
          AiSessionMessageLoadState.header => nextStatistics.totalMessageCount,
          AiSessionMessageLoadState.windowed => _max3(
            this.messageTotalCount,
            nextStatistics.totalMessageCount,
            nextWindowStartIndex + nextMessages.length,
          ),
        };
    return AiSession(
      id: id,
      title: title ?? this.title,
      templateId: templateId,
      templateName: templateName ?? this.templateName,
      templateIconName: templateIconName ?? this.templateIconName,
      templateInternalVersion:
          templateInternalVersion ?? this.templateInternalVersion,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      environment: environment ?? this.environment,
      statistics: statistics ?? this.statistics,
      recentErrors: recentErrors ?? this.recentErrors,
      lastUsedModelId: lastUsedModelId ?? this.lastUsedModelId,
      lastUsedModelLabel: lastUsedModelLabel ?? this.lastUsedModelLabel,
      isTitleManuallyEdited:
          isTitleManuallyEdited ?? this.isTitleManuallyEdited,
      autoTitleAcquired: autoTitleAcquired ?? this.autoTitleAcquired,
      autoTitleRetryCount: autoTitleRetryCount ?? this.autoTitleRetryCount,
      autoTitleFirstUserContent: clearAutoTitleFirstUserContent
          ? null
          : autoTitleFirstUserContent ?? this.autoTitleFirstUserContent,
      autoTitleGeneratedAt: autoTitleGeneratedAt ?? this.autoTitleGeneratedAt,
      autoTitleSourceMessageId:
          autoTitleSourceMessageId ?? this.autoTitleSourceMessageId,
      latestCompressionCheckpointMessageId:
          latestCompressionCheckpointMessageId ??
          this.latestCompressionCheckpointMessageId,
      latestCompressionAt: clearLatestCompressionAt
          ? null
          : latestCompressionAt ?? this.latestCompressionAt,
      lastPromptMetadata: lastPromptMetadata ?? this.lastPromptMetadata,
      todoItems: todoItems ?? this.todoItems,
      mode: mode ?? this.mode,
      awaitingPlanApproval: awaitingPlanApproval ?? this.awaitingPlanApproval,
      pendingPlan: clearPendingPlan ? null : pendingPlan ?? this.pendingPlan,
      pendingPlanAllowedPrompts: clearPendingPlan
          ? const <AiSessionPlanAllowedPrompt>[]
          : pendingPlanAllowedPrompts ?? this.pendingPlanAllowedPrompts,
      planHistory: planHistory ?? this.planHistory,
      fullAccessPermission: fullAccessPermission ?? this.fullAccessPermission,
      metadata: metadata ?? this.metadata,
      messageLoadState: nextLoadState,
      messageWindowStartIndex: nextWindowStartIndex,
      messageTotalCount: nextTotalCount,
    );
  }

  bool get hasCompleteMessages =>
      messageLoadState == AiSessionMessageLoadState.complete;

  bool get hasPartialMessages => !hasCompleteMessages;

  bool get hasLoadedMessages => messages.isNotEmpty;

  bool get hasMoreHistoricalMessages {
    return messageLoadState == AiSessionMessageLoadState.header ||
        (messageLoadState == AiSessionMessageLoadState.windowed &&
            messageWindowStartIndex > 0);
  }

  int get hiddenHistoricalMessageCount {
    if (messageLoadState == AiSessionMessageLoadState.complete) {
      return 0;
    }
    if (messageLoadState == AiSessionMessageLoadState.header) {
      return messageTotalCount;
    }
    return messageWindowStartIndex;
  }

  AiSessionMessage? get latestCompressionPoint {
    final index = latestCompressionPointIndex;
    // Guard against stale cache or concurrent modification.
    if (index == null || index < 0 || index >= messages.length) {
      return null;
    }
    return messages[index];
  }

  int? get latestCompressionPointIndex {
    return _latestCompressionPointIndexCache;
  }

  List<AiSessionMessage> get visibleMessages {
    return _visibleMessagesCache;
  }

  List<AiSessionMessage> get displayMessages {
    return _displayMessagesCache;
  }

  AiSessionPlanRecord? get latestPlanRecord {
    if (planHistory.isEmpty) {
      return null;
    }
    return planHistory.last;
  }

  AiSessionPlanRecord? get latestActivePlanRecord {
    for (var index = planHistory.length - 1; index >= 0; index -= 1) {
      final planRecord = planHistory[index];
      if (planRecord.status.isActive) {
        return planRecord;
      }
    }
    return null;
  }

  AiSessionGoalState get goalState => AiSessionGoalState.fromMetadata(metadata);

  AiSessionGoalRecord? get activeGoal => goalState.current;

  bool get hasActiveGoal => activeGoal?.isActive == true;

  List<AiSessionMessage> get activeConversationMessages {
    final latestCompressionPointIndex = this.latestCompressionPointIndex;
    if (latestCompressionPointIndex == null) {
      return messages
          .where((item) => item.isConversationTurn)
          .toList(growable: false);
    }
    return messages
        .skip(latestCompressionPointIndex + 1)
        .where((item) => item.isConversationTurn)
        .toList(growable: false);
  }

  /// Same slice as [activeConversationMessages] but additionally retains
  /// `reasoning` messages so the prompt builder can echo prior chain-of-
  /// thought back to thinking-mode gateways (e.g. `deepseek-v4-pro`) which
  /// require `reasoning_content` to be passed back on follow-up requests.
  List<AiSessionMessage> get activeConversationMessagesForPrompt {
    final latestCompressionPointIndex = this.latestCompressionPointIndex;
    bool keep(AiSessionMessage item) {
      if (item.isDeleted) {
        return false;
      }
      return item.isConversationTurn ||
          item.kind == AiSessionMessageKind.reasoning;
    }

    if (latestCompressionPointIndex == null) {
      return messages.where(keep).toList(growable: false);
    }
    return messages
        .skip(latestCompressionPointIndex + 1)
        .where(keep)
        .toList(growable: false);
  }

  int? _computeLatestCompressionPointIndex() {
    for (var index = messages.length - 1; index >= 0; index--) {
      if (!messages[index].isDeleted &&
          messages[index].kind == AiSessionMessageKind.compressionPoint) {
        return index;
      }
    }
    return null;
  }

  List<AiSessionMessage> _computeDisplayMessages() {
    final toolCallIds = <String>{};
    for (final message in messages) {
      if (!message.isTranscriptRenderable) continue;
      if (message.kind != AiSessionMessageKind.toolCall) continue;
      final toolCallId = '${message.metadata['tool_call_id'] ?? ''}'.trim();
      if (toolCallId.isNotEmpty) {
        toolCallIds.add(toolCallId);
      }
    }
    final displayMessages = <AiSessionMessage>[];
    for (final message in messages) {
      if (!message.isTranscriptRenderable) continue;
      if (message.metadata['plan_mode_approved'] == true) {
        continue;
      }
      if (message.kind != AiSessionMessageKind.tool &&
          message.kind != AiSessionMessageKind.mcp &&
          message.kind != AiSessionMessageKind.skill &&
          message.kind != AiSessionMessageKind.hook) {
        displayMessages.add(message);
        continue;
      }
      final toolCallId = '${message.metadata['tool_call_id'] ?? ''}'.trim();
      if (toolCallId.isEmpty || !toolCallIds.contains(toolCallId)) {
        displayMessages.add(message);
      }
    }
    return List<AiSessionMessage>.unmodifiable(displayMessages);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': schemaVersion,
      'session': <String, Object?>{
        'id': id,
        'title': title,
        'template_id': templateId,
        'template_name': templateName,
        'template_icon_name': templateIconName,
        'template_internal_version': templateInternalVersion,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'last_used_model_id': lastUsedModelId,
        'last_used_model_label': lastUsedModelLabel,
        'is_title_manually_edited': isTitleManuallyEdited,
        'auto_title_acquired': autoTitleAcquired,
        'auto_title_retry_count': autoTitleRetryCount,
        'auto_title_first_user_content': autoTitleFirstUserContent,
        'auto_title_generated_at': autoTitleGeneratedAt
            ?.toUtc()
            .toIso8601String(),
        'auto_title_source_message_id': autoTitleSourceMessageId,
        'latest_compression_checkpoint_message_id':
            latestCompressionCheckpointMessageId,
        'latest_compression_at': latestCompressionAt?.toUtc().toIso8601String(),
        'mode': mode.storageValue,
        'awaiting_plan_approval': awaitingPlanApproval,
        'pending_plan': pendingPlan,
        'pending_plan_allowed_prompts': pendingPlanAllowedPrompts
            .map((item) => item.toJson())
            .toList(growable: false),
        'full_access_permission': fullAccessPermission,
      },
      'metadata': metadata,
      'environment': environment.toJson(),
      'statistics': statistics.toJson(),
      'last_prompt_metadata': lastPromptMetadata,
      'plan_history': planHistory
          .map((item) => item.toJson())
          .toList(growable: false),
      'todo_items': todoItems
          .map((item) => item.toJson())
          .toList(growable: false),
      'messages': messages.map((item) => item.toJson()).toList(growable: false),
      'recent_errors': recentErrors
          .map((item) => item.toJson())
          .toList(growable: false),
    };
  }

  static Map<String, Object?> _requireMap(Object? value, String label) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return stringKeyedMapFromValue(value);
    }
    throw FormatException('Invalid $label payload.');
  }

  static List<Object?> _requireList(Object? value, String label) {
    if (value is List<Object?>) {
      return value;
    }
    if (value is List) {
      return List<Object?>.from(value);
    }
    throw FormatException('Invalid $label payload.');
  }

  static String? _readNullableString(Object? value) {
    if (value == null) {
      return null;
    }
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  static DateTime _parseDateTime(
    Object? value, {
    required DateTime Function() fallback,
  }) {
    return utcDateTimeFromValue(value) ?? fallback();
  }

  static DateTime? _parseNullableDateTime(Object? value) {
    return utcDateTimeFromValue(value);
  }
}

class AiSessionEnvironment {
  factory AiSessionEnvironment.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return AiSessionEnvironment(
      localeTag: stringFromValue(json['locale_tag']),
      platform: stringFromValue(json['platform']),
      appVersion: stringFromValue(json['app_version']),
      appBuildNumber: stringFromValue(json['app_build_number']),
      applicationDirectory: stringFromValue(json['application_directory']),
      homeDirectory: stringFromValue(json['home_directory']),
      settingsFilePath: stringFromValue(json['settings_file_path']),
      skillsStoragePath: stringFromValue(json['skills_storage_path']),
      mcpServersFilePath: stringFromValue(json['mcp_servers_file_path']),
      userMemoryFilePath: stringFromValue(json['user_memory_file_path']),
      sessionsDirectoryPath: stringFromValue(json['sessions_directory_path']),
      compressionThresholdChars: nonNegativeIntFromValue(
        json['compression_threshold_chars'],
        fallback: 0,
      ),
      singleRoundToolCallLimit: singleRoundToolCallLimitFromValue(
        json['single_round_tool_call_limit'],
      ),
      sequentialToolRoundLimit: sequentialToolRoundLimitFromValue(
        json['sequential_tool_round_limit'],
      ),
    );
  }
  AiSessionEnvironment({
    required this.localeTag,
    required this.platform,
    required this.appVersion,
    required this.appBuildNumber,
    required this.applicationDirectory,
    required this.homeDirectory,
    required this.settingsFilePath,
    required this.skillsStoragePath,
    required this.mcpServersFilePath,
    required this.userMemoryFilePath,
    required this.sessionsDirectoryPath,
    required this.compressionThresholdChars,
    int singleRoundToolCallLimit = defaultSingleRoundToolCallLimit,
    int sequentialToolRoundLimit = defaultSequentialToolRoundLimit,
  }) : singleRoundToolCallLimit = normalizeSingleRoundToolCallLimit(
         singleRoundToolCallLimit,
       ),
       sequentialToolRoundLimit = normalizeSequentialToolRoundLimit(
         sequentialToolRoundLimit,
       );

  static const int defaultSingleRoundToolCallLimit =
      AiToolCallLimitPolicy.defaultSingleRoundToolCallLimit;
  static const int minSingleRoundToolCallLimit =
      AiToolCallLimitPolicy.minSingleRoundToolCallLimit;
  static const int maxSingleRoundToolCallLimit =
      AiToolCallLimitPolicy.maxSingleRoundToolCallLimit;
  static const int defaultSequentialToolRoundLimit =
      AiToolCallLimitPolicy.defaultSequentialToolRoundLimit;
  static const int minSequentialToolRoundLimit =
      AiToolCallLimitPolicy.minSequentialToolRoundLimit;
  static const int maxSequentialToolRoundLimit =
      AiToolCallLimitPolicy.maxSequentialToolRoundLimit;

  static int singleRoundToolCallLimitFromValue(Object? value) {
    return AiToolCallLimitPolicy.singleRoundFromValue(value);
  }

  static int normalizeSingleRoundToolCallLimit(int value) {
    return AiToolCallLimitPolicy.normalizeSingleRound(value);
  }

  static int sequentialToolRoundLimitFromValue(Object? value) {
    return AiToolCallLimitPolicy.sequentialRoundFromValue(value);
  }

  static int normalizeSequentialToolRoundLimit(int value) {
    return AiToolCallLimitPolicy.normalizeSequentialRound(value);
  }

  final String localeTag;
  final String platform;
  final String appVersion;
  final String appBuildNumber;
  final String applicationDirectory;
  final String homeDirectory;
  final String settingsFilePath;
  final String skillsStoragePath;
  final String mcpServersFilePath;
  final String userMemoryFilePath;
  final String sessionsDirectoryPath;
  final int compressionThresholdChars;
  final int singleRoundToolCallLimit;
  final int sequentialToolRoundLimit;

  AiSessionEnvironment copyWith({
    String? localeTag,
    String? platform,
    String? appVersion,
    String? appBuildNumber,
    String? applicationDirectory,
    String? homeDirectory,
    String? settingsFilePath,
    String? skillsStoragePath,
    String? mcpServersFilePath,
    String? userMemoryFilePath,
    String? sessionsDirectoryPath,
    int? compressionThresholdChars,
    int? singleRoundToolCallLimit,
    int? sequentialToolRoundLimit,
  }) {
    return AiSessionEnvironment(
      localeTag: localeTag ?? this.localeTag,
      platform: platform ?? this.platform,
      appVersion: appVersion ?? this.appVersion,
      appBuildNumber: appBuildNumber ?? this.appBuildNumber,
      applicationDirectory: applicationDirectory ?? this.applicationDirectory,
      homeDirectory: homeDirectory ?? this.homeDirectory,
      settingsFilePath: settingsFilePath ?? this.settingsFilePath,
      skillsStoragePath: skillsStoragePath ?? this.skillsStoragePath,
      mcpServersFilePath: mcpServersFilePath ?? this.mcpServersFilePath,
      userMemoryFilePath: userMemoryFilePath ?? this.userMemoryFilePath,
      sessionsDirectoryPath:
          sessionsDirectoryPath ?? this.sessionsDirectoryPath,
      compressionThresholdChars:
          compressionThresholdChars ?? this.compressionThresholdChars,
      singleRoundToolCallLimit:
          singleRoundToolCallLimit ?? this.singleRoundToolCallLimit,
      sequentialToolRoundLimit:
          sequentialToolRoundLimit ?? this.sequentialToolRoundLimit,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'locale_tag': localeTag,
      'platform': platform,
      'app_version': appVersion,
      'app_build_number': appBuildNumber,
      'application_directory': applicationDirectory,
      'home_directory': homeDirectory,
      'settings_file_path': settingsFilePath,
      'skills_storage_path': skillsStoragePath,
      'mcp_servers_file_path': mcpServersFilePath,
      'user_memory_file_path': userMemoryFilePath,
      'sessions_directory_path': sessionsDirectoryPath,
      'compression_threshold_chars': compressionThresholdChars,
      'single_round_tool_call_limit': normalizeSingleRoundToolCallLimit(
        singleRoundToolCallLimit,
      ),
      'sequential_tool_round_limit': normalizeSequentialToolRoundLimit(
        sequentialToolRoundLimit,
      ),
    };
  }
}

class AiSessionStatistics {
  factory AiSessionStatistics.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    final cacheCreationTokens = _readNullableInt(json['cache_creation_tokens']);
    final cacheReadTokens = _readNullableInt(json['cache_read_tokens']);
    final hasCacheUsageTelemetry =
        cacheCreationTokens != null || cacheReadTokens != null;
    final cacheHitTrendPoints = hasCacheUsageTelemetry
        ? _readTrendPoints(json['cache_hit_trend_points'])
        : const <AiSessionCacheHitTrendPoint>[];
    final parsedCacheHitRatio = hasCacheUsageTelemetry
        ? _readNullableDouble(json['cache_hit_ratio'])
        : null;
    final cacheHitRatio =
        (cacheReadTokens ?? 0) > 0 &&
            (parsedCacheHitRatio ?? 0) <= 0 &&
            cacheHitTrendPoints.isNotEmpty
        ? null
        : parsedCacheHitRatio;
    return AiSessionStatistics(
      totalMessageCount: _readInt(json['total_message_count']),
      userMessageCount: _readInt(json['user_message_count']),
      assistantMessageCount: _readInt(json['assistant_message_count']),
      toolMessageCount: _readInt(json['tool_message_count']),
      mcpMessageCount: _readInt(json['mcp_message_count']),
      skillMessageCount: _readInt(json['skill_message_count']),
      compressionPointCount: _readInt(json['compression_point_count']),
      totalInputCharacters: _readInt(json['total_input_characters']),
      totalOutputCharacters: _readInt(json['total_output_characters']),
      totalPromptCharacters: _readInt(json['total_prompt_characters']),
      promptBuildCount: _readInt(json['prompt_build_count']),
      compressionRunCount: _readInt(json['compression_run_count']),
      totalPromptTokens: _readNullableInt(json['total_prompt_tokens']),
      totalCompletionTokens: _readNullableInt(json['total_completion_tokens']),
      totalTokens: _readNullableInt(json['total_tokens']),
      cacheCreationTokens: cacheCreationTokens,
      cacheReadTokens: cacheReadTokens,
      reasoningTokens: _readNullableInt(json['reasoning_tokens']),
      firstPromptTokens: _readNullableInt(json['first_prompt_tokens']),
      lastPromptSystemMessageCount: _readInt(
        json['last_prompt_system_message_count'],
      ),
      lastPromptHistoryMessageCount: _readInt(
        json['last_prompt_history_message_count'],
      ),
      cacheHitRatio: cacheHitRatio,
      cacheHitTrendPoints: cacheHitTrendPoints,
      cacheHitTrendExcludedCount: hasCacheUsageTelemetry
          ? _readInt(json['cache_hit_trend_excluded_count'])
          : 0,
    );
  }
  const AiSessionStatistics({
    required this.totalMessageCount,
    required this.userMessageCount,
    required this.assistantMessageCount,
    required this.toolMessageCount,
    required this.mcpMessageCount,
    required this.skillMessageCount,
    required this.compressionPointCount,
    required this.totalInputCharacters,
    required this.totalOutputCharacters,
    required this.totalPromptCharacters,
    required this.promptBuildCount,
    required this.compressionRunCount,
    this.totalPromptTokens,
    this.totalCompletionTokens,
    this.totalTokens,
    this.cacheCreationTokens,
    this.cacheReadTokens,
    this.reasoningTokens,
    this.firstPromptTokens,
    this.lastPromptSystemMessageCount = 0,
    this.lastPromptHistoryMessageCount = 0,
    this.cacheHitRatio,
    this.cacheHitTrendPoints = const <AiSessionCacheHitTrendPoint>[],
    this.cacheHitTrendExcludedCount = 0,
  });

  const AiSessionStatistics.initial()
    : totalMessageCount = 0,
      userMessageCount = 0,
      assistantMessageCount = 0,
      toolMessageCount = 0,
      mcpMessageCount = 0,
      skillMessageCount = 0,
      compressionPointCount = 0,
      totalInputCharacters = 0,
      totalOutputCharacters = 0,
      totalPromptCharacters = 0,
      promptBuildCount = 0,
      compressionRunCount = 0,
      totalPromptTokens = null,
      totalCompletionTokens = null,
      totalTokens = null,
      cacheCreationTokens = null,
      cacheReadTokens = null,
      reasoningTokens = null,
      firstPromptTokens = null,
      lastPromptSystemMessageCount = 0,
      lastPromptHistoryMessageCount = 0,
      cacheHitRatio = null,
      cacheHitTrendPoints = const <AiSessionCacheHitTrendPoint>[],
      cacheHitTrendExcludedCount = 0;

  final int totalMessageCount;
  final int userMessageCount;
  final int assistantMessageCount;
  final int toolMessageCount;
  final int mcpMessageCount;
  final int skillMessageCount;
  final int compressionPointCount;
  final int totalInputCharacters;
  final int totalOutputCharacters;
  final int totalPromptCharacters;
  final int promptBuildCount;
  final int compressionRunCount;
  final int? totalPromptTokens;
  final int? totalCompletionTokens;
  final int? totalTokens;
  final int? cacheCreationTokens;
  final int? cacheReadTokens;
  final int? reasoningTokens;

  /// 第一轮 prompt 的 token 数，用于排除首轮计算缓存命中率。
  /// 首轮必然 cache miss（此前无上下文可缓存），将其计入分母会拉低真实命中率。
  final int? firstPromptTokens;
  final int lastPromptSystemMessageCount;
  final int lastPromptHistoryMessageCount;

  /// 2026-06-08 — 后端预计算的缓存命中率（已排除极端空闲过期 miss + 首轮
  /// 必然 miss），供 WEB 端、TopBar 胶囊、浮窗统一读取，避免跨端计算口径
  /// 漂移。范围 0.0..1.0。无任何 token 数据时为 null。
  final double? cacheHitRatio;

  /// 2026-06-08 — 后端预计算的逐轮次趋势点。轮次从非 AI 侧消息开始：
  /// 显式用户消息或 OpenHand 后台写入的工具结果。WEB 端不再独立 walk
  /// messages 重算，直接消费。
  final List<AiSessionCacheHitTrendPoint> cacheHitTrendPoints;

  /// 2026-06-08 — 被「排除极端值」模式过滤掉的轮次数（idle_gap>=30min 且
  /// hit_ratio<1%），用于浮窗内展示「已排除 N 轮」提示。
  final int cacheHitTrendExcludedCount;

  AiSessionStatistics copyWith({
    int? totalMessageCount,
    int? userMessageCount,
    int? assistantMessageCount,
    int? toolMessageCount,
    int? mcpMessageCount,
    int? skillMessageCount,
    int? compressionPointCount,
    int? totalInputCharacters,
    int? totalOutputCharacters,
    int? totalPromptCharacters,
    int? promptBuildCount,
    int? compressionRunCount,
    int? totalPromptTokens,
    int? totalCompletionTokens,
    int? totalTokens,
    int? cacheCreationTokens,
    int? cacheReadTokens,
    int? reasoningTokens,
    int? firstPromptTokens,
    int? lastPromptSystemMessageCount,
    int? lastPromptHistoryMessageCount,
    double? cacheHitRatio,
    List<AiSessionCacheHitTrendPoint>? cacheHitTrendPoints,
    int? cacheHitTrendExcludedCount,
  }) {
    return AiSessionStatistics(
      totalMessageCount: totalMessageCount ?? this.totalMessageCount,
      userMessageCount: userMessageCount ?? this.userMessageCount,
      assistantMessageCount:
          assistantMessageCount ?? this.assistantMessageCount,
      toolMessageCount: toolMessageCount ?? this.toolMessageCount,
      mcpMessageCount: mcpMessageCount ?? this.mcpMessageCount,
      skillMessageCount: skillMessageCount ?? this.skillMessageCount,
      compressionPointCount:
          compressionPointCount ?? this.compressionPointCount,
      totalInputCharacters: totalInputCharacters ?? this.totalInputCharacters,
      totalOutputCharacters:
          totalOutputCharacters ?? this.totalOutputCharacters,
      totalPromptCharacters:
          totalPromptCharacters ?? this.totalPromptCharacters,
      promptBuildCount: promptBuildCount ?? this.promptBuildCount,
      compressionRunCount: compressionRunCount ?? this.compressionRunCount,
      totalPromptTokens: totalPromptTokens ?? this.totalPromptTokens,
      totalCompletionTokens:
          totalCompletionTokens ?? this.totalCompletionTokens,
      totalTokens: totalTokens ?? this.totalTokens,
      cacheCreationTokens: cacheCreationTokens ?? this.cacheCreationTokens,
      cacheReadTokens: cacheReadTokens ?? this.cacheReadTokens,
      reasoningTokens: reasoningTokens ?? this.reasoningTokens,
      firstPromptTokens: firstPromptTokens ?? this.firstPromptTokens,
      lastPromptSystemMessageCount:
          lastPromptSystemMessageCount ?? this.lastPromptSystemMessageCount,
      lastPromptHistoryMessageCount:
          lastPromptHistoryMessageCount ?? this.lastPromptHistoryMessageCount,
      cacheHitRatio: cacheHitRatio ?? this.cacheHitRatio,
      cacheHitTrendPoints: cacheHitTrendPoints ?? this.cacheHitTrendPoints,
      cacheHitTrendExcludedCount:
          cacheHitTrendExcludedCount ?? this.cacheHitTrendExcludedCount,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'total_message_count': totalMessageCount,
      'user_message_count': userMessageCount,
      'assistant_message_count': assistantMessageCount,
      'tool_message_count': toolMessageCount,
      'mcp_message_count': mcpMessageCount,
      'skill_message_count': skillMessageCount,
      'compression_point_count': compressionPointCount,
      'total_input_characters': totalInputCharacters,
      'total_output_characters': totalOutputCharacters,
      'total_prompt_characters': totalPromptCharacters,
      'prompt_build_count': promptBuildCount,
      'compression_run_count': compressionRunCount,
      'total_prompt_tokens': totalPromptTokens,
      'total_completion_tokens': totalCompletionTokens,
      'total_tokens': totalTokens,
      'cache_creation_tokens': cacheCreationTokens,
      'cache_read_tokens': cacheReadTokens,
      'reasoning_tokens': reasoningTokens,
      'first_prompt_tokens': firstPromptTokens,
      'last_prompt_system_message_count': lastPromptSystemMessageCount,
      'last_prompt_history_message_count': lastPromptHistoryMessageCount,
      'cache_hit_ratio': cacheHitRatio,
      'cache_hit_trend_points': cacheHitTrendPoints
          .map((p) => p.toJson())
          .toList(growable: false),
      'cache_hit_trend_excluded_count': cacheHitTrendExcludedCount,
    };
  }

  static AiSessionStatistics fromMessages(
    List<AiSessionMessage> messages, {
    required int totalPromptCharacters,
    required int promptBuildCount,
    required int compressionRunCount,
    required AiTokenUsage totalUsage,
    int? firstPromptTokens,
    required int lastPromptSystemMessageCount,
    required int lastPromptHistoryMessageCount,
    double? cacheHitRatio,
    List<AiSessionCacheHitTrendPoint> cacheHitTrendPoints =
        const <AiSessionCacheHitTrendPoint>[],
    int cacheHitTrendExcludedCount = 0,
  }) {
    final visibleMessages = messages
        .where((message) => !message.isDeleted)
        .toList(growable: false);
    var userMessageCount = 0;
    var assistantMessageCount = 0;
    var toolMessageCount = 0;
    var mcpMessageCount = 0;
    var skillMessageCount = 0;
    var compressionPointCount = 0;
    var totalInputCharacters = 0;
    var totalOutputCharacters = 0;

    for (final message in visibleMessages) {
      switch (message.kind) {
        case AiSessionMessageKind.user:
          userMessageCount += 1;
          totalInputCharacters += message.characterCount;
        case AiSessionMessageKind.assistant:
          assistantMessageCount += 1;
          totalOutputCharacters += message.characterCount;
        case AiSessionMessageKind.reasoning:
          totalOutputCharacters += message.characterCount;
        case AiSessionMessageKind.toolCall:
          toolMessageCount += 1;
          totalOutputCharacters += message.characterCount;
        case AiSessionMessageKind.tool:
          toolMessageCount += 1;
          totalOutputCharacters += message.characterCount;
        case AiSessionMessageKind.mcp:
          mcpMessageCount += 1;
          totalOutputCharacters += message.characterCount;
        case AiSessionMessageKind.skill:
          skillMessageCount += 1;
          totalOutputCharacters += message.characterCount;
        case AiSessionMessageKind.hook:
          skillMessageCount += 1;
          totalOutputCharacters += message.characterCount;
        case AiSessionMessageKind.compressionPoint:
          compressionPointCount += 1;
        case AiSessionMessageKind.selfLearning:
          totalOutputCharacters += message.characterCount;
        case AiSessionMessageKind.fileMutationSummary:
          totalOutputCharacters += message.characterCount;
        case AiSessionMessageKind.status:
          totalOutputCharacters += message.characterCount;
      }
    }

    return AiSessionStatistics(
      totalMessageCount: visibleMessages.length,
      userMessageCount: userMessageCount,
      assistantMessageCount: assistantMessageCount,
      toolMessageCount: toolMessageCount,
      mcpMessageCount: mcpMessageCount,
      skillMessageCount: skillMessageCount,
      compressionPointCount: compressionPointCount,
      totalInputCharacters: totalInputCharacters,
      totalOutputCharacters: totalOutputCharacters,
      totalPromptCharacters: totalPromptCharacters,
      promptBuildCount: promptBuildCount,
      compressionRunCount: compressionRunCount,
      totalPromptTokens: totalUsage.promptTokens,
      totalCompletionTokens: totalUsage.completionTokens,
      totalTokens: totalUsage.totalTokens,
      cacheCreationTokens: totalUsage.cacheCreationTokens,
      cacheReadTokens: totalUsage.cacheReadTokens,
      reasoningTokens: totalUsage.reasoningTokens,
      firstPromptTokens: firstPromptTokens,
      lastPromptSystemMessageCount: lastPromptSystemMessageCount,
      lastPromptHistoryMessageCount: lastPromptHistoryMessageCount,
      cacheHitRatio: cacheHitRatio,
      cacheHitTrendPoints: cacheHitTrendPoints,
      cacheHitTrendExcludedCount: cacheHitTrendExcludedCount,
    );
  }

  static int _readInt(Object? value) {
    return _readNullableInt(value) ?? 0;
  }

  static int? _readNullableInt(Object? value) {
    return optionalNonNegativeIntegralIntFromValue(value);
  }

  static double? _readNullableDouble(Object? value) {
    return optionalUnitIntervalFromValue(value);
  }

  static List<AiSessionCacheHitTrendPoint> _readTrendPoints(Object? value) {
    return stringKeyedMapListFromValueOrJsonText(
      value,
    ).map(AiSessionCacheHitTrendPoint.fromJson).toList(growable: false);
  }
}

/// 2026-06-08 — 后端预计算的逐轮次缓存命中点（直接从
/// [SessionCacheHitTurnPoint] 映射）。WEB 端只读消费。
class AiSessionCacheHitTrendPoint {
  const AiSessionCacheHitTrendPoint({
    required this.turnIndex,
    required this.hitRatio,
    required this.promptTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    this.starterMessageId,
    this.starterMessageKind,
    this.starterOrigin,
    this.idleGapSeconds,
  });

  factory AiSessionCacheHitTrendPoint.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return AiSessionCacheHitTrendPoint(
      turnIndex: _readNonNegativeInt(json[turnIndexJsonKey]),
      hitRatio: _readHitRatio(json[hitRatioJsonKey]),
      promptTokens: _readNonNegativeInt(json[promptTokensJsonKey]),
      cacheReadTokens: _readNonNegativeInt(json[cacheReadTokensJsonKey]),
      cacheWriteTokens: _readNonNegativeInt(json[cacheWriteTokensJsonKey]),
      starterMessageId: _readString(json[starterMessageIdJsonKey]),
      starterMessageKind: _readString(json[starterMessageKindJsonKey]),
      starterOrigin: _readString(json[starterOriginJsonKey]),
      idleGapSeconds: _readNullableNonNegativeInt(json[idleGapSecondsJsonKey]),
    );
  }

  static const String turnIndexJsonKey = 'turn_index';
  static const String hitRatioJsonKey = 'hit_ratio';
  static const String promptTokensJsonKey = 'prompt_tokens';
  static const String cacheReadTokensJsonKey = 'cache_read_tokens';
  static const String cacheWriteTokensJsonKey = 'cache_write_tokens';
  static const String starterMessageIdJsonKey = 'starter_message_id';
  static const String starterMessageKindJsonKey = 'starter_message_kind';
  static const String starterOriginJsonKey = 'starter_origin';
  static const String idleGapSecondsJsonKey = 'idle_gap_seconds';

  final int turnIndex;
  final double hitRatio;
  final int promptTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final String? starterMessageId;
  final String? starterMessageKind;
  final String? starterOrigin;
  final int? idleGapSeconds;

  Map<String, Object?> toJson() => <String, Object?>{
    turnIndexJsonKey: turnIndex,
    hitRatioJsonKey: hitRatio,
    promptTokensJsonKey: promptTokens,
    cacheReadTokensJsonKey: cacheReadTokens,
    cacheWriteTokensJsonKey: cacheWriteTokens,
    if (starterMessageId != null) starterMessageIdJsonKey: starterMessageId,
    if (starterMessageKind != null)
      starterMessageKindJsonKey: starterMessageKind,
    if (starterOrigin != null) starterOriginJsonKey: starterOrigin,
    if (idleGapSeconds != null) idleGapSecondsJsonKey: idleGapSeconds,
  };

  static String? _readString(Object? value) {
    final text = optionalStringFromValue(value);
    if (text == null || text == 'null') return null;
    return text;
  }

  static int _readNonNegativeInt(Object? value) {
    return _readNullableNonNegativeInt(value) ?? 0;
  }

  static int? _readNullableNonNegativeInt(Object? value) {
    return optionalNonNegativeIntFromValue(value);
  }

  static double _readHitRatio(Object? value) {
    return optionalUnitIntervalFromValue(value) ?? 0.0;
  }
}

class AiSessionErrorRecord {
  factory AiSessionErrorRecord.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return AiSessionErrorRecord(
      id: stringFromValue(json['id']),
      createdAt:
          utcDateTimeFromValue(json['created_at']) ?? DateTime.now().toUtc(),
      stage: stringFromValue(json['stage']),
      message: stringFromValue(json['message']),
      detail: optionalStringFromValue(json['detail']),
      presentedAt: utcDateTimeFromValue(json['presented_at']),
    );
  }
  const AiSessionErrorRecord({
    required this.id,
    required this.createdAt,
    required this.stage,
    required this.message,
    this.detail,
    this.presentedAt,
  });

  final String id;
  final DateTime createdAt;
  final String stage;
  final String message;
  final String? detail;
  final DateTime? presentedAt;

  bool get hasBeenPresented => presentedAt != null;

  AiSessionErrorRecord copyWith({
    String? message,
    String? detail,
    DateTime? presentedAt,
    bool clearPresentedAt = false,
  }) {
    return AiSessionErrorRecord(
      id: id,
      createdAt: createdAt,
      stage: stage,
      message: message ?? this.message,
      detail: detail ?? this.detail,
      presentedAt: clearPresentedAt ? null : presentedAt ?? this.presentedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'created_at': createdAt.toUtc().toIso8601String(),
      'stage': stage,
      'message': message,
      'detail': detail,
      'presented_at': presentedAt?.toUtc().toIso8601String(),
    };
  }
}
