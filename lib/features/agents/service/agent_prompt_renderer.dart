import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../app/support/silent_log.dart';
import '../model/agent_models.dart';
import 'agent_routing_metadata.dart';

class AgentPromptSnapshot {
  const AgentPromptSnapshot({
    required this.assetPath,
    required this.version,
    required this.renderedPrompt,
    required this.profile,
    required this.capabilities,
    required this.runtimePolicy,
    required this.operationalState,
    required this.taskContext,
  });

  final String assetPath;
  final String version;
  final String renderedPrompt;
  final Map<String, Object?> profile;
  final Map<String, Object?> capabilities;
  final Map<String, Object?> runtimePolicy;
  final Map<String, Object?> operationalState;
  final Map<String, Object?> taskContext;

  Map<String, Object?> metadataJson({bool includePrompt = false}) {
    return <String, Object?>{
      'asset_path': assetPath,
      'version': version,
      'prompt_chars': renderedPrompt.length,
      'profile': profile,
      'capabilities': capabilities,
      'runtime_policy': runtimePolicy,
      'operational_state': operationalState,
      'task_context': taskContext,
      if (includePrompt) 'rendered_prompt': renderedPrompt,
    };
  }
}

class AgentPromptRenderer {
  AgentPromptRenderer({Future<String> Function(String path)? loader})
    : _loader = loader ?? rootBundle.loadString;

  static const String defaultAssetPath =
      'assets/prompts/agents/digital_employee_system_instructions.md';
  static const String promptVersion = '1.1.0';

  final Future<String> Function(String path) _loader;

  Future<AgentPromptSnapshot> render({
    required AgentProfile agent,
    AgentTask? task,
    Map<String, Object?> taskContext = const <String, Object?>{},
  }) async {
    final template = await _loadTemplate();
    final profile = _profileJson(agent);
    final capabilities = _capabilitiesJson(agent);
    final runtimePolicy = _runtimePolicyJson(agent);
    final operationalState = _operationalStateJson(agent);
    final effectiveTaskContext = <String, Object?>{
      if (task != null) 'task': _taskJson(task),
      ...taskContext,
    };
    final rendered = template
        .replaceAll('{{AGENT_PROFILE_JSON}}', _json(profile))
        .replaceAll('{{CAPABILITY_BINDINGS_JSON}}', _json(capabilities))
        .replaceAll('{{RUNTIME_POLICY_JSON}}', _json(runtimePolicy))
        .replaceAll('{{OPERATIONAL_STATE_JSON}}', _json(operationalState))
        .replaceAll('{{TASK_CONTEXT_JSON}}', _json(effectiveTaskContext));
    return AgentPromptSnapshot(
      assetPath: defaultAssetPath,
      version: promptVersion,
      renderedPrompt: rendered.trimRight(),
      profile: profile,
      capabilities: capabilities,
      runtimePolicy: runtimePolicy,
      operationalState: operationalState,
      taskContext: effectiveTaskContext,
    );
  }

  Future<String> _loadTemplate() async {
    try {
      final content = (await _loader(defaultAssetPath)).trim();
      return content.isEmpty ? _fallbackTemplate : content;
    } catch (error, stack) {
      silentLog(
        'agent_prompt_renderer',
        'load $defaultAssetPath',
        error,
        stack,
      );
      return _fallbackTemplate;
    }
  }
}

Map<String, Object?> _profileJson(AgentProfile agent) {
  final routing = AgentRoutingMetadata.fromAgent(agent);
  return <String, Object?>{
    'id': agent.id,
    'name': agent.name,
    'avatar': agent.avatar,
    'position': agent.position,
    'department': agent.department,
    'mentor': agent.mentor,
    'level': agent.level,
    'introduction': agent.introduction,
    'persona': agent.persona,
    'responsibility_boundary': agent.responsibilityBoundary,
    'welcome_message': agent.welcomeMessage,
    'archive': agent.archive,
    'route_front_matter': agent.routeFrontMatter,
    'routing': routing.toJson(),
  };
}

Map<String, Object?> _capabilitiesJson(AgentProfile agent) {
  return <String, Object?>{
    'skills': agent.skillNames,
    'knowledge_sources': agent.knowledgeSourceIds,
    'memories': agent.memoryIds,
    'mcp_servers': agent.mcpServerNames,
    'builtin_tools': agent.builtinToolNames,
    'cron_ids': agent.cronIds,
    'hook_ids': agent.hookIds,
  };
}

Map<String, Object?> _runtimePolicyJson(AgentProfile agent) {
  return <String, Object?>{
    'enabled': agent.enabled,
    'lifecycle_state': agent.lifecycleState.storageValue,
    'execution_mode': agent.executionMode.storageValue,
    'model_provider_config_id': agent.modelProviderConfigId,
    'model_id': agent.modelId,
    'self_learning_enabled': agent.selfLearningEnabled,
    'workspace_path': agent.workspacePath,
    'workspace_scope': agent.workspaceScope,
    'task_labels': agent.taskLabels,
    'scale_settings': agent.scaleSettings.toJson(),
    'kpis': agent.kpis.map((item) => item.toJson()).toList(growable: false),
  };
}

