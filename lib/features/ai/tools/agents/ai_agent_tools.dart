import 'dart:convert';

import '../../../../shared/util/input_value_parsing.dart';
import '../../../agents/index.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

const int _agentTaskRecommendedPollMs = 1500;
const List<String> _agentTaskActiveTools = <String>[
  'AgentTaskPause',
  'AgentTaskCancel',
  'AgentTaskTerminate',
  'AgentTaskComplete',
];
const List<String> _agentTaskPausedTools = <String>[
  'AgentTaskResume',
  'AgentTaskCancel',
  'AgentTaskTerminate',
];
const List<String> _agentTaskBlockedTools = <String>[
  'AgentTaskCancel',
  'AgentTaskTerminate',
];
const Set<String> _agentKpiStatusValues = <String>{
  'tracking',
  'at_risk',
  'done',
  'paused',
};
const Set<String> _agentSchedulerPolicyValues = <String>{
  'least_busy',
  'priority_first',
  'round_robin',
};
const Set<String> _agentWorkerRemovalPolicyValues = <String>{
  'least_busy',
  'newest_first',
};
const Set<String> _agentRetryPolicyValues = <String>{'bounded_retry', 'none'};

enum _AgentToolOperation {
  list,
  detail,
  activityLog,
  auditReport,
  recordAudit,
  requestApproval,
  upsertKpi,
  updateResource,
  configureCluster,
  clusterStatus,
  listTasks,
  publishTask,
  trackTask,
  progressTask,
  cancelTask,
  pauseTask,
  terminateTask,
  resumeTask,
  completeTask,
  resultTask,
}

class AiAgentTool extends AiTool {
  AiAgentTool._({
    required AiBuiltinToolKind kind,
    required String name,
    required _AgentToolOperation operation,
    required AgentsControllerProvider agentsControllerProvider,
    required AgentPromptRenderer promptRenderer,
  }) : _kind = kind,
       _name = name,
       _operation = operation,
       _agentsControllerProvider = agentsControllerProvider,
       _promptRenderer = promptRenderer;

  static List<AiAgentTool> all({
    required AgentsControllerProvider agentsControllerProvider,
    AgentPromptRenderer? promptRenderer,
  }) {
    final renderer = promptRenderer ?? AgentPromptRenderer();
    return <AiAgentTool>[
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentList,
        name: 'AgentList',
        operation: _AgentToolOperation.list,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentDetail,
        name: 'AgentDetail',
        operation: _AgentToolOperation.detail,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentActivityLog,
        name: 'AgentActivityLog',
        operation: _AgentToolOperation.activityLog,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentAuditReport,
        name: 'AgentAuditReport',
        operation: _AgentToolOperation.auditReport,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentAuditRecord,
        name: 'AgentAuditRecord',
        operation: _AgentToolOperation.recordAudit,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentApprovalRequest,
        name: 'AgentApprovalRequest',
        operation: _AgentToolOperation.requestApproval,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentKpiUpsert,
        name: 'AgentKpiUpsert',
        operation: _AgentToolOperation.upsertKpi,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentResourceUpdate,
        name: 'AgentResourceUpdate',
        operation: _AgentToolOperation.updateResource,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentClusterConfigure,
        name: 'AgentClusterConfigure',
        operation: _AgentToolOperation.configureCluster,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentClusterStatus,
        name: 'AgentClusterStatus',
        operation: _AgentToolOperation.clusterStatus,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentTaskList,
        name: 'AgentTaskList',
        operation: _AgentToolOperation.listTasks,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentTaskPublish,
        name: 'AgentTaskPublish',
        operation: _AgentToolOperation.publishTask,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentTaskTrack,
        name: 'AgentTaskTrack',
        operation: _AgentToolOperation.trackTask,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentTaskProgress,
        name: 'AgentTaskProgress',
        operation: _AgentToolOperation.progressTask,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentTaskCancel,
        name: 'AgentTaskCancel',
        operation: _AgentToolOperation.cancelTask,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentTaskPause,
        name: 'AgentTaskPause',
        operation: _AgentToolOperation.pauseTask,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentTaskTerminate,
        name: 'AgentTaskTerminate',
        operation: _AgentToolOperation.terminateTask,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentTaskResume,
        name: 'AgentTaskResume',
        operation: _AgentToolOperation.resumeTask,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentTaskComplete,
        name: 'AgentTaskComplete',
        operation: _AgentToolOperation.completeTask,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
      AiAgentTool._(
        kind: AiBuiltinToolKind.agentTaskResult,
        name: 'AgentTaskResult',
        operation: _AgentToolOperation.resultTask,
        agentsControllerProvider: agentsControllerProvider,
        promptRenderer: renderer,
      ),
    ];
  }

  final AiBuiltinToolKind _kind;
  final String _name;
  final _AgentToolOperation _operation;
  final AgentsControllerProvider _agentsControllerProvider;
  final AgentPromptRenderer _promptRenderer;

  @override
  AiBuiltinToolKind get kind => _kind;

  @override
  List<String> get aliases => <String>[_name, _snakeName(_name)];

  @override
  bool get isDestructive {
    return switch (_operation) {
      _AgentToolOperation.publishTask ||
      _AgentToolOperation.recordAudit ||
      _AgentToolOperation.requestApproval ||
      _AgentToolOperation.upsertKpi ||
      _AgentToolOperation.updateResource ||
      _AgentToolOperation.configureCluster ||
      _AgentToolOperation.cancelTask ||
      _AgentToolOperation.pauseTask ||
      _AgentToolOperation.terminateTask ||
      _AgentToolOperation.resumeTask ||
      _AgentToolOperation.completeTask => true,
      _ => false,
    };
  }

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final stopwatch = Stopwatch()..start();
    final controller = _agentsControllerProvider();
    if (controller == null) {
      return AiToolUtils.invalidResult(
        _name,
        'Agents controller is not available in this session.',
      );
    }
    if (controller.enabledAgents.isEmpty) {
      return _noEnabledAgentsResult(controller);
    }

