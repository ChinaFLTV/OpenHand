import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../app/support/silent_log.dart';
import '../../shared/core/managed_change_notifier.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_normalization.dart';
import '../../shared/util/user_failure_message.dart';
import 'data/agents_store.dart';
import 'model/agent_models.dart';
import 'service/agent_ordering.dart';
import 'service/agent_runtime_availability.dart';

typedef AgentsControllerProvider = AgentsController? Function();

class AgentsController extends ManagedChangeNotifier {
  AgentsController._({
    required AgentsStore store,
    required List<AgentProfile> agents,
    required bool isLoading,
  }) : _store = store,
       _agents = agents,
       _agentsView = List<AgentProfile>.unmodifiable(agents),
       _isLoading = isLoading;

  factory AgentsController.uninitialized({AgentsStore? store}) {
    return AgentsController._(
      store: store ?? AgentsStore(),
      agents: const <AgentProfile>[],
      isLoading: true,
    );
  }

  static const Uuid _uuid = Uuid();
  static const String _retryableExtraKey = 'retryable';
  static const String _retryCountExtraKey = 'retry_count';
  static const String _resourceTelemetryExtraKey =
      '_openhand_resource_telemetry';
  static const String _resourceTelemetryHistoryKey = 'history';
  static const int _maxResourceTelemetrySamples = 36;
  static const int _resourceTelemetrySampleMinGapMs = 1000;
  static const int _resourceCharsPerToken = 4;
  static const int _resourceHandleMemoryBytes = 8 * kBytesPerKiB;
  static const int _resourceWorkerMemoryBytes = 16 * kBytesPerKiB;
  final AgentsStore _store;
  List<AgentProfile> _agents;
  List<AgentProfile> _agentsView;
  bool _isLoading;
  String? _errorMessage;
  bool _hasTrustedSnapshot = false;
  AgentRuntimeAvailabilityProvider? _runtimeAvailabilityProvider;
  final ChangePulse _saveSuccessPulse = ChangePulse();
  final Set<String> _pendingResourceSampleAgentIds = <String>{};

  List<AgentProfile> get agents => _agentsView;
  List<AgentProfile> get enabledAgents {
    if (!_hasTrustedSnapshot || !runtimeAvailability.canRun) {
      return const <AgentProfile>[];
    }
    return _agentsView.where((agent) => agent.enabled).toList(growable: false);
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ValueListenable<int> get saveSuccessSignal => _saveSuccessPulse.listenable;
  AgentRuntimeAvailability get runtimeAvailability =>
      _runtimeAvailabilityProvider?.call() ??
      AgentRuntimeAvailability.optimistic;

  void setRuntimeAvailabilityProvider(
    AgentRuntimeAvailabilityProvider provider,
  ) {
    _runtimeAvailabilityProvider = provider;
    notifyListeners();
  }

  void notifyRuntimeAvailabilityChanged() {
    notifyListeners();
  }

  AgentProfile? agentById(String id) {
    if (!_hasTrustedSnapshot) return null;
    final normalized = id.trim();
    for (final agent in _agents) {
      if (agent.id == normalized) return agent;
    }
    return null;
  }

  AgentProfile? findAgent(
    String rawIdentifier, {
    bool includeDisabled = false,
  }) {
    if (!_hasTrustedSnapshot) return null;
    final identifier = rawIdentifier.trim();
    if (identifier.isEmpty) return null;
    final normalized = identifier.toLowerCase();
    for (final agent in _agents) {
      if (!includeDisabled && !agent.enabled) continue;
      if (agent.id == identifier ||
          agent.name.trim().toLowerCase() == normalized) {
        return agent;
      }
    }
    return null;
  }

  AgentTask? taskById(String agentId, String taskId) {
    final normalizedTaskId = taskId.trim();
    final agent = agentById(agentId);
    if (agent == null || normalizedTaskId.isEmpty) return null;
    for (final task in agent.tasks) {
      if (task.id == normalizedTaskId) return task;
    }
    return null;
  }

  Future<void> refresh() {
    return enqueueOperation(_loadLocked);
  }

  Future<bool> saveAgent(AgentProfile draft) {
    return _commitMutation(() async {
      final now = DateTime.now().toUtc();
      final runtime = runtimeAvailability;
      final canSaveEnabled = !draft.enabled || runtime.canRun;
      final normalized = _normalizeAgent(
        (canSaveEnabled
                ? draft
                : draft.copyWith(
                    enabled: false,
                    lifecycleState: AgentLifecycleState.stopped,
                  ))
            .copyWith(
              id: draft.id.trim().isEmpty ? _uuid.v4() : draft.id.trim(),
              updatedAt: now,
              createdAt: draft.createdAt ?? now,
            ),
      );
      await _upsertAgentAndSave(normalized);
      return true;
    });
  }

  Future<bool> deleteAgent(String id) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return Future<bool>.value(false);
    return _commitMutation(() async {
      final next = _agents.where((agent) => agent.id != normalizedId).toList();
      if (next.length == _agents.length) return false;
      await _store.save(next);
      _setAgents(next);
      return true;
    });
  }

  Future<bool> setAgentEnabled(String id, {required bool enabled}) {
    final runtime = runtimeAvailability;
    if (enabled && !runtime.canRun) {
      return Future<bool>.value(false);
    }
    return updateAgent(id, (agent) {
      final now = DateTime.now().toUtc();
      final kind = enabled ? 'agent_started' : 'agent_stopped';
      final lifecycleState = enabled
          ? AgentLifecycleState.running
          : AgentLifecycleState.stopped;
      final stopDrain = enabled
          ? _AgentStopDrainResult(agent: agent)
          : _pauseRunningTasksForStop(agent, now);
      return stopDrain.agent.copyWith(
        enabled: enabled,
        lifecycleState: lifecycleState,
        activities: _prependActivity(
          stopDrain.agent.activities,
          AgentActivityEvent(
            id: _uuid.v4(),
            kind: kind,
            title: kind,
            createdAt: now,
            metadata: <String, Object?>{
              'enabled': enabled,
              'lifecycle_state': lifecycleState.storageValue,
              if (stopDrain.pausedTaskCount > 0)
                'paused_task_count': stopDrain.pausedTaskCount,
              if (stopDrain.releasedWorkerCount > 0)
                'released_worker_count': stopDrain.releasedWorkerCount,
            },
          ),
        ),
        auditEvents: _prependAudit(
          stopDrain.agent.auditEvents,
          _auditEvent(
            kind: kind,
            summary: kind,
            toolName: 'AgentsController',
            createdAt: now,
            metadata: <String, Object?>{
              'enabled': enabled,
              'lifecycle_state': lifecycleState.storageValue,
              if (stopDrain.pausedTaskCount > 0)
                'paused_task_count': stopDrain.pausedTaskCount,
              if (stopDrain.releasedWorkerCount > 0)
                'released_worker_count': stopDrain.releasedWorkerCount,
            },
          ),
        ),
      );
    });
  }

