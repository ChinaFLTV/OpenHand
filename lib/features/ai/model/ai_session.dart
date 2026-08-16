import 'dart:collection';

import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import 'ai_session_goal.dart';
import 'ai_session_message.dart';
import 'ai_token_usage.dart';
import 'ai_tool_call_limit_policy.dart';

bool isAiPlanFailureToolStatus(String status) {
  return const <String>{
    'failed',
    'cancelled',
    'denied',
    'rejected',
    'timed_out',
    'invalid_arguments',
  }.contains(status);
}

bool isAiPlanRelevantErrorStage(String stage) {
  return const <String>{
    'chat_request',
    'chat_continuation_request',
    'chat_stream',
    'follow_up_request',
    'tool_execution',
    'tool_loop',
  }.contains(stage.trim().toLowerCase());
}

/// 工具调用消息上归一化后的执行状态；非工具消息或未记录时为空串。
String aiToolExecutionStatusOf(AiSessionMessage message) {
  return '${message.metadata['tool_execution_status'] ?? ''}'
      .trim()
      .toLowerCase();
}

/// 工具调用的结束时刻；未记录或无法解析时为 null。
DateTime? aiToolExecutionFinishedAtOf(AiSessionMessage message) {
  final rawValue = '${message.metadata['tool_execution_finished_at'] ?? ''}'
      .trim();
  if (rawValue.isEmpty) return null;
  return utcDateTimeFromValue(rawValue);
}

/// 会话里最近一条「已结束」的工具调用消息：跳过已删除、非工具、以及状态为空
/// 或仍在 running 的消息。
///
/// 计划失败判定的三处入口此前各写了一遍这段倒序扫描；漏掉 running 那一条会把
/// 正在执行的调用当成已失败，计划面板会无端翻红。
AiSessionMessage? latestSettledAiToolCall(AiSession session) {
  for (var index = session.messages.length - 1; index >= 0; index -= 1) {
    final message = session.messages[index];
    if (message.isDeleted || message.kind != AiSessionMessageKind.toolCall) {
      continue;
    }
    final status = aiToolExecutionStatusOf(message);
    if (status.isEmpty || status == 'running') continue;
    return message;
  }
  return null;
}

/// 最近一次工具失败的时刻；最近一条已结束的调用不是失败时为 null。
DateTime? latestAiPlanToolFailureAt(AiSession session) {
  final message = latestSettledAiToolCall(session);
  if (message == null) return null;
  if (!isAiPlanFailureToolStatus(aiToolExecutionStatusOf(message))) return null;
  return aiToolExecutionFinishedAtOf(message) ?? message.createdAt;
}

/// 最近一次与计划相关的会话级错误时刻。
DateTime? latestAiPlanErrorFailureAt(AiSession session) {
  for (final error in session.recentErrors) {
    if (isAiPlanRelevantErrorStage(error.stage)) return error.createdAt;
  }
  return null;
}

/// 该失败是否仍应体现在计划状态上：用户在失败之后发出的恢复指令会把它盖掉。
bool shouldReflectAiPlanFailureAfter(
  DateTime? latestFailureAt,
  AiSessionMessage? latestRecoveryMessage,
) {
  if (latestFailureAt == null) return false;
  if (latestRecoveryMessage == null) return true;
  return !latestRecoveryMessage.createdAt.isAfter(latestFailureAt);
}

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

const Set<String> _standaloneToolResultSuppressedToolNames = <String>{
  'machineterminalread',
  'terminalread',
  'machineterminalwrite',
  'terminalwrite',
  'machineterminalexec',
  'terminalexec',
  'terminalcommand',
  'machineterminalcontrol',
  'terminalcontrol',
};

String _messageMetadataText(AiSessionMessage message, String key) {
  return '${message.metadata[key] ?? ''}'.trim();
}

Set<String> unmatchedTranscriptToolCallIds(
  Iterable<AiSessionMessage> messages,
) {
  final toolCallIds = <String>{};
  final toolResultCallIds = <String>{};
  for (final message in messages) {
    if (!message.isTranscriptRenderable) continue;
    final toolCallId = _messageMetadataText(message, aiSessionMessageToolCallIdMetadataKey);
    if (toolCallId.isEmpty) continue;
    if (message.kind == AiSessionMessageKind.toolCall) {
      toolCallIds.add(toolCallId);
    } else if (message.kind.isToolResultKind) {
      toolResultCallIds.add(toolCallId);
    }
  }
  return toolResultCallIds..removeAll(toolCallIds);
}

bool _contentLooksLikeMachineTerminalOutput(String content) {
  final text = content.trimLeft();
  return text.startsWith('terminal_id:') &&
      text.contains('\nstatus:') &&
      (text.contains('\nduration_ms:') ||
          text.contains('\nwritten_chars:') ||
          text.contains('\noutput:'));
}

bool _metadataLooksLikeMachineTerminal(Map<String, Object?> metadata) {
  return '${metadata['terminal_id'] ?? ''}'.trim().isNotEmpty ||
      metadata['machine_terminal_snapshot'] != null ||
      metadata['machine_terminal_metadata'] != null;
}

bool _isStandaloneMachineTerminalToolResult(AiSessionMessage message) {
  if (message.kind != AiSessionMessageKind.tool) {
    return false;
  }
  final toolName = _messageMetadataText(message, 'tool_name').toLowerCase();
  if (_standaloneToolResultSuppressedToolNames.contains(toolName)) {
    return true;
  }
  return _metadataLooksLikeMachineTerminal(message.metadata) &&
      _contentLooksLikeMachineTerminalOutput(message.content);
}