    try {
      return switch (_operation) {
        _AgentToolOperation.list => _list(controller, context, stopwatch),
        _AgentToolOperation.detail => await _detail(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.activityLog => _activityLog(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.auditReport => _auditReport(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.recordAudit => await _recordAudit(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.requestApproval => await _requestApproval(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.upsertKpi => await _upsertKpi(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.updateResource => await _updateResource(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.configureCluster => await _configureCluster(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.clusterStatus => _clusterStatus(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.listTasks => _listTasks(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.publishTask => await _publishTask(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.trackTask => _trackTask(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.progressTask => _progressTask(
          controller,
          context,
          stopwatch,
        ),
        _AgentToolOperation.cancelTask => await _setTaskStatus(
          controller,
          context,
          stopwatch,
          status: AgentTaskStatus.canceled,
          activityKind: 'task_canceled',
          activityTitle: 'task_canceled',
        ),
        _AgentToolOperation.pauseTask => await _setTaskStatus(
          controller,
          context,
          stopwatch,
          status: AgentTaskStatus.paused,
          activityKind: 'task_paused',
          activityTitle: 'task_paused',
        ),
        _AgentToolOperation.terminateTask => await _setTaskStatus(
          controller,
          context,
          stopwatch,
          status: AgentTaskStatus.failed,
          activityKind: 'task_terminated',
          activityTitle: 'task_terminated',
        ),
        _AgentToolOperation.resumeTask => await _setTaskStatus(
          controller,
          context,
          stopwatch,
          status: AgentTaskStatus.ready,
          activityKind: 'task_resumed',
          activityTitle: 'task_resumed',
        ),
        _AgentToolOperation.completeTask => await _setTaskStatus(
          controller,
          context,
          stopwatch,
          status: AgentTaskStatus.completed,
          activityKind: 'task_completed',
          activityTitle: 'task_completed',
        ),
        _AgentToolOperation.resultTask => _taskResult(
          controller,
          context,
          stopwatch,
        ),
      };
    } catch (error, stackTrace) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: _name,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: '$error\n$stackTrace',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: failure\nerror: $error',
      );
    }
  }

  AiToolExecutionResult _noEnabledAgentsResult(AgentsController controller) {
    final runtime = controller.runtimeAvailability;
    if (!runtime.canRun) {
      return AiToolUtils.invalidResult(
        _name,
        'Agent runtime is unavailable: ${runtime.blockingReason}',
      );
    }
    if (controller.agents.isEmpty) {
      return AiToolUtils.invalidResult(
        _name,
        'No agents are configured. Create and start an agent before using agent tools.',
      );
    }
    return AiToolUtils.invalidResult(
      _name,
      'No enabled agents are available. Start an agent before using agent tools.',
    );
  }

  AiToolExecutionResult _list(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) {
    final args = context.decodedArguments;
    final includeDisabled = boolFromValue(args['include_disabled']);
    final agents = includeDisabled
        ? controller.agents
        : controller.enabledAgents;
    final payload = <String, Object?>{
      'agents': agents.map(_agentSummaryJson).toList(growable: false),
      'count': agents.length,
      'include_disabled': includeDisabled,
    };
    return _success(
      payload,
      stopwatch,
      metadata: <String, Object?>{'action': 'list', 'count': agents.length},
    );
  }

  Future<AiToolExecutionResult> _detail(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) async {
    final args = context.decodedArguments;
    final includeDisabled = boolFromValue(args['include_disabled']);
    final resolution = _resolveAgent(
      controller,
      args,
      includeDisabled: includeDisabled,
    );
    if (resolution.error != null) return resolution.error!;
    final includeTasks = boolFromValue(
      args['include_tasks'],
      defaultValue: true,
    );
    final includeAudit = boolFromValue(args['include_audit']);
    final includeResources = boolFromValue(args['include_resources']);
    final includePrompt = boolFromValue(args['include_prompt']);
    final includePromptText = boolFromValue(args['include_prompt_text']);
    final promptSnapshot = includePrompt || includePromptText
        ? await _promptRenderer.render(agent: resolution.agent!)
        : null;
    final payload = <String, Object?>{
      'agent': _agentDetailJson(
        resolution.agent!,
        includeTasks: includeTasks,
        includeAudit: includeAudit,
        includeResources: includeResources,
      ),
      if (promptSnapshot != null)
        'agent_prompt': promptSnapshot.metadataJson(
          includePrompt: includePromptText,
        ),
    };
    return _success(
      payload,
      stopwatch,
      metadata: <String, Object?>{
        'action': 'detail',
        'agent_id': resolution.agent!.id,
      },
    );
  }

  AiToolExecutionResult _activityLog(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) {
    final args = context.decodedArguments;
    final includeDisabled = boolFromValue(args['include_disabled']);
    final resolution = _resolveAgent(
      controller,
      args,
      includeDisabled: includeDisabled,
    );
    if (resolution.error != null) return resolution.error!;
    final agent = resolution.agent!;
    final limit = clampedIntFromValue(
      args['limit'],
      fallback: 30,
      min: 1,
      max: 100,
    );
    final includeActivities = boolFromValue(
      args['include_activities'],
      defaultValue: true,
    );
    final includeAudit = boolFromValue(
      args['include_audit'],
      defaultValue: true,
    );
    final kind = _optionalText(args['kind'] ?? args['activity_kind']);
    final messageType = AgentActivityMessageType.fromStorage(
      _optionalText(args['message_type'] ?? args['activity_type']),
    );
    final toolName = _optionalText(args['tool_name'] ?? args['tool']);
    final taskId = _optionalText(args['task_id'] ?? args['id']);
    final workerId = _optionalText(args['worker_id']);

    final activities = includeActivities
        ? agent.activities
              .where(
                (event) => _activityMatches(
                  event,
                  kind: kind,
                  messageType: messageType,
                  toolName: toolName,
                  taskId: taskId,
                  workerId: workerId,
                ),
              )
              .take(limit)
              .toList(growable: false)
        : const <AgentActivityEvent>[];
    final auditEvents = includeAudit
        ? agent.auditEvents
              .where(
                (event) => _auditMatches(
                  event,
                  kind: kind,
                  toolName: toolName,
                  taskId: taskId,
                  workerId: workerId,
                ),
              )
              .take(limit)
              .toList(growable: false)
        : const <AgentAuditEvent>[];
    final payload = <String, Object?>{
      'agent': _agentSummaryJson(agent),
      'filters': <String, Object?>{
        'include_disabled': includeDisabled,
        'include_activities': includeActivities,
        'include_audit': includeAudit,
        'limit': limit,
        if (kind != null) 'kind': kind,
        if (messageType != null) 'message_type': messageType.storageValue,
        if (toolName != null) 'tool_name': toolName,
        if (taskId != null) 'task_id': taskId,
        if (workerId != null) 'worker_id': workerId,
      },
      'activities': activities
          .map(_activityEventSummaryJson)
          .toList(growable: false),
      'audit_events': auditEvents
          .map(_auditEventSummaryJson)
          .toList(growable: false),
      'activity_summary': _activitySummaryJson(activities),
      'audit_summary': _auditSummaryJson(auditEvents),
    };
    return _success(
      payload,
      stopwatch,
      metadata: <String, Object?>{
        'action': 'activity_log',
        'agent_id': agent.id,
        'activity_count': activities.length,
        'audit_count': auditEvents.length,
      },
    );
  }

  AiToolExecutionResult _clusterStatus(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) {
    final args = context.decodedArguments;
    final includeDisabled = boolFromValue(args['include_disabled']);
    final resolution = _resolveAgent(
      controller,
      args,
      includeDisabled: includeDisabled,
    );
    if (resolution.error != null) return resolution.error!;
    final agent = resolution.agent!;
    final workerId = _optionalText(args['worker_id']);
    final includeTasks = boolFromValue(
      args['include_tasks'],
      defaultValue: true,
    );
    final includeAudit = boolFromValue(
      args['include_audit'],
      defaultValue: true,
    );
    final limit = clampedIntFromValue(
      args['limit'],
      fallback: 20,
      min: 1,
      max: 100,
    );
    final workers = agent.workers
        .where((worker) => _workerMatches(worker, workerId))
        .toList(growable: false);
    final tasks = includeTasks
        ? agent.tasks
              .where((task) => _clusterTaskMatches(task, workerId: workerId))
              .take(limit)
              .toList(growable: false)
        : const <AgentTask>[];
    final clusterActivities = includeAudit
        ? agent.activities
              .where(_isClusterActivity)
              .where(
                (event) =>
                    _matchesMetadata(event.metadata, 'worker_id', workerId),
              )
              .take(limit)
              .toList(growable: false)
        : const <AgentActivityEvent>[];
    final clusterAuditEvents = includeAudit
        ? agent.auditEvents
              .where(_isClusterAuditEvent)
              .where(
                (event) =>
                    _matchesMetadata(event.metadata, 'worker_id', workerId),
              )
              .take(limit)
              .toList(growable: false)
        : const <AgentAuditEvent>[];

    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(agent),
        'filters': <String, Object?>{
          'include_disabled': includeDisabled,
          'include_tasks': includeTasks,
          'include_audit': includeAudit,
          'limit': limit,
          if (workerId != null) 'worker_id': workerId,
        },
        'scale_settings': agent.scaleSettings.toJson(),
        'worker_capacity': _workerCapacityJsonForAgent(agent),
        'queue_pressure': _queuePressureJson(agent),
        'workers': workers
            .map((worker) => _workerStatusJson(agent, worker))
            .toList(growable: false),
        if (workerId != null) 'worker': _workerSummaryById(agent, workerId),
        if (includeTasks)
          'tasks': tasks
              .map((task) => _taskJson(task, agent: agent))
              .toList(growable: false),
        if (includeTasks) 'task_metrics': _taskMetricsForTasksJson(tasks),
        if (includeAudit)
          'recent_cluster_activities': clusterActivities
              .map(_activityEventSummaryJson)
              .toList(growable: false),
        if (includeAudit)
          'recent_cluster_audit_events': clusterAuditEvents
              .map(_auditEventSummaryJson)
              .toList(growable: false),
        if (includeAudit)
          'cluster_activity_summary': _activitySummaryJson(clusterActivities),
        if (includeAudit)
          'cluster_audit_summary': _auditSummaryJson(clusterAuditEvents),
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': 'cluster_status',
        'agent_id': agent.id,
        'worker_count': workers.length,
      },
    );
  }

  Future<AiToolExecutionResult> _configureCluster(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) async {
    final args = context.decodedArguments;
    final resolution = _resolveAgent(controller, args);
    if (resolution.error != null) return resolution.error!;
    final agent = resolution.agent!;
    final previous = agent.scaleSettings;

    final schedulerPolicy = _optionalAllowedText(
      args,
      'scheduler_policy',
      _agentSchedulerPolicyValues,
    );
    if (schedulerPolicy == '') {
      return AiToolUtils.invalidResult(
        _name,
        'scheduler_policy must be one of: ${_agentSchedulerPolicyValues.join(', ')}.',
      );
    }
    final workerRemovalPolicy = _optionalAllowedText(
      args,
      'worker_removal_policy',
      _agentWorkerRemovalPolicyValues,
    );
    if (workerRemovalPolicy == '') {
      return AiToolUtils.invalidResult(
        _name,
        'worker_removal_policy must be one of: ${_agentWorkerRemovalPolicyValues.join(', ')}.',
      );
    }
    final retryPolicy = _optionalAllowedText(
      args,
      'retry_policy',
      _agentRetryPolicyValues,
    );
    if (retryPolicy == '') {
      return AiToolUtils.invalidResult(
        _name,
        'retry_policy must be one of: ${_agentRetryPolicyValues.join(', ')}.',
      );
    }

    final tags = _hasAnyArgument(args, const <String>['tags', 'labels'])
        ? stringListFromValueOrJsonText(args['tags'] ?? args['labels'])
        : previous.tags;
    final settings = AgentScaleSettings(
      minWorkers:
          optionalNonNegativeIntFromValue(args['min_workers']) ??
          previous.minWorkers,
      maxWorkers:
          optionalPositiveIntFromValue(args['max_workers']) ??
          previous.maxWorkers,
      scaleOutThreshold:
          _optionalRatio(args['scale_out_threshold']) ??
          previous.scaleOutThreshold,
      scaleInThreshold:
          _optionalRatio(args['scale_in_threshold']) ??
          previous.scaleInThreshold,
      workerRemovalPolicy: workerRemovalPolicy ?? previous.workerRemovalPolicy,
      retryPolicy: retryPolicy ?? previous.retryPolicy,
      maxRetries:
          optionalNonNegativeIntFromValue(args['max_retries']) ??
          previous.maxRetries,
      schedulerPolicy: schedulerPolicy ?? previous.schedulerPolicy,
      tags: tags,
    );
    final saved = await controller.saveScaleSettings(
      agent.id,
      settings,
      auditToolName: _name,
    );
    if (!saved) {
      return AiToolUtils.invalidResult(
        _name,
        'Failed to configure cluster. The agent may have been removed.',
      );
    }
    final currentAgent = controller.agentById(agent.id) ?? agent;
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(currentAgent),
        'scale_settings': currentAgent.scaleSettings.toJson(),
        'workers': currentAgent.workers
            .map((worker) => worker.toJson())
            .toList(growable: false),
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': 'cluster_configured',
        'agent_id': agent.id,
      },
    );
  }

  AiToolExecutionResult _auditReport(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) {
    final args = context.decodedArguments;
    final includeDisabled = boolFromValue(args['include_disabled']);
    final resolution = _resolveAgent(
      controller,
      args,
      includeDisabled: includeDisabled,
    );
    if (resolution.error != null) return resolution.error!;
    final agent = resolution.agent!;
    final taskId = _optionalText(args['task_id'] ?? args['id']);
    final workerId = _optionalText(args['worker_id']);
    final kind = _optionalText(args['kind'] ?? args['activity_kind']);
    final messageType = AgentActivityMessageType.fromStorage(
      _optionalText(args['message_type'] ?? args['activity_type']),
    );
    final toolName = _optionalText(args['tool_name'] ?? args['tool']);
    final limit = clampedIntFromValue(
      args['limit'],
      fallback: 20,
      min: 1,
      max: 100,
    );
    final tasks = agent.tasks
        .where(
          (task) => _taskMatchesReportFilter(
            task,
            taskId: taskId,
            workerId: workerId,
          ),
        )
        .toList(growable: false);
    final auditEvents = agent.auditEvents
        .where(
          (event) => _auditMatches(
            event,
            kind: kind,
            toolName: toolName,
            taskId: taskId,
            workerId: workerId,
          ),
        )
        .toList(growable: false);
    final activities = agent.activities
        .where(
          (event) => _activityMatches(
            event,
            kind: kind,
            messageType: messageType,
            toolName: toolName,
            taskId: taskId,
            workerId: workerId,
          ),
        )
        .toList(growable: false);
    final payload = <String, Object?>{
      'agent': _agentSummaryJson(agent),
      'filters': <String, Object?>{
        'include_disabled': includeDisabled,
        'limit': limit,
        if (taskId != null) 'task_id': taskId,
        if (workerId != null) 'worker_id': workerId,
        if (kind != null) 'kind': kind,
        if (messageType != null) 'message_type': messageType.storageValue,
        if (toolName != null) 'tool_name': toolName,
      },
      'task_metrics': _taskMetricsForTasksJson(tasks),
      'worker_capacity': _workerCapacityJsonForAgent(agent),
      if (workerId != null) 'worker': _workerSummaryById(agent, workerId),
      'kpi_summary': _kpiSummaryJson(agent.kpis),
      'kpi_state': agent.kpis
          .take(limit)
          .map((item) => item.toJson())
          .toList(growable: false),
      'approval_summary': _approvalSummaryJson(agent.approvals),
      'pending_approvals': agent.approvals
          .where((item) => item.status == AgentApprovalStatus.pending)
          .take(limit)
          .map((item) => item.toJson())
          .toList(growable: false),
      'resource_usage': _resourceUsageSummaryJson(agent.resourceUsage),
      'audit_summary': _auditSummaryJson(auditEvents),
      'capability_usage': _capabilityUsageJson(auditEvents, limit: limit),
      'worker_execution': _workerExecutionReportJson(
        agent,
        tasks,
        auditEvents,
        limit: limit,
      ),
      'load_summary': _loadSummaryJson(agent),
      'recent_audit_events': auditEvents
          .take(limit)
          .map(_auditEventSummaryJson)
          .toList(growable: false),
      'activity_summary': _activitySummaryJson(activities),
      'recent_activities': activities
          .take(limit)
          .map(_activityEventSummaryJson)
          .toList(growable: false),
      'tasks': tasks
          .take(limit)
          .map((task) => _taskJson(task, agent: agent))
          .toList(growable: false),
    };
    return _success(
      payload,
      stopwatch,
      metadata: <String, Object?>{
        'action': 'audit_report',
        'agent_id': agent.id,
        'task_count': tasks.length,
        'audit_count': auditEvents.length,
      },
    );
  }

  Future<AiToolExecutionResult> _recordAudit(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) async {
    final args = context.decodedArguments;
    final resolution = _resolveAgent(controller, args);
    if (resolution.error != null) return resolution.error!;
    final summary = _optionalText(args['summary']);
    if (summary == null) {
      return AiToolUtils.invalidResult(_name, 'summary is required.');
    }
    final rawMetadata = optionalStringKeyedMapFromValueOrJsonText(
      args['metadata'] ?? args['extra'],
    );
    final metadata = <String, Object?>{
      if (rawMetadata != null) ...rawMetadata,
      if (_optionalText(args['task_id']) case final taskId?) 'task_id': taskId,
      if (_optionalText(args['worker_id']) case final workerId?)
        'worker_id': workerId,
      'recorded_by_session_id': context.sessionId,
    };
    final event = await controller.recordAuditEvent(
      resolution.agent!.id,
      kind: _optionalText(args['kind']) ?? 'capability_used',
      summary: summary,
      toolName: _optionalText(args['tool_name'] ?? args['tool']) ?? '',
      tokenUsage: optionalNonNegativeIntFromValue(args['token_usage']) ?? 0,
      requestCount: optionalNonNegativeIntFromValue(args['request_count']) ?? 0,
      metadata: metadata,
      auditToolName: _name,
    );
    if (event == null) {
      return AiToolUtils.invalidResult(
        _name,
        'Failed to record audit event. The agent may have been removed.',
      );
    }
    final currentAgent = controller.agentById(resolution.agent!.id);
    final auditEvents = currentAgent?.auditEvents ?? <AgentAuditEvent>[event];
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(currentAgent ?? resolution.agent!),
        'audit_event': event.toJson(),
        'audit_summary': _auditSummaryJson(auditEvents),
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': 'audit_recorded',
        'agent_id': resolution.agent!.id,
        'audit_id': event.id,
      },
    );
  }

  Future<AiToolExecutionResult> _updateResource(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) async {
    final args = context.decodedArguments;
    final resolution = _resolveAgent(controller, args);
    if (resolution.error != null) return resolution.error!;
    final agent = resolution.agent!;
    final previous = agent.resourceUsage;
    final rawExtra = optionalStringKeyedMapFromValueOrJsonText(args['extra']);
    final usage = AgentResourceUsage(
      cpuPercent: _optionalRatio(args['cpu_percent']) ?? previous.cpuPercent,
      memoryBytes:
          optionalIntFromValue(args['memory_bytes']) ?? previous.memoryBytes,
      diskBytes: optionalIntFromValue(args['disk_bytes']) ?? previous.diskBytes,
      persistedBytes:
          optionalIntFromValue(args['persisted_bytes']) ??
          previous.persistedBytes,
      tokenBudget:
          optionalIntFromValue(args['token_budget']) ?? previous.tokenBudget,
      tokenUsed: optionalIntFromValue(args['token_used']) ?? previous.tokenUsed,
      openHandles:
          optionalIntFromValue(args['open_handles']) ?? previous.openHandles,
      extra: <String, Object?>{
        ...previous.extra,
        if (rawExtra != null) ...rawExtra,
        'updated_by_session_id': context.sessionId,
      },
    );
    final saved = await controller.saveResourceUsage(
      agent.id,
      usage,
      auditToolName: _name,
    );
    if (!saved) {
      return AiToolUtils.invalidResult(
        _name,
        'Failed to update resource usage. The agent may have been removed.',
      );
    }
    final currentAgent = controller.agentById(agent.id) ?? agent;
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(currentAgent),
        'resource_usage': currentAgent.resourceUsage.toJson(),
        'resource_summary': _resourceUsageSummaryJson(
          currentAgent.resourceUsage,
        ),
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': 'resource_updated',
        'agent_id': agent.id,
      },
    );
  }

  Future<AiToolExecutionResult> _upsertKpi(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) async {
    final args = context.decodedArguments;
    final kpiId = '${args['kpi_id'] ?? args['id'] ?? ''}'.trim();
    final name = '${args['name'] ?? args['title'] ?? ''}'.trim();
    final labels = stringListFromValueOrJsonText(
      args['labels'] ?? args['tags'],
    );
    final resolution = _resolveKpiAgent(
      controller,
      args,
      name: name,
      labels: labels,
    );
    if (resolution.error != null) return resolution.error!;

    final agent = resolution.agent!;
    final existing = kpiId.isNotEmpty
        ? _findAgentKpi(agent, kpiId)
        : _findAgentKpiByName(agent, name);
    if (kpiId.isNotEmpty && existing == null) {
      return AiToolUtils.invalidResult(
        _name,
        'No KPI "$kpiId" was found for agent "${agent.name}".',
      );
    }

    final resolvedName = name.isNotEmpty ? name : existing?.name.trim() ?? '';
    if (resolvedName.isEmpty) {
      return AiToolUtils.invalidResult(
        _name,
        'name is required when creating a KPI.',
      );
    }

    final rawStatus = _optionalText(args['status']);
    final status = rawStatus == null
        ? (existing?.status.trim().isNotEmpty == true
              ? existing!.status.trim()
              : 'tracking')
        : _normalizedKpiStatus(rawStatus);
    if (status == null) {
      return AiToolUtils.invalidResult(
        _name,
        'status must be one of: ${_agentKpiStatusValues.join(', ')}.',
      );
    }

    final rawExtra = optionalStringKeyedMapFromValueOrJsonText(args['extra']);
    final extra = <String, Object?>{
      if (existing != null) ...existing.extra,
      if (rawExtra != null) ...rawExtra,
      if (labels.isNotEmpty) 'labels': labels,
      'updated_by_session_id': context.sessionId,
      if (resolution.routeReason != null)
        'agent_route_reason': resolution.routeReason,
      if (resolution.routeScore != null)
        'agent_route_score': resolution.routeScore,
    };
    final draft = AgentKpiItem(
      id: existing?.id ?? kpiId,
      name: resolvedName,
      target: _optionalText(args['target']) ?? existing?.target ?? '',
      progress: _optionalRatio(args['progress']) ?? existing?.progress ?? 0,
      status: status,
      plan: _optionalText(args['plan']) ?? existing?.plan ?? '',
      createdAt: existing?.createdAt,
      extra: extra,
    );
    final saved = await controller.saveKpi(
      agent.id,
      draft,
      auditToolName: _name,
    );
    if (saved == null) {
      return AiToolUtils.invalidResult(
        _name,
        'Failed to save KPI. The agent may have been removed.',
      );
    }

    final currentAgent = controller.agentById(agent.id);
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(currentAgent ?? agent),
        'kpi': saved.toJson(),
        if (currentAgent != null)
          'kpi_state': currentAgent.kpis
              .map((item) => item.toJson())
              .toList(growable: false),
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': existing == null ? 'kpi_created' : 'kpi_updated',
        'agent_id': agent.id,
        'kpi_id': saved.id,
      },
    );
  }

  Future<AiToolExecutionResult> _requestApproval(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) async {
    final args = context.decodedArguments;
    final title = '${args['title'] ?? ''}'.trim();
    if (title.isEmpty) {
      return AiToolUtils.invalidResult(_name, 'title is required.');
    }
    final labels = stringListFromValueOrJsonText(
      args['labels'] ?? args['tags'],
    );
    final resolution = _resolveApprovalAgent(
      controller,
      args,
      title: title,
      labels: labels,
    );
    if (resolution.error != null) return resolution.error!;
    final rawExtra = optionalStringKeyedMapFromValueOrJsonText(args['extra']);
    final approval = await controller.requestApproval(
      resolution.agent!.id,
      title: title,
      reason: '${args['reason'] ?? ''}'.trim(),
      requestedAction: '${args['requested_action'] ?? ''}'.trim(),
      extra: <String, Object?>{
        if (rawExtra != null) ...rawExtra,
        if (labels.isNotEmpty) 'labels': labels,
        'requested_by_session_id': context.sessionId,
        if (resolution.routeReason != null)
          'agent_route_reason': resolution.routeReason,
        if (resolution.routeScore != null)
          'agent_route_score': resolution.routeScore,
      },
      auditToolName: _name,
    );
    if (approval == null) {
      return AiToolUtils.invalidResult(
        _name,
        'Failed to request approval. The agent may have been disabled or removed.',
      );
    }
    final currentAgent = controller.agentById(resolution.agent!.id);
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(currentAgent ?? resolution.agent!),
        'approval': approval.toJson(),
        'pending_approvals': currentAgent?.pendingApprovalCount ?? 1,
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': 'request_approval',
        'agent_id': resolution.agent!.id,
        'approval_id': approval.id,
      },
    );
  }

  AiToolExecutionResult _listTasks(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) {
    final args = context.decodedArguments;
    final includeDisabled = boolFromValue(args['include_disabled']);
    final resolution = _resolveAgent(
      controller,
      args,
      includeDisabled: includeDisabled,
    );
    if (resolution.error != null) return resolution.error!;
    final agent = resolution.agent!;
    final statusFilter = _optionalTaskStatus(args['status']);
    if (statusFilter.invalid) {
      return AiToolUtils.invalidResult(
        _name,
        'status must be one of: ${AgentTaskStatus.values.map((item) => item.storageValue).join(', ')}.',
      );
    }
    final workerId = _optionalText(args['worker_id']);
    final labels = stringListFromValueOrJsonText(
      args['labels'] ?? args['tags'] ?? args['label'] ?? args['tag'],
    );
    final limit = clampedIntFromValue(
      args['limit'],
      fallback: 50,
      min: 1,
      max: 200,
    );
    final tasks = agent.tasks
        .where(
          (task) => _taskMatchesListFilter(
            task,
            status: statusFilter.status,
            workerId: workerId,
            labels: labels,
          ),
        )
        .take(limit)
        .toList(growable: false);
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(agent),
        'filters': <String, Object?>{
          'include_disabled': includeDisabled,
          'limit': limit,
          if (statusFilter.status != null)
            'status': statusFilter.status!.storageValue,
          if (workerId != null) 'worker_id': workerId,
          if (labels.isNotEmpty) 'labels': labels,
        },
        'tasks': tasks
            .map((task) => _taskJson(task, agent: agent))
            .toList(growable: false),
        'task_metrics': _taskMetricsJson(agent),
        'worker_capacity': _workerCapacityJsonForAgent(agent),
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': 'list_tasks',
        'agent_id': agent.id,
        'task_count': tasks.length,
      },
    );
  }

  Future<AiToolExecutionResult> _publishTask(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) async {
    final args = context.decodedArguments;
    final title = '${args['title'] ?? ''}'.trim();
    if (title.isEmpty) {
      return AiToolUtils.invalidResult(_name, 'title is required.');
    }
    final rawExtra = optionalStringKeyedMapFromValueOrJsonText(args['extra']);
    final labels = stringListFromValueOrJsonText(
      args['labels'] ?? args['tags'],
    );
    final resolution = _resolvePublishAgent(
      controller,
      args,
      title: title,
      labels: labels,
    );
    if (resolution.error != null) return resolution.error!;
    final promptSnapshot = await _promptRenderer.render(
      agent: resolution.agent!,
      taskContext: <String, Object?>{
        'incoming_task': <String, Object?>{
          'title': title,
          'description': '${args['description'] ?? ''}'.trim(),
          'content': '${args['content'] ?? ''}'.trim(),
          'note': '${args['note'] ?? ''}'.trim(),
          if (labels.isNotEmpty) 'labels': labels,
        },
        'published_by_session_id': context.sessionId,
      },
    );
    final task = await controller.publishTaskWithResult(
      resolution.agent!.id,
      title: title,
      description: '${args['description'] ?? ''}'.trim(),
      content: '${args['content'] ?? ''}'.trim(),
      note: '${args['note'] ?? ''}'.trim(),
      extra: <String, Object?>{
        if (rawExtra != null) ...rawExtra,
        if (labels.isNotEmpty) 'labels': labels,
        'published_by_session_id': context.sessionId,
        if (resolution.routeReason != null)
          'agent_route_reason': resolution.routeReason,
        if (resolution.routeScore != null)
          'agent_route_score': resolution.routeScore,
        'agent_prompt_snapshot': promptSnapshot.metadataJson(),
        'agent_system_prompt': promptSnapshot.renderedPrompt,
      },
      auditToolName: _name,
    );
    if (task == null) {
      return AiToolUtils.invalidResult(
        _name,
        'Failed to publish task. The agent may have been disabled or removed.',
      );
    }
    final currentAgent = controller.agentById(resolution.agent!.id);
    final payload = <String, Object?>{
      'agent': _agentSummaryJson(currentAgent ?? resolution.agent!),
      'task': _taskJson(task, agent: currentAgent),
      if (currentAgent != null)
        'operational_summary': _taskOperationalSummaryJson(currentAgent, task),
      'agent_prompt': promptSnapshot.metadataJson(),
    };
    return _success(
      payload,
      stopwatch,
      metadata: <String, Object?>{
        'action': 'publish_task',
        'agent_id': resolution.agent!.id,
        'task_id': task.id,
      },
    );
  }

  AiToolExecutionResult _trackTask(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) {
    final resolved = _resolveTask(controller, context.decodedArguments);
    if (resolved.error != null) return resolved.error!;
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(resolved.agent!),
        'task': _taskJson(resolved.task!, agent: resolved.agent),
        'operational_summary': _taskOperationalSummaryJson(
          resolved.agent!,
          resolved.task!,
        ),
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': 'track_task',
        'agent_id': resolved.agent!.id,
        'task_id': resolved.task!.id,
      },
    );
  }

  AiToolExecutionResult _progressTask(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) {
    final resolved = _resolveTask(controller, context.decodedArguments);
    if (resolved.error != null) return resolved.error!;
    final task = resolved.task!;
    final assignedWorker = _assignedWorkerJson(resolved.agent!, task);
    final state = _taskStateJson(task);
    return _success(
      <String, Object?>{
        'agent_id': resolved.agent!.id,
        'task_id': task.id,
        'status': task.status.storageValue,
        'progress': task.progress,
        'state': state,
        'result_available': _taskResultAvailable(task),
        if (_taskNextPollJson(task) case final nextPoll?) 'next_poll': nextPoll,
        if (assignedWorker != null) 'assigned_worker': assignedWorker,
        'operational_summary': _taskOperationalSummaryJson(
          resolved.agent!,
          task,
        ),
        'updated_at': _iso(task.updatedAt),
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': 'progress_task',
        'agent_id': resolved.agent!.id,
        'task_id': task.id,
      },
    );
  }

  Future<AiToolExecutionResult> _setTaskStatus(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch, {
    required AgentTaskStatus status,
    required String activityKind,
    required String activityTitle,
  }) async {
    final args = context.decodedArguments;
    final resolved = _resolveTask(controller, args);
    if (resolved.error != null) return resolved.error!;
    if (!_allowedTaskTools(resolved.task!.status).contains(_name)) {
      return AiToolUtils.invalidResult(
        _name,
        _taskStatusToolRejectedMessage(_name, resolved.task!),
      );
    }
    final explicitProgress = _optionalRatio(args['progress']);
    final nextProgress = switch (status) {
      AgentTaskStatus.completed => 1.0,
      AgentTaskStatus.canceled => explicitProgress ?? resolved.task!.progress,
      _ => explicitProgress,
    };
    final resultText = _optionalText(args['result']);
    if (status == AgentTaskStatus.completed && resultText == null) {
      return AiToolUtils.invalidResult(
        _name,
        'result is required when completing a task.',
      );
    }
    final rawExtra = optionalStringKeyedMapFromValueOrJsonText(args['extra']);
    final updated = await controller.updateTaskState(
      resolved.agent!.id,
      resolved.task!.id,
      status: status,
      progress: nextProgress,
      note: _optionalText(args['note']),
      result: resultText,
      extra: <String, Object?>{
        if (rawExtra != null) ...rawExtra,
        'updated_by_session_id': context.sessionId,
        'tool_action': activityKind,
      },
      activityKind: activityKind,
      activityTitle: activityTitle,
      auditToolName: _name,
    );
    if (updated == null) {
      return AiToolUtils.invalidResult(
        _name,
        'Failed to update task. The agent or task may have changed.',
      );
    }
    final currentAgent = controller.agentById(resolved.agent!.id);
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(currentAgent ?? resolved.agent!),
        'task': _taskJson(updated, agent: currentAgent),
        if (currentAgent != null)
          'operational_summary': _taskOperationalSummaryJson(
            currentAgent,
            updated,
          ),
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': activityKind,
        'agent_id': resolved.agent!.id,
        'task_id': updated.id,
      },
    );
  }

  AiToolExecutionResult _taskResult(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) {
    final resolved = _resolveTask(controller, context.decodedArguments);
    if (resolved.error != null) return resolved.error!;
    final task = resolved.task!;
    final assignedWorker = _assignedWorkerJson(resolved.agent!, task);
    final state = _taskStateJson(task);
    return _success(
      <String, Object?>{
        'agent_id': resolved.agent!.id,
        'task_id': task.id,
        'title': task.title,
        'status': task.status.storageValue,
        'progress': task.progress,
        'state': state,
        'result_available': _taskResultAvailable(task),
        'handoff': _taskHandoffJson(task),
        'result': task.result,
        'note': task.note,
        'extra': _taskExtraJson(task.extra),
        if (_taskNextPollJson(task) case final nextPoll?) 'next_poll': nextPoll,
        if (assignedWorker != null) 'assigned_worker': assignedWorker,
        'operational_summary': _taskOperationalSummaryJson(
          resolved.agent!,
          task,
        ),
        'updated_at': _iso(task.updatedAt),
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': 'task_result',
        'agent_id': resolved.agent!.id,
        'task_id': task.id,
      },
    );
  }

  _AgentResolution _resolveAgent(
    AgentsController controller,
    Map<String, Object?> args, {
    bool includeDisabled = false,
  }) {
    final identifier =
        '${args['agent_id'] ?? args['agent_name'] ?? args['agent'] ?? ''}'
            .trim();
    if (identifier.isEmpty) {
      return _AgentResolution.error(
        AiToolUtils.invalidResult(
          _name,
          'agent_id, agent_name, or agent is required.',
        ),
      );
    }
    final agent = controller.findAgent(
      identifier,
      includeDisabled: includeDisabled,
    );
    if (agent != null) return _AgentResolution.agent(agent);
    final disabled = controller.findAgent(identifier, includeDisabled: true);
    if (disabled != null && !disabled.enabled) {
      return _AgentResolution.error(
        AiToolUtils.invalidResult(
          _name,
          'Agent "$identifier" is disabled. Start the agent before using it.',
        ),
      );
    }
    return _AgentResolution.error(
      AiToolUtils.invalidResult(
        _name,
        'No enabled agent matched "$identifier".',
      ),
    );
  }

  _AgentResolution _resolveKpiAgent(
    AgentsController controller,
    Map<String, Object?> args, {
    required String name,
    required List<String> labels,
  }) {
    final identifier =
        '${args['agent_id'] ?? args['agent_name'] ?? args['agent'] ?? ''}'
            .trim();
    if (identifier.isNotEmpty) return _resolveAgent(controller, args);

    final candidates = controller.enabledAgents;
    if (candidates.length == 1) {
      return _AgentResolution.agent(
        candidates.single,
        routeReason: 'single_enabled_agent',
        routeScore: 0,
      );
    }
    final routed = _routeAgentForTask(
      candidates,
      title: name,
      description: '${args['target'] ?? ''}',
      content: '${args['plan'] ?? ''}',
      note: '${args['status'] ?? ''}',
      labels: labels,
    );
    if (routed != null) {
      return _AgentResolution.agent(
        routed.agent,
        routeReason: routed.reason,
        routeScore: routed.score,
      );
    }
    return _AgentResolution.error(
      AiToolUtils.invalidResult(
        _name,
        'agent_id, agent_name, or a routable KPI context is required. Use AgentList or AgentDetail before saving KPI when multiple agents are enabled.',
      ),
    );
  }

  _AgentResolution _resolveApprovalAgent(
    AgentsController controller,
    Map<String, Object?> args, {
    required String title,
    required List<String> labels,
  }) {
    final identifier =
        '${args['agent_id'] ?? args['agent_name'] ?? args['agent'] ?? ''}'
            .trim();
    if (identifier.isNotEmpty) return _resolveAgent(controller, args);

    final candidates = controller.enabledAgents;
    if (candidates.length == 1) {
      return _AgentResolution.agent(
        candidates.single,
        routeReason: 'single_enabled_agent',
        routeScore: 0,
      );
    }
    final routed = _routeAgentForTask(
      candidates,
      title: title,
      description: '${args['reason'] ?? ''}',
      content: '${args['requested_action'] ?? ''}',
      note: '',
      labels: labels,
    );
    if (routed != null) {
      return _AgentResolution.agent(
        routed.agent,
        routeReason: routed.reason,
        routeScore: routed.score,
      );
    }
    return _AgentResolution.error(
      AiToolUtils.invalidResult(
        _name,
        'agent_id, agent_name, or a routable approval context is required. Use AgentList or AgentDetail before requesting approval when multiple agents are enabled.',
      ),
    );
  }

  _AgentResolution _resolvePublishAgent(
    AgentsController controller,
    Map<String, Object?> args, {
    required String title,
    required List<String> labels,
  }) {
    final identifier =
        '${args['agent_id'] ?? args['agent_name'] ?? args['agent'] ?? ''}'
            .trim();
    if (identifier.isNotEmpty) return _resolveAgent(controller, args);

    final candidates = controller.enabledAgents;
    if (candidates.length == 1) {
      return _AgentResolution.agent(
        candidates.single,
        routeReason: 'single_enabled_agent',
        routeScore: 0,
      );
    }
    final routed = _routeAgentForTask(
      candidates,
      title: title,
      description: '${args['description'] ?? ''}',
      content: '${args['content'] ?? ''}',
      note: '${args['note'] ?? ''}',
      labels: labels,
    );
    if (routed != null) {
      return _AgentResolution.agent(
        routed.agent,
        routeReason: routed.reason,
        routeScore: routed.score,
      );
    }
    return _AgentResolution.error(
      AiToolUtils.invalidResult(
        _name,
        'agent_id, agent_name, or a routable task context is required. Use AgentList or AgentDetail before publishing when multiple agents are enabled.',
      ),
    );
  }

  _AgentRouteMatch? _routeAgentForTask(
    List<AgentProfile> agents, {
    required String title,
    required String description,
    required String content,
    required String note,
    required List<String> labels,
  }) {
    _AgentRouteMatch? best;
    var tied = false;
    for (final agent in agents) {
      final match = _scoreAgentRoute(
        agent,
        title: title,
        description: description,
        content: content,
        note: note,
        labels: labels,
      );
      if (match == null) continue;
      if (best == null || match.score > best.score) {
        best = match;
        tied = false;
      } else if (match.score == best.score) {
        tied = true;
      }
    }
    if (best == null || best.score < 4 || tied) return null;
    return best;
  }

  _AgentRouteMatch? _scoreAgentRoute(
    AgentProfile agent, {
    required String title,
    required String description,
    required String content,
    required String note,
    required List<String> labels,
  }) {
    final routing = AgentRoutingMetadata.fromAgent(agent);
    final taskText = _normalizeRouteText(
      <String>[title, description, content, note, ...labels].join(' '),
    );
    if (taskText.isEmpty) return null;

    var score = 0;
    final reasons = <String>[];
    void addSignal(String label, Iterable<String> values, int weight) {
      for (final value in values) {
        final normalized = _normalizeRouteText(value);
        if (normalized.isEmpty) continue;
        if (taskText.contains(normalized)) {
          score += weight;
          reasons.add('$label:$value');
        }
      }
    }

    addSignal('agent', <String>[agent.name], 10);
    addSignal('routing', routing.keywords, 8);
    addSignal('label', agent.taskLabels, 7);
    addSignal('skill', agent.skillNames, 6);
    addSignal('role', <String>[agent.position, agent.department], 4);
    addSignal('profile', <String>[
      agent.introduction,
      agent.responsibilityBoundary,
    ], 2);
    if (score <= 0) return null;
    return _AgentRouteMatch(
      agent: agent,
      score: score,
      reason: reasons.take(6).join(', '),
    );
  }

  _TaskResolution _resolveTask(
    AgentsController controller,
    Map<String, Object?> args,
  ) {
    final agentResolution = _resolveAgent(controller, args);
    if (agentResolution.error != null) {
      return _TaskResolution.error(agentResolution.error!);
    }
    final taskId = '${args['task_id'] ?? args['id'] ?? ''}'.trim();
    if (taskId.isEmpty) {
      return _TaskResolution.error(
        AiToolUtils.invalidResult(_name, 'task_id is required.'),
      );
    }
    final agent = agentResolution.agent!;
    final task = controller.taskById(agent.id, taskId);
    if (task == null) {
      return _TaskResolution.error(
        AiToolUtils.invalidResult(
          _name,
          'No task "$taskId" was found for agent "${agent.name}".',
        ),
      );
    }
    return _TaskResolution(agent: agent, task: task);
  }

  AiToolExecutionResult _success(
    Map<String, Object?> payload,
    Stopwatch stopwatch, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiToolUtils.simpleSuccessResult(
      command: _name,
      output: const JsonEncoder.withIndent('  ').convert(payload),
      durationMs: stopwatch.elapsedMilliseconds,
      metadata: <String, Object?>{'tool': _name, ...metadata},
    );
  }

  static String _snakeName(String value) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      final isUpper = code >= 0x41 && code <= 0x5A;
      if (isUpper && i > 0) buffer.write('_');
      buffer.writeCharCode(isUpper ? code | 0x20 : code);
    }
    return buffer.toString();
  }
}