  Future<bool> publishTask(
    String agentId, {
    required String title,
    String description = '',
    String content = '',
    String note = '',
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return publishTaskWithResult(
      agentId,
      title: title,
      description: description,
      content: content,
      note: note,
      extra: extra,
    ).then((task) => task != null);
  }

  Future<AgentTask?> publishTaskWithResult(
    String agentId, {
    required String title,
    String description = '',
    String content = '',
    String note = '',
    Map<String, Object?> extra = const <String, Object?>{},
    String auditToolName = 'AgentTaskDesk',
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) return null;
    AgentTask? createdTask;
    final normalizedAgentId = agentId.trim();
    if (normalizedAgentId.isEmpty) return null;
    final changed = await _commitMutation(() async {
      final index = _agentIndexById(normalizedAgentId);
      if (index < 0) return false;
      final agent = _agents[index];
      if (!agent.enabled ||
          agent.lifecycleState != AgentLifecycleState.running) {
        return false;
      }
      final now = DateTime.now().toUtc();
      final task = AgentTask(
        id: _uuid.v4(),
        title: normalizedTitle,
        description: description.trim(),
        content: content.trim(),
        note: note.trim(),
        extra: extra,
        status: AgentTaskStatus.ready,
        createdAt: now,
        updatedAt: now,
      );
      createdTask = task;
      final queued = agent.copyWith(
        tasks: <AgentTask>[task, ...agent.tasks],
        activities: _prependActivity(
          agent.activities,
          AgentActivityEvent(
            id: _uuid.v4(),
            kind: 'task_published',
            title: 'task_published',
            content: task.title,
            createdAt: now,
            metadata: <String, Object?>{'task_id': task.id},
          ),
        ),
        auditEvents: _prependAudit(
          agent.auditEvents,
          _auditEvent(
            kind: 'task_published',
            summary: 'task_published: ${task.title}',
            toolName: auditToolName,
            createdAt: now,
            metadata: <String, Object?>{
              'task_id': task.id,
              'task_status': task.status.storageValue,
              if (extra.containsKey('published_by_session_id'))
                'published_by_session_id': extra['published_by_session_id'],
            },
          ),
        ),
      );
      final dispatched = _dispatchReadyTasksForAgent(
        queued,
        now,
        auditToolName: auditToolName,
      );
      createdTask = dispatched.tasks.firstWhere(
        (item) => item.id == task.id,
        orElse: () => task,
      );
      final normalized = _normalizeAgent(dispatched.copyWith(updatedAt: now));
      createdTask = normalized.tasks.firstWhere(
        (item) => item.id == task.id,
        orElse: () => createdTask!,
      );
      await _replaceAgentAtAndSave(index, normalized);
      return true;
    });
    return changed ? createdTask : null;
  }

  Future<AgentTask?> updateTaskState(
    String agentId,
    String taskId, {
    AgentTaskStatus? status,
    String? expectedAssignmentId,
    double? progress,
    String? note,
    String? result,
    Map<String, Object?>? extra,
    String activityKind = 'task_updated',
    String activityTitle = 'task_updated',
    String auditToolName = 'AgentTaskDesk',
  }) async {
    AgentTask? updatedTask;
    final normalizedTaskId = taskId.trim();
    final normalizedExpectedAssignmentId = expectedAssignmentId?.trim();
    if (normalizedTaskId.isEmpty ||
        (normalizedExpectedAssignmentId != null &&
            normalizedExpectedAssignmentId.isEmpty)) {
      return null;
    }
    final changed = await _commitMutation(() async {
      final index = _agentIndexById(agentId);
      if (index < 0) return false;
      final agent = _agents[index];
      if (!agent.enabled) return false;
      final now = DateTime.now().toUtc();
      var found = false;
      final tasks = agent.tasks
          .map((task) {
            if (task.id != normalizedTaskId) return task;
            found = true;
            if (normalizedExpectedAssignmentId != null &&
                (task.status != AgentTaskStatus.running ||
                    '${task.extra[agentTaskAssignmentIdExtraKey] ?? ''}'
                            .trim() !=
                        normalizedExpectedAssignmentId)) {
              return task;
            }
            if (!_canUpdateTaskState(task, status)) return task;
            final nextProgress = progress == null
                ? status == AgentTaskStatus.completed
                      ? 1.0
                      : task.progress
                : clampUnitInterval(progress);
            final nextExtra = extra == null || extra.isEmpty
                ? task.extra
                : <String, Object?>{...task.extra, ...extra};
            if ((status == null || status == task.status) &&
                nextProgress == task.progress &&
                (note == null || note == task.note) &&
                (result == null || result == task.result) &&
                mapEquals(nextExtra, task.extra)) {
              return task;
            }
            updatedTask = task.copyWith(
              status: status,
              progress: nextProgress,
              note: note,
              result: result,
              extra: nextExtra,
              updatedAt: now,
            );
            return updatedTask!;
          })
          .toList(growable: false);
      if (!found || updatedTask == null) return false;
      final releasedTask = updatedTask!;
      final retryScheduled = _shouldRetryTask(
        agent,
        updatedTask!,
        extra: extra,
        activityKind: activityKind,
      );
      if (retryScheduled) {
        updatedTask = _retryTask(updatedTask!, now);
      }
      final eventTask = releasedTask;
      final nextTasks = retryScheduled
          ? tasks
                .map(
                  (task) => task.id == normalizedTaskId ? updatedTask! : task,
                )
                .toList(growable: false)
          : tasks;
      final releasingStatus =
          status != null && _taskStatusReleasesWorker(status) ? status : null;
      final nextWorkers = releasingStatus == null
          ? agent.workers
          : _releaseWorkersForTask(
              agent.workers,
              releasedTask,
              now,
              countExecution: _taskStatusCountsExecution(releasingStatus),
            );
      var updated = agent.copyWith(
        tasks: nextTasks,
        workers: nextWorkers,
        activities: _prependActivity(
          agent.activities,
          AgentActivityEvent(
            id: _uuid.v4(),
            kind: activityKind,
            title: activityTitle,
            content: eventTask.title,
            createdAt: now,
            metadata: <String, Object?>{
              'task_id': eventTask.id,
              'task_status': eventTask.status.storageValue,
            },
          ),
        ),
        auditEvents: _prependAudit(
          agent.auditEvents,
          _auditEvent(
            kind: activityKind,
            summary: '$activityTitle: ${eventTask.title}',
            toolName: auditToolName,
            createdAt: now,
            metadata: <String, Object?>{
              'task_id': eventTask.id,
              'task_status': eventTask.status.storageValue,
              'task_progress': eventTask.progress,
              if (extra != null && extra.containsKey('updated_by_session_id'))
                'updated_by_session_id': extra['updated_by_session_id'],
            },
          ),
        ),
      );
      if (retryScheduled) {
        updated = _recordTaskRetryScheduled(
          updated,
          updatedTask!,
          now,
          auditToolName: auditToolName,
        );
      } else if (releasingStatus != null) {
        updated = _scaleInIdleWorkers(
          updated,
          now,
          auditToolName: auditToolName,
        );
      }
      final shouldDispatch =
          retryScheduled ||
          status == AgentTaskStatus.ready ||
          releasingStatus != null;
      final next = shouldDispatch
          ? _dispatchReadyTasksForAgent(
              updated,
              now,
              auditToolName: auditToolName,
            )
          : updated;
      updatedTask = next.tasks.firstWhere(
        (task) => task.id == normalizedTaskId,
        orElse: () => updatedTask!,
      );
      final normalized = _normalizeAgent(next.copyWith(updatedAt: now));
      updatedTask = normalized.tasks.firstWhere(
        (task) => task.id == normalizedTaskId,
        orElse: () => updatedTask!,
      );
      await _replaceAgentAtAndSave(index, normalized);
      return true;
    });
    return changed ? updatedTask : null;
  }

  Future<AgentApprovalRequest?> requestApproval(
    String agentId, {
    required String title,
    String reason = '',
    String requestedAction = '',
    Map<String, Object?> extra = const <String, Object?>{},
    String auditToolName = 'AgentApprovalsDialog',
  }) async {
    final normalizedAgentId = agentId.trim();
    final trimmedTitle = title.trim();
    if (normalizedAgentId.isEmpty || trimmedTitle.isEmpty) return null;
    AgentApprovalRequest? createdApproval;
    final changed = await _commitMutation(() async {
      final index = _agentIndexById(normalizedAgentId);
      if (index < 0) return false;
      final agent = _agents[index];
      final now = DateTime.now().toUtc();
      createdApproval = AgentApprovalRequest(
        id: _uuid.v4(),
        title: trimmedTitle,
        reason: reason.trim(),
        requestedAction: requestedAction.trim(),
        createdAt: now,
        extra: extra,
      );
      final metadata = <String, Object?>{
        'approval_id': createdApproval!.id,
        'approval_status': createdApproval!.status.storageValue,
        if (createdApproval!.requestedAction.trim().isNotEmpty)
          'requested_action': createdApproval!.requestedAction,
      };
      final updated = _normalizeAgent(
        agent.copyWith(
          approvals: <AgentApprovalRequest>[
            createdApproval!,
            ...agent.approvals,
          ],
          activities: _prependActivity(
            agent.activities,
            AgentActivityEvent(
              id: _uuid.v4(),
              kind: 'approval_requested',
              title: 'approval_requested',
              content: createdApproval!.title,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          auditEvents: _prependAudit(
            agent.auditEvents,
            _auditEvent(
              kind: 'approval_requested',
              summary: 'approval_requested: ${createdApproval!.title}',
              toolName: auditToolName,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          updatedAt: now,
        ),
      );
      await _replaceAgentAtAndSave(index, updated);
      return true;
    });
    return changed ? createdApproval : null;
  }

  Future<AgentApprovalRequest?> resolveApproval(
    String agentId,
    String approvalId,
    AgentApprovalStatus status, {
    String note = '',
    String auditToolName = 'AgentApprovalsDialog',
  }) async {
    final normalizedAgentId = agentId.trim();
    final normalizedApprovalId = approvalId.trim();
    if (normalizedAgentId.isEmpty ||
        normalizedApprovalId.isEmpty ||
        status == AgentApprovalStatus.pending) {
      return null;
    }
    AgentApprovalRequest? resolvedApproval;
    final changed = await _commitMutation(() async {
      final index = _agentIndexById(normalizedAgentId);
      if (index < 0) return false;
      final agent = _agents[index];
      final now = DateTime.now().toUtc();
      final trimmedNote = note.trim();
      var found = false;
      final approvals = agent.approvals
          .map((approval) {
            if (approval.id != normalizedApprovalId) return approval;
            found = true;
            if (approval.status != AgentApprovalStatus.pending) return approval;
            resolvedApproval = approval.copyWith(
              status: status,
              resolvedAt: now,
              extra: trimmedNote.isEmpty
                  ? approval.extra
                  : <String, Object?>{
                      ...approval.extra,
                      'resolution_note': trimmedNote,
                    },
            );
            return resolvedApproval!;
          })
          .toList(growable: false);
      if (!found || resolvedApproval == null) return false;
      final kind = switch (status) {
        AgentApprovalStatus.approved => 'approval_approved',
        AgentApprovalStatus.rejected => 'approval_rejected',
        AgentApprovalStatus.expired => 'approval_expired',
        AgentApprovalStatus.pending => 'approval_pending',
      };
      final metadata = <String, Object?>{
        'approval_id': resolvedApproval!.id,
        'approval_status': resolvedApproval!.status.storageValue,
        if (resolvedApproval!.requestedAction.trim().isNotEmpty)
          'requested_action': resolvedApproval!.requestedAction,
        if (trimmedNote.isNotEmpty) 'note': trimmedNote,
      };
      final updated = _normalizeAgent(
        agent.copyWith(
          approvals: approvals,
          activities: _prependActivity(
            agent.activities,
            AgentActivityEvent(
              id: _uuid.v4(),
              kind: kind,
              title: kind,
              content: resolvedApproval!.title,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          auditEvents: _prependAudit(
            agent.auditEvents,
            _auditEvent(
              kind: kind,
              summary: '$kind: ${resolvedApproval!.title}',
              toolName: auditToolName,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          updatedAt: now,
        ),
      );
      await _replaceAgentAtAndSave(index, updated);
      return true;
    });
    return changed ? resolvedApproval : null;
  }

  Future<AgentKpiItem?> saveKpi(
    String agentId,
    AgentKpiItem draft, {
    String auditToolName = 'AgentKpiDialog',
  }) async {
    final normalizedAgentId = agentId.trim();
    final trimmedName = draft.name.trim();
    if (normalizedAgentId.isEmpty || trimmedName.isEmpty) return null;
    AgentKpiItem? savedKpi;
    final changed = await _commitMutation(() async {
      final index = _agentIndexById(normalizedAgentId);
      if (index < 0) return false;
      final agent = _agents[index];
      final now = DateTime.now().toUtc();
      final normalizedId = draft.id.trim().isEmpty
          ? _uuid.v4()
          : draft.id.trim();
      final existed = agent.kpis.any((item) => item.id == normalizedId);
      final normalizedStatus = draft.status.trim().isEmpty
          ? agentKpiStatusTracking
          : draft.status.trim();
      savedKpi = draft.copyWith(
        id: normalizedId,
        name: trimmedName,
        target: draft.target.trim(),
        plan: draft.plan.trim(),
        status: normalizedStatus,
        progress: clampUnitInterval(draft.progress),
        createdAt: draft.createdAt ?? now,
        updatedAt: now,
      );
      final nextKpis = existed
          ? agent.kpis
                .map((item) => item.id == normalizedId ? savedKpi! : item)
                .toList(growable: false)
          : <AgentKpiItem>[savedKpi!, ...agent.kpis];
      final kind = existed ? 'kpi_updated' : 'kpi_created';
      final metadata = <String, Object?>{
        'kpi_id': savedKpi!.id,
        'kpi_status': savedKpi!.status,
        'kpi_progress': savedKpi!.progress,
      };
      final updated = _normalizeAgent(
        agent.copyWith(
          kpis: nextKpis,
          activities: _prependActivity(
            agent.activities,
            AgentActivityEvent(
              id: _uuid.v4(),
              kind: kind,
              title: kind,
              content: savedKpi!.name,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          auditEvents: _prependAudit(
            agent.auditEvents,
            _auditEvent(
              kind: kind,
              summary: '$kind: ${savedKpi!.name}',
              toolName: auditToolName,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          updatedAt: now,
        ),
      );
      await _replaceAgentAtAndSave(index, updated);
      return true;
    });
    return changed ? savedKpi : null;
  }

  Future<bool> deleteKpi(
    String agentId,
    String kpiId, {
    String auditToolName = 'AgentKpiDialog',
  }) {
    final normalizedAgentId = agentId.trim();
    final normalizedKpiId = kpiId.trim();
    if (normalizedAgentId.isEmpty || normalizedKpiId.isEmpty) {
      return Future<bool>.value(false);
    }
    return _commitMutation(() async {
      final index = _agentIndexById(normalizedAgentId);
      if (index < 0) return false;
      final agent = _agents[index];
      AgentKpiItem? deletedKpi;
      final nextKpis = <AgentKpiItem>[];
      for (final item in agent.kpis) {
        if (item.id == normalizedKpiId) {
          deletedKpi = item;
          continue;
        }
        nextKpis.add(item);
      }
      if (deletedKpi == null) return false;
      final now = DateTime.now().toUtc();
      final metadata = <String, Object?>{
        'kpi_id': deletedKpi.id,
        'kpi_status': deletedKpi.status,
        'kpi_progress': deletedKpi.progress,
      };
      final updated = _normalizeAgent(
        agent.copyWith(
          kpis: nextKpis,
          activities: _prependActivity(
            agent.activities,
            AgentActivityEvent(
              id: _uuid.v4(),
              kind: 'kpi_deleted',
              title: 'kpi_deleted',
              content: deletedKpi.name,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          auditEvents: _prependAudit(
            agent.auditEvents,
            _auditEvent(
              kind: 'kpi_deleted',
              summary: 'kpi_deleted: ${deletedKpi.name}',
              toolName: auditToolName,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          updatedAt: now,
        ),
      );
      await _replaceAgentAtAndSave(index, updated);
      return true;
    });
  }

  Future<bool> saveResourceUsage(
    String agentId,
    AgentResourceUsage usage, {
    String auditToolName = 'AgentResourcesDialog',
  }) {
    final normalizedAgentId = agentId.trim();
    if (normalizedAgentId.isEmpty) return Future<bool>.value(false);
    return _commitMutation(() async {
      final index = _agentIndexById(normalizedAgentId);
      if (index < 0) return false;
      final agent = _agents[index];
      final now = DateTime.now().toUtc();
      final normalized = usage.copyWith(
        cpuPercent: clampUnitInterval(usage.cpuPercent),
        memoryBytes: _nonNegativeAgentMetric(usage.memoryBytes),
        diskBytes: _nonNegativeAgentMetric(usage.diskBytes),
        persistedBytes: _nonNegativeAgentMetric(usage.persistedBytes),
        tokenBudget: _nonNegativeAgentMetric(usage.tokenBudget),
        tokenUsed: _nonNegativeAgentMetric(usage.tokenUsed),
        openHandles: _nonNegativeAgentMetric(usage.openHandles),
        extra: usage.publicExtra,
      );
      final metadata = <String, Object?>{
        'cpu_percent': normalized.cpuPercent,
        'memory_bytes': normalized.memoryBytes,
        'disk_bytes': normalized.diskBytes,
        'persisted_bytes': normalized.persistedBytes,
        'token_budget': normalized.tokenBudget,
        'token_used': normalized.tokenUsed,
        'open_handles': normalized.openHandles,
      };
      final updated = _normalizeAgent(
        agent.copyWith(
          resourceUsage: normalized,
          activities: _prependActivity(
            agent.activities,
            AgentActivityEvent(
              id: _uuid.v4(),
              kind: 'resource_updated',
              title: 'resource_updated',
              content: agent.name,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          auditEvents: _prependAudit(
            agent.auditEvents,
            _auditEvent(
              kind: 'resource_updated',
              summary: 'resource_updated: ${agent.name}',
              toolName: auditToolName,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          updatedAt: now,
        ),
      );
      await _replaceAgentAtAndSave(index, updated);
      return true;
    });
  }

  Future<bool> sampleResourceUsage(String agentId) {
    final normalizedAgentId = agentId.trim();
    if (normalizedAgentId.isEmpty) return Future<bool>.value(false);
    if (!_pendingResourceSampleAgentIds.add(normalizedAgentId)) {
      return Future<bool>.value(false);
    }
    return enqueueOperation(() async {
      if (!_hasTrustedSnapshot) return false;
      final index = _agentIndexById(normalizedAgentId);
      if (index < 0) return false;
      final agent = _agents[index];
      final sampled = agent.copyWith(
        resourceUsage: _normalizeResourceUsageForAgent(
          agent,
          reusePersistedByteEstimate: true,
        ),
      );
      _replaceAgentAt(index, sampled);
      notifyListeners();
      return true;
    }).whenComplete(
      () => _pendingResourceSampleAgentIds.remove(normalizedAgentId),
    );
  }

  Future<AgentAuditEvent?> recordAuditEvent(
    String agentId, {
    required String kind,
    required String summary,
    String toolName = '',
    int tokenUsage = 0,
    int requestCount = 0,
    Map<String, Object?> metadata = const <String, Object?>{},
    String auditToolName = 'AgentAuditDialog',
  }) async {
    final normalizedAgentId = agentId.trim();
    final trimmedSummary = summary.trim();
    if (normalizedAgentId.isEmpty || trimmedSummary.isEmpty) return null;
    AgentAuditEvent? savedEvent;
    final changed = await _commitMutation(() async {
      final index = _agentIndexById(normalizedAgentId);
      if (index < 0) return false;
      final agent = _agents[index];
      final now = DateTime.now().toUtc();
      final normalizedKind = kind.trim().isEmpty ? 'audit' : kind.trim();
      final normalizedToolName = toolName.trim();
      savedEvent = AgentAuditEvent(
        id: _uuid.v4(),
        kind: normalizedKind,
        summary: trimmedSummary,
        toolName: normalizedToolName,
        tokenUsage: _nonNegativeAgentMetric(tokenUsage),
        requestCount: _nonNegativeAgentMetric(requestCount),
        createdAt: now,
        metadata: <String, Object?>{...metadata, 'recorded_by': auditToolName},
      );
      final activityMetadata = <String, Object?>{
        'audit_id': savedEvent!.id,
        'audit_kind': savedEvent!.kind,
        if (normalizedToolName.isNotEmpty) 'tool_name': normalizedToolName,
      };
      final updated = _normalizeAgent(
        agent.copyWith(
          activities: _prependActivity(
            agent.activities,
            AgentActivityEvent(
              id: _uuid.v4(),
              kind: 'audit_recorded',
              title: 'audit_recorded',
              content: trimmedSummary,
              createdAt: now,
              metadata: activityMetadata,
            ),
          ),
          auditEvents: _prependAudit(agent.auditEvents, savedEvent!),
          updatedAt: now,
        ),
      );
      await _replaceAgentAtAndSave(index, updated);
      return true;
    });
    return changed ? savedEvent : null;
  }

  Future<bool> saveScaleSettings(
    String agentId,
    AgentScaleSettings settings, {
    String auditToolName = 'AgentClusterDialog',
  }) {
    final normalizedAgentId = agentId.trim();
    if (normalizedAgentId.isEmpty) return Future<bool>.value(false);
    return _commitMutation(() async {
      final index = _agentIndexById(normalizedAgentId);
      if (index < 0) return false;
      final agent = _agents[index];
      final now = DateTime.now().toUtc();
      final requestedMaxWorkers = settings.maxWorkers
          .clamp(agentScaleMaxWorkersMinimum, agentScaleWorkersMaximum)
          .toInt();
      final protectedWorkerCount = _protectedWorkerCount(agent.workers);
      final normalized = _normalizeScaleSettings(
        settings,
        minimumMaxWorkers: protectedWorkerCount,
      );
      final maxWorkers = normalized.maxWorkers;
      final metadata = <String, Object?>{
        'min_workers': normalized.minWorkers,
        'max_workers': normalized.maxWorkers,
        'scale_out_threshold': normalized.scaleOutThreshold,
        'scale_in_threshold': normalized.scaleInThreshold,
        'worker_removal_policy': normalized.workerRemovalPolicy,
        'retry_policy': normalized.retryPolicy,
        'max_retries': normalized.maxRetries,
        'scheduler_policy': normalized.schedulerPolicy,
        'tags': normalized.tags,
        if (maxWorkers != requestedMaxWorkers)
          'requested_max_workers': requestedMaxWorkers,
        if (protectedWorkerCount > 0)
          'protected_active_workers': protectedWorkerCount,
      };
      final updated = _normalizeAgent(
        agent.copyWith(
          scaleSettings: normalized,
          workers: agent.workers
              .map(
                (worker) =>
                    worker.copyWith(labels: normalized.tags, updatedAt: now),
              )
              .toList(growable: false),
          activities: _prependActivity(
            agent.activities,
            AgentActivityEvent(
              id: _uuid.v4(),
              kind: 'cluster_updated',
              title: 'cluster_updated',
              content: agent.name,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          auditEvents: _prependAudit(
            agent.auditEvents,
            _auditEvent(
              kind: 'cluster_updated',
              summary: 'cluster_updated: ${agent.name}',
              toolName: auditToolName,
              createdAt: now,
              metadata: metadata,
            ),
          ),
          updatedAt: now,
        ),
      );
      await _replaceAgentAtAndSave(index, updated);
      return true;
    });
  }

  Future<bool> updateAgent(
    String id,
    AgentProfile Function(AgentProfile agent) mutate,
  ) {
    return _commitMutation(() async {
      final index = _agentIndexById(id);
      if (index < 0) return false;
      final updated = _normalizeAgent(
        mutate(_agents[index]).copyWith(updatedAt: DateTime.now().toUtc()),
      );
      await _replaceAgentAtAndSave(index, updated);
      return true;
    });
  }

  @override
  void dispose() {
    _saveSuccessPulse.dispose();
    super.dispose();
  }

  Future<bool> _commitMutation(Future<bool> Function() mutation) {
    return enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
      final previous = List<AgentProfile>.from(_agents);
      _errorMessage = null;
      try {
        final changed = await mutation();
        _hasTrustedSnapshot = true;
        if (changed) _saveSuccessPulse.emit();
        notifyListeners();
        return changed;
      } catch (error, stack) {
        silentLog('agents_controller', '保存智能体配置', error, stack);
        _setAgents(previous);
        _hasTrustedSnapshot = true;
        _errorMessage = userFailureMessage(error, fallback: '智能体配置保存失败，请稍后重试。');
        notifyListeners();
        return false;
      }
    });
  }

  Future<void> _loadLocked() async {
    final hadTrustedSnapshot = _hasTrustedSnapshot;
    _isLoading = true;
    _hasTrustedSnapshot = false;
    _errorMessage = null;
    notifyListeners();
    try {
      _setAgents(await _store.load());
      _hasTrustedSnapshot = true;
    } catch (error, stack) {
      silentLog('agents_controller', '加载智能体配置', error, stack);
      _hasTrustedSnapshot = hadTrustedSnapshot;
      _errorMessage = userFailureMessage(error, fallback: '智能体配置加载失败，请稍后重试。');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _ensureTrustedSnapshotLocked() async {
    if (_hasTrustedSnapshot) return true;
    await _loadLocked();
    return _hasTrustedSnapshot;
  }

  void _setAgents(List<AgentProfile> value) {
    _agents = value;
    _agentsView = List<AgentProfile>.unmodifiable(value);
  }

  int _agentIndexById(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) return -1;
    return _agents.indexWhere((agent) => agent.id == normalized);
  }

  void _replaceAgentAt(int index, AgentProfile agent) {
    _setAgents(<AgentProfile>[
      ..._agents.sublist(0, index),
      agent,
      ..._agents.sublist(index + 1),
    ]);
  }

  Future<void> _replaceAgentAtAndSave(int index, AgentProfile agent) async {
    final next = <AgentProfile>[
      ..._agents.sublist(0, index),
      agent,
      ..._agents.sublist(index + 1),
    ];
    await _store.save(next);
    _setAgents(next);
  }

  Future<void> _upsertAgentAndSave(AgentProfile agent) async {
    final index = _agentIndexById(agent.id);
    final next = index < 0
        ? <AgentProfile>[agent, ..._agents]
        : <AgentProfile>[
            ..._agents.sublist(0, index),
            agent,
            ..._agents.sublist(index + 1),
          ];
    await _store.save(next);
    _setAgents(next);
  }

  AgentProfile _normalizeAgent(AgentProfile agent) {
    final scaleSettings = _normalizeScaleSettings(agent.scaleSettings);
    final workerTarget = scaleSettings.minWorkers
        .clamp(0, scaleSettings.maxWorkers)
        .toInt();
    final now = DateTime.now().toUtc();
    final workers = List<AgentWorker>.from(agent.workers);
    while (workers.length < workerTarget) {
      final workerId = _nextWorkerId(agent, workers);
      workers.add(
        AgentWorker(
          id: workerId,
          name: _defaultWorkerName(agent, workerId),
          updatedAt: now,
          labels: scaleSettings.tags,
        ),
      );
    }
    final scaledAgent = agent.copyWith(scaleSettings: scaleSettings);
    final normalizedWorkers = _normalizeWorkersForScale(scaledAgent, workers);
    final normalized = scaledAgent.copyWith(
      name: agent.name.trim().isEmpty ? 'Unnamed Agent' : agent.name.trim(),
      skillNames: dedupeNonEmptyStrings(agent.skillNames),
      knowledgeSourceIds: dedupeNonEmptyStrings(agent.knowledgeSourceIds),
      memoryIds: dedupeNonEmptyStrings(agent.memoryIds),
      taskLabels: dedupeNonEmptyStrings(agent.taskLabels),
      mcpServerNames: dedupeNonEmptyStrings(agent.mcpServerNames),
      builtinToolNames: normalizeAgentBuiltinToolNames(agent.builtinToolNames),
      cronIds: dedupeNonEmptyStrings(agent.cronIds),
      hookIds: dedupeNonEmptyStrings(agent.hookIds),
      instructionIds: dedupeNonEmptyStrings(agent.instructionIds),
      activities: agent.activities.take(agentStoredActivityEventLimit).toList(),
      auditEvents: agent.auditEvents.take(agentStoredAuditEventLimit).toList(),
      workers: normalizedWorkers,
    );
    return normalized.copyWith(
      resourceUsage: _normalizeResourceUsageForAgent(normalized),
    );
  }

  AgentResourceUsage _normalizeResourceUsageForAgent(
    AgentProfile agent, {
    bool reusePersistedByteEstimate = false,
  }) {
    final usage = agent.resourceUsage;
    final telemetry = stringKeyedMapFromValue(
      usage.extra[_resourceTelemetryExtraKey],
    );
    final activeTaskCount = agent.tasks
        .where((task) => !task.status.isTerminal)
        .length;
    final busyWorkerCount = agent.workers
        .where(
          (worker) =>
              worker.status == AgentWorkerStatus.busy || worker.busyScore > 0,
        )
        .length;
    final pendingApprovalCount = agent.approvals
        .where((item) => item.status == AgentApprovalStatus.pending)
        .length;
    final derivedOpenHandles =
        activeTaskCount + busyWorkerCount + pendingApprovalCount;
    final previousPersistedByteEstimate = optionalNonNegativeIntFromValue(
      telemetry['persisted_bytes'],
    );
    final derivedPersistedBytes =
        reusePersistedByteEstimate && previousPersistedByteEstimate != null
        ? previousPersistedByteEstimate
        : _resourcePayloadBytes(agent.toJson());
    final auditTokens = agent.auditEvents.fold<int>(
      0,
      (sum, event) => sum + event.tokenUsage,
    );
    final taskPayloadTokens = agent.tasks.fold<int>(
      0,
      (sum, task) => sum + _taskPayloadTokenEstimate(task),
    );
    final derivedTokenUsed = auditTokens + taskPayloadTokens;
    final workerPressure = clampUnitInterval(agent.workerUtilization);
    final queuePressure = activeTaskCount <= 0
        ? 0.0
        : unitRatio(activeTaskCount, agent.scaleSettings.maxWorkers) * 0.35;
    final derivedCpuPercent = math.max(workerPressure, queuePressure);
    final derivedMemoryBytes = derivedOpenHandles <= 0
        ? 0
        : derivedPersistedBytes +
              derivedOpenHandles * _resourceHandleMemoryBytes +
              agent.workers.length * _resourceWorkerMemoryBytes;
    final manualCpuPercent = _manualResourceRatioMetric(
      usage.cpuPercent,
      telemetry,
      'cpu_percent',
    );
    final manualMemoryBytes = _manualResourceIntMetric(
      usage.memoryBytes,
      telemetry,
      'memory_bytes',
    );
    final manualPersistedBytes = _manualResourceIntMetric(
      usage.persistedBytes,
      telemetry,
      'persisted_bytes',
    );
    final manualTokenUsed = _manualResourceIntMetric(
      usage.tokenUsed,
      telemetry,
      'token_used',
    );
    final manualOpenHandles = _manualResourceIntMetric(
      usage.openHandles,
      telemetry,
      'open_handles',
    );
    final normalizedCpuPercent = clampUnitInterval(
      math.max(manualCpuPercent, derivedCpuPercent),
    );
    final normalizedMemoryBytes = math.max(
      manualMemoryBytes,
      derivedMemoryBytes,
    );
    final normalizedDiskBytes = _nonNegativeAgentMetric(usage.diskBytes);
    final normalizedPersistedBytes = math.max(
      manualPersistedBytes,
      derivedPersistedBytes,
    );
    final normalizedTokenBudget = _nonNegativeAgentMetric(usage.tokenBudget);
    final normalizedTokenUsed = math.max(manualTokenUsed, derivedTokenUsed);
    final normalizedOpenHandles = math.max(
      manualOpenHandles,
      derivedOpenHandles,
    );
    final sampledAt = DateTime.now().toUtc();
    final resourceSample = <String, Object?>{
      'sampled_at': sampledAt.toIso8601String(),
      'cpu_percent': normalizedCpuPercent,
      'memory_bytes': normalizedMemoryBytes,
      'disk_bytes': normalizedDiskBytes,
      'persisted_bytes': normalizedPersistedBytes,
      'token_budget': normalizedTokenBudget,
      'token_used': normalizedTokenUsed,
      'open_handles': normalizedOpenHandles,
      'active_task_count': activeTaskCount,
      'busy_workers': busyWorkerCount,
      'pending_approvals': pendingApprovalCount,
      'audit_token_usage': auditTokens,
      'task_payload_tokens': taskPayloadTokens,
    };
    final nextExtra = <String, Object?>{
      ...usage.publicExtra,
      if (agent.workspacePath.trim().isNotEmpty)
        'workspace_path': agent.workspacePath.trim(),
      'task_count': agent.tasks.length,
      'active_task_count': activeTaskCount,
      'busy_workers': busyWorkerCount,
      'pending_approvals': pendingApprovalCount,
      'audit_token_usage': auditTokens,
      'task_payload_tokens': taskPayloadTokens,
      _resourceTelemetryExtraKey: <String, Object?>{
        'sampled_at': sampledAt.toIso8601String(),
        'cpu_percent': derivedCpuPercent,
        'memory_bytes': derivedMemoryBytes,
        'persisted_bytes': derivedPersistedBytes,
        'token_used': derivedTokenUsed,
        'open_handles': derivedOpenHandles,
        _resourceTelemetryHistoryKey: _appendResourceTelemetrySample(
          telemetry[_resourceTelemetryHistoryKey],
          resourceSample,
          sampledAt,
        ),
      },
    };
    return usage.copyWith(
      cpuPercent: normalizedCpuPercent,
      memoryBytes: normalizedMemoryBytes,
      diskBytes: normalizedDiskBytes,
      persistedBytes: normalizedPersistedBytes,
      tokenBudget: normalizedTokenBudget,
      tokenUsed: normalizedTokenUsed,
      openHandles: normalizedOpenHandles,
      extra: nextExtra,
    );
  }

  List<Map<String, Object?>> _appendResourceTelemetrySample(
    Object? rawHistory,
    Map<String, Object?> sample,
    DateTime sampledAt,
  ) {
    final history = stringKeyedMapListFromValue(rawHistory).toList();
    final previous = history.isEmpty ? null : history.last;
    final previousSampledAt = DateTime.tryParse(
      optionalStringFromValue(previous?['sampled_at']) ?? '',
    );
    if (previousSampledAt != null &&
        sampledAt.difference(previousSampledAt).inMilliseconds <
            _resourceTelemetrySampleMinGapMs) {
      return _trimResourceTelemetryHistory(history);
    }
    history.add(sample);
    return _trimResourceTelemetryHistory(history);
  }

  List<Map<String, Object?>> _trimResourceTelemetryHistory(
    List<Map<String, Object?>> history,
  ) {
    final start = math.max(0, history.length - _maxResourceTelemetrySamples);
    return history.sublist(start).toList(growable: false);
  }

  double _manualResourceRatioMetric(
    double value,
    Map<String, Object?> telemetry,
    String key,
  ) {
    final normalized = clampUnitInterval(value);
    final previousAuto = optionalDoubleFromValue(telemetry[key]);
    if (previousAuto != null &&
        (normalized - clampUnitInterval(previousAuto)).abs() < 0.0001) {
      return 0;
    }
    return normalized;
  }

  int _manualResourceIntMetric(
    int value,
    Map<String, Object?> telemetry,
    String key,
  ) {
    final normalized = _nonNegativeAgentMetric(value);
    final previousAuto = optionalNonNegativeIntFromValue(telemetry[key]);
    if (previousAuto != null && normalized == previousAuto) return 0;
    return normalized;
  }

  int _nonNegativeAgentMetric(int value) {
    return nonNegativeIntFromValue(value, fallback: 0);
  }

  int _taskPayloadTokenEstimate(AgentTask task) {
    final length =
        task.title.length +
        task.description.length +
        task.content.length +
        task.note.length +
        task.result.length;
    if (length <= 0) return 0;
    return (length / _resourceCharsPerToken).ceil();
  }

  int _resourcePayloadBytes(Object? value) {
    try {
      return utf8.encode(jsonEncode(value)).length;
    } catch (_) {
      return utf8.encode('$value').length;
    }
  }

  AgentScaleSettings _normalizeScaleSettings(
    AgentScaleSettings settings, {
    int minimumMaxWorkers = agentScaleMaxWorkersMinimum,
  }) {
    final requestedMaxWorkers = settings.maxWorkers
        .clamp(agentScaleMaxWorkersMinimum, agentScaleWorkersMaximum)
        .toInt();
    final maxWorkers = math.max(requestedMaxWorkers, minimumMaxWorkers);
    return settings.copyWith(
      minWorkers: settings.minWorkers
          .clamp(agentScaleMinWorkersMinimum, maxWorkers)
          .toInt(),
      maxWorkers: maxWorkers,
      scaleOutThreshold: settings.scaleOutThreshold
          .clamp(agentScaleRatioMinimum, agentScaleRatioMaximum)
          .toDouble(),
      scaleInThreshold: settings.scaleInThreshold
          .clamp(agentScaleRatioMinimum, agentScaleRatioMaximum)
          .toDouble(),
      workerRemovalPolicy: _policyOrFallback(
        settings.workerRemovalPolicy,
        agentWorkerRemovalPolicyOptions,
        agentWorkerRemovalPolicyLeastBusy,
      ),
      retryPolicy: _policyOrFallback(
        settings.retryPolicy,
        agentRetryPolicyOptions,
        agentRetryPolicyBoundedRetry,
      ),
      maxRetries: settings.maxRetries
          .clamp(agentScaleMaxRetriesMinimum, agentScaleMaxRetriesMaximum)
          .toInt(),
      schedulerPolicy: _policyOrFallback(
        settings.schedulerPolicy,
        agentSchedulerPolicyOptions,
        agentSchedulerPolicyLeastBusy,
      ),
      tags: dedupeNonEmptyStrings(settings.tags),
    );
  }

  String _policyOrFallback(
    String value,
    Iterable<String> allowedValues,
    String fallback,
  ) {
    final normalized = value.trim().toLowerCase();
    return allowedValues.contains(normalized) ? normalized : fallback;
  }

  List<AgentActivityEvent> _prependActivity(
    List<AgentActivityEvent> existing,
    AgentActivityEvent event,
  ) {
    return <AgentActivityEvent>[
      event,
      ...existing,
    ].take(agentStoredActivityEventLimit).toList();
  }

  /// 审计事件的统一构造：标识符由控制器生成，一次操作默认计一次请求。
  AgentAuditEvent _auditEvent({
    required String kind,
    required String summary,
    required String toolName,
    required DateTime createdAt,
    required Map<String, Object?> metadata,
    int requestCount = 1,
  }) {
    return AgentAuditEvent(
      id: _uuid.v4(),
      kind: kind,
      summary: summary,
      toolName: toolName,
      requestCount: requestCount,
      createdAt: createdAt,
      metadata: metadata,
    );
  }

  List<AgentAuditEvent> _prependAudit(
    List<AgentAuditEvent> existing,
    AgentAuditEvent event,
  ) {
    return <AgentAuditEvent>[
      event,
      ...existing,
    ].take(agentStoredAuditEventLimit).toList();
  }

  AgentProfile _dispatchReadyTasksForAgent(
    AgentProfile agent,
    DateTime now, {
    required String auditToolName,
  }) {
    if (!agent.enabled || agent.lifecycleState != AgentLifecycleState.running) {
      return agent;
    }
    final scaledAgent = _scaleOutForReadyTasks(
      agent,
      now,
      auditToolName: auditToolName,
    );
    final workers = List<AgentWorker>.from(scaledAgent.workers);
    if (workers.isEmpty) return agent;
    final tasks = List<AgentTask>.from(scaledAgent.tasks);
    final readyTasks = oldestReadyAgentTasks(
      tasks.reversed,
      limit: workers.where(_workerAcceptsTask).length,
    );
    if (readyTasks.isEmpty) return agent;
    final taskIndexById = <String, int>{
      for (var index = 0; index < tasks.length; index++) tasks[index].id: index,
    };
    final activities = List<AgentActivityEvent>.from(scaledAgent.activities);
    final auditEvents = List<AgentAuditEvent>.from(scaledAgent.auditEvents);
    var changed = false;
    for (final task in readyTasks) {
      final taskIndex = taskIndexById[task.id]!;
      final workerIndex = _selectWorkerIndex(workers, agent);
      if (workerIndex < 0) break;
      final worker = workers[workerIndex];
      final workerName = worker.name.trim().isEmpty ? worker.id : worker.name;
      final assigned = task.copyWith(
        status: AgentTaskStatus.running,
        progress: task.progress <= 0 ? 0.05 : task.progress,
        updatedAt: now,
        extra: <String, Object?>{
          ...task.extra,
          'assigned_worker_id': worker.id,
          'assigned_worker_name': workerName,
          'assigned_at': now.toIso8601String(),
          agentTaskAssignmentIdExtraKey: _uuid.v4(),
        },
      );
      tasks[taskIndex] = assigned;
      workers[workerIndex] = worker.copyWith(
        status: AgentWorkerStatus.busy,
        busyScore: 1,
        currentTaskId: task.id,
        updatedAt: now,
        extra: <String, Object?>{
          ...worker.extra,
          'last_assigned_task_id': task.id,
          'last_assigned_at': now.toIso8601String(),
        },
      );
      activities.insert(
        0,
        AgentActivityEvent(
          id: _uuid.v4(),
          kind: 'task_assigned',
          title: 'task_assigned',
          content: assigned.title,
          createdAt: now,
          metadata: <String, Object?>{
            'task_id': assigned.id,
            'worker_id': worker.id,
          },
        ),
      );
      auditEvents.insert(
        0,
        _auditEvent(
          kind: 'task_assigned',
          summary: 'task_assigned: ${assigned.title}',
          toolName: auditToolName,
          createdAt: now,
          metadata: <String, Object?>{
            'task_id': assigned.id,
            'worker_id': worker.id,
            'scheduler_policy': agent.scaleSettings.schedulerPolicy,
          },
        ),
      );
      changed = true;
    }
    if (!changed) return agent;
    return scaledAgent.copyWith(
      tasks: tasks,
      workers: workers,
      activities: activities
          .take(agentStoredActivityEventLimit)
          .toList(growable: false),
      auditEvents: auditEvents
          .take(agentStoredAuditEventLimit)
          .toList(growable: false),
    );
  }

  int _selectWorkerIndex(List<AgentWorker> workers, AgentProfile agent) {
    var selected = -1;
    for (var i = 0; i < workers.length; i++) {
      final worker = workers[i];
      if (!_workerAcceptsTask(worker)) continue;
      if (selected < 0 ||
          _workerRanksBefore(
            worker,
            workers[selected],
            agent.scaleSettings.schedulerPolicy,
          )) {
        selected = i;
      }
    }
    return selected;
  }

  bool _workerAcceptsTask(AgentWorker worker) {
    return worker.status == AgentWorkerStatus.idle &&
        worker.currentTaskId.trim().isEmpty;
  }

  int _protectedWorkerCount(List<AgentWorker> workers) {
    return workers.where((worker) => !_workerAcceptsTask(worker)).length;
  }

  List<AgentWorker> _normalizeWorkersForScale(
    AgentProfile agent,
    List<AgentWorker> workers,
  ) {
    final maxWorkers = agent.scaleSettings.maxWorkers
        .clamp(agentScaleMaxWorkersMinimum, agentScaleWorkersMaximum)
        .toInt();
    if (workers.length <= maxWorkers) return workers;
    final removable = workers.where(_workerAcceptsTask).toList(growable: false);
    final removalBudget = math.min(
      workers.length - maxWorkers,
      removable.length,
    );
    if (removalBudget <= 0) return workers;
    final removeIds = _selectWorkerRemovalIds(
      removable,
      agent.scaleSettings.workerRemovalPolicy,
      removalBudget,
    );
    if (removeIds.isEmpty) return workers;
    return workers
        .where((worker) => !removeIds.contains(worker.id))
        .toList(growable: false);
  }

  bool _workerRanksBefore(
    AgentWorker candidate,
    AgentWorker current,
    String schedulerPolicy,
  ) {
    final normalizedPolicy = schedulerPolicy.trim().toLowerCase();
    if (normalizedPolicy == agentSchedulerPolicyPriorityFirst ||
        normalizedPolicy.contains('priority')) {
      if (candidate.priority != current.priority) {
        return candidate.priority > current.priority;
      }
      if (candidate.busyScore != current.busyScore) {
        return candidate.busyScore < current.busyScore;
      }
      if (candidate.executedTaskCount != current.executedTaskCount) {
        return candidate.executedTaskCount < current.executedTaskCount;
      }
      return candidate.id.compareTo(current.id) < 0;
    }
    if (normalizedPolicy == agentSchedulerPolicyRoundRobin ||
        normalizedPolicy.contains('round')) {
      final candidateLastAssigned = _workerLastAssignedAt(candidate);
      final currentLastAssigned = _workerLastAssignedAt(current);
      if (candidateLastAssigned == null && currentLastAssigned != null) {
        return true;
      }
      if (candidateLastAssigned != null && currentLastAssigned == null) {
        return false;
      }
      if (candidateLastAssigned != null && currentLastAssigned != null) {
        final compared = candidateLastAssigned.compareTo(currentLastAssigned);
        if (compared != 0) return compared < 0;
      }
      if (candidate.executedTaskCount != current.executedTaskCount) {
        return candidate.executedTaskCount < current.executedTaskCount;
      }
      return candidate.id.compareTo(current.id) < 0;
    }
    if (candidate.busyScore != current.busyScore) {
      return candidate.busyScore < current.busyScore;
    }
    if (candidate.executedTaskCount != current.executedTaskCount) {
      return candidate.executedTaskCount < current.executedTaskCount;
    }
    return candidate.id.compareTo(current.id) < 0;
  }

  AgentProfile _scaleOutForReadyTasks(
    AgentProfile agent,
    DateTime now, {
    required String auditToolName,
  }) {
    final readyCount = agent.tasks
        .where((task) => task.status == AgentTaskStatus.ready)
        .length;
    if (readyCount == 0) return agent;
    final workers = List<AgentWorker>.from(agent.workers);
    final maxWorkers = agent.scaleSettings.maxWorkers;
    if (workers.length >= maxWorkers) return agent;
    final idleCount = workers.where(_workerAcceptsTask).length;
    final missingCapacity = readyCount - idleCount;
    if (missingCapacity <= 0) return agent;
    final utilization = _workerUtilization(workers);
    if (workers.isNotEmpty &&
        idleCount > 0 &&
        utilization < agent.scaleSettings.scaleOutThreshold) {
      return agent;
    }
    final addCount = math.min(missingCapacity, maxWorkers - workers.length);
    if (addCount <= 0) return agent;
    for (var i = 0; i < addCount; i++) {
      final workerId = _nextWorkerId(agent, workers);
      workers.add(
        AgentWorker(
          id: workerId,
          name: _defaultWorkerName(agent, workerId),
          labels: agent.scaleSettings.tags,
          updatedAt: now,
          extra: <String, Object?>{'scaled_out_at': now.toIso8601String()},
        ),
      );
    }
    return _recordClusterScaleEvent(
      agent.copyWith(workers: workers),
      now,
      kind: 'worker_scaled_out',
      summary: 'worker_scaled_out: +$addCount',
      auditToolName: auditToolName,
      metadata: <String, Object?>{
        'delta': addCount,
        'worker_count': workers.length,
        'ready_task_count': readyCount,
        'scale_out_threshold': agent.scaleSettings.scaleOutThreshold,
      },
    );
  }

  AgentProfile _scaleInIdleWorkers(
    AgentProfile agent,
    DateTime now, {
    required String auditToolName,
  }) {
    final minWorkers = agent.scaleSettings.minWorkers.clamp(
      agentScaleMinWorkersMinimum,
      agent.scaleSettings.maxWorkers,
    );
    final workers = List<AgentWorker>.from(agent.workers);
    if (workers.length <= minWorkers) return agent;
    final hasQueuedOrRunningTasks = agent.tasks.any(
      (task) =>
          task.status == AgentTaskStatus.ready ||
          task.status == AgentTaskStatus.running,
    );
    if (hasQueuedOrRunningTasks) return agent;
    if (_workerUtilization(workers) > agent.scaleSettings.scaleInThreshold) {
      return agent;
    }
    final removable = workers
        .where(
          (worker) =>
              worker.status == AgentWorkerStatus.idle &&
              worker.currentTaskId.trim().isEmpty,
        )
        .toList(growable: false);
    if (removable.isEmpty) return agent;
    final removalBudget = math.min(
      workers.length - minWorkers,
      removable.length,
    );
    final removeIds = _selectWorkerRemovalIds(
      removable,
      agent.scaleSettings.workerRemovalPolicy,
      removalBudget,
    );
    if (removeIds.isEmpty) return agent;
    final nextWorkers = workers
        .where((worker) => !removeIds.contains(worker.id))
        .toList(growable: false);
    return _recordClusterScaleEvent(
      agent.copyWith(workers: nextWorkers),
      now,
      kind: 'worker_scaled_in',
      summary: 'worker_scaled_in: -${removeIds.length}',
      auditToolName: auditToolName,
      metadata: <String, Object?>{
        'delta': -removeIds.length,
        'worker_count': nextWorkers.length,
        'removed_worker_ids': removeIds.toList(growable: false),
        'scale_in_threshold': agent.scaleSettings.scaleInThreshold,
        'worker_removal_policy': agent.scaleSettings.workerRemovalPolicy,
      },
    );
  }

  AgentProfile _recordClusterScaleEvent(
    AgentProfile agent,
    DateTime now, {
    required String kind,
    required String summary,
    required String auditToolName,
    required Map<String, Object?> metadata,
  }) {
    return agent.copyWith(
      activities: _prependActivity(
        agent.activities,
        AgentActivityEvent(
          id: _uuid.v4(),
          kind: kind,
          title: kind,
          createdAt: now,
          metadata: metadata,
        ),
      ),
      auditEvents: _prependAudit(
        agent.auditEvents,
        _auditEvent(
          kind: kind,
          summary: summary,
          toolName: auditToolName,
          createdAt: now,
          metadata: metadata,
        ),
      ),
    );
  }

  AgentProfile _recordTaskRetryScheduled(
    AgentProfile agent,
    AgentTask task,
    DateTime now, {
    required String auditToolName,
  }) {
    final retryCount = _taskRetryCount(task);
    return agent.copyWith(
      activities: _prependActivity(
        agent.activities,
        AgentActivityEvent(
          id: _uuid.v4(),
          kind: 'task_retry_scheduled',
          title: 'task_retry_scheduled',
          content: task.title,
          createdAt: now,
          metadata: <String, Object?>{
            'task_id': task.id,
            'retry_count': retryCount,
          },
        ),
      ),
      auditEvents: _prependAudit(
        agent.auditEvents,
        _auditEvent(
          kind: 'task_retry_scheduled',
          summary: 'task_retry_scheduled: ${task.title}',
          toolName: auditToolName,
          createdAt: now,
          metadata: <String, Object?>{
            'task_id': task.id,
            'retry_count': retryCount,
            'max_retries': agent.scaleSettings.maxRetries,
            'retry_policy': agent.scaleSettings.retryPolicy,
          },
        ),
      ),
    );
  }

  _AgentStopDrainResult _pauseRunningTasksForStop(
    AgentProfile agent,
    DateTime now,
  ) {
    final pausedTaskIds = <String>{};
    final tasks = agent.tasks
        .map((task) {
          if (task.status != AgentTaskStatus.running) return task;
          pausedTaskIds.add(task.id);
          return task.copyWith(
            status: AgentTaskStatus.paused,
            updatedAt: now,
            extra: <String, Object?>{
              ...task.extra,
              'paused_by_agent_stop': true,
              'paused_at': now.toIso8601String(),
            },
          );
        })
        .toList(growable: false);
    if (pausedTaskIds.isEmpty) {
      return _AgentStopDrainResult(agent: agent);
    }
    var workers = agent.workers;
    for (final task in tasks) {
      if (!pausedTaskIds.contains(task.id)) continue;
      workers = _releaseWorkersForTask(
        workers,
        task,
        now,
        countExecution: false,
      );
    }
    final releasedWorkerCount = workers
        .where(
          (worker) =>
              pausedTaskIds.contains(
                '${worker.extra['last_finished_task_id'] ?? ''}'.trim(),
              ) &&
              '${worker.extra['last_finished_status'] ?? ''}' == 'paused',
        )
        .length;
    return _AgentStopDrainResult(
      agent: agent.copyWith(tasks: tasks, workers: workers),
      pausedTaskCount: pausedTaskIds.length,
      releasedWorkerCount: releasedWorkerCount,
    );
  }

  bool _canUpdateTaskState(AgentTask task, AgentTaskStatus? nextStatus) {
    if (task.status.isTerminal) return false;
    if (nextStatus == null) return true;
    if (nextStatus == task.status) return true;
    return switch (task.status) {
      AgentTaskStatus.waitingApproval =>
        nextStatus == AgentTaskStatus.canceled ||
            nextStatus == AgentTaskStatus.failed,
      AgentTaskStatus.paused =>
        nextStatus == AgentTaskStatus.ready ||
            nextStatus == AgentTaskStatus.canceled ||
            nextStatus == AgentTaskStatus.failed,
      AgentTaskStatus.backlog ||
      AgentTaskStatus.ready ||
      AgentTaskStatus.running => true,
      AgentTaskStatus.completed ||
      AgentTaskStatus.failed ||
      AgentTaskStatus.canceled => false,
    };
  }

  Set<String> _selectWorkerRemovalIds(
    List<AgentWorker> workers,
    String removalPolicy,
    int count,
  ) {
    if (count <= 0) return const <String>{};
    final sorted = List<AgentWorker>.from(workers);
    final normalizedPolicy = removalPolicy.trim().toLowerCase();
    sorted.sort((left, right) {
      if (normalizedPolicy.contains('newest')) {
        final leftUpdatedAt = left.updatedAt;
        final rightUpdatedAt = right.updatedAt;
        if (leftUpdatedAt != null && rightUpdatedAt != null) {
          final compared = rightUpdatedAt.compareTo(leftUpdatedAt);
          if (compared != 0) return compared;
        } else if (leftUpdatedAt != null) {
          return -1;
        } else if (rightUpdatedAt != null) {
          return 1;
        }
      }
      if (left.busyScore != right.busyScore) {
        return left.busyScore.compareTo(right.busyScore);
      }
      if (left.executedTaskCount != right.executedTaskCount) {
        return left.executedTaskCount.compareTo(right.executedTaskCount);
      }
      return right.id.compareTo(left.id);
    });
    return sorted.take(count).map((worker) => worker.id).toSet();
  }

  bool _shouldRetryTask(
    AgentProfile agent,
    AgentTask task, {
    required Map<String, Object?>? extra,
    required String activityKind,
  }) {
    if (task.status != AgentTaskStatus.failed) return false;
    if (agent.scaleSettings.maxRetries <= 0) return false;
    final retryPolicy = agent.scaleSettings.retryPolicy.trim().toLowerCase();
    if (retryPolicy.isEmpty ||
        retryPolicy == agentRetryPolicyNone ||
        (retryPolicy != agentRetryPolicyBoundedRetry &&
            !retryPolicy.contains('retry'))) {
      return false;
    }
    final retryable = extra != null && extra.containsKey(_retryableExtraKey)
        ? boolFromValue(extra[_retryableExtraKey])
        : activityKind == 'task_failed';
    if (!retryable) return false;
    return _taskRetryCount(task) < agent.scaleSettings.maxRetries;
  }

  AgentTask _retryTask(AgentTask task, DateTime now) {
    final retryCount = _taskRetryCount(task) + 1;
    return task.copyWith(
      status: AgentTaskStatus.ready,
      progress: 0,
      result: '',
      note: '',
      updatedAt: now,
      extra: <String, Object?>{
        ...task.extra,
        _retryCountExtraKey: retryCount,
        'last_retry_at': now.toIso8601String(),
        'last_failure_result': task.result,
        'last_failure_note': task.note,
      },
    );
  }

  int _taskRetryCount(AgentTask task) {
    return nonNegativeIntFromValue(
      task.extra[_retryCountExtraKey],
      fallback: 0,
    );
  }

  double _workerUtilization(List<AgentWorker> workers) {
    if (workers.isEmpty) return 1;
    final busyCount = workers
        .where((worker) => worker.status == AgentWorkerStatus.busy)
        .length;
    return busyCount / workers.length;
  }

  DateTime? _workerLastAssignedAt(AgentWorker worker) {
    return dateTimeFromValue(worker.extra['last_assigned_at']);
  }

  String _nextWorkerId(AgentProfile agent, List<AgentWorker> workers) {
    final used = workers.map((worker) => worker.id).toSet();
    for (var index = 1; index < 10000; index++) {
      final id = '${agent.id}-worker-$index';
      if (!used.contains(id)) return id;
    }
    return '${agent.id}-worker-${_uuid.v4()}';
  }

  String _defaultWorkerName(AgentProfile agent, String workerId) {
    final suffix = workerId.split('-').last;
    final name = agent.name.trim().isEmpty ? 'Agent' : agent.name.trim();
    return '$name Worker $suffix';
  }

  List<AgentWorker> _releaseWorkersForTask(
    List<AgentWorker> workers,
    AgentTask task,
    DateTime now, {
    required bool countExecution,
  }) {
    final assignedWorkerId = '${task.extra['assigned_worker_id'] ?? ''}'.trim();
    return workers
        .map((worker) {
          final ownsTask =
              worker.currentTaskId == task.id ||
              (worker.currentTaskId.trim().isEmpty &&
                  assignedWorkerId.isNotEmpty &&
                  worker.id == assignedWorkerId &&
                  (worker.status == AgentWorkerStatus.busy ||
                      worker.busyScore > 0));
          if (!ownsTask) return worker;
          final wasActivelyRunningTask = worker.currentTaskId == task.id;
          return worker.copyWith(
            status: AgentWorkerStatus.idle,
            busyScore: 0,
            currentTaskId: '',
            executedTaskCount: countExecution
                ? worker.executedTaskCount + (wasActivelyRunningTask ? 1 : 0)
                : worker.executedTaskCount,
            updatedAt: now,
            extra: <String, Object?>{
              ...worker.extra,
              'last_finished_task_id': task.id,
              'last_finished_status': task.status.storageValue,
              'last_finished_at': now.toIso8601String(),
            },
          );
        })
        .toList(growable: false);
  }

  bool _taskStatusReleasesWorker(AgentTaskStatus status) {
    return switch (status) {
      AgentTaskStatus.waitingApproval ||
      AgentTaskStatus.paused ||
      AgentTaskStatus.completed ||
      AgentTaskStatus.failed ||
      AgentTaskStatus.canceled => true,
      AgentTaskStatus.backlog ||
      AgentTaskStatus.ready ||
      AgentTaskStatus.running => false,
    };
  }

  /// 语义独立于 [AgentTaskStatus.isTerminal]：这里回答“是否计入已执行数”，
  /// 当前取值集合恰好相同，一旦两个概念分叉必须各自演进，勿合并。
  bool _taskStatusCountsExecution(AgentTaskStatus status) {
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
}

class _AgentStopDrainResult {
  const _AgentStopDrainResult({
    required this.agent,
    this.pausedTaskCount = 0,
    this.releasedWorkerCount = 0,
  });

  final AgentProfile agent;
  final int pausedTaskCount;
  final int releasedWorkerCount;
}
