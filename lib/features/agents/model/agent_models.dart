import 'package:characters/characters.dart';

import '../../../shared/util/input_value_parsing.dart';

enum AgentExecutionMode {
  normal('normal'),
  fullAccess('full_access');

  const AgentExecutionMode(this.storageValue);

  final String storageValue;

  static AgentExecutionMode fromStorage(String? raw) {
    final normalized = raw?.trim().toLowerCase() ?? '';
    for (final value in values) {
      if (value.storageValue == normalized) return value;
    }
    return AgentExecutionMode.normal;
  }
}

enum AgentLifecycleState {
  stopped('stopped'),
  running('running'),
  paused('paused'),
  degraded('degraded');

  const AgentLifecycleState(this.storageValue);

  final String storageValue;

  static AgentLifecycleState fromStorage(String? raw) {
    final normalized = raw?.trim().toLowerCase() ?? '';
    for (final value in values) {
      if (value.storageValue == normalized) return value;
    }
    return AgentLifecycleState.stopped;
  }
}

enum AgentTaskStatus {
  backlog('backlog'),
  ready('ready'),
  running('running'),
  waitingApproval('waiting_approval'),
  paused('paused'),
  completed('completed'),
  failed('failed'),
  canceled('canceled');

  const AgentTaskStatus(this.storageValue);

  final String storageValue;

  static AgentTaskStatus fromStorage(String? raw) {
    final normalized = raw?.trim().toLowerCase() ?? '';
    for (final value in values) {
      if (value.storageValue == normalized) return value;
    }
    return AgentTaskStatus.backlog;
  }
}

enum AgentApprovalStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  expired('expired');

  const AgentApprovalStatus(this.storageValue);

  final String storageValue;

  static AgentApprovalStatus fromStorage(String? raw) {
    final normalized = raw?.trim().toLowerCase() ?? '';
    for (final value in values) {
      if (value.storageValue == normalized) return value;
    }
    return AgentApprovalStatus.pending;
  }
}

enum AgentWorkerStatus {
  idle('idle'),
  busy('busy'),
  draining('draining'),
  offline('offline');

  const AgentWorkerStatus(this.storageValue);

  final String storageValue;

  static AgentWorkerStatus fromStorage(String? raw) {
    final normalized = raw?.trim().toLowerCase() ?? '';
    for (final value in values) {
      if (value.storageValue == normalized) return value;
    }
    return AgentWorkerStatus.idle;
  }
}

class AgentScaleSettings {
  const AgentScaleSettings({
    this.minWorkers = 1,
    this.maxWorkers = 1,
    this.scaleOutThreshold = 0.75,
    this.scaleInThreshold = 0.25,
    this.workerRemovalPolicy = 'least_busy',
    this.retryPolicy = 'bounded_retry',
    this.maxRetries = 2,
    this.schedulerPolicy = 'least_busy',
    this.tags = const <String>[],
  });