class _AgentResolution {
  const _AgentResolution({
    this.agent,
    this.error,
    this.routeReason,
    this.routeScore,
  });

  factory _AgentResolution.agent(
    AgentProfile agent, {
    String? routeReason,
    int? routeScore,
  }) {
    return _AgentResolution(
      agent: agent,
      routeReason: routeReason,
      routeScore: routeScore,
    );
  }

  factory _AgentResolution.error(AiToolExecutionResult error) {
    return _AgentResolution(error: error);
  }

  final AgentProfile? agent;
  final AiToolExecutionResult? error;
  final String? routeReason;
  final int? routeScore;
}

class _TaskResolution {
  const _TaskResolution({this.agent, this.task, this.error});

  factory _TaskResolution.error(AiToolExecutionResult error) {
    return _TaskResolution(error: error);
  }

  final AgentProfile? agent;
  final AgentTask? task;
  final AiToolExecutionResult? error;
}

class _AgentRouteMatch {
  const _AgentRouteMatch({
    required this.agent,
    required this.score,
    required this.reason,
  });

  final AgentProfile agent;
  final int score;
  final String reason;
}

AgentKpiItem? _findAgentKpi(AgentProfile agent, String kpiId) {
  final normalized = kpiId.trim();
  if (normalized.isEmpty) return null;
  for (final item in agent.kpis) {
    if (item.id == normalized) return item;
  }
  return null;
}