bool _shouldSuppressTranscriptToolResult(
  AiSessionMessage message,
  Set<String> toolCallIds, {
  required bool suppressUnpairedToolResults,
}) {
  if (!message.kind.isToolResultKind) {
    return false;
  }
  final toolCallId = _messageMetadataText(message, aiSessionMessageToolCallIdMetadataKey);
  if (toolCallId.isNotEmpty) {
    if (toolCallIds.contains(toolCallId) || suppressUnpairedToolResults) {
      return true;
    }
  }
  return _isStandaloneMachineTerminalToolResult(message);
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

abstract final class AiSessionDataLimits {
  static const int maxTodoItems = 100;
  static const int maxTodoIdCharacters = 128;
  static const int maxTodoContentCharacters = 2000;
  static const int maxTodoStatusCharacters = 32;
  static const int maxTodoActiveFormCharacters = 1000;
  static const int maxPlanAllowedPrompts = 256;
  static const int maxPlanAllowedPromptToolCharacters = 128;
  static const int maxPlanAllowedPromptCharacters = 4096;
  static const int maxPlanRecordIdCharacters = 128;
  static const int maxPlanCharacters = 32000;
  static const int maxRecentErrors = 1000;
  static const int maxPlanHistoryEntries = 1000;
  static const int maxErrorIdCharacters = 128;
  static const int maxErrorStageCharacters = 256;
  static const int maxErrorMessageCharacters = 2000;
  static const int maxErrorDetailCharacters = 8000;
  static const int maxCacheHitTrendPoints = 10000;
  static const int maxStatisticsReferenceCharacters = 256;
  static const int maxSessionIdCharacters = 256;
  static const int maxSessionTitleCharacters = 200;
  static const int maxTemplateIdCharacters = 256;
  static const int maxTemplateNameCharacters = 512;
  static const int maxTemplateIconCharacters = 128;
  static const int maxVersionCharacters = 128;
  static const int maxModelFieldCharacters = 512;
  static const int maxSessionReferenceIdCharacters = 256;
  static const int maxAutoTitleSourceCharacters = 8000;
  static const int maxEnvironmentTagCharacters = 128;
  static const int maxEnvironmentPathCharacters = 4096;
}

String normalizeAiSessionPlan(Object? value) {
  return clipTextByCodeUnits(
    stringFromValue(value),
    AiSessionDataLimits.maxPlanCharacters,
    suffix: '…',
  );
}

String normalizeAiSessionAutoTitleSource(Object? value) {
  return clipTextByCodeUnits(
    stringFromValue(value),
    AiSessionDataLimits.maxAutoTitleSourceCharacters,
    suffix: '…',
  );
}

String _boundedAiSessionText(Object? value, int maxCharacters) {
  return clipTextByCodeUnits(
    stringFromValue(value),
    maxCharacters,
    suffix: '…',
  );
}

String? _boundedNullableAiSessionText(Object? value, int maxCharacters) {
  return nullIfBlank(_boundedAiSessionText(value, maxCharacters));
}

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

  static AiSessionTodoItem? fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    final id = stringFromValue(json['id']);
    final content = stringFromValue(json['content']);
    final status = stringFromValue(json['status']);
    final activeForm = stringFromValue(
      json['activeForm'] ?? json['active_form'],
    );
    if (id.isEmpty ||
        content.isEmpty ||
        status.isEmpty ||
        id.length > AiSessionDataLimits.maxTodoIdCharacters ||
        status.length > AiSessionDataLimits.maxTodoStatusCharacters) {
      return null;
    }
    return AiSessionTodoItem(
      id: id,
      content: clipTextByCodeUnits(
        content,
        AiSessionDataLimits.maxTodoContentCharacters,
        suffix: '…',
      ),
      status: status,
      activeForm: clipTextByCodeUnits(
        activeForm,
        AiSessionDataLimits.maxTodoActiveFormCharacters,
        suffix: '…',
      ),
    );
  }

  static List<AiSessionTodoItem> listFromJson(Object? rawValue) {
    final items = <AiSessionTodoItem>[];
    final ids = <String>{};
    for (final raw in stringKeyedMapListFromValueOrJsonText(
      rawValue,
      limit: AiSessionDataLimits.maxTodoItems,
    )) {
      final item = AiSessionTodoItem.fromJson(raw);
      if (item != null && ids.add(item.id)) items.add(item);
    }
    return items.toList(growable: false);
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
    if (tool.isEmpty ||
        prompt.isEmpty ||
        tool.length > AiSessionDataLimits.maxPlanAllowedPromptToolCharacters) {
      return null;
    }
    return AiSessionPlanAllowedPrompt(
      tool: tool,
      prompt: clipTextByCodeUnits(
        prompt,
        AiSessionDataLimits.maxPlanAllowedPromptCharacters,
        suffix: '…',
      ),
    );
  }

  static List<AiSessionPlanAllowedPrompt> listFromJson(Object? rawValue) {
    return stringKeyedMapListFromValueOrJsonText(
          rawValue,
          limit: AiSessionDataLimits.maxPlanAllowedPrompts,
        )
        .map(AiSessionPlanAllowedPrompt.fromJson)
        .whereType<AiSessionPlanAllowedPrompt>()
        .toList(growable: false);
  }
}