  factory AgentScaleSettings.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    final minWorkers = clampedIntFromValue(
      json['min_workers'],
      fallback: 1,
      min: 0,
      max: 999,
    );
    final maxWorkers = clampedIntFromValue(
      json['max_workers'],
      fallback: minWorkers < 1 ? 1 : minWorkers,
      min: 1,
      max: 999,
    );
    return AgentScaleSettings(
      minWorkers: minWorkers > maxWorkers ? maxWorkers : minWorkers,
      maxWorkers: maxWorkers,
      scaleOutThreshold: _ratioFromValue(
        json['scale_out_threshold'],
        fallback: 0.75,
      ),
      scaleInThreshold: _ratioFromValue(
        json['scale_in_threshold'],
        fallback: 0.25,
      ),
      workerRemovalPolicy: _nonEmpty(
        json['worker_removal_policy'],
        'least_busy',
      ),
      retryPolicy: _nonEmpty(json['retry_policy'], 'bounded_retry'),
      maxRetries: clampedIntFromValue(
        json['max_retries'],
        fallback: 2,
        min: 0,
        max: 20,
      ),
      schedulerPolicy: _nonEmpty(json['scheduler_policy'], 'least_busy'),
      tags: stringListFromValue(json['tags']),
    );
  }

  final int minWorkers;
  final int maxWorkers;
  final double scaleOutThreshold;
  final double scaleInThreshold;
  final String workerRemovalPolicy;
  final String retryPolicy;
  final int maxRetries;
  final String schedulerPolicy;
  final List<String> tags;

  AgentScaleSettings copyWith({
    int? minWorkers,
    int? maxWorkers,
    double? scaleOutThreshold,
    double? scaleInThreshold,
    String? workerRemovalPolicy,
    String? retryPolicy,
    int? maxRetries,
    String? schedulerPolicy,
    List<String>? tags,
  }) {
    final nextMin = minWorkers ?? this.minWorkers;
    final nextMax = maxWorkers ?? this.maxWorkers;
    return AgentScaleSettings(
      minWorkers: nextMin > nextMax ? nextMax : nextMin,
      maxWorkers: nextMax < 1 ? 1 : nextMax,
      scaleOutThreshold: scaleOutThreshold ?? this.scaleOutThreshold,
      scaleInThreshold: scaleInThreshold ?? this.scaleInThreshold,
      workerRemovalPolicy: workerRemovalPolicy ?? this.workerRemovalPolicy,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      maxRetries: maxRetries ?? this.maxRetries,
      schedulerPolicy: schedulerPolicy ?? this.schedulerPolicy,
      tags: tags ?? this.tags,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'min_workers': minWorkers,
      'max_workers': maxWorkers,
      'scale_out_threshold': scaleOutThreshold,
      'scale_in_threshold': scaleInThreshold,
      'worker_removal_policy': workerRemovalPolicy,
      'retry_policy': retryPolicy,
      'max_retries': maxRetries,
      'scheduler_policy': schedulerPolicy,
      'tags': tags,
    };
  }
}

class AgentResourceUsage {
  const AgentResourceUsage({
    this.cpuPercent = 0,
    this.memoryBytes = 0,
    this.diskBytes = 0,
    this.persistedBytes = 0,
    this.tokenBudget = 0,
    this.tokenUsed = 0,
    this.openHandles = 0,
    this.extra = const <String, Object?>{},
  });

  factory AgentResourceUsage.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AgentResourceUsage(
      cpuPercent: _ratioFromValue(json['cpu_percent'], fallback: 0),
      memoryBytes: nonNegativeIntFromValue(json['memory_bytes'], fallback: 0),
      diskBytes: nonNegativeIntFromValue(json['disk_bytes'], fallback: 0),
      persistedBytes: nonNegativeIntFromValue(
        json['persisted_bytes'],
        fallback: 0,
      ),
      tokenBudget: nonNegativeIntFromValue(json['token_budget'], fallback: 0),
      tokenUsed: nonNegativeIntFromValue(json['token_used'], fallback: 0),
      openHandles: nonNegativeIntFromValue(json['open_handles'], fallback: 0),
      extra: stringKeyedMapFromValue(json['extra']),
    );
  }

  final double cpuPercent;
  final int memoryBytes;
  final int diskBytes;
  final int persistedBytes;
  final int tokenBudget;
  final int tokenUsed;
  final int openHandles;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'cpu_percent': cpuPercent,
      'memory_bytes': memoryBytes,
      'disk_bytes': diskBytes,
      'persisted_bytes': persistedBytes,
      'token_budget': tokenBudget,
      'token_used': tokenUsed,
      'open_handles': openHandles,
      'extra': extra,
    };
  }
}

class AgentTask {
  const AgentTask({
    required this.id,
    required this.title,
    this.description = '',
    this.content = '',
    this.progress = 0,
    this.result = '',
    this.status = AgentTaskStatus.backlog,
    this.note = '',
    this.extra = const <String, Object?>{},
    this.createdAt,
    this.updatedAt,
  });