AgentKpiItem? _findAgentKpiByName(AgentProfile agent, String name) {
  final normalized = name.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final item in agent.kpis) {
    if (item.name.trim().toLowerCase() == normalized) return item;
  }
  return null;
}

Map<String, Object?> _agentSummaryJson(AgentProfile agent) {
  final routing = AgentRoutingMetadata.fromAgent(agent);
  return <String, Object?>{
    'id': agent.id,
    'name': agent.name,
    'position': agent.position,
    'department': agent.department,
    'mentor': agent.mentor,
    'level': agent.level,
    'enabled': agent.enabled,
    'lifecycle_state': agent.lifecycleState.storageValue,
    'execution_mode': agent.executionMode.storageValue,
    'approval_policy': agent.approvalPolicy,
    'model_provider_config_id': agent.modelProviderConfigId,
    'model_id': agent.modelId,
    'task_counts': <String, Object?>{
      'total': agent.tasks.length,
      'running': agent.runningTaskCount,
      'completed': agent.completedTaskCount,
      'pending_approvals': agent.pendingApprovalCount,
    },
    'worker_count': agent.workers.length,
    'capabilities': agentCapabilityBindingsJson(agent),
    'workspace_policy': agentWorkspacePolicyJson(agent),
    'routing': routing.toJson(includeRawPreview: false),
    'updated_at': _iso(agent.updatedAt),
  };
}