class AiSessionPlanRecord {
  AiSessionPlanRecord({
    required String id,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    String plan = '',
    this.steps = const <AiSessionTodoItem>[],
    this.allowedPrompts = const <AiSessionPlanAllowedPrompt>[],
  }) : id = clipTextByCodeUnits(
         stringFromValue(id),
         AiSessionDataLimits.maxPlanRecordIdCharacters,
         suffix: '',
       ),
       plan = normalizeAiSessionPlan(plan);

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
      steps: AiSessionTodoItem.listFromJson(json['steps']),
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
                .take(AiSessionDataLimits.maxRecentErrors)
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
      isTitleManuallyEdited:
          sessionJson['is_title_manually_edited'] is bool &&
          sessionJson['is_title_manually_edited'] as bool,
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
      awaitingPlanApproval:
          sessionJson['awaiting_plan_approval'] is bool &&
          sessionJson['awaiting_plan_approval'] as bool,
      pendingPlan: _readNullableString(sessionJson['pending_plan']),
      pendingPlanAllowedPrompts: AiSessionPlanAllowedPrompt.listFromJson(
        sessionJson['pending_plan_allowed_prompts'],
      ),
      fullAccessPermission:
          sessionJson['full_access_permission'] is bool &&
          sessionJson['full_access_permission'] as bool,
      planHistory: planHistoryJson is List
          ? planHistoryJson
                .skip(
                  planHistoryJson.length >
                          AiSessionDataLimits.maxPlanHistoryEntries
                      ? planHistoryJson.length -
                            AiSessionDataLimits.maxPlanHistoryEntries
                      : 0,
                )
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
      todoItems: AiSessionTodoItem.listFromJson(todoItemsJson),
      messageLoadState: AiSessionMessageLoadState.complete,
      messageWindowStartIndex: 0,
      messageTotalCount: messagesJson.length,
    );
  }
  AiSession({
    required String id,
    required String title,
    required String templateId,
    required String templateName,
    required String templateIconName,
    required String templateInternalVersion,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    required this.environment,
    required this.statistics,
    required this.recentErrors,
    String? lastUsedModelId,
    String? lastUsedModelLabel,
    this.isTitleManuallyEdited = false,
    this.autoTitleAcquired = false,
    this.autoTitleRetryCount = 0,
    String? autoTitleFirstUserContent,
    this.autoTitleGeneratedAt,
    String? autoTitleSourceMessageId,
    String? latestCompressionCheckpointMessageId,
    this.latestCompressionAt,
    this.lastPromptMetadata = const <String, Object?>{},
    this.todoItems = const <AiSessionTodoItem>[],
    this.mode = AiSessionMode.chat,
    this.awaitingPlanApproval = false,
    String? pendingPlan,
    this.pendingPlanAllowedPrompts = const <AiSessionPlanAllowedPrompt>[],
    this.planHistory = const <AiSessionPlanRecord>[],
    this.fullAccessPermission = false,
    this.metadata = const <String, Object?>{},
    AiSessionMessageLoadState? messageLoadState,
    int? messageWindowStartIndex,
    int? messageTotalCount,
  }) : id = _boundedAiSessionText(
         id,
         AiSessionDataLimits.maxSessionIdCharacters,
       ),
       title = clipText(
         stringFromValue(title),
         AiSessionDataLimits.maxSessionTitleCharacters,
         suffix: '…',
       ),
       templateId = _boundedAiSessionText(
         templateId,
         AiSessionDataLimits.maxTemplateIdCharacters,
       ),
       templateName = _boundedAiSessionText(
         templateName,
         AiSessionDataLimits.maxTemplateNameCharacters,
       ),
       templateIconName = _boundedAiSessionText(
         templateIconName,
         AiSessionDataLimits.maxTemplateIconCharacters,
       ),
       templateInternalVersion = _boundedAiSessionText(
         templateInternalVersion,
         AiSessionDataLimits.maxVersionCharacters,
       ),
       lastUsedModelId = _boundedNullableAiSessionText(
         lastUsedModelId,
         AiSessionDataLimits.maxModelFieldCharacters,
       ),
       lastUsedModelLabel = _boundedNullableAiSessionText(
         lastUsedModelLabel,
         AiSessionDataLimits.maxModelFieldCharacters,
       ),
       autoTitleFirstUserContent = nullIfBlank(
         normalizeAiSessionAutoTitleSource(autoTitleFirstUserContent),
       ),
       autoTitleSourceMessageId = _boundedNullableAiSessionText(
         autoTitleSourceMessageId,
         AiSessionDataLimits.maxSessionReferenceIdCharacters,
       ),
       latestCompressionCheckpointMessageId = _boundedNullableAiSessionText(
         latestCompressionCheckpointMessageId,
         AiSessionDataLimits.maxSessionReferenceIdCharacters,
       ),
       pendingPlan = nullIfBlank(normalizeAiSessionPlan(pendingPlan)),
       messageLoadState =
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

  /// 是否由钉钉消息网关创建。此类会话仅供网关复用，不显示在普通线程导航中。
  bool get isDingTalkGatewaySession =>
      metadata['created_via'] == 'dingtalk_gateway' ||
      metadata.containsKey('dingtalk_conversation_id');

  /// 是否允许出现在主工作区并成为当前线程。
  bool get isPrimaryWorkspaceSession => !isDingTalkGatewaySession;

  // 派生自 [messages] 的 O(N) 缓存。刻意不用 `late final` 字段初始化器：
  // 那样每个 copyWith 产出的新实例都会在首次访问时重跑全量扫描，而
  // 绝大多数 copyWith（改标题 / 统计 / 错误 / 流式节流等）并不改动
  // messages 引用。改为惰性 memo + copyWith 在 messages 引用未变时透传，
  // 消除大会话每次无关更新在 UI 线程重跑全量扫描，同时让下游按
  // `identical(displayMessages)` 命中的 memo（transcript 索引表 / 占位判定）
  // 保持稳定。
  // 压缩点索引可能合法地为 null，需独立的「已算」标记以免每次访问都
  // 重跑逆序扫描。
  bool _latestCompressionPointIndexComputed = false;
  int? _latestCompressionPointIndexCache;
  List<AiSessionMessage>? _visibleMessagesCache;
  List<AiSessionMessage>? _displayMessagesCache;
  Map<String, int>? _messageIndexByIdCache;
  Map<String, AiSessionMessage>? _displayMessageByIdCache;
  Map<String, AiSessionMessage>? _displayToolCallByCallIdCache;

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
    final next = AiSession(
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
    // messages 引用未变时透传全部派生缓存；它们只依赖 messages，可安全
    // 复用，省掉 O(N) 重扫；同时保持
    // displayMessages 的 identity 稳定，让下游 `identical` memo 继续命中。
    if (identical(nextMessages, this.messages)) {
      next._seedDerivedCachesFrom(this);
    }
    return next;
  }

  /// 仅追加或替换尾消息，并增量维护已物化的派生缓存。
  ///
  /// 流式响应会高频更新最后一条消息。普通 [copyWith] 必须让所有消息派生
  /// 缓存失效，而这里能证明历史前缀未变，可将每次更新从全量扫描收敛为 O(1)。
  AiSession copyWithTailMessage(
    AiSessionMessage nextTail, {
    required bool append,
    DateTime? updatedAt,
  }) {
    final previousLength = messages.length;
    if (!append && previousLength == 0) {
      throw StateError('空会话不能替换尾消息。');
    }
    final previousTail = append ? null : messages.last;
    final nextMessages = append
        ? _AiSessionTailMessages.append(messages, nextTail)
        : _AiSessionTailMessages.replace(messages, nextTail);
    final next = copyWith(messages: nextMessages, updatedAt: updatedAt);
    if (hasCompleteMessages) {
      next._seedDerivedCachesAfterTailChange(
        this,
        previousTail: previousTail,
        nextTail: nextTail,
        appended: append,
      );
    }
    return next;
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
    if (_latestCompressionPointIndexComputed) {
      return _latestCompressionPointIndexCache;
    }
    _latestCompressionPointIndexCache = _computeLatestCompressionPointIndex();
    _latestCompressionPointIndexComputed = true;
    return _latestCompressionPointIndexCache;
  }

  List<AiSessionMessage> get visibleMessages {
    return _visibleMessagesCache ??= messages
        .where((item) => item.isVisible)
        .toList(growable: false);
  }

  List<AiSessionMessage> get displayMessages {
    return _displayMessagesCache ??= _computeDisplayMessages();
  }

  int messageIndexOf(String messageId) {
    return (_messageIndexByIdCache ??= <String, int>{
          for (var index = 0; index < messages.length; index += 1)
            messages[index].id: index,
        })[messageId] ??
        -1;
  }

  /// 将一次模型请求的起始消息解析为线程中实际渲染的卡片。
  ///
  /// 工具结果与对应 tool-call 合并展示时，结果消息本身不会进入
  /// [displayMessages]，此时返回承载该结果的 tool-call。没有配对卡片时，
  /// 回退到同一请求内首条可展示消息。
  AiSessionMessage? transcriptAnchorForRoundStarter(String starterMessageId) {
    final normalizedId = starterMessageId.trim();
    if (normalizedId.isEmpty) return null;
    final starterIndex = messageIndexOf(normalizedId);
    if (starterIndex < 0 || messages[starterIndex].isDeleted) return null;

    final displayById = _displayMessageByIdCache ??= <String, AiSessionMessage>{
      for (final message in displayMessages) message.id: message,
    };
    final direct = displayById[normalizedId];
    if (direct != null) return direct;

    final starter = messages[starterIndex];
    final toolCallId = _messageMetadataText(starter, aiSessionMessageToolCallIdMetadataKey);
    if (starter.kind.isToolResultKind && toolCallId.isNotEmpty) {
      final toolCallsById = _displayToolCallByCallIdCache ??=
          <String, AiSessionMessage>{
            for (final message in displayMessages)
              if (message.kind == AiSessionMessageKind.toolCall &&
                  _messageMetadataText(message, aiSessionMessageToolCallIdMetadataKey).isNotEmpty)
                _messageMetadataText(message, aiSessionMessageToolCallIdMetadataKey): message,
          };
      final toolCall = toolCallsById[toolCallId];
      if (toolCall != null && messageIndexOf(toolCall.id) < starterIndex) {
        return toolCall;
      }
    }

    for (var index = starterIndex + 1; index < messages.length; index += 1) {
      final candidate = messages[index];
      if (candidate.startsConversationRound) break;
      final visible = displayById[candidate.id];
      if (visible != null) return visible;
    }
    return null;
  }

  /// 当 messages 引用未变时，把【已经算过】的派生缓存透传给 copyWith
  /// 产出的新实例，避免大会话在无关字段更新后被迫重跑全量扫描。
  /// 只搬运 source 上已物化的缓存，绝不主动触发计算——从未展示过的
  /// 后台会话保持惰性，不会因一次 copyWith 就白算一轮 O(N)。仅由
  /// copyWith 在确认 `identical(nextMessages, messages)` 时调用。
  void _seedDerivedCachesFrom(AiSession source) {
    if (source._latestCompressionPointIndexComputed) {
      _latestCompressionPointIndexCache =
          source._latestCompressionPointIndexCache;
      _latestCompressionPointIndexComputed = true;
    }
    if (source._visibleMessagesCache != null) {
      _visibleMessagesCache = source._visibleMessagesCache;
    }
    if (source._displayMessagesCache != null) {
      _displayMessagesCache = source._displayMessagesCache;
    }
    if (source._messageIndexByIdCache != null) {
      _messageIndexByIdCache = source._messageIndexByIdCache;
    }
    if (source._displayMessageByIdCache != null) {
      _displayMessageByIdCache = source._displayMessageByIdCache;
    }
    if (source._displayToolCallByCallIdCache != null) {
      _displayToolCallByCallIdCache = source._displayToolCallByCallIdCache;
    }
  }

  void _seedDerivedCachesAfterTailChange(
    AiSession source, {
    required AiSessionMessage? previousTail,
    required AiSessionMessage nextTail,
    required bool appended,
  }) {
    final previousVisible = source._visibleMessagesCache;
    if (previousVisible != null) {
      _visibleMessagesCache = _updatedTailDerivedList(
        previousVisible,
        previousTail: previousTail,
        nextTail: nextTail,
        previousIncluded: previousTail?.isVisible ?? false,
        nextIncluded: nextTail.isVisible,
        displayList: false,
      );
    }

    final previousDisplay = source._displayMessagesCache;
    if (previousDisplay != null) {
      final previousIncluded =
          previousTail != null &&
          previousDisplay.isNotEmpty &&
          identical(previousDisplay.last, previousTail);
      final nextIncluded = _tailDisplayMembershipAfterChange(
        previousTail: previousTail,
        nextTail: nextTail,
        previousIncluded: previousIncluded,
        appended: appended,
      );
      if (nextIncluded != null) {
        _displayMessagesCache = _updatedTailDerivedList(
          previousDisplay,
          previousTail: previousTail,
          nextTail: nextTail,
          previousIncluded: previousIncluded,
          nextIncluded: nextIncluded,
          displayList: true,
        );
      }
    }

    if (source._latestCompressionPointIndexComputed) {
      if (appended) {
        if (nextTail.kind == AiSessionMessageKind.compressionPoint &&
            !nextTail.isDeleted) {
          _latestCompressionPointIndexCache = messages.length - 1;
        } else {
          _latestCompressionPointIndexCache =
              source._latestCompressionPointIndexCache;
        }
        _latestCompressionPointIndexComputed = true;
      } else if (previousTail?.kind != AiSessionMessageKind.compressionPoint &&
          nextTail.kind != AiSessionMessageKind.compressionPoint) {
        _latestCompressionPointIndexCache =
            source._latestCompressionPointIndexCache;
        _latestCompressionPointIndexComputed = true;
      }
    }

    final previousIndex = source._messageIndexByIdCache;
    if (previousIndex != null &&
        (previousTail == null || previousTail.id == nextTail.id)) {
      if (appended) {
        _messageIndexByIdCache = _AiSessionTailMessageIndex.append(
          previousIndex,
          nextTail.id,
          messages.length - 1,
        );
      } else {
        _messageIndexByIdCache = previousIndex;
      }
    }
  }

  List<AiSessionMessage> _updatedTailDerivedList(
    List<AiSessionMessage> previous, {
    required AiSessionMessage? previousTail,
    required AiSessionMessage nextTail,
    required bool previousIncluded,
    required bool nextIncluded,
    required bool displayList,
  }) {
    if (!previousIncluded && !nextIncluded) return previous;
    if (!previousIncluded) {
      return _AiSessionTailMessages.append(previous, nextTail);
    }
    if (previous.isEmpty || !identical(previous.last, previousTail)) {
      return displayList
          ? _computeDisplayMessages()
          : messages
                .where((message) => message.isVisible)
                .toList(growable: false);
    }
    if (!nextIncluded) {
      return _AiSessionTailMessages.removeLast(previous);
    }
    return _AiSessionTailMessages.replace(previous, nextTail);
  }

  bool? _tailDisplayMembershipAfterChange({
    required AiSessionMessage? previousTail,
    required AiSessionMessage nextTail,
    required bool previousIncluded,
    required bool appended,
  }) {
    if (appended) {
      if (nextTail.kind == AiSessionMessageKind.toolCall &&
          _messageMetadataText(nextTail, aiSessionMessageToolCallIdMetadataKey).isNotEmpty) {
        return null;
      }
      if (nextTail.kind.isToolResultKind) return null;
      return nextTail.isTranscriptRenderable &&
          nextTail.metadata['plan_mode_approved'] != true;
    }
    if (previousTail == null ||
        previousTail.id != nextTail.id ||
        previousTail.kind != nextTail.kind ||
        previousTail.isTranscriptRenderable !=
            nextTail.isTranscriptRenderable ||
        previousTail.metadata['plan_mode_approved'] !=
            nextTail.metadata['plan_mode_approved']) {
      return null;
    }
    if ((nextTail.kind == AiSessionMessageKind.toolCall ||
            nextTail.kind.isToolResultKind) &&
        _messageMetadataText(previousTail, aiSessionMessageToolCallIdMetadataKey) !=
            _messageMetadataText(nextTail, aiSessionMessageToolCallIdMetadataKey)) {
      return null;
    }
    if (nextTail.kind.isToolResultKind &&
        _isStandaloneMachineTerminalToolResult(previousTail) !=
            _isStandaloneMachineTerminalToolResult(nextTail)) {
      return null;
    }
    return previousIncluded;
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
      final toolCallId = _messageMetadataText(message, aiSessionMessageToolCallIdMetadataKey);
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
      if (_shouldSuppressTranscriptToolResult(
        message,
        toolCallIds,
        suppressUnpairedToolResults: hasMoreHistoricalMessages,
      )) {
        continue;
      }
      displayMessages.add(message);
    }
    return List<AiSessionMessage>.unmodifiable(displayMessages);
  }

  Map<String, Object?> toJson({bool includeMessages = true}) {
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
      if (includeMessages)
        'messages': messages
            .map((item) => item.toJson())
            .toList(growable: false),
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

/// 流式尾消息共享历史前缀，只复制极小尾段，避免每个片段复制整段会话历史。
class _AiSessionTailMessages extends ListBase<AiSessionMessage> {
  _AiSessionTailMessages._(this._prefix, this._prefixLength, this._tail);

  factory _AiSessionTailMessages.append(
    List<AiSessionMessage> source,
    AiSessionMessage message,
  ) {
    if (source is _AiSessionTailMessages &&
        source._tail.length < _maxSharedTailLength) {
      return _AiSessionTailMessages._(
        source._prefix,
        source._prefixLength,
        List<AiSessionMessage>.unmodifiable(<AiSessionMessage>[
          ...source._tail,
          message,
        ]),
      );
    }
    final prefix = source is _AiSessionTailMessages
        ? List<AiSessionMessage>.unmodifiable(source)
        : source;
    return _AiSessionTailMessages._(
      prefix,
      prefix.length,
      List<AiSessionMessage>.unmodifiable(<AiSessionMessage>[message]),
    );
  }

  factory _AiSessionTailMessages.replace(
    List<AiSessionMessage> source,
    AiSessionMessage message,
  ) {
    if (source is _AiSessionTailMessages) {
      return _AiSessionTailMessages._(
        source._prefix,
        source._tail.isEmpty ? source._prefixLength - 1 : source._prefixLength,
        List<AiSessionMessage>.unmodifiable(<AiSessionMessage>[
          if (source._tail.isNotEmpty)
            ...source._tail.take(source._tail.length - 1),
          message,
        ]),
      );
    }
    return _AiSessionTailMessages._(
      source,
      source.length - 1,
      List<AiSessionMessage>.unmodifiable(<AiSessionMessage>[message]),
    );
  }

  factory _AiSessionTailMessages.removeLast(List<AiSessionMessage> source) {
    if (source.isEmpty) {
      throw StateError('空会话消息列表不能移除尾消息。');
    }
    if (source is _AiSessionTailMessages) {
      return _AiSessionTailMessages._(
        source._prefix,
        source._tail.isEmpty ? source._prefixLength - 1 : source._prefixLength,
        source._tail.isEmpty
            ? const <AiSessionMessage>[]
            : List<AiSessionMessage>.unmodifiable(
                source._tail.take(source._tail.length - 1),
              ),
      );
    }
    return _AiSessionTailMessages._(
      source,
      source.length - 1,
      const <AiSessionMessage>[],
    );
  }

  static const int _maxSharedTailLength = 64;

  final List<AiSessionMessage> _prefix;
  final int _prefixLength;
  final List<AiSessionMessage> _tail;

  @override
  int get length => _prefixLength + _tail.length;

  @override
  set length(int value) => throw UnsupportedError('会话消息列表不可修改。');

  @override
  AiSessionMessage operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return index < _prefixLength
        ? _prefix[index]
        : _tail[index - _prefixLength];
  }

  @override
  void operator []=(int index, AiSessionMessage value) {
    throw UnsupportedError('会话消息列表不可修改。');
  }
}