Map<String, Object?> _operationalStateJson(AgentProfile agent) {
  final pendingApprovals = agent.approvals
      .where((item) => item.status == AgentApprovalStatus.pending)
      .take(10)
      .map(_approvalJson)
      .toList(growable: false);
  final workers = agent.workers;
  final idleWorkers = workers
      .where((worker) => worker.status == AgentWorkerStatus.idle)
      .length;
  final busyWorkers = workers
      .where((worker) => worker.status == AgentWorkerStatus.busy)
      .length;
  final drainingWorkers = workers
      .where((worker) => worker.status == AgentWorkerStatus.draining)
      .length;
  final offlineWorkers = workers
      .where((worker) => worker.status == AgentWorkerStatus.offline)
      .length;
  final resourceUsage = agent.resourceUsage;
  final tokenRatio = resourceUsage.tokenBudget <= 0
      ? 0
      : resourceUsage.tokenUsed / resourceUsage.tokenBudget;
  final resourcePressure =
      resourceUsage.cpuPercent >= 0.85 || tokenRatio >= 0.85;
  final requests = agent.auditEvents.fold<int>(
    0,
    (sum, event) => sum + event.requestCount,
  );
  final tokens = agent.auditEvents.fold<int>(
    0,
    (sum, event) => sum + event.tokenUsage,
  );
  return <String, Object?>{
    'task_counts': <String, Object?>{
      'total': agent.tasks.length,
      'backlog': agent.tasks
          .where((task) => task.status == AgentTaskStatus.backlog)
          .length,
      'ready': agent.tasks
          .where((task) => task.status == AgentTaskStatus.ready)
          .length,
      'running': agent.runningTaskCount,
      'paused': agent.tasks
          .where((task) => task.status == AgentTaskStatus.paused)
          .length,
      'completed': agent.completedTaskCount,
      'waiting_approval': agent.tasks
          .where((task) => task.status == AgentTaskStatus.waitingApproval)
          .length,
      'failed': agent.tasks
          .where((task) => task.status == AgentTaskStatus.failed)
          .length,
      'canceled': agent.tasks
          .where((task) => task.status == AgentTaskStatus.canceled)
          .length,
    },
    'state_flags': <String, Object?>{
      'enabled': agent.enabled,
      'running': agent.isRunning,
      'has_pending_approvals': pendingApprovals.isNotEmpty,
      'has_active_tasks': agent.runningTaskCount > 0,
      'has_blocked_tasks': agent.tasks.any(
        (task) =>
            task.status == AgentTaskStatus.waitingApproval ||
            task.status == AgentTaskStatus.paused ||
            task.status == AgentTaskStatus.failed,
      ),
      'workers_saturated': workers.isNotEmpty && idleWorkers == 0,
      'resource_pressure': resourcePressure,
    },
    'worker_capacity': <String, Object?>{
      'total': workers.length,
      'idle': idleWorkers,
      'busy': busyWorkers,
      'draining': drainingWorkers,
      'offline': offlineWorkers,
      'utilization': agent.workerUtilization,
    },
    'pending_approvals': pendingApprovals,
    'workers': agent.workers.map(_workerJson).toList(growable: false),
    'resource_usage': agent.resourceUsage.toJson(),
    'audit_summary': <String, Object?>{
      'events': agent.auditEvents.length,
      'requests': requests,
      'tokens': tokens,
      'recent_kinds': agent.auditEvents
          .take(10)
          .map((event) => event.kind)
          .toList(growable: false),
      'recent_tools': agent.auditEvents
          .where((event) => event.toolName.trim().isNotEmpty)
          .take(10)
          .map((event) => event.toolName)
          .toList(growable: false),
    },
  };
}

Map<String, Object?> _approvalJson(AgentApprovalRequest approval) {
  return <String, Object?>{
    'id': approval.id,
    'title': approval.title,
    'reason': approval.reason,
    'requested_action': approval.requestedAction,
    'status': approval.status.storageValue,
    'created_at': approval.createdAt?.toUtc().toIso8601String(),
  };
}

Map<String, Object?> _workerJson(AgentWorker worker) {
  return <String, Object?>{
    'id': worker.id,
    'name': worker.name,
    'status': worker.status.storageValue,
    'current_task_id': worker.currentTaskId,
    'executed_task_count': worker.executedTaskCount,
    'busy_score': worker.busyScore,
    'priority': worker.priority,
    'labels': worker.labels,
    'updated_at': worker.updatedAt?.toUtc().toIso8601String(),
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
    'note': task.note,
    'created_at': task.createdAt?.toUtc().toIso8601String(),
    'updated_at': task.updatedAt?.toUtc().toIso8601String(),
  };
}

String _json(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

const String _fallbackTemplate = '''
<identity>
You are an OpenHand digital employee. Stay inside your profile, mentor chain, responsibility boundary, and enabled capabilities.
</identity>

<agent_profile>
{{AGENT_PROFILE_JSON}}
</agent_profile>

<capability_bindings>
{{CAPABILITY_BINDINGS_JSON}}
</capability_bindings>

<runtime_policy>
{{RUNTIME_POLICY_JSON}}
</runtime_policy>

<operational_state>
{{OPERATIONAL_STATE_JSON}}
</operational_state>

<task_context>
{{TASK_CONTEXT_JSON}}
</task_context>

<core_rules>
1. Work only on in-boundary, auditable tasks.
2. Use real tools from the current catalog; do not invent tools.
3. Escalate uncertainty, missing permission, or high-risk actions to the mentor/user.
4. Verify before claiming completion.
5. Read `operational_state.state_flags` first; respect pending approvals, worker load, resource limits, and blocked tasks before starting new work.
</core_rules>
''';