Map<String, Object?> _agentDetailJson(
  AgentProfile agent, {
  required bool includeTasks,
  required bool includeAudit,
  required bool includeResources,
}) {
  return <String, Object?>{
    ..._agentSummaryJson(agent),
    'avatar': agent.avatar,
    'introduction': agent.introduction,
    'persona': agent.persona,
    'responsibility_boundary': agent.responsibilityBoundary,
    'workspace_path': agent.workspacePath,
    'workspace_scope': agent.workspaceScopeText,
    'workspace_scope_paths': agent.normalizedWorkspaceScopePaths,
    'workspace_policy': agentWorkspacePolicyJson(agent),
    'self_learning_enabled': agent.selfLearningEnabled,
    'routing': AgentRoutingMetadata.fromAgent(agent).toJson(),
    'task_labels': agent.taskLabels,
    'cron_ids': agent.cronIds,
    'hook_ids': agent.hookIds,
    'scale_settings': agent.scaleSettings.toJson(),
    'kpis': agent.kpis.map((item) => item.toJson()).toList(growable: false),
    'workers': agent.workers
        .map((item) => item.toJson())
        .toList(growable: false),
    'approvals': agent.approvals
        .map((item) => item.toJson())
        .toList(growable: false),
    'recent_activities': agent.activities
        .take(20)
        .map((item) => item.toJson())
        .toList(growable: false),
    if (includeTasks)
      'tasks': agent.tasks
          .map((task) => _taskJson(task, agent: agent))
          .toList(growable: false),
    if (includeAudit)
      'audit_events': agent.auditEvents
          .take(50)
          .map((item) => item.toJson())
          .toList(growable: false),
    if (includeResources) 'resource_usage': agent.resourceUsage.toJson(),
    'created_at': _iso(agent.createdAt),
  };
}

Map<String, Object?> _taskJson(AgentTask task, {AgentProfile? agent}) {
  final assignedWorker = agent == null
      ? null
      : _assignedWorkerJson(agent, task);
  return <String, Object?>{
    'id': task.id,
    'title': task.title,
    'description': task.description,
    'content': task.content,
    'status': task.status.storageValue,
    'progress': task.progress,
    'state': _taskStateJson(task),
    'result': task.result,
    'note': task.note,
    if (assignedWorker != null) 'assigned_worker': assignedWorker,
    'extra': _taskExtraJson(task.extra),
    'created_at': _iso(task.createdAt),
    'updated_at': _iso(task.updatedAt),
  };
}

Map<String, Object?> _taskStateJson(AgentTask task) {
  final terminal = _taskIsTerminal(task.status);
  final requiresAttention =
      task.status == AgentTaskStatus.waitingApproval ||
      task.status == AgentTaskStatus.paused ||
      task.status == AgentTaskStatus.failed;
  final needsPolling = !terminal && !requiresAttention;
  final terminalReason = _taskTerminalReason(task);
  return <String, Object?>{
    'terminal': terminal,
    'needs_polling': needsPolling,
    'requires_attention': requiresAttention,
    'next_action': _taskNextAction(task, needsPolling: needsPolling),
    'allowed_tools': _allowedTaskTools(task.status),
    if (_taskRetryJson(task) case final retry?) 'retry': retry,
    if (terminalReason != null) 'terminal_reason': terminalReason,
    if (needsPolling) 'recommended_poll_ms': _agentTaskRecommendedPollMs,
  };
}

bool _taskResultAvailable(AgentTask task) {
  return task.status == AgentTaskStatus.completed &&
      task.result.trim().isNotEmpty;
}

Map<String, Object?> _taskHandoffJson(AgentTask task) {
  final state = _taskStateJson(task);
  final resultAvailable = _taskResultAvailable(task);
  return <String, Object?>{
    'result_available': resultAvailable,
    'message': _taskHandoffMessage(task, resultAvailable: resultAvailable),
    'status': task.status.storageValue,
    'next_action': state['next_action'],
    'needs_polling': state['needs_polling'],
    'requires_attention': state['requires_attention'],
    'terminal': state['terminal'],
    'allowed_tools': state['allowed_tools'],
    if (state['retry'] != null) 'retry': state['retry'],
    if (state['terminal_reason'] != null)
      'terminal_reason': state['terminal_reason'],
    if (resultAvailable) 'result': task.result,
    if (task.note.trim().isNotEmpty) 'note': task.note,
    if (_taskNextPollJson(task) case final nextPoll?) 'next_poll': nextPoll,
  };
}