class _AiSessionTailMessageIndex extends MapBase<String, int> {
  _AiSessionTailMessageIndex._(this._prefix, this._tail);

  factory _AiSessionTailMessageIndex.append(
    Map<String, int> source,
    String messageId,
    int index,
  ) {
    if (source is _AiSessionTailMessageIndex &&
        source._tail.length < _maxSharedTailLength) {
      return _AiSessionTailMessageIndex._(
        source._prefix,
        Map<String, int>.unmodifiable(<String, int>{
          ...source._tail,
          messageId: index,
        }),
      );
    }
    final prefix = source is _AiSessionTailMessageIndex
        ? Map<String, int>.unmodifiable(source)
        : source;
    return _AiSessionTailMessageIndex._(
      prefix,
      Map<String, int>.unmodifiable(<String, int>{messageId: index}),
    );
  }

  static const int _maxSharedTailLength = 64;

  final Map<String, int> _prefix;
  final Map<String, int> _tail;

  @override
  int? operator [](Object? key) {
    return _tail.containsKey(key) ? _tail[key] : _prefix[key];
  }

  @override
  void operator []=(String key, int value) {
    throw UnsupportedError('会话消息索引不可修改。');
  }

  @override
  void clear() {
    throw UnsupportedError('会话消息索引不可修改。');
  }