  factory AgentTask.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    final now = DateTime.now().toUtc();
    return AgentTask(
      id: _nonEmpty(json['id'], ''),
      title: _nonEmpty(json['title'], 'Untitled task'),
      description: stringFromValue(json['description']),
      content: stringFromValue(json['content']),
      progress: _ratioFromValue(json['progress'], fallback: 0),
      result: stringFromValue(json['result']),
      status: AgentTaskStatus.fromStorage(stringFromValue(json['status'])),
      note: stringFromValue(json['note']),
      extra: stringKeyedMapFromValue(json['extra']),
      createdAt: _dateFromValue(json['created_at']) ?? now,
      updatedAt: _dateFromValue(json['updated_at']),
    );
  }

  final String id;
  final String title;
  final String description;
  final String content;
  final double progress;
  final String result;
  final AgentTaskStatus status;
  final String note;
  final Map<String, Object?> extra;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AgentTask copyWith({
    String? id,
    String? title,
    String? description,
    String? content,
    double? progress,
    String? result,
    AgentTaskStatus? status,
    String? note,
    Map<String, Object?>? extra,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AgentTask(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      content: content ?? this.content,
      progress: progress ?? this.progress,
      result: result ?? this.result,
      status: status ?? this.status,
      note: note ?? this.note,
      extra: extra ?? this.extra,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'description': description,
      'content': content,
      'progress': progress,
      'result': result,
      'status': status.storageValue,
      'note': note,
      'extra': extra,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
    };
  }
}

class AgentApprovalRequest {
  const AgentApprovalRequest({
    required this.id,
    required this.title,
    this.reason = '',
    this.requestedAction = '',
    this.status = AgentApprovalStatus.pending,
    this.createdAt,
    this.resolvedAt,
    this.extra = const <String, Object?>{},
  });

  factory AgentApprovalRequest.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AgentApprovalRequest(
      id: _nonEmpty(json['id'], ''),
      title: _nonEmpty(json['title'], 'Approval request'),
      reason: stringFromValue(json['reason']),
      requestedAction: stringFromValue(json['requested_action']),
      status: AgentApprovalStatus.fromStorage(stringFromValue(json['status'])),
      createdAt: _dateFromValue(json['created_at']),
      resolvedAt: _dateFromValue(json['resolved_at']),
      extra: stringKeyedMapFromValue(json['extra']),
    );
  }

  final String id;
  final String title;
  final String reason;
  final String requestedAction;
  final AgentApprovalStatus status;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final Map<String, Object?> extra;

  AgentApprovalRequest copyWith({
    String? id,
    String? title,
    String? reason,
    String? requestedAction,
    AgentApprovalStatus? status,
    DateTime? createdAt,
    DateTime? resolvedAt,
    Map<String, Object?>? extra,
  }) {
    return AgentApprovalRequest(
      id: id ?? this.id,
      title: title ?? this.title,
      reason: reason ?? this.reason,
      requestedAction: requestedAction ?? this.requestedAction,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      extra: extra ?? this.extra,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'reason': reason,
      'requested_action': requestedAction,
      'status': status.storageValue,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'resolved_at': resolvedAt?.toUtc().toIso8601String(),
      'extra': extra,
    };
  }
}

class AgentActivityEvent {
  const AgentActivityEvent({
    required this.id,
    required this.kind,
    required this.title,
    this.content = '',
    this.createdAt,
    this.metadata = const <String, Object?>{},
  });

  factory AgentActivityEvent.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AgentActivityEvent(
      id: _nonEmpty(json['id'], ''),
      kind: _nonEmpty(json['kind'], 'response'),
      title: _nonEmpty(json['title'], 'Activity'),
      content: stringFromValue(json['content']),
      createdAt: _dateFromValue(json['created_at']),
      metadata: stringKeyedMapFromValue(json['metadata']),
    );
  }

  final String id;
  final String kind;
  final String title;
  final String content;
  final DateTime? createdAt;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind,
      'title': title,
      'content': content,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'metadata': metadata,
    };
  }
}

class AgentAuditEvent {
  const AgentAuditEvent({
    required this.id,
    required this.kind,
    required this.summary,
    this.toolName = '',
    this.tokenUsage = 0,
    this.requestCount = 0,
    this.createdAt,
    this.metadata = const <String, Object?>{},
  });

