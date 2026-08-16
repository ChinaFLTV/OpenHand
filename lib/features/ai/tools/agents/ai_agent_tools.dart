import 'dart:async';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_json_conversion.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../../agents/index.dart';
import '../../../ai/model/ai_session_message.dart';
import '../../../instructions/index.dart'
    show InstructionsControllerProvider, UserInstructionEntry;
import '../../model/ai_builtin_tool_config.dart'
    show
        AiAgentBuiltinToolGroup,
        AiBuiltinToolKindAgentMetadata,
        agentBuiltinToolCanonicalName,
        aiAgentBuiltinToolKinds,
        aiAgentToolAccessEnabledMetadataKey,
        aiAgentToolAccessSourceMetadataKey,
        aiAgentToolAllowedAgentIdsMetadataKey,
        kAiReadOnlyBuiltinToolKinds;
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/chat/ai_chat_service.dart';
import '../../service/chat/ai_protocol_adapter.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../../service/usage/ai_usage_tracker.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';
import '../planning/ai_task_tool.dart' show AiSubToolExecutor;

const int _agentTaskDefaultResultWaitMs = 30000;
const int _agentTaskMaxResultWaitMs = 90000;
const int _agentTaskMinPollMs = 300;
const int _agentWorkerMaxToolRounds = 8;
const int _agentWorkerMaxToolCallsPerRound = 8;
const int _agentWorkerMaxTotalToolCalls = 32;
const int _agentWorkerMaxToolArgumentChars = 256 * kBytesPerKiB;
const int _agentWorkerMaxToolOutputChars = 64 * kBytesPerKiB;
const int _agentWorkerMaxTotalToolOutputChars = 256 * kBytesPerKiB;
const int _agentWorkerResultMaxChars = 24000;
const int _agentWorkerResultPreviewMaxChars = 1200;
const int _agentListDefaultLimit = 100;
const int _agentListMaxLimit = 500;
const int _agentDetailDefaultLimit = 50;
const int _agentDetailMaxLimit = 200;
const int _agentToolResultMaxNodes = 50000;
const int _agentToolResultMaxStringChars = 120000;
const int _agentToolResultMaxTotalStringChars = 120000;
const Duration _agentWorkerTurnTimeout = Duration(seconds: 75);
const String _agentTaskAutoWorkerToolName = 'AgentWorker';
const String _agentTaskAutoExecuteExtraKey = 'agent_auto_execute';
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
const List<AiBuiltinToolKind> _agentCoordinationToolKinds =
    aiAgentBuiltinToolKinds;
const Set<AiBuiltinToolKind> _agentWorkerBlockedBuiltinKinds =
    <AiBuiltinToolKind>{
      AiBuiltinToolKind.task,
      AiBuiltinToolKind.todoWrite,
      AiBuiltinToolKind.exitPlanMode,
      AiBuiltinToolKind.askUserChoice,
      ...aiAgentBuiltinToolKinds,
    };
const Set<String> _agentToolSensitivePromptKeys = <String>{
  agentSystemPromptMetadataKey,
  'rendered_prompt',
  'system_prompt',
  'developer_prompt',
  'hidden_prompt',
};
const BoundedJsonConversionConfig _agentToolResultConversionConfig =
    BoundedJsonConversionConfig(
      maxDepth: 24,
      maxContainerItems: _agentListMaxLimit,
      maxTotalNodes: _agentToolResultMaxNodes,
      maxStringCodeUnits: _agentToolResultMaxStringChars,
      maxTotalStringCodeUnits: _agentToolResultMaxTotalStringChars,
      truncatedStringSuffix: '...[已截断]',
      mapValueTransformer: _redactAgentToolPromptValue,
      maxDepthPlaceholder: '<层级过深>',
      cyclicMapPlaceholder: '<循环映射>',
      cyclicIterablePlaceholder: '<循环集合>',
      truncatedPlaceholder: aiSessionMessageTruncatedPlaceholder,
    );