Map<String, Object?>? _taskRetryJson(AgentTask task) {
  final retryCount = nonNegativeIntFromValue(
    task.extra['retry_count'],
    fallback: 0,
  );
  if (retryCount <= 0) return null;
  final lastFailureResult = '${task.extra['last_failure_result'] ?? ''}'.trim();
  final lastFailureNote = '${task.extra['last_failure_note'] ?? ''}'.trim();
  return <String, Object?>{
    'retry_count': retryCount,
    if (task.extra['last_retry_at'] != null)
      'last_retry_at': '${task.extra['last_retry_at']}',
    if (lastFailureResult.isNotEmpty) 'last_failure_result': lastFailureResult,
    if (lastFailureNote.isNotEmpty) 'last_failure_note': lastFailureNote,
  };
}

String _taskHandoffMessage(AgentTask task, {required bool resultAvailable}) {
  if (resultAvailable) return 'result_ready';
  if (!_taskIsTerminal(task.status)) {
    return switch (task.status) {
      AgentTaskStatus.waitingApproval => 'waiting_for_approval',
      AgentTaskStatus.paused => 'paused_requires_resume_or_cancel',
      AgentTaskStatus.backlog ||
      AgentTaskStatus.ready ||
      AgentTaskStatus.running => 'result_not_ready_poll',
      AgentTaskStatus.completed ||
      AgentTaskStatus.failed ||
      AgentTaskStatus.canceled => 'result_not_available',
    };
  }
  return switch (task.status) {
    AgentTaskStatus.completed => 'completed_without_result',
    AgentTaskStatus.failed =>
      _taskTerminalReason(task) == 'terminated'
          ? 'terminated_without_result'
          : 'failed_without_result',
    AgentTaskStatus.canceled => 'canceled_without_result',
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running ||
    AgentTaskStatus.waitingApproval ||
    AgentTaskStatus.paused => 'result_not_available',
  };
}

Map<String, Object?>? _taskNextPollJson(AgentTask task) {
  if (_taskIsTerminal(task.status) ||
      task.status == AgentTaskStatus.waitingApproval ||
      task.status == AgentTaskStatus.paused) {
    return null;
  }
  return const <String, Object?>{
    'tool': 'AgentTaskProgress',
    'result_tool': 'AgentTaskResult',
    'recommended_poll_ms': _agentTaskRecommendedPollMs,
  };
}

String _taskNextAction(AgentTask task, {required bool needsPolling}) {
  if (needsPolling) return 'poll';
  return switch (task.status) {
    AgentTaskStatus.waitingApproval => 'review_approval',
    AgentTaskStatus.paused => 'resume_or_cancel',
    AgentTaskStatus.completed => 'read_result',
    AgentTaskStatus.failed =>
      _taskTerminalReason(task) == 'terminated' ? 'stop' : 'inspect_failure',
    AgentTaskStatus.canceled => 'stop',
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running => 'poll',
  };
}

String? _taskTerminalReason(AgentTask task) {
  return switch (task.status) {
    AgentTaskStatus.completed => 'completed',
    AgentTaskStatus.failed =>
      '${task.extra['tool_action'] ?? ''}'.trim() == 'task_terminated'
          ? 'terminated'
          : 'failed',
    AgentTaskStatus.canceled => 'canceled',
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running ||
    AgentTaskStatus.waitingApproval ||
    AgentTaskStatus.paused => null,
  };
}

List<String> _allowedTaskTools(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running => _agentTaskActiveTools,
    AgentTaskStatus.waitingApproval => _agentTaskBlockedTools,
    AgentTaskStatus.paused => _agentTaskPausedTools,
    AgentTaskStatus.completed ||
    AgentTaskStatus.failed ||
    AgentTaskStatus.canceled => const <String>[],
  };
}

String _taskStatusToolRejectedMessage(String toolName, AgentTask task) {
  final allowedTools = _allowedTaskTools(task.status);
  final allowedText = allowedTools.isEmpty ? 'none' : allowedTools.join(', ');
  return '$toolName is not allowed when task status is ${task.status.storageValue}. allowed_tools: $allowedText.';
}

bool _taskIsTerminal(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.completed ||
    AgentTaskStatus.failed ||
    AgentTaskStatus.canceled => true,
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running ||
    AgentTaskStatus.waitingApproval ||
    AgentTaskStatus.paused => false,
  };
}

bool _taskMatchesListFilter(
  AgentTask task, {
  required AgentTaskStatus? status,
  required String? workerId,
  required List<String> labels,
}) {
  if (status != null && task.status != status) return false;
  if (workerId != null &&
      !_matchesText('${task.extra['assigned_worker_id'] ?? ''}', workerId)) {
    return false;
  }
  if (labels.isNotEmpty) {
    final taskLabels = stringListFromValueOrJsonText(
      task.extra['labels'] ?? task.extra['tags'],
    ).map((item) => item.toLowerCase()).toSet();
    for (final label in labels) {
      if (!taskLabels.contains(label.toLowerCase())) return false;
    }
  }
  return true;
}

bool _taskMatchesReportFilter(
  AgentTask task, {
  required String? taskId,
  required String? workerId,
}) {
  if (taskId != null && !_matchesText(task.id, taskId)) return false;
  if (workerId != null &&
      !_matchesText('${task.extra['assigned_worker_id'] ?? ''}', workerId)) {
    return false;
  }
  return true;
}

Map<String, Object?>? _assignedWorkerJson(AgentProfile agent, AgentTask task) {
  final workerId = '${task.extra['assigned_worker_id'] ?? ''}'.trim();
  if (workerId.isEmpty) return null;
  for (final worker in agent.workers) {
    if (worker.id != workerId) continue;
    return <String, Object?>{
      'id': worker.id,
      'name': worker.name,
      'status': worker.status.storageValue,
      'executed_task_count': worker.executedTaskCount,
      'busy_score': worker.busyScore,
      'priority': worker.priority,
      'current_task_id': worker.currentTaskId,
      'labels': worker.labels,
      'updated_at': _iso(worker.updatedAt),
    };
  }
  return <String, Object?>{'id': workerId, 'missing': true};
}

Map<String, Object?> _taskOperationalSummaryJson(
  AgentProfile agent,
  AgentTask task,
) {
  final auditEvents = _auditEventsForTask(agent.auditEvents, task.id);
  return <String, Object?>{
    'task_metrics': _taskMetricsJson(agent),
    'worker_capacity': _workerCapacityJson(agent, task),
    'audit_summary': _auditSummaryJson(auditEvents),
    'resource_usage': _resourceUsageSummaryJson(agent.resourceUsage),
  };
}

Map<String, Object?> _taskMetricsJson(AgentProfile agent) {
  return _taskMetricsForTasksJson(agent.tasks);
}

Map<String, Object?> _taskMetricsForTasksJson(List<AgentTask> tasks) {
  final byStatus = <String, int>{
    for (final status in AgentTaskStatus.values) status.storageValue: 0,
  };
  for (final task in tasks) {
    byStatus[task.status.storageValue] =
        (byStatus[task.status.storageValue] ?? 0) + 1;
  }
  final total = tasks.length;
  final completed = byStatus[AgentTaskStatus.completed.storageValue] ?? 0;
  final failed = byStatus[AgentTaskStatus.failed.storageValue] ?? 0;
  final canceled = byStatus[AgentTaskStatus.canceled.storageValue] ?? 0;
  final terminal = completed + failed + canceled;
  return <String, Object?>{
    'total': total,
    'by_status': byStatus,
    'active': total - terminal,
    'terminal': terminal,
    'completed': completed,
    'completion_rate': total <= 0 ? 0 : completed / total,
  };
}

Map<String, Object?> _kpiSummaryJson(List<AgentKpiItem> items) {
  final byStatus = <String, int>{};
  var totalProgress = 0.0;
  for (final item in items) {
    final status = item.status.trim().isEmpty ? 'tracking' : item.status.trim();
    byStatus[status] = (byStatus[status] ?? 0) + 1;
    totalProgress += item.progress.clamp(0, 1).toDouble();
  }
  return <String, Object?>{
    'total': items.length,
    'by_status': byStatus,
    'at_risk': byStatus['at_risk'] ?? 0,
    'done': byStatus['done'] ?? 0,
    'average_progress': items.isEmpty ? 0 : totalProgress / items.length,
  };
}

Map<String, Object?> _approvalSummaryJson(List<AgentApprovalRequest> items) {
  final byStatus = <String, int>{
    for (final status in AgentApprovalStatus.values) status.storageValue: 0,
  };
  for (final item in items) {
    byStatus[item.status.storageValue] =
        (byStatus[item.status.storageValue] ?? 0) + 1;
  }
  return <String, Object?>{
    'total': items.length,
    'by_status': byStatus,
    'pending': byStatus[AgentApprovalStatus.pending.storageValue] ?? 0,
    'approved': byStatus[AgentApprovalStatus.approved.storageValue] ?? 0,
    'rejected': byStatus[AgentApprovalStatus.rejected.storageValue] ?? 0,
    'expired': byStatus[AgentApprovalStatus.expired.storageValue] ?? 0,
  };
}

Map<String, Object?> _workerCapacityJson(AgentProfile agent, AgentTask task) {
  final payload = _workerCapacityJsonForAgent(agent);
  final assignedWorkerId = '${task.extra['assigned_worker_id'] ?? ''}'.trim();
  final assignedWorker = assignedWorkerId.isEmpty
      ? null
      : _assignedWorkerJson(agent, task);
  return <String, Object?>{
    ...payload,
    if (assignedWorkerId.isNotEmpty) 'assigned_worker_id': assignedWorkerId,
    if (assignedWorker != null)
      'assigned_worker_status': assignedWorker['status'],
  };
}

Map<String, Object?> _workerCapacityJsonForAgent(AgentProfile agent) {
  final byStatus = <String, int>{
    for (final status in AgentWorkerStatus.values) status.storageValue: 0,
  };
  for (final worker in agent.workers) {
    byStatus[worker.status.storageValue] =
        (byStatus[worker.status.storageValue] ?? 0) + 1;
  }
  return <String, Object?>{
    'total': agent.workers.length,
    'by_status': byStatus,
    'idle': byStatus[AgentWorkerStatus.idle.storageValue] ?? 0,
    'busy': byStatus[AgentWorkerStatus.busy.storageValue] ?? 0,
    'draining': byStatus[AgentWorkerStatus.draining.storageValue] ?? 0,
    'offline': byStatus[AgentWorkerStatus.offline.storageValue] ?? 0,
    'utilization': agent.workerUtilization,
    'running_tasks': agent.runningTaskCount,
    'pending_approvals': agent.pendingApprovalCount,
  };
}