  factory AgentAuditEvent.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AgentAuditEvent(
      id: _nonEmpty(json['id'], ''),
      kind: _nonEmpty(json['kind'], 'audit'),
      summary: _nonEmpty(json['summary'], ''),
      toolName: stringFromValue(json['tool_name']),
      tokenUsage: nonNegativeIntFromValue(json['token_usage'], fallback: 0),
      requestCount: nonNegativeIntFromValue(json['request_count'], fallback: 0),
      createdAt: _dateFromValue(json['created_at']),
      metadata: stringKeyedMapFromValue(json['metadata']),
    );
  }

  final String id;
  final String kind;
  final String summary;
  final String toolName;
  final int tokenUsage;
  final int requestCount;
  final DateTime? createdAt;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind,
      'summary': summary,
      'tool_name': toolName,
      'token_usage': tokenUsage,
      'request_count': requestCount,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'metadata': metadata,
    };
  }
}

class AgentKpiItem {
  const AgentKpiItem({
    required this.id,
    required this.name,
    this.target = '',
    this.progress = 0,
    this.status = 'tracking',
    this.plan = '',
    this.createdAt,
    this.updatedAt,
    this.extra = const <String, Object?>{},
  });

  factory AgentKpiItem.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AgentKpiItem(
      id: _nonEmpty(json['id'], ''),
      name: _nonEmpty(json['name'], 'KPI'),
      target: stringFromValue(json['target']),
      progress: _ratioFromValue(json['progress'], fallback: 0),
      status: _nonEmpty(json['status'], 'tracking'),
      plan: stringFromValue(json['plan']),
      createdAt: _dateFromValue(json['created_at']),
      updatedAt: _dateFromValue(json['updated_at']),
      extra: stringKeyedMapFromValue(json['extra']),
    );
  }

  final String id;
  final String name;
  final String target;
  final double progress;
  final String status;
  final String plan;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, Object?> extra;

  AgentKpiItem copyWith({
    String? id,
    String? name,
    String? target,
    double? progress,
    String? status,
    String? plan,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, Object?>? extra,
  }) {
    return AgentKpiItem(
      id: id ?? this.id,
      name: name ?? this.name,
      target: target ?? this.target,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      plan: plan ?? this.plan,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      extra: extra ?? this.extra,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'target': target,
      'progress': progress,
      'status': status,
      'plan': plan,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
      'extra': extra,
    };
  }
}

class AgentWorker {
  const AgentWorker({
    required this.id,
    this.name = '',
    this.status = AgentWorkerStatus.idle,
    this.executedTaskCount = 0,
    this.busyScore = 0,
    this.priority = 0,
    this.currentTaskId = '',
    this.labels = const <String>[],
    this.updatedAt,
    this.extra = const <String, Object?>{},
  });

  factory AgentWorker.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    return AgentWorker(
      id: _nonEmpty(json['id'], ''),
      name: stringFromValue(json['name']),
      status: AgentWorkerStatus.fromStorage(stringFromValue(json['status'])),
      executedTaskCount: nonNegativeIntFromValue(
        json['executed_task_count'],
        fallback: 0,
      ),
      busyScore: _ratioFromValue(json['busy_score'], fallback: 0),
      priority: clampedIntFromValue(
        json['priority'],
        fallback: 0,
        min: -1000,
        max: 1000,
      ),
      currentTaskId: stringFromValue(json['current_task_id']),
      labels: stringListFromValue(json['labels']),
      updatedAt: _dateFromValue(json['updated_at']),
      extra: stringKeyedMapFromValue(json['extra']),
    );
  }

  final String id;
  final String name;
  final AgentWorkerStatus status;
  final int executedTaskCount;
  final double busyScore;
  final int priority;
  final String currentTaskId;
  final List<String> labels;
  final DateTime? updatedAt;
  final Map<String, Object?> extra;

  AgentWorker copyWith({
    String? id,
    String? name,
    AgentWorkerStatus? status,
    int? executedTaskCount,
    double? busyScore,
    int? priority,
    String? currentTaskId,
    List<String>? labels,
    DateTime? updatedAt,
    Map<String, Object?>? extra,
  }) {
    return AgentWorker(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      executedTaskCount: executedTaskCount ?? this.executedTaskCount,
      busyScore: busyScore ?? this.busyScore,
      priority: priority ?? this.priority,
      currentTaskId: currentTaskId ?? this.currentTaskId,
      labels: labels ?? this.labels,
      updatedAt: updatedAt ?? this.updatedAt,
      extra: extra ?? this.extra,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'status': status.storageValue,
      'executed_task_count': executedTaskCount,
      'busy_score': busyScore,
      'priority': priority,
      'current_task_id': currentTaskId,
      'labels': labels,
      'updated_at': updatedAt?.toUtc().toIso8601String(),
      'extra': extra,
    };
  }
}