/// 数字员工 worker 的默认工具：只读集合再加上知识库检索。
const Set<AiBuiltinToolKind> _agentWorkerDefaultBuiltinKinds =
    <AiBuiltinToolKind>{
      ...kAiReadOnlyBuiltinToolKinds,
      AiBuiltinToolKind.knowledgeSearch,
      AiBuiltinToolKind.knowledgeRead,
    };

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
    AiChatClient? backgroundChatClient,
    List<AiModelConfig> Function()? aiModelsProvider,
    InstructionsControllerProvider? instructionsControllerProvider,
  }) : _kind = kind,
       _name = name,
       _operation = operation,
       _agentsControllerProvider = agentsControllerProvider,
       _promptRenderer = promptRenderer,
       _backgroundChatClient = backgroundChatClient,
       _aiModelsProvider = aiModelsProvider,
       _instructionsControllerProvider = instructionsControllerProvider;

  static List<AiAgentTool> all({
    required AgentsControllerProvider agentsControllerProvider,
    AgentPromptRenderer? promptRenderer,
    AiChatClient? backgroundChatClient,
    List<AiModelConfig> Function()? aiModelsProvider,
    InstructionsControllerProvider? instructionsControllerProvider,
  }) {
    final renderer = promptRenderer ?? AgentPromptRenderer();
    // 全部数字员工工具共享同一组依赖，这里只声明各自的种类、对外名称与操作。
    const catalog = <(AiBuiltinToolKind, String, _AgentToolOperation)>[
      (AiBuiltinToolKind.agentList, 'AgentList', _AgentToolOperation.list),
      (
        AiBuiltinToolKind.agentDetail,
        'AgentDetail',
        _AgentToolOperation.detail,
      ),
      (
        AiBuiltinToolKind.agentActivityLog,
        'AgentActivityLog',
        _AgentToolOperation.activityLog,
      ),
      (
        AiBuiltinToolKind.agentAuditReport,
        'AgentAuditReport',
        _AgentToolOperation.auditReport,
      ),
      (
        AiBuiltinToolKind.agentAuditRecord,
        'AgentAuditRecord',
        _AgentToolOperation.recordAudit,
      ),
      (
        AiBuiltinToolKind.agentApprovalRequest,
        'AgentApprovalRequest',
        _AgentToolOperation.requestApproval,
      ),
      (
        AiBuiltinToolKind.agentKpiUpsert,
        'AgentKpiUpsert',
        _AgentToolOperation.upsertKpi,
      ),
      (
        AiBuiltinToolKind.agentResourceUpdate,
        'AgentResourceUpdate',
        _AgentToolOperation.updateResource,
      ),
      (
        AiBuiltinToolKind.agentClusterConfigure,
        'AgentClusterConfigure',
        _AgentToolOperation.configureCluster,
      ),
      (
        AiBuiltinToolKind.agentClusterStatus,
        'AgentClusterStatus',
        _AgentToolOperation.clusterStatus,
      ),
      (
        AiBuiltinToolKind.agentTaskList,
        'AgentTaskList',
        _AgentToolOperation.listTasks,
      ),
      (
        AiBuiltinToolKind.agentTaskPublish,
        'AgentTaskPublish',
        _AgentToolOperation.publishTask,
      ),
      (
        AiBuiltinToolKind.agentTaskTrack,
        agentTaskTrackToolName,
        _AgentToolOperation.trackTask,
      ),
      (
        AiBuiltinToolKind.agentTaskProgress,
        agentTaskProgressToolName,
        _AgentToolOperation.progressTask,
      ),
      (
        AiBuiltinToolKind.agentTaskCancel,
        'AgentTaskCancel',
        _AgentToolOperation.cancelTask,
      ),
      (
        AiBuiltinToolKind.agentTaskPause,
        'AgentTaskPause',
        _AgentToolOperation.pauseTask,
      ),
      (
        AiBuiltinToolKind.agentTaskTerminate,
        'AgentTaskTerminate',
        _AgentToolOperation.terminateTask,
      ),
      (
        AiBuiltinToolKind.agentTaskResume,
        'AgentTaskResume',
        _AgentToolOperation.resumeTask,
      ),
      (
        AiBuiltinToolKind.agentTaskComplete,
        'AgentTaskComplete',
        _AgentToolOperation.completeTask,
      ),
      (
        AiBuiltinToolKind.agentTaskResult,
        agentTaskResultToolName,
        _AgentToolOperation.resultTask,
      ),
    ];
    return <AiAgentTool>[
      for (final (kind, name, operation) in catalog)
        AiAgentTool._(
          kind: kind,
          name: name,
          operation: operation,
          agentsControllerProvider: agentsControllerProvider,
          promptRenderer: renderer,
          backgroundChatClient: backgroundChatClient,
          aiModelsProvider: aiModelsProvider,
          instructionsControllerProvider: instructionsControllerProvider,
        ),
    ];
  }

  final AiBuiltinToolKind _kind;
  final String _name;
  final _AgentToolOperation _operation;
  final AgentsControllerProvider _agentsControllerProvider;
  final AgentPromptRenderer _promptRenderer;
  final AiChatClient? _backgroundChatClient;
  final List<AiModelConfig> Function()? _aiModelsProvider;
  final InstructionsControllerProvider? _instructionsControllerProvider;
  AiSubToolExecutor? _subToolExecutor;

  AiAgentTool withExecutor(AiSubToolExecutor executor) {
    _subToolExecutor = executor;
    return this;
  }

  List<UserInstructionEntry> _boundInstructionsForAgent(AgentProfile agent) {
    if (agent.instructionIds.isEmpty) return const <UserInstructionEntry>[];
    final controller = _instructionsControllerProvider?.call();
    if (controller == null) return const <UserInstructionEntry>[];
    final byId = <String, UserInstructionEntry>{
      for (final entry in controller.entries)
        if (entry.enabled) entry.id: entry,
    };
    final result = <UserInstructionEntry>[];
    for (final id in agent.instructionIds) {
      final entry = byId[id];
      if (entry != null) result.add(entry);
    }
    return result;
  }

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
        '当前会话无法使用数字员工控制器。',
      );
    }
    final accessPolicy = _AgentToolAccessPolicy.fromMetadata(context.metadata);
    if (!accessPolicy.enabled) {
      return AiToolUtils.invalidResult(
        _name,
        '当前会话已禁用数字员工工具。',
      );
    }
    if (_enabledAgentsForPolicy(controller, accessPolicy).isEmpty) {
      return _noEnabledAgentsResult(controller, accessPolicy);
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
        _AgentToolOperation.resultTask => await _taskResult(
          controller,
          context,
          stopwatch,
        ),
      };
    } catch (error, stackTrace) {
      silentLog('ai_agent_tools', '执行数字员工工具 $_name', error, stackTrace);
      const message = '数字员工工具执行失败。';
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: _name,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: message,
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: failure\nerror: $message',
      );
    }
  }

  AiToolExecutionResult _noEnabledAgentsResult(
    AgentsController controller,
    _AgentToolAccessPolicy accessPolicy,
  ) {
    final runtime = controller.runtimeAvailability;
    if (!runtime.canRun) {
      return AiToolUtils.invalidResult(
        _name,
        '数字员工运行时不可用：${runtime.blockingReason}',
      );
    }
    if (controller.agents.isEmpty) {
      return AiToolUtils.invalidResult(
        _name,
        '尚未配置数字员工，请先创建并启动数字员工。',
      );
    }
    if (accessPolicy.isScoped) {
      return AiToolUtils.invalidResult(
        _name,
        '当前会话没有可用的数字员工，请启用并至少选择一个数字员工。',
      );
    }
    return AiToolUtils.invalidResult(
      _name,
      '没有已启用的数字员工，请先启动数字员工。',
    );
  }

  AiToolExecutionResult _list(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) {
    final args = context.decodedArguments;
    final includeDisabled = boolFromValue(args['include_disabled']);
    final accessPolicy = _AgentToolAccessPolicy.fromMetadata(context.metadata);
    final agents = _agentsForPolicy(
      controller,
      accessPolicy,
      includeDisabled: includeDisabled,
    );
    final limit = clampedIntFromValue(
      args['limit'],
      fallback: _agentListDefaultLimit,
      min: 1,
      max: _agentListMaxLimit,
    );
    final visibleAgents = agents.take(limit).toList(growable: false);
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    final payload = <String, Object?>{
      'agents': visibleAgents
          .map(
            (agent) => _agentSummaryJson(
              agent,
              callableAgentToolNames: callableAgentToolNames,
            ),
          )
          .toList(growable: false),
      'count': visibleAgents.length,
      'total_count': agents.length,
      'limit': limit,
      'truncated': visibleAgents.length < agents.length,
      'include_disabled': includeDisabled,
    };
    return _success(
      payload,
      stopwatch,
      metadata: <String, Object?>{
        'action': 'list',
        'count': visibleAgents.length,
        'total_count': agents.length,
      },
    );
  }

  Future<AiToolExecutionResult> _detail(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) async {
    final args = context.decodedArguments;
    final resolution = _resolveContextAgent(
      controller,
      context,
      honorIncludeDisabled: true,
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
    final limit = clampedIntFromValue(
      args['limit'],
      fallback: _agentDetailDefaultLimit,
      min: 1,
      max: _agentDetailMaxLimit,
    );
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    final promptSnapshot = includePrompt || includePromptText
        ? await _promptRenderer.render(
            agent: resolution.agent!,
            callableAgentToolNames: callableAgentToolNames,
            boundInstructions: _boundInstructionsForAgent(resolution.agent!),
          )
        : null;
    final promptMetadata = promptSnapshot?.metadataJson();
    if (includePromptText && promptSnapshot != null) {
      promptMetadata!['rendered_prompt'] = _ExplicitAgentPromptText(
        promptSnapshot.renderedPrompt,
      );
    }
    final payload = <String, Object?>{
      'agent': _agentDetailJson(
        resolution.agent!,
        includeTasks: includeTasks,
        includeAudit: includeAudit,
        includeResources: includeResources,
        itemLimit: limit,
        callableAgentToolNames: callableAgentToolNames,
      ),
      'limit': limit,
      if (promptMetadata != null) 'agent_prompt': promptMetadata,
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
    final resolution = _resolveContextAgent(
      controller,
      context,
      honorIncludeDisabled: true,
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
        ? recentAgentActivities(
            agent.activities,
            test: (event) => _activityMatches(
              event,
              kind: kind,
              messageType: messageType,
              toolName: toolName,
              taskId: taskId,
              workerId: workerId,
            ),
            limit: limit,
          )
        : const <AgentActivityEvent>[];
    final auditEvents = includeAudit
        ? recentAgentAuditEvents(
            agent.auditEvents,
            test: (event) => _auditMatches(
              event,
              kind: kind,
              toolName: toolName,
              taskId: taskId,
              workerId: workerId,
            ),
            limit: limit,
          )
        : const <AgentAuditEvent>[];
    final payload = <String, Object?>{
      'agent': _agentSummaryJson(
        agent,
        callableAgentToolNames: _callableAgentToolNames(context.catalog),
      ),
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
    final resolution = _resolveContextAgent(
      controller,
      context,
      honorIncludeDisabled: true,
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
        ? sortedAgentTasksForAttention(
            agent.tasks,
            test: (task) => _clusterTaskMatches(task, workerId: workerId),
            limit: limit,
          )
        : const <AgentTask>[];
    final clusterActivities = includeAudit
        ? recentAgentActivities(
            agent.activities,
            test: (event) =>
                _isClusterActivity(event) &&
                _matchesMetadata(event.metadata, 'worker_id', workerId),
            limit: limit,
          )
        : const <AgentActivityEvent>[];
    final clusterAuditEvents = includeAudit
        ? recentAgentAuditEvents(
            agent.auditEvents,
            test: (event) =>
                _isClusterAuditEvent(event) &&
                _matchesMetadata(event.metadata, 'worker_id', workerId),
            limit: limit,
          )
        : const <AgentAuditEvent>[];
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);

    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(
          agent,
          callableAgentToolNames: callableAgentToolNames,
        ),
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
              .map(
                (task) => _taskJson(
                  task,
                  agent: agent,
                  callableAgentToolNames: callableAgentToolNames,
                ),
              )
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
    final resolution = _resolveContextAgent(controller, context);
    if (resolution.error != null) return resolution.error!;
    final agent = resolution.agent!;
    final previous = agent.scaleSettings;

    final schedulerPolicy = _optionalAllowedText(
      args,
      'scheduler_policy',
      agentSchedulerPolicyOptions,
    );
    if (schedulerPolicy == '') {
      return AiToolUtils.invalidResult(
        _name,
        'scheduler_policy 必须是以下值之一：${agentSchedulerPolicyOptions.join(', ')}。',
      );
    }
    final workerRemovalPolicy = _optionalAllowedText(
      args,
      'worker_removal_policy',
      agentWorkerRemovalPolicyOptions,
    );
    if (workerRemovalPolicy == '') {
      return AiToolUtils.invalidResult(
        _name,
        'worker_removal_policy 必须是以下值之一：${agentWorkerRemovalPolicyOptions.join(', ')}。',
      );
    }
    final retryPolicy = _optionalAllowedText(
      args,
      'retry_policy',
      agentRetryPolicyOptions,
    );
    if (retryPolicy == '') {
      return AiToolUtils.invalidResult(
        _name,
        'retry_policy 必须是以下值之一：${agentRetryPolicyOptions.join(', ')}。',
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
        '配置数字员工集群失败，目标数字员工可能已被移除。',
      );
    }
    final currentAgent = controller.agentById(agent.id) ?? agent;
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(
          currentAgent,
          callableAgentToolNames: callableAgentToolNames,
        ),
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
    final resolution = _resolveContextAgent(
      controller,
      context,
      honorIncludeDisabled: true,
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
    final tasks = sortedAgentTasksForAttention(agent.tasks)
        .where(
          (task) => _taskMatchesReportFilter(
            task,
            taskId: taskId,
            workerId: workerId,
          ),
        )
        .toList(growable: false);
    final auditEvents = recentAgentAuditEvents(agent.auditEvents)
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
    final activities = recentAgentActivities(agent.activities)
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
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    final payload = <String, Object?>{
      'agent': _agentSummaryJson(
        agent,
        callableAgentToolNames: callableAgentToolNames,
      ),
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
      'kpi_state': sortedAgentKpisForAttention(
        agent.kpis,
        limit: limit,
      ).map((item) => item.toJson()).toList(growable: false),
      'approval_summary': _approvalSummaryJson(agent.approvals),
      'pending_approvals': sortedAgentApprovalsForAttention(
        agent.approvals,
        test: (item) => item.status == AgentApprovalStatus.pending,
        limit: limit,
      ).map((item) => item.toJson()).toList(growable: false),
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
          .map(
            (task) => _taskJson(
              task,
              agent: agent,
              callableAgentToolNames: callableAgentToolNames,
            ),
          )
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
    final resolution = _resolveContextAgent(controller, context);
    if (resolution.error != null) return resolution.error!;
    final summary = _optionalText(args['summary']);
    if (summary == null) {
      return AiToolUtils.invalidResult(_name, 'summary 为必填参数。');
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
        '记录审计事件失败，目标数字员工可能已被移除。',
      );
    }
    final currentAgent = controller.agentById(resolution.agent!.id);
    final auditEvents = currentAgent?.auditEvents ?? <AgentAuditEvent>[event];
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(
          currentAgent ?? resolution.agent!,
          callableAgentToolNames: callableAgentToolNames,
        ),
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
    final resolution = _resolveContextAgent(controller, context);
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
        '更新资源用量失败，目标数字员工可能已被移除。',
      );
    }
    final currentAgent = controller.agentById(agent.id) ?? agent;
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(
          currentAgent,
          callableAgentToolNames: callableAgentToolNames,
        ),
        'resource_usage': currentAgent.resourceUsage.toJson(
          includeInternalExtra: false,
        ),
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
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    final accessPolicy = _AgentToolAccessPolicy.fromMetadata(context.metadata);
    final resolution = _resolveKpiAgent(
      controller,
      args,
      name: name,
      labels: labels,
      callableAgentToolNames: callableAgentToolNames,
      accessPolicy: accessPolicy,
    );
    if (resolution.error != null) return resolution.error!;

    final agent = resolution.agent!;
    final existing = kpiId.isNotEmpty
        ? _findAgentKpi(agent, kpiId)
        : _findAgentKpiByName(agent, name);
    if (kpiId.isNotEmpty && existing == null) {
      return AiToolUtils.invalidResult(
        _name,
        '数字员工“${agent.name}”不存在 KPI“$kpiId”。',
      );
    }

    final resolvedName = name.isNotEmpty ? name : existing?.name.trim() ?? '';
    if (resolvedName.isEmpty) {
      return AiToolUtils.invalidResult(
        _name,
        '创建 KPI 时 name 为必填参数。',
      );
    }

    final rawStatus = _optionalText(args['status']);
    final status = rawStatus == null
        ? (existing?.status.trim().isNotEmpty == true
              ? existing!.status.trim()
              : agentKpiStatusTracking)
        : _normalizedKpiStatus(rawStatus);
    if (status == null) {
      return AiToolUtils.invalidResult(
        _name,
        'status 必须是以下值之一：${agentKpiStatusOptions.join(', ')}。',
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
        '保存 KPI 失败，目标数字员工可能已被移除。',
      );
    }

    final currentAgent = controller.agentById(agent.id);
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(
          currentAgent ?? agent,
          callableAgentToolNames: callableAgentToolNames,
        ),
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
      return AiToolUtils.invalidResult(_name, 'title 为必填参数。');
    }
    final labels = stringListFromValueOrJsonText(
      args['labels'] ?? args['tags'],
    );
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    final accessPolicy = _AgentToolAccessPolicy.fromMetadata(context.metadata);
    final resolution = _resolveApprovalAgent(
      controller,
      args,
      title: title,
      labels: labels,
      callableAgentToolNames: callableAgentToolNames,
      accessPolicy: accessPolicy,
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
        '申请审批失败，目标数字员工可能已停用或被移除。',
      );
    }
    final currentAgent = controller.agentById(resolution.agent!.id);
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(
          currentAgent ?? resolution.agent!,
          callableAgentToolNames: callableAgentToolNames,
        ),
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
    final resolution = _resolveContextAgent(
      controller,
      context,
      honorIncludeDisabled: true,
    );
    if (resolution.error != null) return resolution.error!;
    final agent = resolution.agent!;
    final statusFilter = _optionalTaskStatus(args['status']);
    if (statusFilter.invalid) {
      return AiToolUtils.invalidResult(
        _name,
        'status 必须是以下值之一：${AgentTaskStatus.values.map((item) => item.storageValue).join(', ')}。',
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
    final tasks = sortedAgentTasksForAttention(
      agent.tasks,
      test: (task) => _taskMatchesListFilter(
        task,
        status: statusFilter.status,
        workerId: workerId,
        labels: labels,
      ),
      limit: limit,
    );
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(
          agent,
          callableAgentToolNames: callableAgentToolNames,
        ),
        'filters': <String, Object?>{
          'include_disabled': includeDisabled,
          'limit': limit,
          if (statusFilter.status != null)
            'status': statusFilter.status!.storageValue,
          if (workerId != null) 'worker_id': workerId,
          if (labels.isNotEmpty) 'labels': labels,
        },
        'tasks': tasks
            .map(
              (task) => _taskJson(
                task,
                agent: agent,
                callableAgentToolNames: callableAgentToolNames,
              ),
            )
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
      return AiToolUtils.invalidResult(_name, 'title 为必填参数。');
    }
    final rawExtra = optionalStringKeyedMapFromValueOrJsonText(args['extra']);
    final labels = stringListFromValueOrJsonText(
      args['labels'] ?? args['tags'],
    );
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    final accessPolicy = _AgentToolAccessPolicy.fromMetadata(context.metadata);
    final resolution = _resolvePublishAgent(
      controller,
      args,
      title: title,
      labels: labels,
      callableAgentToolNames: callableAgentToolNames,
      accessPolicy: accessPolicy,
    );
    if (resolution.error != null) return resolution.error!;
    final promptSnapshot = await _promptRenderer.render(
      agent: resolution.agent!,
      callableAgentToolNames: callableAgentToolNames,
      boundInstructions: _boundInstructionsForAgent(resolution.agent!),
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
        '发布任务失败，目标数字员工可能已停用或被移除。',
      );
    }
    var currentAgent = controller.agentById(resolution.agent!.id);
    var currentTask = task;
    _AgentWorkerRunResult? workerExecution;
    if (_shouldAutoExecuteTask(args, task)) {
      final workerWaitMs = _agentWorkerWaitMs(args);
      workerExecution = await _runAgentWorker(
        controller: controller,
        context: context,
        agent: currentAgent ?? resolution.agent!,
        task: task,
        callableAgentToolNames: callableAgentToolNames,
        maxDurationMs: workerWaitMs,
      );
      currentAgent = controller.agentById(resolution.agent!.id);
      currentTask =
          currentAgent?.tasks.firstWhere(
            (item) => item.id == task.id,
            orElse: () => task,
          ) ??
          task;
    }
    final payload = <String, Object?>{
      'agent': _agentSummaryJson(
        currentAgent ?? resolution.agent!,
        callableAgentToolNames: callableAgentToolNames,
      ),
      'task': _taskJson(
        currentTask,
        agent: currentAgent,
        callableAgentToolNames: callableAgentToolNames,
      ),
      if (currentAgent != null)
        'operational_summary': _taskOperationalSummaryJson(
          currentAgent,
          currentTask,
        ),
      'agent_prompt': promptSnapshot.metadataJson(),
      if (workerExecution != null) 'worker_execution': workerExecution.toJson(),
    };
    return _success(
      payload,
      stopwatch,
      metadata: <String, Object?>{
        'action': 'publish_task',
        'agent_id': resolution.agent!.id,
        'task_id': currentTask.id,
        if (workerExecution != null)
          'worker_execution_status': workerExecution.status,
        if (workerExecution != null)
          'task_update_applied': workerExecution.taskUpdateApplied,
        if (workerExecution != null && workerExecution.taskStatus.isNotEmpty)
          'task_status': workerExecution.taskStatus,
      },
    );
  }

  AiToolExecutionResult _trackTask(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) {
    final accessPolicy = _AgentToolAccessPolicy.fromMetadata(context.metadata);
    final resolved = _resolveTask(
      controller,
      context.decodedArguments,
      sessionId: context.sessionId,
      allowHeuristicRecovery: true,
      accessPolicy: accessPolicy,
    );
    if (resolved.error != null) return resolved.error!;
    final task = resolved.task!;
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    final tracking = _taskTrackingFields(
      resolved.agent!,
      task,
      recovery: resolved.recovery,
      callableAgentToolNames: callableAgentToolNames,
    );
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(
          resolved.agent!,
          callableAgentToolNames: callableAgentToolNames,
        ),
        'task': _taskJson(
          task,
          agent: resolved.agent,
          callableAgentToolNames: callableAgentToolNames,
        ),
        ...tracking,
        'handoff': _taskHandoffJson(
          task,
          agent: resolved.agent,
          callableAgentToolNames: callableAgentToolNames,
        ),
      },
      stopwatch,
      metadata: <String, Object?>{
        'action': 'track_task',
        'agent_id': resolved.agent!.id,
        'task_id': task.id,
      },
    );
  }

  AiToolExecutionResult _progressTask(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) {
    final accessPolicy = _AgentToolAccessPolicy.fromMetadata(context.metadata);
    final resolved = _resolveTask(
      controller,
      context.decodedArguments,
      sessionId: context.sessionId,
      allowHeuristicRecovery: true,
      accessPolicy: accessPolicy,
    );
    if (resolved.error != null) return resolved.error!;
    final task = resolved.task!;
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    final tracking = _taskTrackingFields(
      resolved.agent!,
      task,
      recovery: resolved.recovery,
      callableAgentToolNames: callableAgentToolNames,
    );
    return _success(
      <String, Object?>{
        'agent_id': resolved.agent!.id,
        'task_id': task.id,
        'status': task.status.storageValue,
        'progress': task.progress,
        ...tracking,
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
    final accessPolicy = _AgentToolAccessPolicy.fromMetadata(context.metadata);
    final resolved = _resolveTask(
      controller,
      args,
      sessionId: context.sessionId,
      accessPolicy: accessPolicy,
    );
    if (resolved.error != null) return resolved.error!;
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    if (!_allowedTaskTools(
      resolved.task!.status,
      agent: resolved.agent,
      callableAgentToolNames: callableAgentToolNames,
    ).contains(_name)) {
      return AiToolUtils.invalidResult(
        _name,
        _taskStatusToolRejectedMessage(
          _name,
          resolved.task!,
          agent: resolved.agent,
          callableAgentToolNames: callableAgentToolNames,
        ),
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
        '完成任务时 result 为必填参数。',
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
        '更新任务失败，数字员工或任务状态可能已变化。',
      );
    }
    final currentAgent = controller.agentById(resolved.agent!.id);
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(
          currentAgent ?? resolved.agent!,
          callableAgentToolNames: callableAgentToolNames,
        ),
        'task': _taskJson(
          updated,
          agent: currentAgent,
          callableAgentToolNames: callableAgentToolNames,
        ),
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

  Future<AiToolExecutionResult> _taskResult(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) async {
    final args = context.decodedArguments;
    final accessPolicy = _AgentToolAccessPolicy.fromMetadata(context.metadata);
    var resolved = _resolveTask(
      controller,
      args,
      sessionId: context.sessionId,
      allowHeuristicRecovery: true,
      accessPolicy: accessPolicy,
    );
    if (resolved.error != null) return resolved.error!;
    final wait = _resultWaitOptions(args);
    final waitStartedAt = Stopwatch()..start();
    var waitedMs = 0;
    while (!_taskResultTerminalEnough(resolved.task!) &&
        waitedMs < wait.maxMs) {
      // 必须区分「轮询间隔到期」与「用户取消」：取消信号会让等待立即返回，
      // 若继续循环就会退化成无间隔空转，持续占用执行线程直到总时限。
      final remainingMs = wait.maxMs - waitedMs;
      final delayMs = remainingMs < wait.pollMs ? remainingMs : wait.pollMs;
      final cancelled = await delayUntilCancelled(
        Duration(milliseconds: delayMs),
        cancelSignal: context.cancelSignal,
      );
      if (cancelled) {
        return AiToolUtils.cancelledResult(
          command: _name,
          durationMs: stopwatch.elapsedMilliseconds,
          metadata: <String, Object?>{
            'tool': _name,
            'agent_id': resolved.agent!.id,
            'task_id': resolved.task!.id,
          },
        );
      }
      waitedMs = waitStartedAt.elapsedMilliseconds;
      final refreshed = _resolveTask(
        controller,
        <String, Object?>{
          ...args,
          'agent_id': resolved.agent!.id,
          'task_id': resolved.task!.id,
        },
        sessionId: context.sessionId,
        accessPolicy: accessPolicy,
      );
      if (refreshed.error != null) return refreshed.error!;
      resolved = refreshed;
    }
    final task = resolved.task!;
    final assignedWorker = _assignedWorkerJson(resolved.agent!, task);
    final callableAgentToolNames = _callableAgentToolNames(context.catalog);
    final state = _taskStateJson(
      task,
      agent: resolved.agent,
      callableAgentToolNames: callableAgentToolNames,
    );
    return _success(
      <String, Object?>{
        'agent_id': resolved.agent!.id,
        'task_id': task.id,
        if (resolved.recovery != null) 'resolution': resolved.recovery,
        'title': task.title,
        'status': task.status.storageValue,
        'progress': task.progress,
        'state': state,
        'next_action': state['next_action'],
        'allowed_tools': state['allowed_tools'],
        if (state['terminal_reason'] != null)
          'terminal_reason': state['terminal_reason'],
        'result_available': task.hasResult,
        'wait': <String, Object?>{
          'requested_ms': wait.maxMs,
          'poll_ms': wait.pollMs,
          'elapsed_ms': waitedMs,
          'completed_during_wait': waitedMs > 0 && task.hasResult,
        },
        'handoff': _taskHandoffJson(
          task,
          agent: resolved.agent,
          callableAgentToolNames: callableAgentToolNames,
        ),
        'result': task.result,
        'note': task.note,
        'extra': _taskExtraJson(task.extra),
        if (_taskNextPollJson(
              task,
              agent: resolved.agent,
              callableAgentToolNames: callableAgentToolNames,
            )
            case final nextPoll?)
          'next_poll': nextPoll,
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
        'wait_elapsed_ms': waitedMs,
      },
    );
  }

  bool _shouldAutoExecuteTask(Map<String, Object?> args, AgentTask task) {
    if (_backgroundChatClient == null || _subToolExecutor == null) {
      return false;
    }
    if (task.status != AgentTaskStatus.running ||
        '${task.extra[agentTaskAssignmentIdExtraKey] ?? ''}'.trim().isEmpty) {
      return false;
    }
    if (_agentWorkerWaitMs(args) <= 0) return false;
    final rawExtra = optionalStringKeyedMapFromValueOrJsonText(args['extra']);
    if (rawExtra != null &&
        rawExtra.containsKey(_agentTaskAutoExecuteExtraKey)) {
      return boolFromValue(rawExtra[_agentTaskAutoExecuteExtraKey]);
    }
    if (args.containsKey('auto_execute')) {
      return boolFromValue(args['auto_execute']);
    }
    return boolFromValue(args['wait_for_result'], defaultValue: true);
  }

  Future<_AgentWorkerRunResult> _runAgentWorker({
    required AgentsController controller,
    required AiToolExecutionContext context,
    required AgentProfile agent,
    required AgentTask task,
    required Set<String> callableAgentToolNames,
    required int maxDurationMs,
  }) async {
    final startedAt = Stopwatch()..start();
    final maxDuration = Duration(milliseconds: maxDurationMs);
    final timeoutMessage = '数字员工执行超过 $maxDurationMs 毫秒时限。';
    final workerId = '${task.extra['assigned_worker_id'] ?? ''}'.trim();
    final workerSessionId =
        '${context.sessionId}/agent/${_normalizeWorkerToken(agent.id)}/task/${_normalizeWorkerToken(task.id)}';
    final toolEntries = _agentWorkerToolEntries(agent, context.catalog);
    final workerCatalog = AiResolvedToolCatalog(
      definitions: toolEntries
          .map((entry) => entry.value.definition)
          .toList(growable: false),
      toolsByName: Map<String, AiResolvedTool>.fromEntries(toolEntries),
    );
    final workerModel = _modelForAgent(agent, context.model);
    final readFiles = <String>{};
    final toolCalls = <Map<String, Object?>>[];
    AiTokenUsage? usage;
    var completedRounds = 0;
    var toolOutputChars = 0;
    String boundedToolOutput(String value) {
      final remaining = _agentWorkerMaxTotalToolOutputChars - toolOutputChars;
      if (remaining <= 0) {
        return '[工具输出已省略：累计输出达到上限]';
      }
      final limit = remaining < _agentWorkerMaxToolOutputChars
          ? remaining
          : _agentWorkerMaxToolOutputChars;
      final bounded = clipTextByCodeUnits(
        value,
        limit,
        suffix: '\n\n[工具输出已截断]',
      );
      toolOutputChars += bounded.length;
      return bounded;
    }

    Future<_AgentWorkerRunResult> finishFailure(String status, String error) {
      return _writeWorkerFailure(
        controller,
        agent,
        task,
        _AgentWorkerRunResult(
          status: status,
          rounds: completedRounds,
          toolCount: workerCatalog.definitions.length,
          toolCalls: toolCalls,
          durationMs: startedAt.elapsedMilliseconds,
          modelConfigId: workerModel.id,
          modelId: workerModel.modelId,
          tokenUsage: usage,
          error: error,
        ),
      );
    }

    Future<_AgentWorkerRunResult> finishTimeout() {
      return finishFailure('timeout', timeoutMessage);
    }

    Future<_AgentWorkerRunResult> finishCancelled() {
      return finishFailure(
        'cancelled',
        '数字员工执行已取消。',
      );
    }

    if (await isCancelSignalCompleted(context.cancelSignal)) {
      return finishCancelled();
    }
    try {
      final promptBudget = maxDuration - startedAt.elapsed;
      if (promptBudget <= Duration.zero) {
        return finishTimeout();
      }
      final promptSnapshot = await AiToolUtils.awaitWithCancellation(
        _promptRenderer
            .render(
              agent: agent,
              task: task,
              callableAgentToolNames: callableAgentToolNames,
              boundInstructions: _boundInstructionsForAgent(agent),
              taskContext: <String, Object?>{
                'execution_mode': 'automatic_worker',
                'worker_session_id': workerSessionId,
                if (workerId.isNotEmpty) 'worker_id': workerId,
              },
            )
            .timeout(promptBudget),
        cancelSignal: context.cancelSignal,
      );
      if (promptSnapshot == null) return finishCancelled();
      final turns = <AiChatTurn>[
        AiChatTurn(
          role: AiChatRole.system,
          content:
              '${promptSnapshot.renderedPrompt}\n\n'
              '<worker_execution>\n'
              'Complete this assigned task now. Use bound tools only when useful. '
              'Do not call agent coordination tools, Task, TodoWrite, or plan approval. '
              'Return the final result only.\n'
              '</worker_execution>',
        ),
        AiChatTurn(role: AiChatRole.user, content: _workerTaskPrompt(task)),
      ];
      for (var round = 0; round < _agentWorkerMaxToolRounds; round++) {
        if (await isCancelSignalCompleted(context.cancelSignal)) {
          return finishCancelled();
        }
        final remaining = maxDuration - startedAt.elapsed;
        if (remaining <= Duration.zero) {
          return finishTimeout();
        }
        final turnTimeout = remaining < _agentWorkerTurnTimeout
            ? remaining
            : _agentWorkerTurnTimeout;
        final completion = await AiToolUtils.awaitWithCancellation(
          AiUsageTraceContext.runDerived(
            source: AiUsageSource.agent,
            operation: 'agent_worker_round',
            metadata: <String, Object?>{
              'agent_id': agent.id,
              'task_id': task.id,
              'round': round + 1,
            },
            body: () => _backgroundChatClient!
                .sendMessage(
                  model: workerModel,
                  messages: turns,
                  tools: workerCatalog.definitions,
                  timeout: turnTimeout,
                  cancelSignal: context.cancelSignal,
                )
                .timeout(turnTimeout),
          ),
          cancelSignal: context.cancelSignal,
        );
        if (completion == null) {
          return finishCancelled();
        }
        completedRounds = round + 1;
        usage = usage == null
            ? completion.usage
            : completion.usage == null
            ? usage
            : usage.merge(completion.usage!);
        final reply = _boundedWorkerResult(completion.reply);
        if (completion.toolCalls.isEmpty) {
          final finalResult = reply;
          final result = _AgentWorkerRunResult(
            status: finalResult.isEmpty ? 'failed' : 'completed',
            rounds: round + 1,
            toolCount: workerCatalog.definitions.length,
            toolCalls: toolCalls,
            durationMs: startedAt.elapsedMilliseconds,
            modelConfigId: workerModel.id,
            modelId: workerModel.modelId,
            tokenUsage: usage,
            result: finalResult,
            error: finalResult.isEmpty
                ? '数字员工执行完成，但未返回结果。'
                : null,
          );
          if (finalResult.isEmpty) {
            return _writeWorkerFailure(controller, agent, task, result);
          }
          return _writeWorkerSuccess(controller, agent, task, result);
        }
        if (completion.toolCalls.length > _agentWorkerMaxToolCallsPerRound ||
            toolCalls.length + completion.toolCalls.length >
                _agentWorkerMaxTotalToolCalls) {
          return finishFailure(
            'failed',
            '数字员工工具调用次数超过安全上限。',
          );
        }
        if (completion.toolCalls.any(
          (call) => call.arguments.length > _agentWorkerMaxToolArgumentChars,
        )) {
          return finishFailure(
            'failed',
            '数字员工工具参数超过安全上限。',
          );
        }
        turns.add(
          AiChatTurn(
            role: AiChatRole.assistant,
            content: reply,
            toolCalls: completion.toolCalls,
          ),
        );
        for (final toolCall in completion.toolCalls) {
          if (await isCancelSignalCompleted(context.cancelSignal)) {
            return finishCancelled();
          }
          final decodedArguments = AiToolUtils.decodeArguments(
            toolCall.arguments,
          );
          final resolvedTool = workerCatalog.find(toolCall.name);
          if (resolvedTool?.builtinKind == null) {
            final result = AiToolUtils.invalidResult(
              toolCall.name,
              '当前数字员工无法使用该工具。',
            );
            turns.add(
              AiChatTurn(
                role: AiChatRole.tool,
                toolCallId: toolCall.id,
                content: boundedToolOutput(result.toToolOutput()),
              ),
            );
            toolCalls.add(_workerToolCallJson(toolCall, result));
            continue;
          }
          final toolBudget = maxDuration - startedAt.elapsed;
          if (toolBudget <= Duration.zero) {
            return finishTimeout();
          }
          final timeoutCancellation = Completer<void>();
          final subContext = AiToolExecutionContext(
            sessionId: workerSessionId,
            catalog: workerCatalog,
            toolCall: toolCall,
            decodedArguments: decodedArguments,
            model: workerModel,
            previouslyReadFiles: readFiles,
            denyCommandRules: context.denyCommandRules,
            requireWriteCommandConfirmation:
                context.requireWriteCommandConfirmation,
            confirmWriteCommand: context.confirmWriteCommand,
            cancelSignal: combineCancelSignals(<Future<void>?>[
              context.cancelSignal,
              timeoutCancellation.future,
            ]),
            onBashUpdate: context.onBashUpdate,
            metadata: <String, Object?>{
              ...context.metadata,
              'agent_worker_execution': true,
              'agent_id': agent.id,
              'task_id': task.id,
              if (workerId.isNotEmpty) 'worker_id': workerId,
            },
          );
          final toolResult = await AiToolUtils.awaitWithCancellation(
            _subToolExecutor!(context, subContext).timeout(
              toolBudget,
              onTimeout: () {
                if (!timeoutCancellation.isCompleted) {
                  timeoutCancellation.complete();
                }
                throw TimeoutException(
                  timeoutMessage,
                  maxDuration,
                );
              },
            ),
            cancelSignal: context.cancelSignal,
          );
          if (toolResult == null) return finishCancelled();
          final readFilePath = '${toolResult.metadata['read_file_path'] ?? ''}'
              .trim();
          if (readFilePath.isNotEmpty) readFiles.add(readFilePath);
          turns.add(
            AiChatTurn(
              role: AiChatRole.tool,
              toolCallId: toolCall.id,
              content: boundedToolOutput(toolResult.toToolOutput()),
            ),
          );
          toolCalls.add(_workerToolCallJson(toolCall, toolResult));
        }
      }
      return finishFailure(
        'failed',
        '数字员工超过 $_agentWorkerMaxToolRounds 个工具轮次。',
      );
    } on TimeoutException catch (error, stack) {
      if (await isCancelSignalCompleted(context.cancelSignal)) {
        return finishCancelled();
      }
      silentLog('ai_agent_tools', '执行数字员工任务超时', error, stack);
      return finishTimeout();
    } catch (error, stack) {
      if (await isCancelSignalCompleted(context.cancelSignal)) {
        return finishCancelled();
      }
      silentLog('ai_agent_tools', '执行数字员工任务', error, stack);
      return finishFailure('failed', '数字员工执行失败。');
    }
  }

  List<MapEntry<String, AiResolvedTool>> _agentWorkerToolEntries(
    AgentProfile agent,
    AiResolvedToolCatalog catalog,
  ) {
    final configured = trimmedNonEmptyStrings(agent.builtinToolNames);
    final configuredLookup = configured
        .where((name) => !isAgentNoCoordinationToolsBinding(name))
        .map(_normalizedAgentToolName)
        .toSet();
    return catalog.toolsByName.entries
        .where((entry) {
          final tool = entry.value;
          if (tool.source != AiRuntimeToolSource.builtin) return false;
          final kind = tool.builtinKind;
          if (kind == null || _agentWorkerBlockedBuiltinKinds.contains(kind)) {
            return false;
          }
          if (configured.isEmpty) {
            return _agentWorkerDefaultBuiltinKinds.contains(kind);
          }
          return configuredLookup.contains(
                _normalizedAgentToolName(tool.name),
              ) ||
              configuredLookup.contains(
                _normalizedAgentToolName(tool.definition.name),
              ) ||
              configuredLookup.contains(_normalizedAgentToolName(kind.name));
        })
        .toList(growable: false);
  }

  AiModelConfig _modelForAgent(AgentProfile agent, AiModelConfig fallback) {
    final configId = agent.modelProviderConfigId?.trim() ?? '';
    final modelId = agent.modelId?.trim() ?? '';
    final models = _aiModelsProvider?.call() ?? const <AiModelConfig>[];
    AiModelConfig? match;
    if (configId.isNotEmpty) {
      for (final model in models) {
        if (model.id == configId) {
          match = model;
          break;
        }
      }
    }
    if (match == null && modelId.isNotEmpty) {
      for (final model in models) {
        if (model.allModelIds.contains(modelId)) {
          match = model;
          break;
        }
      }
    }
    if (match == null) return fallback;
    return modelId.isEmpty ? match : match.copyWith(modelId: modelId);
  }

  Future<_AgentWorkerRunResult> _writeWorkerSuccess(
    AgentsController controller,
    AgentProfile agent,
    AgentTask task,
    _AgentWorkerRunResult result,
  ) async {
    final updated = await controller.updateTaskState(
      agent.id,
      task.id,
      status: AgentTaskStatus.completed,
      expectedAssignmentId:
          '${task.extra[agentTaskAssignmentIdExtraKey] ?? ''}',
      progress: 1,
      result: result.result ?? '',
      extra: _workerTaskExtra(result, retryable: false),
      activityKind: 'task_completed',
      activityTitle: 'task_completed',
      auditToolName: _agentTaskAutoWorkerToolName,
    );
    return _recordWorkerExecution(
      controller,
      agent,
      task,
      result,
      updatedTask: updated,
    );
  }

  Future<_AgentWorkerRunResult> _writeWorkerFailure(
    AgentsController controller,
    AgentProfile agent,
    AgentTask task,
    _AgentWorkerRunResult result,
  ) async {
    final cancelled = result.status == 'cancelled';
    final updated = await controller.updateTaskState(
      agent.id,
      task.id,
      status: cancelled ? AgentTaskStatus.canceled : AgentTaskStatus.failed,
      expectedAssignmentId:
          '${task.extra[agentTaskAssignmentIdExtraKey] ?? ''}',
      progress: task.progress,
      note:
          result.error ??
          (cancelled
              ? '数字员工执行已取消。'
              : '数字员工执行失败。'),
      result: result.result ?? '',
      extra: _workerTaskExtra(result, retryable: false),
      activityKind: cancelled ? 'task_canceled' : 'task_failed',
      activityTitle: cancelled ? 'task_canceled' : 'task_failed',
      auditToolName: _agentTaskAutoWorkerToolName,
    );
    return _recordWorkerExecution(
      controller,
      agent,
      task,
      result,
      updatedTask: updated,
    );
  }

  Future<_AgentWorkerRunResult> _recordWorkerExecution(
    AgentsController controller,
    AgentProfile agent,
    AgentTask task,
    _AgentWorkerRunResult result, {
    required AgentTask? updatedTask,
  }) async {
    final currentTask = updatedTask ?? controller.taskById(agent.id, task.id);
    final recorded = result.copyWith(
      taskUpdateApplied: updatedTask != null,
      taskStatus: currentTask?.status.storageValue ?? '',
    );
    await controller.recordAuditEvent(
      agent.id,
      kind: 'worker_execution',
      summary: '数字员工执行：${task.title}（${recorded.status}）',
      toolName: _agentTaskAutoWorkerToolName,
      tokenUsage: recorded.tokenUsage?.totalTokens ?? 0,
      requestCount: 1,
      metadata: <String, Object?>{
        'task_id': task.id,
        if ('${task.extra['assigned_worker_id'] ?? ''}'.trim().isNotEmpty)
          'worker_id': '${task.extra['assigned_worker_id']}',
        'worker_execution_status': recorded.status,
        'task_update_applied': recorded.taskUpdateApplied,
        if (recorded.taskStatus.isNotEmpty) 'task_status': recorded.taskStatus,
        'duration_ms': recorded.durationMs,
        'rounds': recorded.rounds,
        'tool_call_count': recorded.toolCalls.length,
        'model_config_id': recorded.modelConfigId,
        'model_id': recorded.modelId,
        if (recorded.error != null) 'error': recorded.error,
      },
      auditToolName: _agentTaskAutoWorkerToolName,
    );
    return recorded;
  }

  Map<String, Object?> _workerTaskExtra(
    _AgentWorkerRunResult result, {
    required bool retryable,
  }) {
    return <String, Object?>{
      _agentTaskAutoExecuteExtraKey: true,
      'worker_execution_status': result.status,
      'worker_execution_duration_ms': result.durationMs,
      'worker_execution_rounds': result.rounds,
      'worker_execution_tool_call_count': result.toolCalls.length,
      'worker_model_config_id': result.modelConfigId,
      'worker_model_id': result.modelId,
      'worker_finished_at': DateTime.now().toUtc().toIso8601String(),
      'retryable': retryable,
      if (result.error != null) 'worker_execution_error': result.error,
      if (result.tokenUsage != null)
        'worker_token_usage': result.tokenUsage!.toJson(),
    };
  }

  Map<String, Object?> _workerToolCallJson(
    AiToolCall toolCall,
    AiToolExecutionResult result,
  ) {
    return <String, Object?>{
      'name': toolCall.name,
      'status': result.status.name,
      'duration_ms': result.durationMs,
    };
  }

  int _agentWorkerWaitMs(Map<String, Object?> args) {
    return clampedIntFromValue(
      args['wait_ms'] ?? args['timeout_ms'],
      fallback: _agentTaskDefaultResultWaitMs,
      min: 0,
      max: _agentTaskMaxResultWaitMs,
    );
  }

  ({int maxMs, int pollMs}) _resultWaitOptions(Map<String, Object?> args) {
    final maxMs = clampedIntFromValue(
      args['wait_ms'] ?? args['timeout_ms'],
      fallback: _agentTaskDefaultResultWaitMs,
      min: 0,
      max: _agentTaskMaxResultWaitMs,
    );
    final pollMs = clampedIntFromValue(
      args['poll_ms'],
      fallback: agentTaskRecommendedPollMs,
      min: _agentTaskMinPollMs,
      max: agentTaskRecommendedPollMs * 4,
    );
    return (maxMs: maxMs, pollMs: pollMs);
  }

  bool _taskResultTerminalEnough(AgentTask task) {
    return task.hasResult ||
        task.status == AgentTaskStatus.failed ||
        task.status == AgentTaskStatus.canceled ||
        task.status == AgentTaskStatus.waitingApproval ||
        task.status == AgentTaskStatus.paused;
  }

  String _workerTaskPrompt(AgentTask task) {
    return [
      'Task id: ${task.id}',
      'Title: ${task.title}',
      if (task.description.trim().isNotEmpty)
        'Description:\n${task.description.trim()}',
      if (task.content.trim().isNotEmpty) 'Content:\n${task.content.trim()}',
      if (task.note.trim().isNotEmpty) 'Note:\n${task.note.trim()}',
    ].join('\n\n');
  }

  String _boundedWorkerResult(String value) {
    final trimmed = value.trim();
    return clipTextByCodeUnits(
      trimmed,
      _agentWorkerResultMaxChars,
      suffix: '\n\n[结果已截断]',
    );
  }

  String _normalizeWorkerToken(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? 'worker' : sanitized;
  }

  List<AgentProfile> _enabledAgentsForPolicy(
    AgentsController controller,
    _AgentToolAccessPolicy accessPolicy,
  ) {
    return _agentsForPolicy(controller, accessPolicy);
  }

  List<AgentProfile> _agentsForPolicy(
    AgentsController controller,
    _AgentToolAccessPolicy accessPolicy, {
    bool includeDisabled = false,
  }) {
    if (!accessPolicy.enabled) return const <AgentProfile>[];
    final source = includeDisabled
        ? controller.agents
        : controller.enabledAgents;
    if (!accessPolicy.isScoped) return source.toList(growable: false);
    return source.where(accessPolicy.allows).toList(growable: false);
  }

  AgentProfile? _findAgentForPolicy(
    AgentsController controller,
    String identifier,
    _AgentToolAccessPolicy accessPolicy, {
    bool includeDisabled = false,
  }) {
    final normalized = identifier.trim();
    if (normalized.isEmpty) return null;
    final normalizedName = normalized.toLowerCase();
    for (final agent in _agentsForPolicy(
      controller,
      accessPolicy,
      includeDisabled: includeDisabled,
    )) {
      if (agent.id == normalized ||
          agent.name.trim().toLowerCase() == normalizedName) {
        return agent;
      }
    }
    return null;
  }

  /// 从执行上下文解析目标数字员工：统一读取入参、会话可见性策略与
  /// `include_disabled` 开关，避免各操作重复拼装同一段样板。
  _AgentResolution _resolveContextAgent(
    AgentsController controller,
    AiToolExecutionContext context, {
    bool honorIncludeDisabled = false,
  }) {
    final args = context.decodedArguments;
    return _resolveAgent(
      controller,
      args,
      includeDisabled:
          honorIncludeDisabled && boolFromValue(args['include_disabled']),
      accessPolicy: _AgentToolAccessPolicy.fromMetadata(context.metadata),
    );
  }

  _AgentResolution _resolveAgent(
    AgentsController controller,
    Map<String, Object?> args, {
    bool includeDisabled = false,
    required _AgentToolAccessPolicy accessPolicy,
  }) {
    final identifier =
        '${args['agent_id'] ?? args['agent_name'] ?? args['agent'] ?? ''}'
            .trim();
    if (identifier.isEmpty) {
      return _AgentResolution.error(
        AiToolUtils.invalidResult(
          _name,
          'agent_id、agent_name 或 agent 至少需要提供一个。',
        ),
      );
    }
    final agent = _findAgentForPolicy(
      controller,
      identifier,
      accessPolicy,
      includeDisabled: includeDisabled,
    );
    if (agent != null) {
      if (!_agentAllowsCurrentTool(agent)) {
        return _AgentResolution.error(
          AiToolUtils.invalidResult(
            _name,
            '数字员工“${agent.name}”未绑定 $_name，请先在其配置中启用该工具。',
          ),
        );
      }
      return _AgentResolution.agent(agent);
    }
    final disabled = _findAgentForPolicy(
      controller,
      identifier,
      accessPolicy,
      includeDisabled: true,
    );
    if (disabled != null && !disabled.enabled) {
      return _AgentResolution.error(
        AiToolUtils.invalidResult(
          _name,
          '数字员工“$identifier”已停用，请先启动。',
        ),
      );
    }
    final existing = controller.findAgent(identifier, includeDisabled: true);
    if (existing != null && !accessPolicy.allows(existing)) {
      return _AgentResolution.error(
        AiToolUtils.invalidResult(
          _name,
          '当前会话无法访问数字员工“$identifier”。',
        ),
      );
    }
    return _AgentResolution.error(
      AiToolUtils.invalidResult(
        _name,
        '未找到匹配“$identifier”的已启用数字员工。',
      ),
    );
  }

  _AgentResolution _resolveKpiAgent(
    AgentsController controller,
    Map<String, Object?> args, {
    required String name,
    required List<String> labels,
    required Set<String> callableAgentToolNames,
    required _AgentToolAccessPolicy accessPolicy,
  }) {
    return _resolveRoutedAgent(
      controller,
      args,
      title: name,
      description: '${args['target'] ?? ''}',
      content: '${args['plan'] ?? ''}',
      note: '${args['status'] ?? ''}',
      labels: labels,
      contextKind: 'kpi',
      guidance:
          '需要提供 agent_id、agent_name 或可路由的 KPI 上下文。启用多个数字员工时，请先从 routing_diagnostics 选择 agent_id。',
      callableAgentToolNames: callableAgentToolNames,
      accessPolicy: accessPolicy,
    );
  }

  _AgentResolution _resolveApprovalAgent(
    AgentsController controller,
    Map<String, Object?> args, {
    required String title,
    required List<String> labels,
    required Set<String> callableAgentToolNames,
    required _AgentToolAccessPolicy accessPolicy,
  }) {
    return _resolveRoutedAgent(
      controller,
      args,
      title: title,
      description: '${args['reason'] ?? ''}',
      content: '${args['requested_action'] ?? ''}',
      note: '',
      labels: labels,
      contextKind: 'approval',
      guidance:
          '需要提供 agent_id、agent_name 或可路由的审批上下文。启用多个数字员工时，请先从 routing_diagnostics 选择 agent_id。',
      callableAgentToolNames: callableAgentToolNames,
      accessPolicy: accessPolicy,
    );
  }

  _AgentResolution _resolvePublishAgent(
    AgentsController controller,
    Map<String, Object?> args, {
    required String title,
    required List<String> labels,
    required Set<String> callableAgentToolNames,
    required _AgentToolAccessPolicy accessPolicy,
  }) {
    return _resolveRoutedAgent(
      controller,
      args,
      title: title,
      description: '${args['description'] ?? ''}',
      content: '${args['content'] ?? ''}',
      note: '${args['note'] ?? ''}',
      labels: labels,
      contextKind: 'task',
      guidance:
          '需要提供 agent_id、agent_name 或可路由的任务上下文。启用多个数字员工时，请先从 routing_diagnostics 选择 agent_id。',
      callableAgentToolNames: callableAgentToolNames,
      accessPolicy: accessPolicy,
    );
  }

  _AgentResolution _resolveRoutedAgent(
    AgentsController controller,
    Map<String, Object?> args, {
    required String title,
    required String description,
    required String content,
    required String note,
    required List<String> labels,
    required String contextKind,
    required String guidance,
    required Set<String> callableAgentToolNames,
    required _AgentToolAccessPolicy accessPolicy,
  }) {
    final identifier =
        '${args['agent_id'] ?? args['agent_name'] ?? args['agent'] ?? ''}'
            .trim();
    if (identifier.isNotEmpty) {
      return _resolveAgent(controller, args, accessPolicy: accessPolicy);
    }

    final candidates = _enabledAgentsForCurrentTool(controller, accessPolicy);
    if (candidates.isEmpty) return _noAgentBoundCurrentToolResult();
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
      description: description,
      content: content,
      note: note,
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
      _routingRequiredResult(
        candidates,
        contextKind: contextKind,
        guidance: guidance,
        title: title,
        description: description,
        content: content,
        note: note,
        labels: labels,
        callableAgentToolNames: callableAgentToolNames,
      ),
    );
  }

  List<AgentProfile> _enabledAgentsForCurrentTool(
    AgentsController controller,
    _AgentToolAccessPolicy accessPolicy,
  ) {
    return _enabledAgentsForPolicy(
      controller,
      accessPolicy,
    ).where(_agentAllowsCurrentTool).toList(growable: false);
  }

  _AgentResolution _noAgentBoundCurrentToolResult() {
    return _AgentResolution.error(
      AiToolUtils.invalidResult(
        _name,
        '没有已启用的数字员工绑定 $_name，请先在数字员工配置中启用该工具。',
      ),
    );
  }

  bool _agentAllowsCurrentTool(AgentProfile agent) {
    return _agentAllowsToolNames(agent, <String>{
      _normalizedAgentToolName(_name),
      _normalizedAgentToolName(_kind.name),
      _normalizedAgentToolName(_snakeName(_name)),
    });
  }

  AiToolExecutionResult _routingRequiredResult(
    List<AgentProfile> candidates, {
    required String contextKind,
    required String guidance,
    required String title,
    required String description,
    required String content,
    required String note,
    required List<String> labels,
    required Set<String> callableAgentToolNames,
  }) {
    final diagnostics = _routingDiagnosticsJson(
      candidates,
      title: title,
      description: description,
      content: content,
      note: note,
      labels: labels,
      callableAgentToolNames: callableAgentToolNames,
    );
    final payload = <String, Object?>{
      'status': BashToolExecutionStatus.invalidArguments.storageValue,
      'error': guidance,
      'context_kind': contextKind,
      'next_action': 'select_agent_id',
      'routing_diagnostics': diagnostics,
    };
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.invalidArguments,
      command: _name,
      workingDirectory: AiToolUtils.defaultWorkingDirectory(),
      stdout: '',
      stderr: guidance,
      durationMs: 0,
      resultText: prettyPrintJson(payload),
      metadata: <String, Object?>{
        'tool': _name,
        'action': 'agent_routing_required',
        'context_kind': contextKind,
        'candidate_count': (diagnostics['candidates'] as List<Object?>).length,
      },
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
    final matches = _routeMatchesForTask(
      agents,
      title: title,
      description: description,
      content: content,
      note: note,
      labels: labels,
    );
    if (matches.isEmpty || matches.first.score < 4) return null;
    if (matches.length > 1 && matches[1].score == matches.first.score) {
      return null;
    }
    return matches.first;
  }

  Map<String, Object?> _routingDiagnosticsJson(
    List<AgentProfile> agents, {
    required String title,
    required String description,
    required String content,
    required String note,
    required List<String> labels,
    required Set<String> callableAgentToolNames,
  }) {
    final matches = _routeMatchesForTask(
      agents,
      title: title,
      description: description,
      content: content,
      note: note,
      labels: labels,
    );
    final bestScore = matches.isEmpty ? 0 : matches.first.score;
    final topTieCount = matches
        .where((match) => match.score == bestScore)
        .length;
    final candidates = matches.isEmpty
        ? agents
              .take(5)
              .map(
                (agent) => _routeCandidateJson(
                  agent,
                  score: 0,
                  reason: '',
                  matched: false,
                  callableAgentToolNames: callableAgentToolNames,
                ),
              )
              .toList(growable: false)
        : matches
              .take(5)
              .map(
                (match) => _routeCandidateJson(
                  match.agent,
                  score: match.score,
                  reason: match.reason,
                  matched: true,
                  callableAgentToolNames: callableAgentToolNames,
                ),
              )
              .toList(growable: false);
    return <String, Object?>{
      'input': <String, Object?>{
        'title': title,
        if (description.trim().isNotEmpty) 'description': description,
        if (content.trim().isNotEmpty) 'content': content,
        if (note.trim().isNotEmpty) 'note': note,
        if (labels.isNotEmpty) 'labels': labels,
      },
      'candidate_count': candidates.length,
      'best_score': bestScore,
      'minimum_score': 4,
      'ambiguous': topTieCount > 1,
      'reason': matches.isEmpty
          ? 'no_route_signal'
          : topTieCount > 1
          ? 'ambiguous_top_score'
          : 'score_below_threshold',
      'candidates': candidates,
    };
  }

  List<_AgentRouteMatch> _routeMatchesForTask(
    List<AgentProfile> agents, {
    required String title,
    required String description,
    required String content,
    required String note,
    required List<String> labels,
  }) {
    final matches = <_AgentRouteMatch>[];
    for (final agent in agents) {
      final match = _scoreAgentRoute(
        agent,
        title: title,
        description: description,
        content: content,
        note: note,
        labels: labels,
      );
      if (match != null) matches.add(match);
    }
    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.agent.name.toLowerCase().compareTo(b.agent.name.toLowerCase());
    });
    return matches;
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
    final taskTexts = _routeTextVariants(
      <String>[title, description, content, note, ...labels].join(' '),
    );
    if (taskTexts.isEmpty) return null;

    var score = 0;
    final reasons = <String>[];
    void addSignal(String label, Iterable<String> values, int weight) {
      for (final value in values) {
        final signals = _routeTextVariants(value);
        if (signals.isEmpty) continue;
        final matched = signals.any(
          (signal) => taskTexts.any((taskText) => taskText.contains(signal)),
        );
        if (matched) {
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
    Map<String, Object?> args, {
    required String sessionId,
    required _AgentToolAccessPolicy accessPolicy,
    bool allowHeuristicRecovery = false,
  }) {
    final agentResolution = _resolveAgent(
      controller,
      args,
      accessPolicy: accessPolicy,
    );
    if (agentResolution.error != null) {
      return _TaskResolution.error(agentResolution.error!);
    }
    final taskId = '${args['task_id'] ?? args['id'] ?? ''}'.trim();
    final agent = agentResolution.agent!;
    final workerId = _optionalText(args['worker_id']);
    if (taskId.isEmpty) {
      if (allowHeuristicRecovery) {
        final recovered = _recoverTask(
          agent,
          requestedTaskId: null,
          workerId: workerId,
          sessionId: sessionId,
        );
        if (recovered != null) {
          return _TaskResolution(
            agent: agent,
            task: recovered.task,
            recovery: recovered.toJson(),
          );
        }
      }
      return _TaskResolution.error(
        AiToolUtils.invalidResult(_name, 'task_id 为必填参数。'),
      );
    }
    final task = controller.taskById(agent.id, taskId);
    if (task == null) {
      if (allowHeuristicRecovery) {
        final recovered = _recoverTask(
          agent,
          requestedTaskId: taskId,
          workerId: workerId,
          sessionId: sessionId,
        );
        if (recovered != null) {
          return _TaskResolution(
            agent: agent,
            task: recovered.task,
            recovery: recovered.toJson(),
          );
        }
      }
      return _TaskResolution.error(
        AiToolUtils.invalidResult(
          _name,
          '数字员工“${agent.name}”不存在任务“$taskId”。'
          '${_recentTaskHint(agent)}',
        ),
      );
    }
    return _TaskResolution(agent: agent, task: task);
  }

  _RecoveredTask? _recoverTask(
    AgentProfile agent, {
    required String? requestedTaskId,
    required String? workerId,
    required String sessionId,
  }) {
    final byWorker = workerId == null
        ? const <AgentTask>[]
        : recentAgentTasks(agent.tasks)
              .where((task) => _taskAssignedToWorker(task, workerId))
              .toList(growable: false);
    if (byWorker.length == 1) {
      return _RecoveredTask(
        task: byWorker.single,
        requestedTaskId: requestedTaskId,
        reason: 'unique_worker_task',
      );
    }

    final bySession = recentAgentTasks(agent.tasks)
        .where(
          (task) =>
              '${task.extra['published_by_session_id'] ?? ''}'.trim() ==
              sessionId,
        )
        .toList(growable: false);
    final activeBySession = bySession
        .where((task) => !task.status.isTerminal)
        .toList(growable: false);
    if (activeBySession.length == 1) {
      return _RecoveredTask(
        task: activeBySession.single,
        requestedTaskId: requestedTaskId,
        reason: 'unique_active_session_task',
      );
    }
    if (bySession.length == 1) {
      return _RecoveredTask(
        task: bySession.single,
        requestedTaskId: requestedTaskId,
        reason: 'unique_session_task',
      );
    }

    final active = recentAgentTasks(
      agent.tasks,
    ).where((task) => !task.status.isTerminal).toList(growable: false);
    if (active.length == 1) {
      return _RecoveredTask(
        task: active.single,
        requestedTaskId: requestedTaskId,
        reason: 'unique_active_task',
      );
    }
    final tasks = recentAgentTasks(agent.tasks);
    if (tasks.length == 1) {
      return _RecoveredTask(
        task: tasks.single,
        requestedTaskId: requestedTaskId,
        reason: 'only_task',
      );
    }
    return null;
  }

  String _recentTaskHint(AgentProfile agent) {
    final recent = recentAgentTasks(agent.tasks, limit: 5)
        .map((task) {
          return '${task.id}(${task.status.storageValue})';
        })
        .join(', ');
    return recent.isEmpty
        ? '当前没有任务记录。'
        : '最近任务：$recent。';
  }

  AiToolExecutionResult _success(
    Map<String, Object?> payload,
    Stopwatch stopwatch, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final output = prettyPrintJson(
      convertToJsonSafeMap(payload, config: _agentToolResultConversionConfig),
    );
    return AiToolUtils.simpleSuccessResult(
      command: _name,
      output: output,
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

Object? _redactAgentToolPromptValue(String key, Object? value) {
  final normalizedKey = key.toLowerCase();
  if (normalizedKey == 'rendered_prompt' && value is _ExplicitAgentPromptText) {
    return value.text;
  }
  if (!_agentToolSensitivePromptKeys.contains(normalizedKey)) return value;
  return <String, Object?>{
    'omitted': true,
    if (value is String) 'chars': value.length,
    'reason': '敏感提示内容已从智能体工具结果中移除。',
  };
}

final class _ExplicitAgentPromptText {
  const _ExplicitAgentPromptText(this.text);

  final String text;
}

String _normalizedAgentToolName(String value) {
  return normalizeAsciiLookupKey(value);
}

bool _agentAllowsToolNames(AgentProfile agent, Set<String> normalizedNames) {
  final configured = trimmedNonEmptyStrings(agent.builtinToolNames);
  if (configured.isEmpty) return true;
  if (agentHasNoCoordinationToolsBinding(configured)) return false;
  return configured.any(
    (name) => normalizedNames.contains(_normalizedAgentToolName(name)),
  );
}

class _AgentToolAccessPolicy {
  const _AgentToolAccessPolicy({
    required this.enabled,
    required this.allowedAgentIds,
    required this.source,
  });

  factory _AgentToolAccessPolicy.fromMetadata(Map<String, Object?> metadata) {
    final source = '${metadata[aiAgentToolAccessSourceMetadataKey] ?? ''}'
        .trim();
    final hasScopedMetadata =
        source.isNotEmpty ||
        metadata.containsKey(aiAgentToolAccessEnabledMetadataKey) ||
        metadata.containsKey(aiAgentToolAllowedAgentIdsMetadataKey);
    if (!hasScopedMetadata) return unrestricted;
    final enabled = boolFromValue(
      metadata[aiAgentToolAccessEnabledMetadataKey],
      defaultValue: true,
    );
    final allowedIds = stringListFromValue(
      metadata[aiAgentToolAllowedAgentIdsMetadataKey],
    ).where((id) => id.trim().isNotEmpty).toSet();
    return _AgentToolAccessPolicy(
      enabled: enabled,
      allowedAgentIds: allowedIds,
      source: source,
    );
  }

  static const _AgentToolAccessPolicy unrestricted = _AgentToolAccessPolicy(
    enabled: true,
    allowedAgentIds: null,
    source: '',
  );

  final bool enabled;
  final Set<String>? allowedAgentIds;
  final String source;

  bool get isScoped => allowedAgentIds != null;

  bool allows(AgentProfile agent) {
    final ids = allowedAgentIds;
    return enabled && (ids == null || ids.contains(agent.id));
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
  const _TaskResolution({this.agent, this.task, this.error, this.recovery});

  factory _TaskResolution.error(AiToolExecutionResult error) {
    return _TaskResolution(error: error);
  }

  final AgentProfile? agent;
  final AgentTask? task;
  final AiToolExecutionResult? error;
  final Map<String, Object?>? recovery;
}

class _RecoveredTask {
  const _RecoveredTask({
    required this.task,
    required this.requestedTaskId,
    required this.reason,
  });

  final AgentTask task;
  final String? requestedTaskId;
  final String reason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'recovered': true,
      if (requestedTaskId != null && requestedTaskId!.isNotEmpty)
        'requested_task_id': requestedTaskId,
      'resolved_task_id': task.id,
      'reason': reason,
      'message':
          '请求的任务 ID 缺失或不存在，OpenHand 已恢复最可靠的匹配任务。',
    };
  }
}

class _AgentWorkerRunResult {
  const _AgentWorkerRunResult({
    required this.status,
    required this.rounds,
    required this.toolCount,
    required this.toolCalls,
    required this.durationMs,
    required this.modelConfigId,
    required this.modelId,
    this.tokenUsage,
    this.result,
    this.error,
    this.taskUpdateApplied = false,
    this.taskStatus = '',
  });

  final String status;
  final int rounds;
  final int toolCount;
  final List<Map<String, Object?>> toolCalls;
  final int durationMs;
  final String modelConfigId;
  final String modelId;
  final AiTokenUsage? tokenUsage;
  final String? result;
  final String? error;
  final bool taskUpdateApplied;
  final String taskStatus;

  _AgentWorkerRunResult copyWith({
    bool? taskUpdateApplied,
    String? taskStatus,
  }) {
    return _AgentWorkerRunResult(
      status: status,
      rounds: rounds,
      toolCount: toolCount,
      toolCalls: toolCalls,
      durationMs: durationMs,
      modelConfigId: modelConfigId,
      modelId: modelId,
      tokenUsage: tokenUsage,
      result: result,
      error: error,
      taskUpdateApplied: taskUpdateApplied ?? this.taskUpdateApplied,
      taskStatus: taskStatus ?? this.taskStatus,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status,
      'rounds': rounds,
      'tool_count': toolCount,
      'tool_calls': toolCalls,
      'duration_ms': durationMs,
      'model_config_id': modelConfigId,
      'model_id': modelId,
      'task_update_applied': taskUpdateApplied,
      if (taskStatus.isNotEmpty) 'task_status': taskStatus,
      if (tokenUsage != null) 'token_usage': tokenUsage!.toJson(),
      if (result != null && result!.trim().isNotEmpty)
        'result_preview': _previewText(result!),
      if (error != null && error!.trim().isNotEmpty) 'error': error,
    };
  }
}

String _previewText(String value) {
  final trimmed = value.trim();
  return clipTextByCodeUnits(
    trimmed,
    _agentWorkerResultPreviewMaxChars,
    suffix: '\n\n[预览已截断]',
  );
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

Set<String> _callableAgentToolNames(AiResolvedToolCatalog catalog) {
  // 仅解析当前目录，避免结果声明已全局禁用的工具。
  final result = <String>{};
  for (final kind in _agentCoordinationToolKinds) {
    final name = agentBuiltinToolCanonicalName(kind);
    if (catalog.find(name) != null) {
      result.add(_normalizedAgentToolName(name));
    }
  }
  return result;
}

Map<String, Object?> _agentSummaryJson(
  AgentProfile agent, {
  Set<String>? callableAgentToolNames,
}) {
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
    'capabilities': agentCapabilityBindingsJson(
      agent,
      callableAgentToolNames: callableAgentToolNames,
    ),
    'agent_tools': _agentToolBindingSummaryJson(
      agent,
      callableAgentToolNames: callableAgentToolNames,
    ),
    'workspace_policy': agentWorkspacePolicyJson(agent),
    'routing': routing.toJson(includeRawPreview: false),
    'operational_summary': _agentOperationalSummaryJson(agent),
    'updated_at': _iso(agent.updatedAt),
  };
}

Map<String, Object?> _agentToolBindingSummaryJson(
  AgentProfile agent, {
  Set<String>? callableAgentToolNames,
}) {
  final configured = normalizeAgentBuiltinToolNames(agent.builtinToolNames);
  final hasExplicitNone = agentHasNoCoordinationToolsBinding(configured);
  final configuredKinds = hasExplicitNone
      ? const <AiBuiltinToolKind>[]
      : configured.isEmpty
      ? _agentCoordinationToolKinds
      : _agentToolKindsFromNames(configured);
  final kinds = callableAgentToolNames == null
      ? configuredKinds
      : configuredKinds
            .where(
              (kind) => callableAgentToolNames.contains(
                _normalizedAgentToolName(agentBuiltinToolCanonicalName(kind)),
              ),
            )
            .toList(growable: false);
  final hasNoAgentToolBindings =
      hasExplicitNone || (configured.isNotEmpty && configuredKinds.isEmpty);
  final tools = kinds
      .map(agentBuiltinToolCanonicalName)
      .toList(growable: false);
  final groups = <String, List<String>>{};
  final mutationTools = <String>[];
  for (final kind in kinds) {
    final tool = agentBuiltinToolCanonicalName(kind);
    final group = _agentToolGroupStorageName(kind.agentToolGroup);
    if (group != null) {
      groups.putIfAbsent(group, () => <String>[]).add(tool);
    }
    if (kind.isAgentMutationTool) mutationTools.add(tool);
  }
  return <String, Object?>{
    'binding_mode': hasNoAgentToolBindings
        ? 'none'
        : configured.isEmpty
        ? 'all_agent_tools'
        : 'explicit',
    'tools': tools,
    'groups': groups,
    'mutation_tools': mutationTools,
    'count': tools.length,
    if (callableAgentToolNames != null) ...<String, Object?>{
      'configured_count': configuredKinds.length,
      'runtime_filtered': configuredKinds.length != tools.length,
    },
  };
}

List<AiBuiltinToolKind> _agentToolKindsFromNames(Iterable<String> names) {
  final byName = <String, AiBuiltinToolKind>{
    for (final kind in _agentCoordinationToolKinds) ...{
      _normalizedAgentToolName(kind.name): kind,
      _normalizedAgentToolName(agentBuiltinToolCanonicalName(kind)): kind,
      _normalizedAgentToolName(
        _snakeAgentToolName(agentBuiltinToolCanonicalName(kind)),
      ): kind,
    },
  };
  final seen = <AiBuiltinToolKind>{};
  final result = <AiBuiltinToolKind>[];
  for (final name in names) {
    final kind = byName[_normalizedAgentToolName(name)];
    if (kind == null || !seen.add(kind)) continue;
    result.add(kind);
  }
  return result;
}

String? _agentToolGroupStorageName(AiAgentBuiltinToolGroup? group) {
  return switch (group) {
    AiAgentBuiltinToolGroup.discovery => 'discovery',
    AiAgentBuiltinToolGroup.taskLifecycle => 'task_lifecycle',
    AiAgentBuiltinToolGroup.governance => 'governance',
    AiAgentBuiltinToolGroup.operations => 'operations',
    AiAgentBuiltinToolGroup.cluster => 'cluster',
    null => null,
  };
}

String _snakeAgentToolName(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i += 1) {
    final code = value.codeUnitAt(i);
    final isUpper = code >= 0x41 && code <= 0x5A;
    if (isUpper && i > 0) buffer.write('_');
    buffer.writeCharCode(isUpper ? code | 0x20 : code);
  }
  return buffer.toString();
}

Map<String, Object?> _routeCandidateJson(
  AgentProfile agent, {
  required int score,
  required String reason,
  required bool matched,
  required Set<String> callableAgentToolNames,
}) {
  final routing = AgentRoutingMetadata.fromAgent(agent);
  return <String, Object?>{
    'agent_id': agent.id,
    'agent_name': agent.name,
    'score': score,
    'matched': matched,
    if (reason.trim().isNotEmpty) 'reason': reason,
    if (agent.position.trim().isNotEmpty) 'position': agent.position,
    if (agent.department.trim().isNotEmpty) 'department': agent.department,
    if (agent.taskLabels.isNotEmpty) 'task_labels': agent.taskLabels,
    if (agent.skillNames.isNotEmpty) 'skills': agent.skillNames,
    'agent_tools': _agentToolBindingSummaryJson(
      agent,
      callableAgentToolNames: callableAgentToolNames,
    ),
    if (routing.keywords.isNotEmpty)
      'routing_keywords': routing.keywords.take(12).toList(growable: false),
  };
}

Map<String, Object?> _agentDetailJson(
  AgentProfile agent, {
  required bool includeTasks,
  required bool includeAudit,
  required bool includeResources,
  required int itemLimit,
  Set<String>? callableAgentToolNames,
}) {
  return <String, Object?>{
    ..._agentSummaryJson(agent, callableAgentToolNames: callableAgentToolNames),
    'avatar': agent.avatar,
    'introduction': agent.introduction,
    'archive': agent.archive,
    'welcome_message': agent.welcomeMessage,
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
    'instruction_ids': agent.instructionIds,
    'metadata': agent.metadata,
    'scale_settings': agent.scaleSettings.toJson(),
    'task_metrics': _taskMetricsForTasksJson(agent.tasks),
    'worker_capacity': _workerCapacityJsonForAgent(agent),
    'queue_pressure': _queuePressureJson(agent),
    'kpi_summary': _kpiSummaryJson(agent.kpis),
    'approval_summary': _approvalSummaryJson(agent.approvals),
    'resource_summary': _resourceUsageSummaryJson(agent.resourceUsage),
    'kpis': sortedAgentKpisForAttention(
      agent.kpis,
      limit: itemLimit,
    ).map((item) => item.toJson()).toList(growable: false),
    'workers': agent.workers
        .take(itemLimit)
        .map((item) => item.toJson())
        .toList(growable: false),
    'approvals': sortedAgentApprovalsForAttention(
      agent.approvals,
      limit: itemLimit,
    ).map((item) => item.toJson()).toList(growable: false),
    'recent_activities': recentAgentActivities(
      agent.activities,
      limit: itemLimit < 20 ? itemLimit : 20,
    ).map((item) => item.toJson()).toList(growable: false),
    if (includeTasks)
      'tasks': sortedAgentTasksForAttention(agent.tasks, limit: itemLimit)
          .map(
            (task) => _taskJson(
              task,
              agent: agent,
              callableAgentToolNames: callableAgentToolNames,
            ),
          )
          .toList(growable: false),
    if (includeAudit)
      'audit_events': recentAgentAuditEvents(
        agent.auditEvents,
        limit: itemLimit < 50 ? itemLimit : 50,
      ).map((item) => item.toJson()).toList(growable: false),
    if (includeResources)
      'resource_usage': agent.resourceUsage.toJson(includeInternalExtra: false),
    'created_at': _iso(agent.createdAt),
  };
}

Map<String, Object?> _agentOperationalSummaryJson(AgentProfile agent) {
  return <String, Object?>{
    'task_metrics': _taskMetricsForTasksJson(agent.tasks),
    'worker_capacity': _workerCapacityJsonForAgent(agent),
    'queue_pressure': _queuePressureJson(agent),
    'approval_summary': _approvalSummaryJson(agent.approvals),
    'kpi_summary': _kpiSummaryJson(agent.kpis),
    'resource_summary': _resourceUsageSummaryJson(agent.resourceUsage),
  };
}

Map<String, Object?> _taskJson(
  AgentTask task, {
  AgentProfile? agent,
  Set<String>? callableAgentToolNames,
}) {
  final assignedWorker = agent == null
      ? null
      : _assignedWorkerJson(agent, task);
  final state = _taskStateJson(
    task,
    agent: agent,
    callableAgentToolNames: callableAgentToolNames,
  );
  final resultAvailable = task.hasResult;
  return <String, Object?>{
    'id': task.id,
    'title': task.title,
    'description': task.description,
    'content': task.content,
    'status': task.status.storageValue,
    'progress': task.progress,
    'state': state,
    'next_action': state['next_action'],
    'allowed_tools': state['allowed_tools'],
    if (state['terminal_reason'] != null)
      'terminal_reason': state['terminal_reason'],
    'result_available': resultAvailable,
    'handoff': _taskHandoffJson(
      task,
      agent: agent,
      callableAgentToolNames: callableAgentToolNames,
    ),
    if (_taskNextPollJson(
          task,
          agent: agent,
          callableAgentToolNames: callableAgentToolNames,
        )
        case final nextPoll?)
      'next_poll': nextPoll,
    'result': task.result,
    'note': task.note,
    if (assignedWorker != null) 'assigned_worker': assignedWorker,
    'extra': _taskExtraJson(task.extra),
    'created_at': _iso(task.createdAt),
    'updated_at': _iso(task.updatedAt),
  };
}

Map<String, Object?> _taskStateJson(
  AgentTask task, {
  AgentProfile? agent,
  Set<String>? callableAgentToolNames,
}) {
  final terminal = task.status.isTerminal;
  final requiresAttention =
      task.status == AgentTaskStatus.waitingApproval ||
      task.status == AgentTaskStatus.paused ||
      task.status == AgentTaskStatus.failed;
  final needsPolling = !terminal && !requiresAttention;
  final canPoll =
      needsPolling &&
      _taskPollingAvailable(
        agent,
        callableAgentToolNames: callableAgentToolNames,
      );
  final terminalReason = _taskTerminalReason(task);
  return <String, Object?>{
    'terminal': terminal,
    'needs_polling': needsPolling,
    'requires_attention': requiresAttention,
    'next_action': _taskNextAction(
      task,
      needsPolling: needsPolling,
      agent: agent,
      callableAgentToolNames: callableAgentToolNames,
    ),
    'allowed_tools': _allowedTaskTools(
      task.status,
      agent: agent,
      callableAgentToolNames: callableAgentToolNames,
    ),
    if (_taskRetryJson(task) case final retry?) 'retry': retry,
    if (terminalReason != null) 'terminal_reason': terminalReason,
    if (canPoll) 'recommended_poll_ms': agentTaskRecommendedPollMs,
  };
}

Map<String, Object?> _taskTrackingFields(
  AgentProfile agent,
  AgentTask task, {
  required Map<String, Object?>? recovery,
  required Set<String> callableAgentToolNames,
}) {
  final state = _taskStateJson(
    task,
    agent: agent,
    callableAgentToolNames: callableAgentToolNames,
  );
  final assignedWorker = _assignedWorkerJson(agent, task);
  return <String, Object?>{
    if (recovery != null) 'resolution': recovery,
    'state': state,
    'next_action': state['next_action'],
    'allowed_tools': state['allowed_tools'],
    if (state['terminal_reason'] != null)
      'terminal_reason': state['terminal_reason'],
    'result_available': task.hasResult,
    if (_taskNextPollJson(
          task,
          agent: agent,
          callableAgentToolNames: callableAgentToolNames,
        )
        case final nextPoll?)
      'next_poll': nextPoll,
    if (assignedWorker != null) 'assigned_worker': assignedWorker,
    'operational_summary': _taskOperationalSummaryJson(agent, task),
  };
}

Map<String, Object?> _taskHandoffJson(
  AgentTask task, {
  AgentProfile? agent,
  Set<String>? callableAgentToolNames,
}) {
  final state = _taskStateJson(
    task,
    agent: agent,
    callableAgentToolNames: callableAgentToolNames,
  );
  final resultAvailable = task.hasResult;
  return <String, Object?>{
    'result_available': resultAvailable,
    'message': _taskHandoffMessage(
      task,
      resultAvailable: resultAvailable,
      agent: agent,
    ),
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
    if (_taskNextPollJson(
          task,
          agent: agent,
          callableAgentToolNames: callableAgentToolNames,
        )
        case final nextPoll?)
      'next_poll': nextPoll,
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

String _taskHandoffMessage(
  AgentTask task, {
  required bool resultAvailable,
  AgentProfile? agent,
}) {
  if (resultAvailable) return 'result_ready';
  if (!task.status.isTerminal) {
    return switch (task.status) {
      AgentTaskStatus.waitingApproval => 'waiting_for_approval',
      AgentTaskStatus.paused => 'paused_requires_resume_or_cancel',
      AgentTaskStatus.backlog ||
      AgentTaskStatus.ready ||
      AgentTaskStatus.running =>
        _taskPollingAvailable(agent)
            ? 'result_not_ready_poll'
            : 'polling_tools_not_bound',
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

Map<String, Object?>? _taskNextPollJson(
  AgentTask task, {
  AgentProfile? agent,
  Set<String>? callableAgentToolNames,
}) {
  if (task.status.isTerminal ||
      task.status == AgentTaskStatus.waitingApproval ||
      task.status == AgentTaskStatus.paused) {
    return null;
  }
  final progressAvailable = _agentToolAvailable(
    agent,
    agentTaskProgressToolName,
    callableAgentToolNames: callableAgentToolNames,
  );
  final resultAvailable = _agentToolAvailable(
    agent,
    agentTaskResultToolName,
    callableAgentToolNames: callableAgentToolNames,
  );
  return <String, Object?>{
    'available': progressAvailable || resultAvailable,
    if (progressAvailable) 'tool': agentTaskProgressToolName,
    if (resultAvailable) 'result_tool': agentTaskResultToolName,
    if (!progressAvailable || !resultAvailable)
      'missing_tools': <String>[
        if (!progressAvailable) agentTaskProgressToolName,
        if (!resultAvailable) agentTaskResultToolName,
      ],
    if (!progressAvailable && !resultAvailable)
      'blocked_reason':
          '该数字员工未绑定任务轮询工具，请在配置中启用 AgentTaskProgress 或 AgentTaskResult。',
    'recommended_poll_ms': agentTaskRecommendedPollMs,
  };
}

String _taskNextAction(
  AgentTask task, {
  required bool needsPolling,
  AgentProfile? agent,
  Set<String>? callableAgentToolNames,
}) {
  if (needsPolling) {
    return _taskPollingAvailable(
          agent,
          callableAgentToolNames: callableAgentToolNames,
        )
        ? 'poll'
        : 'enable_task_polling_tool';
  }
  return switch (task.status) {
    AgentTaskStatus.waitingApproval => 'review_approval',
    AgentTaskStatus.paused => 'resume_or_cancel',
    AgentTaskStatus.completed =>
      task.hasResult ? 'read_result' : 'inspect_missing_result',
    AgentTaskStatus.failed =>
      _taskTerminalReason(task) == 'terminated' ? 'stop' : 'inspect_failure',
    AgentTaskStatus.canceled => 'stop',
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running => 'poll',
  };
}

bool _taskPollingAvailable(
  AgentProfile? agent, {
  Set<String>? callableAgentToolNames,
}) {
  return _agentToolAvailable(
        agent,
        agentTaskProgressToolName,
        callableAgentToolNames: callableAgentToolNames,
      ) ||
      _agentToolAvailable(
        agent,
        agentTaskResultToolName,
        callableAgentToolNames: callableAgentToolNames,
      );
}

bool _agentToolAvailable(
  AgentProfile? agent,
  String toolName, {
  Set<String>? callableAgentToolNames,
}) {
  final normalized = _normalizedAgentToolName(toolName);
  if (callableAgentToolNames != null &&
      !callableAgentToolNames.contains(normalized)) {
    return false;
  }
  return agent == null || _agentAllowsToolNames(agent, <String>{normalized});
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

List<String> _allowedTaskTools(
  AgentTaskStatus status, {
  AgentProfile? agent,
  Set<String>? callableAgentToolNames,
}) {
  final tools = switch (status) {
    AgentTaskStatus.backlog ||
    AgentTaskStatus.ready ||
    AgentTaskStatus.running => _agentTaskActiveTools,
    AgentTaskStatus.waitingApproval => _agentTaskBlockedTools,
    AgentTaskStatus.paused => _agentTaskPausedTools,
    AgentTaskStatus.completed ||
    AgentTaskStatus.failed ||
    AgentTaskStatus.canceled => const <String>[],
  };
  if (tools.isEmpty) return tools;
  return tools
      .where(
        (tool) => _agentToolAvailable(
          agent,
          tool,
          callableAgentToolNames: callableAgentToolNames,
        ),
      )
      .toList(growable: false);
}

String _taskStatusToolRejectedMessage(
  String toolName,
  AgentTask task, {
  AgentProfile? agent,
  Set<String>? callableAgentToolNames,
}) {
  final allowedTools = _allowedTaskTools(
    task.status,
    agent: agent,
    callableAgentToolNames: callableAgentToolNames,
  );
  final allowedText = allowedTools.isEmpty ? '无' : allowedTools.join(', ');
  return '任务状态为 ${task.status.storageValue} 时不允许调用 $toolName。可用工具：$allowedText。';
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
    'completion_rate': unitRatio(completed, total),
  };
}

Map<String, Object?> _kpiSummaryJson(List<AgentKpiItem> items) {
  final byStatus = <String, int>{};
  var totalProgress = 0.0;
  for (final item in items) {
    final status = item.status.trim().isEmpty
        ? agentKpiStatusTracking
        : item.status.trim();
    byStatus[status] = (byStatus[status] ?? 0) + 1;
    totalProgress += clampUnitInterval(item.progress);
  }
  return <String, Object?>{
    'total': items.length,
    'by_status': byStatus,
    agentKpiStatusAtRisk: byStatus[agentKpiStatusAtRisk] ?? 0,
    agentKpiStatusDone: byStatus[agentKpiStatusDone] ?? 0,
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
  return recentAgentAuditEvents(events)
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
            final worker = agent.workerById(workerId);
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

DateTime? _latestDateTime(DateTime? left, DateTime? right) {
  if (left == null) return right;
  if (right == null) return left;
  return right.isAfter(left) ? right : left;
}

Map<String, Object?> _resourcePressureJson(AgentResourceUsage usage) {
  final tokenRatio = unitRatio(usage.tokenUsed, usage.tokenBudget);
  final diskPressure = unitRatio(usage.persistedBytes, usage.diskBytes);
  final handlePressure = unitRatio(
    usage.openHandles,
    agentResourceOpenHandlePressureLimit,
  );
  final maxPressure = _maxResourcePressure(
    usage.cpuPercent,
    tokenRatio,
    diskPressure,
    handlePressure,
  );
  return <String, Object?>{
    'cpu_percent': usage.cpuPercent,
    'token_usage_ratio': tokenRatio,
    'persisted_disk_ratio': diskPressure,
    'open_handle_ratio': handlePressure,
    'open_handle_limit': agentResourceOpenHandlePressureLimit,
    'open_handles': usage.openHandles,
    'max_pressure': maxPressure,
    'pressure_level': _resourcePressureLevel(maxPressure),
    'has_pressure': maxPressure >= 0.85,
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
  final payload = Map<String, Object?>.from(
    usage.toJson(includeInternalExtra: false),
  );
  final tokenRatio = unitRatio(usage.tokenUsed, usage.tokenBudget);
  final persistedRatio = unitRatio(usage.persistedBytes, usage.diskBytes);
  final handleRatio = unitRatio(
    usage.openHandles,
    agentResourceOpenHandlePressureLimit,
  );
  final maxPressure = _maxResourcePressure(
    usage.cpuPercent,
    tokenRatio,
    persistedRatio,
    handleRatio,
  );
  if (usage.tokenBudget > 0) {
    payload['token_remaining'] = nonNegativeRemaining(
      usage.tokenBudget,
      usage.tokenUsed,
    );
  } else {
    payload['token_remaining'] = null;
  }
  payload['token_usage_ratio'] = tokenRatio;
  if (usage.diskBytes > 0) {
    payload['persisted_remaining_bytes'] = nonNegativeRemaining(
      usage.diskBytes,
      usage.persistedBytes,
    );
  } else {
    payload['persisted_remaining_bytes'] = null;
  }
  payload['persisted_disk_ratio'] = persistedRatio;
  payload['open_handle_limit'] = agentResourceOpenHandlePressureLimit;
  payload['open_handle_ratio'] = handleRatio;
  payload['max_pressure'] = maxPressure;
  payload['pressure_level'] = _resourcePressureLevel(maxPressure);
  payload['has_pressure'] = maxPressure >= 0.85;
  return payload;
}

double _maxResourcePressure(
  double cpu,
  double token,
  double persisted,
  double handles,
) {
  var maxPressure = clampUnitInterval(cpu);
  if (token > maxPressure) maxPressure = token;
  if (persisted > maxPressure) maxPressure = persisted;
  if (handles > maxPressure) maxPressure = handles;
  return maxPressure;
}

String _resourcePressureLevel(double pressure) {
  if (pressure >= 0.85) return 'high';
  if (pressure >= 0.65) return 'watch';
  return 'normal';
}

Map<String, Object?> _taskExtraJson(Map<String, Object?> extra) {
  return omitAgentSystemPromptMetadata(
    extra,
    reason:
        '除非明确需要完整提示词，否则请使用 agent_prompt_snapshot 元数据。',
  );
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
  return value.clamp(agentScaleRatioMinimum, agentScaleRatioMaximum).toDouble();
}

String _normalizeAgentStatusToken(String raw) {
  return normalizeSnakeStorageKey(raw);
}

String? _normalizedKpiStatus(String raw) {
  final normalized = _normalizeAgentStatusToken(raw);
  if (agentKpiStatusOptions.contains(normalized)) return normalized;
  return null;
}

({AgentTaskStatus? status, bool invalid}) _optionalTaskStatus(Object? raw) {
  final text = optionalStringFromValue(raw);
  if (text == null) return (status: null, invalid: false);
  final status = enumByStorageValue(
    AgentTaskStatus.values,
    text,
    (status) => status.storageValue,
    normalize: _normalizeAgentStatusToken,
  );
  return status == null
      ? (status: null, invalid: true)
      : (status: status, invalid: false);
}

String? _optionalAllowedText(
  Map<String, Object?> args,
  String key,
  Iterable<String> allowed,
) {
  if (!args.containsKey(key) || args[key] == null) return null;
  final normalized = normalizeSnakeStorageKey('${args[key]}');
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
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_\-./,;:|，。；、：/\\()\[\]{}<>「」『』（）【】]+'), ' ')
      .trim()
      .replaceAll(kInlineWhitespacePattern, ' ');
}

Set<String> _routeTextVariants(String value) {
  final normalized = _normalizeRouteText(value);
  if (normalized.isEmpty) return const <String>{};
  final compact = normalized.replaceAll(' ', '');
  return <String>{normalized, if (compact.isNotEmpty) compact};
}