Map<String, Object?> _queuePressureJson(AgentProfile agent) {
  final backlog = agent.tasks
      .where((task) => task.status == AgentTaskStatus.backlog)
      .length;
  final ready = agent.tasks
      .where((task) => task.status == AgentTaskStatus.ready)
      .length;
  final running = agent.tasks
      .where((task) => task.status == AgentTaskStatus.running)
      .length;
  final blocked = agent.tasks
      .where(
        (task) =>
            task.status == AgentTaskStatus.waitingApproval ||
            task.status == AgentTaskStatus.paused,
      )
      .length;
  final idleWorkers = agent.workers
      .where((worker) => worker.status == AgentWorkerStatus.idle)
      .length;
  final busyWorkers = agent.workers
      .where((worker) => worker.status == AgentWorkerStatus.busy)
      .length;
  final canScaleOut = agent.workers.length < agent.scaleSettings.maxWorkers;
  final workersSaturated = agent.workers.isNotEmpty && idleWorkers == 0;
  final scaleOutRecommended =
      ready > idleWorkers &&
      canScaleOut &&
      (agent.workers.isEmpty ||
          agent.workerUtilization >= agent.scaleSettings.scaleOutThreshold);
  final canScaleIn =
      agent.workers.length > agent.scaleSettings.minWorkers &&
      ready == 0 &&
      running == 0 &&
      agent.workerUtilization <= agent.scaleSettings.scaleInThreshold;
  return <String, Object?>{
    'backlog_tasks': backlog,
    'ready_tasks': ready,
    'queued_tasks': backlog + ready,
    'running_tasks': running,
    'blocked_tasks': blocked,
    'pending_approvals': agent.pendingApprovalCount,
    'idle_workers': idleWorkers,
    'busy_workers': busyWorkers,
    'workers_saturated': workersSaturated,
    'can_scale_out': canScaleOut,
    'scale_out_recommended': scaleOutRecommended,
    'can_scale_in': canScaleIn,
    'scale_out_threshold': agent.scaleSettings.scaleOutThreshold,
    'scale_in_threshold': agent.scaleSettings.scaleInThreshold,
  };
}

Map<String, Object?>? _workerSummaryById(AgentProfile agent, String workerId) {
  for (final worker in agent.workers) {
    if (!_matchesText(worker.id, workerId)) continue;
    return <String, Object?>{
      'id': worker.id,
      'name': worker.name,
      'status': worker.status.storageValue,
      'executed_task_count': worker.executedTaskCount,
      'busy_score': worker.busyScore,
      'priority': worker.priority,
      'current_task_id': worker.currentTaskId,
      'labels': worker.labels,
      'updated_at': _iso(worker.updatedAt),
    };
  }
  return null;
}

Map<String, Object?> _workerStatusJson(AgentProfile agent, AgentWorker worker) {
  final currentTask = _workerCurrentTask(agent, worker);
  final assignedTasks = agent.tasks
      .where((task) => _taskAssignedToWorker(task, worker.id))
      .take(10)
      .map((task) => _taskJson(task, agent: agent))
      .toList(growable: false);
  return <String, Object?>{
    'id': worker.id,
    'name': worker.name,
    'status': worker.status.storageValue,
    'idle': worker.status == AgentWorkerStatus.idle,
    'executed_task_count': worker.executedTaskCount,
    'busy_score': worker.busyScore,
    'priority': worker.priority,
    'current_task_id': worker.currentTaskId,
    'labels': worker.labels,
    'updated_at': _iso(worker.updatedAt),
    'extra': worker.extra,
    if (currentTask != null)
      'current_task': _taskJson(currentTask, agent: agent),
    if (assignedTasks.isNotEmpty) 'assigned_tasks': assignedTasks,
  };
}

AgentTask? _workerCurrentTask(AgentProfile agent, AgentWorker worker) {
  final currentTaskId = worker.currentTaskId.trim();
  if (currentTaskId.isNotEmpty) {
    for (final task in agent.tasks) {
      if (task.id == currentTaskId) return task;
    }
  }
  for (final task in agent.tasks) {
    if (task.status == AgentTaskStatus.running &&
        _taskAssignedToWorker(task, worker.id)) {
      return task;
    }
  }
  return null;
}

bool _workerMatches(AgentWorker worker, String? workerId) {
  if (workerId == null) return true;
  return _matchesText(worker.id, workerId);
}

bool _clusterTaskMatches(AgentTask task, {required String? workerId}) {
  if (workerId != null && !_taskAssignedToWorker(task, workerId)) {
    return false;
  }
  return task.status == AgentTaskStatus.backlog ||
      task.status == AgentTaskStatus.ready ||
      task.status == AgentTaskStatus.running ||
      task.status == AgentTaskStatus.waitingApproval ||
      task.status == AgentTaskStatus.paused;
}

bool _taskAssignedToWorker(AgentTask task, String workerId) {
  return _matchesText('${task.extra['assigned_worker_id'] ?? ''}', workerId);
}

bool _isClusterActivity(AgentActivityEvent event) {
  return _isClusterEventKind(event.kind);
}

bool _isClusterAuditEvent(AgentAuditEvent event) {
  return _isClusterEventKind(event.kind);
}

bool _isClusterEventKind(String kind) {
  final normalized = kind.trim().toLowerCase();
  return normalized == 'cluster_updated' ||
      normalized == 'worker_scaled_out' ||
      normalized == 'worker_scaled_in' ||
      normalized == 'task_assigned' ||
      normalized == 'task_completed' ||
      normalized == 'task_canceled' ||
      normalized == 'task_paused' ||
      normalized == 'task_resumed' ||
      normalized == 'task_terminated';
}

List<AgentAuditEvent> _auditEventsForTask(
  List<AgentAuditEvent> events,
  String taskId,
) {
  return events
      .where((event) => '${event.metadata['task_id'] ?? ''}'.trim() == taskId)
      .toList(growable: false);
}

Map<String, Object?> _auditSummaryJson(List<AgentAuditEvent> events) {
  final toolCounts = <String, int>{};
  var requestCount = 0;
  var tokenUsage = 0;
  for (final event in events) {
    requestCount += event.requestCount;
    tokenUsage += event.tokenUsage;
    final key = event.toolName.trim().isEmpty
        ? event.kind.trim()
        : event.toolName.trim();
    if (key.isEmpty) continue;
    toolCounts[key] = (toolCounts[key] ?? 0) + 1;
  }
  return <String, Object?>{
    'event_count': events.length,
    'request_count': requestCount,
    'token_usage': tokenUsage,
    if (toolCounts.isNotEmpty) 'tool_counts': toolCounts,
    'recent_events': events
        .take(5)
        .map(_auditEventSummaryJson)
        .toList(growable: false),
  };
}

Map<String, Object?> _capabilityUsageJson(
  List<AgentAuditEvent> events, {
  int limit = 10,
}) {
  final byType = <String, int>{};
  final groups = <String, Map<String, Object?>>{};
  var requestCount = 0;
  var tokenUsage = 0;
  for (final event in events) {
    requestCount += event.requestCount;
    tokenUsage += event.tokenUsage;
    final type = _auditCapabilityType(event);
    byType[type] = (byType[type] ?? 0) + 1;
    final name = _auditCapabilityName(event);
    final key = '$type::$name';
    final group = groups.putIfAbsent(
      key,
      () => <String, Object?>{
        'type': type,
        'name': name,
        'event_count': 0,
        'request_count': 0,
        'token_usage': 0,
        'kinds': <String>{},
        'last_used_at': null,
      },
    );
    group['event_count'] = (group['event_count'] as int) + 1;
    group['request_count'] =
        (group['request_count'] as int) + event.requestCount;
    group['token_usage'] = (group['token_usage'] as int) + event.tokenUsage;
    (group['kinds'] as Set<String>).add(event.kind);
    group['last_used_at'] = _latestDateTime(
      group['last_used_at'] as DateTime?,
      event.createdAt,
    );
  }
  final topCapabilities =
      groups.values
          .map(
            (group) => <String, Object?>{
              'type': group['type'],
              'name': group['name'],
              'event_count': group['event_count'],
              'request_count': group['request_count'],
              'token_usage': group['token_usage'],
              'kinds': (group['kinds'] as Set<String>).toList(growable: false),
              'last_used_at': _iso(group['last_used_at'] as DateTime?),
            },
          )
          .toList(growable: false)
        ..sort(_capabilityUsageCompare);
  return <String, Object?>{
    'event_count': events.length,
    'request_count': requestCount,
    'token_usage': tokenUsage,
    'by_type': byType,
    'top_capabilities': topCapabilities.take(limit).toList(growable: false),
  };
}

Map<String, Object?> _workerExecutionReportJson(
  AgentProfile agent,
  List<AgentTask> tasks,
  List<AgentAuditEvent> auditEvents, {
  int limit = 10,
}) {
  final workerIds = <String>{};
  for (final worker in agent.workers) {
    workerIds.add(worker.id);
  }
  for (final task in tasks) {
    final workerId = '${task.extra['assigned_worker_id'] ?? ''}'.trim();
    if (workerId.isNotEmpty) workerIds.add(workerId);
  }
  for (final event in auditEvents) {
    final workerId = '${event.metadata['worker_id'] ?? ''}'.trim();
    if (workerId.isNotEmpty) workerIds.add(workerId);
  }

  var assignedTaskCount = 0;
  final workers =
      workerIds
          .map((workerId) {
            final worker = _workerById(agent, workerId);
            final workerTasks = tasks
                .where((task) => _taskAssignedToWorker(task, workerId))
                .toList(growable: false);
            final workerAuditEvents = auditEvents
                .where(
                  (event) =>
                      _matchesMetadata(event.metadata, 'worker_id', workerId),
                )
                .toList(growable: false);
            assignedTaskCount += workerTasks.length;
            final latestTaskAt = workerTasks.fold<DateTime?>(
              null,
              (latest, task) =>
                  _latestDateTime(latest, task.updatedAt ?? task.createdAt),
            );
            final latestAuditAt = workerAuditEvents.fold<DateTime?>(
              null,
              (latest, event) => _latestDateTime(latest, event.createdAt),
            );
            final auditSummary = _auditSummaryJson(workerAuditEvents);
            return <String, Object?>{
              'id': workerId,
              'name': worker?.name ?? '',
              'missing': worker == null,
              'status': worker?.status.storageValue ?? 'unknown',
              'idle': worker?.status == AgentWorkerStatus.idle,
              'executed_task_count': worker?.executedTaskCount ?? 0,
              'busy_score': worker?.busyScore ?? 0,
              'priority': worker?.priority ?? 0,
              'current_task_id': worker?.currentTaskId ?? '',
              'labels': worker?.labels ?? const <String>[],
              'task_metrics': _taskMetricsForTasksJson(workerTasks),
              'audit_summary': auditSummary,
              'last_activity_at': _iso(
                _latestDateTime(latestTaskAt, latestAuditAt),
              ),
            };
          })
          .toList(growable: false)
        ..sort(_workerExecutionCompare);

  return <String, Object?>{
    'total_workers': agent.workers.length,
    'observed_workers': workers.length,
    'busy_workers': agent.workers
        .where((worker) => worker.status == AgentWorkerStatus.busy)
        .length,
    'idle_workers': agent.workers
        .where((worker) => worker.status == AgentWorkerStatus.idle)
        .length,
    'executed_task_count': agent.workers.fold<int>(
      0,
      (sum, worker) => sum + worker.executedTaskCount,
    ),
    'task_assignment_count': assignedTaskCount,
    'unassigned_task_count': tasks.length - assignedTaskCount,
    'workers': workers.take(limit).toList(growable: false),
  };
}