class AgentProfile {
  const AgentProfile({
    required this.id,
    required this.name,
    this.avatar = '',
    this.position = '',
    this.department = '',
    this.mentor = '',
    this.level = '',
    this.introduction = '',
    this.archive = '',
    this.routeFrontMatter = '',
    this.welcomeMessage = '',
    this.modelProviderConfigId,
    this.modelId,
    this.persona = '',
    this.responsibilityBoundary = '',
    this.skillNames = const <String>[],
    this.knowledgeSourceIds = const <String>[],
    this.memoryIds = const <String>[],
    this.taskLabels = const <String>[],
    this.mcpServerNames = const <String>[],
    this.builtinToolNames = const <String>[],
    this.workspacePath = '',
    this.workspaceScope = '',
    this.cronIds = const <String>[],
    this.hookIds = const <String>[],
    this.selfLearningEnabled = true,
    this.enabled = false,
    this.executionMode = AgentExecutionMode.normal,
    this.lifecycleState = AgentLifecycleState.stopped,
    this.scaleSettings = const AgentScaleSettings(),
    this.tasks = const <AgentTask>[],
    this.approvals = const <AgentApprovalRequest>[],
    this.activities = const <AgentActivityEvent>[],
    this.auditEvents = const <AgentAuditEvent>[],
    this.kpis = const <AgentKpiItem>[],
    this.workers = const <AgentWorker>[],
    this.resourceUsage = const AgentResourceUsage(),
    this.metadata = const <String, Object?>{},
    this.createdAt,
    this.updatedAt,
  });

  factory AgentProfile.fromJson(Object? raw) {
    final json = stringKeyedMapFromValue(raw);
    final now = DateTime.now().toUtc();
    return AgentProfile(
      id: _nonEmpty(json['id'], ''),
      name: _nonEmpty(json['name'], 'Unnamed Agent'),
      avatar: stringFromValue(json['avatar']),
      position: stringFromValue(json['position']),
      department: stringFromValue(json['department']),
      mentor: stringFromValue(json['mentor']),
      level: stringFromValue(json['level']),
      introduction: stringFromValue(json['introduction']),
      archive: stringFromValue(json['archive']),
      routeFrontMatter: stringFromValue(json['route_front_matter']),
      welcomeMessage: stringFromValue(json['welcome_message']),
      modelProviderConfigId: optionalStringFromValue(
        json['model_provider_config_id'],
      ),
      modelId: optionalStringFromValue(json['model_id']),
      persona: stringFromValue(json['persona']),
      responsibilityBoundary: stringFromValue(json['responsibility_boundary']),
      skillNames: stringListFromValue(json['skill_names']),
      knowledgeSourceIds: stringListFromValue(json['knowledge_source_ids']),
      memoryIds: stringListFromValue(json['memory_ids']),
      taskLabels: stringListFromValue(json['task_labels']),
      mcpServerNames: stringListFromValue(json['mcp_server_names']),
      builtinToolNames: stringListFromValue(json['builtin_tool_names']),
      workspacePath: stringFromValue(json['workspace_path']),
      workspaceScope: stringFromValue(json['workspace_scope']),
      cronIds: stringListFromValue(json['cron_ids']),
      hookIds: stringListFromValue(json['hook_ids']),
      selfLearningEnabled: boolFromValue(
        json['self_learning_enabled'],
        defaultValue: true,
      ),
      enabled: boolFromValue(json['enabled']),
      executionMode: AgentExecutionMode.fromStorage(
        stringFromValue(json['execution_mode']),
      ),
      lifecycleState: AgentLifecycleState.fromStorage(
        stringFromValue(json['lifecycle_state']),
      ),
      scaleSettings: AgentScaleSettings.fromJson(json['scale_settings']),
      tasks: _listFromValue(json['tasks'], AgentTask.fromJson),
      approvals: _listFromValue(
        json['approvals'],
        AgentApprovalRequest.fromJson,
      ),
      activities: _listFromValue(
        json['activities'],
        AgentActivityEvent.fromJson,
      ),
      auditEvents: _listFromValue(
        json['audit_events'],
        AgentAuditEvent.fromJson,
      ),
      kpis: _listFromValue(json['kpis'], AgentKpiItem.fromJson),
      workers: _listFromValue(json['workers'], AgentWorker.fromJson),
      resourceUsage: AgentResourceUsage.fromJson(json['resource_usage']),
      metadata: stringKeyedMapFromValue(json['metadata']),
      createdAt: _dateFromValue(json['created_at']) ?? now,
      updatedAt: _dateFromValue(json['updated_at']) ?? now,
    );
  }

