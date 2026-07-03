import 'dart:convert';

import '../../../../shared/util/input_value_parsing.dart';
import '../../../agents/index.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

enum _AgentToolOperation {
  list,
  detail,
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
      return AiToolUtils.invalidResult(
        _name,
        'No enabled agents are available. Start an agent before using agent tools.',
      );
    }

    try {
      return switch (_operation) {
        _AgentToolOperation.list => _list(controller, context, stopwatch),
        _AgentToolOperation.detail => await _detail(
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

  Future<AiToolExecutionResult> _publishTask(
    AgentsController controller,
    AiToolExecutionContext context,
    Stopwatch stopwatch,
  ) async {
    final args = context.decodedArguments;
    final resolution = _resolveAgent(controller, args);
    if (resolution.error != null) return resolution.error!;
    final title = '${args['title'] ?? ''}'.trim();
    if (title.isEmpty) {
      return AiToolUtils.invalidResult(_name, 'title is required.');
    }
    final rawExtra = optionalStringKeyedMapFromValueOrJsonText(args['extra']);
    final labels = stringListFromValueOrJsonText(
      args['labels'] ?? args['tags'],
    );
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
    final payload = <String, Object?>{
      'agent': _agentSummaryJson(resolution.agent!),
      'task': _taskJson(task),
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
        'task': _taskJson(resolved.task!),
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
    return _success(
      <String, Object?>{
        'agent_id': resolved.agent!.id,
        'task_id': task.id,
        'status': task.status.storageValue,
        'progress': task.progress,
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
    return _success(
      <String, Object?>{
        'agent': _agentSummaryJson(resolved.agent!),
        'task': _taskJson(updated),
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
    return _success(
      <String, Object?>{
        'agent_id': resolved.agent!.id,
        'task_id': task.id,
        'title': task.title,
        'status': task.status.storageValue,
        'progress': task.progress,
        'result': task.result,
        'note': task.note,
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
  const _AgentResolution({this.agent, this.error});

  factory _AgentResolution.agent(AgentProfile agent) {
    return _AgentResolution(agent: agent);
  }

  factory _AgentResolution.error(AiToolExecutionResult error) {
    return _AgentResolution(error: error);
  }

  final AgentProfile? agent;
  final AiToolExecutionResult? error;
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
    'model_provider_config_id': agent.modelProviderConfigId,
    'model_id': agent.modelId,
    'task_counts': <String, Object?>{
      'total': agent.tasks.length,
      'running': agent.runningTaskCount,
      'completed': agent.completedTaskCount,
      'pending_approvals': agent.pendingApprovalCount,
    },
    'worker_count': agent.workers.length,
    'capabilities': <String, Object?>{
      'skills': agent.skillNames,
      'knowledge_sources': agent.knowledgeSourceIds,
      'memories': agent.memoryIds,
      'mcp_servers': agent.mcpServerNames,
      'builtin_tools': agent.builtinToolNames,
    },
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
    'workspace_scope': agent.workspaceScope,
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
      'tasks': agent.tasks.map(_taskJson).toList(growable: false),
    if (includeAudit)
      'audit_events': agent.auditEvents
          .take(50)
          .map((item) => item.toJson())
          .toList(growable: false),
    if (includeResources) 'resource_usage': agent.resourceUsage.toJson(),
    'created_at': _iso(agent.createdAt),
  };
}

Map<String, Object?> _taskJson(AgentTask task) {
  return <String, Object?>{
    'id': task.id,
    'title': task.title,
    'description': task.description,
    'content': task.content,
    'status': task.status.storageValue,
    'progress': task.progress,
    'result': task.result,
    'note': task.note,
    'extra': _taskExtraJson(task.extra),
    'created_at': _iso(task.createdAt),
    'updated_at': _iso(task.updatedAt),
  };
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
    String s => double.tryParse(s.trim()),
    _ => null,
  };
  if (value == null || !value.isFinite) return null;
  return value.clamp(0, 1).toDouble();
}