  @override
  Iterable<String> get keys sync* {
    for (final key in _prefix.keys) {
      if (!_tail.containsKey(key)) yield key;
    }
    yield* _tail.keys;
  }

  @override
  int? remove(Object? key) {
    throw UnsupportedError('会话消息索引不可修改。');
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
    required String localeTag,
    required String platform,
    required String appVersion,
    required String appBuildNumber,
    required String applicationDirectory,
    required String homeDirectory,
    required String settingsFilePath,
    required String skillsStoragePath,
    required String mcpServersFilePath,
    required String userMemoryFilePath,
    required String sessionsDirectoryPath,
    required int compressionThresholdChars,
    int singleRoundToolCallLimit = defaultSingleRoundToolCallLimit,
    int sequentialToolRoundLimit = defaultSequentialToolRoundLimit,
  }) : localeTag = _boundedAiSessionText(
         localeTag,
         AiSessionDataLimits.maxEnvironmentTagCharacters,
       ),
       platform = _boundedAiSessionText(
         platform,
         AiSessionDataLimits.maxEnvironmentTagCharacters,
       ),
       appVersion = _boundedAiSessionText(
         appVersion,
         AiSessionDataLimits.maxVersionCharacters,
       ),
       appBuildNumber = _boundedAiSessionText(
         appBuildNumber,
         AiSessionDataLimits.maxVersionCharacters,
       ),
       applicationDirectory = _boundedAiSessionText(
         applicationDirectory,
         AiSessionDataLimits.maxEnvironmentPathCharacters,
       ),
       homeDirectory = _boundedAiSessionText(
         homeDirectory,
         AiSessionDataLimits.maxEnvironmentPathCharacters,
       ),
       settingsFilePath = _boundedAiSessionText(
         settingsFilePath,
         AiSessionDataLimits.maxEnvironmentPathCharacters,
       ),
       skillsStoragePath = _boundedAiSessionText(
         skillsStoragePath,
         AiSessionDataLimits.maxEnvironmentPathCharacters,
       ),
       mcpServersFilePath = _boundedAiSessionText(
         mcpServersFilePath,
         AiSessionDataLimits.maxEnvironmentPathCharacters,
       ),
       userMemoryFilePath = _boundedAiSessionText(
         userMemoryFilePath,
         AiSessionDataLimits.maxEnvironmentPathCharacters,
       ),
       sessionsDirectoryPath = _boundedAiSessionText(
         sessionsDirectoryPath,
         AiSessionDataLimits.maxEnvironmentPathCharacters,
       ),
       compressionThresholdChars = compressionThresholdChars < 0
           ? 0
           : compressionThresholdChars,
       singleRoundToolCallLimit = normalizeSingleRoundToolCallLimit(
         singleRoundToolCallLimit,
       ),
       sequentialToolRoundLimit = normalizeSequentialToolRoundLimit(
         sequentialToolRoundLimit,
       );

  static const int defaultSingleRoundToolCallLimit =
      AiToolCallLimitPolicy.defaultSingleRoundToolCallLimit;
  static const int defaultSequentialToolRoundLimit =
      AiToolCallLimitPolicy.defaultSequentialToolRoundLimit;

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
      audioInputTokens: _readNullableInt(json['audio_input_tokens']),
      imageInputTokens: _readNullableInt(json['image_input_tokens']),
      videoInputTokens: _readNullableInt(json['video_input_tokens']),
      webSearchToolUsage: _readNullableInt(json['web_search_tool_usage']),
      webSearchPageUsage: _readNullableInt(json['web_search_page_usage']),
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
    this.audioInputTokens,
    this.imageInputTokens,
    this.videoInputTokens,
    this.webSearchToolUsage,
    this.webSearchPageUsage,
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
      audioInputTokens = null,
      imageInputTokens = null,
      videoInputTokens = null,
      webSearchToolUsage = null,
      webSearchPageUsage = null,
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
  final int? audioInputTokens;
  final int? imageInputTokens;
  final int? videoInputTokens;
  final int? webSearchToolUsage;
  final int? webSearchPageUsage;

  /// 首个计入会话累计的模型请求 Prompt Token，仅用于旧数据的缓存冷启动排除。
  final int? firstPromptTokens;
  final int lastPromptSystemMessageCount;
  final int lastPromptHistoryMessageCount;

  /// 后端预计算的缓存命中率（逐模型请求聚合，默认排除首轮
  /// 冷请求与过期异常），供 WEB 端、TopBar 胶囊、浮窗统一读取，避免跨端
  /// 计算口径漂移。范围 0.0..1.0。无任何 token 数据时为 null。
  final double? cacheHitRatio;

  /// 后端预计算的逐轮次趋势点。轮次从非 AI 侧消息开始：
  /// 显式用户消息或 OpenHand 后台写入的工具结果。WEB 端不再独立 walk
  /// messages 重算，直接消费。
  final List<AiSessionCacheHitTrendPoint> cacheHitTrendPoints;

  /// 被「不包含过期异常」模式过滤掉的轮次数（首轮冷请求，
  /// 或 idle_gap>30min 且 hit_ratio<3%），用于浮窗内展示「已排除 N 轮」提示。
  final int cacheHitTrendExcludedCount;

  bool get hasCacheUsageTelemetry =>
      cacheCreationTokens != null || cacheReadTokens != null;

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
    int? audioInputTokens,
    int? imageInputTokens,
    int? videoInputTokens,
    int? webSearchToolUsage,
    int? webSearchPageUsage,
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
      audioInputTokens: audioInputTokens ?? this.audioInputTokens,
      imageInputTokens: imageInputTokens ?? this.imageInputTokens,
      videoInputTokens: videoInputTokens ?? this.videoInputTokens,
      webSearchToolUsage: webSearchToolUsage ?? this.webSearchToolUsage,
      webSearchPageUsage: webSearchPageUsage ?? this.webSearchPageUsage,
      firstPromptTokens: firstPromptTokens ?? this.firstPromptTokens,
      lastPromptSystemMessageCount:
          lastPromptSystemMessageCount ?? this.lastPromptSystemMessageCount,
      lastPromptHistoryMessageCount:
          lastPromptHistoryMessageCount ?? this.lastPromptHistoryMessageCount,
      cacheHitRatio: cacheHitRatio ?? this.cacheHitRatio,
      cacheHitTrendPoints: cacheHitTrendPoints == null
          ? this.cacheHitTrendPoints
          : _retainRecentTrendPoints(cacheHitTrendPoints),
      cacheHitTrendExcludedCount:
          cacheHitTrendExcludedCount ?? this.cacheHitTrendExcludedCount,
    );
  }

  Map<String, Object?> toJson({bool includeCacheHitTrendPoints = true}) {
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
      'audio_input_tokens': audioInputTokens,
      'image_input_tokens': imageInputTokens,
      'video_input_tokens': videoInputTokens,
      'web_search_tool_usage': webSearchToolUsage,
      'web_search_page_usage': webSearchPageUsage,
      'first_prompt_tokens': firstPromptTokens,
      'last_prompt_system_message_count': lastPromptSystemMessageCount,
      'last_prompt_history_message_count': lastPromptHistoryMessageCount,
      'cache_hit_ratio': cacheHitRatio,
      if (includeCacheHitTrendPoints)
        'cache_hit_trend_points': _retainRecentTrendPoints(
          cacheHitTrendPoints,
        ).map((p) => p.toJson()).toList(growable: false),
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
      audioInputTokens: totalUsage.audioInputTokens,
      imageInputTokens: totalUsage.imageInputTokens,
      videoInputTokens: totalUsage.videoInputTokens,
      webSearchToolUsage: totalUsage.webSearchToolUsage,
      webSearchPageUsage: totalUsage.webSearchPageUsage,
      firstPromptTokens: firstPromptTokens,
      lastPromptSystemMessageCount: lastPromptSystemMessageCount,
      lastPromptHistoryMessageCount: lastPromptHistoryMessageCount,
      cacheHitRatio: cacheHitRatio,
      cacheHitTrendPoints: _retainRecentTrendPoints(cacheHitTrendPoints),
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
      limit: AiSessionDataLimits.maxCacheHitTrendPoints,
      fromEnd: true,
    ).map(AiSessionCacheHitTrendPoint.fromJson).toList(growable: false);
  }

  static List<AiSessionCacheHitTrendPoint> _retainRecentTrendPoints(
    List<AiSessionCacheHitTrendPoint> points,
  ) {
    final start = points.length > AiSessionDataLimits.maxCacheHitTrendPoints
        ? points.length - AiSessionDataLimits.maxCacheHitTrendPoints
        : 0;
    return points.skip(start).toList(growable: false);
  }
}