Map<String, Object?> _loadSummaryJson(AgentProfile agent) {
  return <String, Object?>{
    'worker_capacity': _workerCapacityJsonForAgent(agent),
    'queue_pressure': _queuePressureJson(agent),
    'resource_pressure': _resourcePressureJson(agent.resourceUsage),
  };
}

String _auditCapabilityType(AgentAuditEvent event) {
  final values = <String>[
    event.kind,
    event.toolName,
    '${event.metadata['capability_type'] ?? ''}',
    '${event.metadata['type'] ?? ''}',
  ].join(' ').toLowerCase();
  if (values.contains('skill')) return 'skill';
  if (values.contains('mcp')) return 'mcp';
  if (values.contains('memory')) return 'memory';
  if (values.contains('knowledge')) return 'knowledge';
  if (values.contains('builtin')) return 'builtin_tool';
  if (values.contains('model')) return 'model_request';
  if (values.contains('resource')) return 'resource';
  if (values.contains('approval')) return 'approval';
  if (values.contains('kpi')) return 'kpi';
  if (values.contains('worker') || values.contains('task')) {
    return 'worker_execution';
  }
  return 'other';
}

String _auditCapabilityName(AgentAuditEvent event) {
  for (final raw in <Object?>[
    event.toolName,
    event.metadata['tool_name'],
    event.metadata['tool'],
    event.metadata['capability_name'],
    event.kind,
  ]) {
    final text = '$raw'.trim();
    if (text.isNotEmpty) return text;
  }
  return 'unknown';
}

int _capabilityUsageCompare(
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  final tokenCompare = _intValue(
    right['token_usage'],
  ).compareTo(_intValue(left['token_usage']));
  if (tokenCompare != 0) return tokenCompare;
  final requestCompare = _intValue(
    right['request_count'],
  ).compareTo(_intValue(left['request_count']));
  if (requestCompare != 0) return requestCompare;
  final eventCompare = _intValue(
    right['event_count'],
  ).compareTo(_intValue(left['event_count']));
  if (eventCompare != 0) return eventCompare;
  return '${left['name'] ?? ''}'.compareTo('${right['name'] ?? ''}');
}

int _workerExecutionCompare(
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  final leftAudit = stringKeyedMapFromValue(left['audit_summary']);
  final rightAudit = stringKeyedMapFromValue(right['audit_summary']);
  final tokenCompare = _intValue(
    rightAudit['token_usage'],
  ).compareTo(_intValue(leftAudit['token_usage']));
  if (tokenCompare != 0) return tokenCompare;
  final requestCompare = _intValue(
    rightAudit['request_count'],
  ).compareTo(_intValue(leftAudit['request_count']));
  if (requestCompare != 0) return requestCompare;
  final taskCompare =
      _intValue(
        stringKeyedMapFromValue(right['task_metrics'])['total'],
      ).compareTo(
        _intValue(stringKeyedMapFromValue(left['task_metrics'])['total']),
      );
  if (taskCompare != 0) return taskCompare;
  return '${left['id'] ?? ''}'.compareTo('${right['id'] ?? ''}');
}

AgentWorker? _workerById(AgentProfile agent, String workerId) {
  for (final worker in agent.workers) {
    if (worker.id == workerId) return worker;
  }
  return null;
}

DateTime? _latestDateTime(DateTime? left, DateTime? right) {
  if (left == null) return right;
  if (right == null) return left;
  return right.isAfter(left) ? right : left;
}

Map<String, Object?> _resourcePressureJson(AgentResourceUsage usage) {
  final tokenRatio = usage.tokenBudget > 0
      ? (usage.tokenUsed / usage.tokenBudget).clamp(0, 1).toDouble()
      : 0.0;
  final diskPressure = usage.diskBytes > 0
      ? (usage.persistedBytes / usage.diskBytes).clamp(0, 1).toDouble()
      : 0.0;
  return <String, Object?>{
    'cpu_percent': usage.cpuPercent,
    'token_usage_ratio': tokenRatio,
    'persisted_disk_ratio': diskPressure,
    'open_handles': usage.openHandles,
    'has_pressure':
        usage.cpuPercent >= 0.85 ||
        tokenRatio >= 0.85 ||
        diskPressure >= 0.85 ||
        usage.openHandles >= 100,
  };
}

int _intValue(Object? raw) {
  return optionalIntFromValue(raw) ?? 0;
}

Map<String, Object?> _activitySummaryJson(List<AgentActivityEvent> events) {
  final kindCounts = <String, int>{};
  final messageTypeCounts = <String, int>{};
  for (final event in events) {
    final kind = event.kind.trim();
    if (kind.isEmpty) continue;
    kindCounts[kind] = (kindCounts[kind] ?? 0) + 1;
    final messageType = event.effectiveMessageType.storageValue;
    messageTypeCounts[messageType] = (messageTypeCounts[messageType] ?? 0) + 1;
  }
  return <String, Object?>{
    'event_count': events.length,
    if (kindCounts.isNotEmpty) 'kind_counts': kindCounts,
    if (messageTypeCounts.isNotEmpty) 'message_type_counts': messageTypeCounts,
    'recent_events': events
        .take(5)
        .map(_activityEventSummaryJson)
        .toList(growable: false),
  };
}

Map<String, Object?> _activityEventSummaryJson(AgentActivityEvent event) {
  return <String, Object?>{
    'id': event.id,
    'kind': event.kind,
    'message_type': event.effectiveMessageType.storageValue,
    'title': event.title,
    'content': event.content,
    'created_at': _iso(event.createdAt),
    'metadata': event.metadata,
  };
}

Map<String, Object?> _auditEventSummaryJson(AgentAuditEvent event) {
  return <String, Object?>{
    'id': event.id,
    'kind': event.kind,
    'summary': event.summary,
    'tool_name': event.toolName,
    'request_count': event.requestCount,
    'token_usage': event.tokenUsage,
    'created_at': _iso(event.createdAt),
    'metadata': event.metadata,
  };
}

bool _activityMatches(
  AgentActivityEvent event, {
  required String? kind,
  required AgentActivityMessageType? messageType,
  required String? toolName,
  required String? taskId,
  required String? workerId,
}) {
  if (!_matchesText(event.kind, kind)) return false;
  if (messageType != null && event.effectiveMessageType != messageType) {
    return false;
  }
  if (!_matchesMetadata(event.metadata, 'task_id', taskId)) return false;
  if (!_matchesMetadata(event.metadata, 'worker_id', workerId)) return false;
  if (toolName != null &&
      !_matchesAnyText(toolName, <String>[
        '${event.metadata['tool_name'] ?? ''}',
        '${event.metadata['tool'] ?? ''}',
        '${event.metadata['recorded_by'] ?? ''}',
      ])) {
    return false;
  }
  return true;
}

bool _auditMatches(
  AgentAuditEvent event, {
  required String? kind,
  required String? toolName,
  required String? taskId,
  required String? workerId,
}) {
  if (!_matchesText(event.kind, kind)) return false;
  if (!_matchesMetadata(event.metadata, 'task_id', taskId)) return false;
  if (!_matchesMetadata(event.metadata, 'worker_id', workerId)) return false;
  if (toolName != null &&
      !_matchesAnyText(toolName, <String>[
        event.toolName,
        '${event.metadata['tool_name'] ?? ''}',
        '${event.metadata['tool'] ?? ''}',
        '${event.metadata['recorded_by'] ?? ''}',
      ])) {
    return false;
  }
  return true;
}

bool _matchesMetadata(
  Map<String, Object?> metadata,
  String key,
  String? expected,
) {
  if (expected == null) return true;
  return _matchesText('${metadata[key] ?? ''}', expected);
}

bool _matchesAnyText(String expected, Iterable<String> candidates) {
  for (final candidate in candidates) {
    if (_matchesText(candidate, expected)) return true;
  }
  return false;
}

bool _matchesText(String actual, String? expected) {
  if (expected == null) return true;
  return actual.trim().toLowerCase() == expected.trim().toLowerCase();
}

Map<String, Object?> _resourceUsageSummaryJson(AgentResourceUsage usage) {
  final payload = Map<String, Object?>.from(usage.toJson());
  if (usage.tokenBudget > 0) {
    final remaining = usage.tokenBudget - usage.tokenUsed;
    payload['token_remaining'] = remaining < 0 ? 0 : remaining;
    payload['token_usage_ratio'] = (usage.tokenUsed / usage.tokenBudget)
        .clamp(0, 1)
        .toDouble();
  } else {
    payload['token_remaining'] = null;
    payload['token_usage_ratio'] = 0;
  }
  return payload;
}

Map<String, Object?> _taskExtraJson(Map<String, Object?> extra) {
  if (extra.isEmpty) return const <String, Object?>{};
  final sanitized = Map<String, Object?>.from(extra);
  final prompt = sanitized.remove('agent_system_prompt');
  if (prompt is String && prompt.isNotEmpty) {
    sanitized['agent_system_prompt'] = <String, Object?>{
      'omitted': true,
      'chars': prompt.length,
      'reason':
          'Use agent_prompt_snapshot metadata unless full prompt text is explicitly needed.',
    };
  }
  return sanitized;
}

String? _iso(DateTime? value) => value?.toUtc().toIso8601String();

String? _optionalText(Object? raw) {
  if (raw == null) return null;
  final text = '$raw'.trim();
  return text.isEmpty ? null : text;
}

double? _optionalRatio(Object? raw) {
  if (raw == null) return null;
  final value = switch (raw) {
    num n => n.toDouble(),
    String s => optionalDoubleFromValue(s),
    _ => null,
  };
  if (value == null || !value.isFinite) return null;
  return value.clamp(0, 1).toDouble();
}

String? _normalizedKpiStatus(String raw) {
  final normalized = raw.trim().toLowerCase().replaceAll(
    RegExp(r'[\s-]+'),
    '_',
  );
  if (_agentKpiStatusValues.contains(normalized)) return normalized;
  return null;
}

({AgentTaskStatus? status, bool invalid}) _optionalTaskStatus(Object? raw) {
  if (raw == null) return (status: null, invalid: false);
  final normalized = '$raw'.trim().toLowerCase().replaceAll(
    RegExp(r'[\s-]+'),
    '_',
  );
  if (normalized.isEmpty) return (status: null, invalid: false);
  for (final status in AgentTaskStatus.values) {
    if (status.storageValue == normalized) {
      return (status: status, invalid: false);
    }
  }
  return (status: null, invalid: true);
}

String? _optionalAllowedText(
  Map<String, Object?> args,
  String key,
  Set<String> allowed,
) {
  if (!args.containsKey(key) || args[key] == null) return null;
  final normalized = '${args[key]}'.trim().toLowerCase().replaceAll(
    RegExp(r'[\s-]+'),
    '_',
  );
  if (allowed.contains(normalized)) return normalized;
  return '';
}

bool _hasAnyArgument(Map<String, Object?> args, List<String> keys) {
  for (final key in keys) {
    if (args.containsKey(key)) return true;
  }
  return false;
}

String _normalizeRouteText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