  final String id;
  final String name;
  final String avatar;
  final String position;
  final String department;
  final String mentor;
  final String level;
  final String introduction;
  final String archive;
  final String routeFrontMatter;
  final String welcomeMessage;
  final String? modelProviderConfigId;
  final String? modelId;
  final String persona;
  final String responsibilityBoundary;
  final List<String> skillNames;
  final List<String> knowledgeSourceIds;
  final List<String> memoryIds;
  final List<String> taskLabels;
  final List<String> mcpServerNames;
  final List<String> builtinToolNames;
  final String workspacePath;
  final String workspaceScope;
  final List<String> cronIds;
  final List<String> hookIds;
  final bool selfLearningEnabled;
  final bool enabled;
  final AgentExecutionMode executionMode;
  final AgentLifecycleState lifecycleState;
  final AgentScaleSettings scaleSettings;
  final List<AgentTask> tasks;
  final List<AgentApprovalRequest> approvals;
  final List<AgentActivityEvent> activities;
  final List<AgentAuditEvent> auditEvents;
  final List<AgentKpiItem> kpis;
  final List<AgentWorker> workers;
  final AgentResourceUsage resourceUsage;
  final Map<String, Object?> metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get initials {
    final source = name.trim().isNotEmpty ? name.trim() : id.trim();
    if (source.isEmpty) return 'A';
    return source.characters.first.toUpperCase();
  }

  bool get isRunning =>
      enabled && lifecycleState == AgentLifecycleState.running;

  int get pendingApprovalCount => approvals
      .where((item) => item.status == AgentApprovalStatus.pending)
      .length;

  int get runningTaskCount =>
      tasks.where((item) => item.status == AgentTaskStatus.running).length;

  int get completedTaskCount =>
      tasks.where((item) => item.status == AgentTaskStatus.completed).length;

  double get workerUtilization {
    if (workers.isEmpty) return 0;
    final total = workers.fold<double>(
      0,
      (sum, worker) => sum + worker.busyScore,
    );
    return total / workers.length;
  }