/// 后端预计算的逐轮次缓存命中点（直接从
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
    this.anchorMessageId,
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
      anchorMessageId: _readString(json[anchorMessageIdJsonKey]),
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
  static const String anchorMessageIdJsonKey = 'anchor_message_id';
  static const String idleGapSecondsJsonKey = 'idle_gap_seconds';

  final int turnIndex;
  final double hitRatio;
  final int promptTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final String? starterMessageId;
  final String? starterMessageKind;
  final String? starterOrigin;
  final String? anchorMessageId;
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
    if (anchorMessageId != null) anchorMessageIdJsonKey: anchorMessageId,
    if (idleGapSeconds != null) idleGapSecondsJsonKey: idleGapSeconds,
  };

  static String? _readString(Object? value) {
    final text = optionalStringFromValue(value);
    if (text == null || text == 'null') return null;
    return clipTextByCodeUnits(
      text,
      AiSessionDataLimits.maxStatisticsReferenceCharacters,
      suffix: '…',
    );
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
  AiSessionErrorRecord({
    required String id,
    required this.createdAt,
    required String stage,
    required String message,
    String? detail,
    this.presentedAt,
  }) : id = clipTextByCodeUnits(
         id.trim(),
         AiSessionDataLimits.maxErrorIdCharacters,
         suffix: '',
       ),
       stage = clipTextByCodeUnits(
         stage.trim(),
         AiSessionDataLimits.maxErrorStageCharacters,
         suffix: '…',
       ),
       message = clipTextByCodeUnits(
         message.trim(),
         AiSessionDataLimits.maxErrorMessageCharacters,
         suffix: '…',
       ),
       detail = nullIfBlank(detail) == null
           ? null
           : clipTextByCodeUnits(
               detail!.trim(),
               AiSessionDataLimits.maxErrorDetailCharacters,
               suffix: '…',
             );

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