  AgentProfile copyWith({
    String? id,
    String? name,
    String? avatar,
    String? position,
    String? department,
    String? mentor,
    String? level,
    String? introduction,
    String? archive,
    String? routeFrontMatter,
    String? welcomeMessage,
    String? modelProviderConfigId,
    String? modelId,
    String? persona,
    String? responsibilityBoundary,
    List<String>? skillNames,
    List<String>? knowledgeSourceIds,
    List<String>? memoryIds,
    List<String>? taskLabels,
    List<String>? mcpServerNames,
    List<String>? builtinToolNames,
    String? workspacePath,
    String? workspaceScope,
    List<String>? cronIds,
    List<String>? hookIds,
    bool? selfLearningEnabled,
    bool? enabled,
    AgentExecutionMode? executionMode,
    AgentLifecycleState? lifecycleState,
    AgentScaleSettings? scaleSettings,
    List<AgentTask>? tasks,
    List<AgentApprovalRequest>? approvals,
    List<AgentActivityEvent>? activities,
    List<AgentAuditEvent>? auditEvents,
    List<AgentKpiItem>? kpis,
    List<AgentWorker>? workers,
    AgentResourceUsage? resourceUsage,
    Map<String, Object?>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearModelProviderConfigId = false,
    bool clearModelId = false,
  }) {
    return AgentProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      position: position ?? this.position,
      department: department ?? this.department,
      mentor: mentor ?? this.mentor,
      level: level ?? this.level,
      introduction: introduction ?? this.introduction,
      archive: archive ?? this.archive,
      routeFrontMatter: routeFrontMatter ?? this.routeFrontMatter,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      modelProviderConfigId: clearModelProviderConfigId
          ? null
          : (modelProviderConfigId ?? this.modelProviderConfigId),
      modelId: clearModelId ? null : (modelId ?? this.modelId),
      persona: persona ?? this.persona,
      responsibilityBoundary:
          responsibilityBoundary ?? this.responsibilityBoundary,
      skillNames: skillNames ?? this.skillNames,
      knowledgeSourceIds: knowledgeSourceIds ?? this.knowledgeSourceIds,
      memoryIds: memoryIds ?? this.memoryIds,
      taskLabels: taskLabels ?? this.taskLabels,
      mcpServerNames: mcpServerNames ?? this.mcpServerNames,
      builtinToolNames: builtinToolNames ?? this.builtinToolNames,
      workspacePath: workspacePath ?? this.workspacePath,
      workspaceScope: workspaceScope ?? this.workspaceScope,
      cronIds: cronIds ?? this.cronIds,
      hookIds: hookIds ?? this.hookIds,
      selfLearningEnabled: selfLearningEnabled ?? this.selfLearningEnabled,
      enabled: enabled ?? this.enabled,
      executionMode: executionMode ?? this.executionMode,
      lifecycleState: lifecycleState ?? this.lifecycleState,
      scaleSettings: scaleSettings ?? this.scaleSettings,
      tasks: tasks ?? this.tasks,
      approvals: approvals ?? this.approvals,
      activities: activities ?? this.activities,
      auditEvents: auditEvents ?? this.auditEvents,
      kpis: kpis ?? this.kpis,
      workers: workers ?? this.workers,
      resourceUsage: resourceUsage ?? this.resourceUsage,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'avatar': avatar,
      'position': position,
      'department': department,
      'mentor': mentor,
      'level': level,
      'introduction': introduction,
      'archive': archive,
      'route_front_matter': routeFrontMatter,
      'welcome_message': welcomeMessage,
      'model_provider_config_id': modelProviderConfigId,
      'model_id': modelId,
      'persona': persona,
      'responsibility_boundary': responsibilityBoundary,
      'skill_names': skillNames,
      'knowledge_source_ids': knowledgeSourceIds,
      'memory_ids': memoryIds,
      'task_labels': taskLabels,
      'mcp_server_names': mcpServerNames,
      'builtin_tool_names': builtinToolNames,
      'workspace_path': workspacePath,
      'workspace_scope': workspaceScope,
      'cron_ids': cronIds,
      'hook_ids': hookIds,
      'self_learning_enabled': selfLearningEnabled,
      'enabled': enabled,
      'execution_mode': executionMode.storageValue,
      'lifecycle_state': lifecycleState.storageValue,
      'scale_settings': scaleSettings.toJson(),
      'tasks': tasks.map((item) => item.toJson()).toList(growable: false),
      'approvals': approvals
          .map((item) => item.toJson())
          .toList(growable: false),
      'activities': activities
          .map((item) => item.toJson())
          .toList(growable: false),
      'audit_events': auditEvents
          .map((item) => item.toJson())
          .toList(growable: false),
      'kpis': kpis.map((item) => item.toJson()).toList(growable: false),
      'workers': workers.map((item) => item.toJson()).toList(growable: false),
      'resource_usage': resourceUsage.toJson(),
      'metadata': metadata,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
    };
  }
}

List<T> _listFromValue<T>(Object? raw, T Function(Object? raw) parse) {
  if (raw is! List) return <T>[];
  return raw.map(parse).toList(growable: false);
}

DateTime? _dateFromValue(Object? raw) {
  return utcDateTimeFromValue(raw);
}

String _nonEmpty(Object? raw, String fallback) {
  final value = stringFromValue(raw).trim();
  return value.isEmpty ? fallback : value;
}

double _ratioFromValue(Object? raw, {required double fallback}) {
  final value = optionalDoubleFromValue(raw) ?? fallback;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}
