import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../shared/core/managed_change_notifier.dart';
import 'data/agents_store.dart';
import 'model/agent_models.dart';
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
  static const int _maxActivityEvents = 200;
  static const int _maxAuditEvents = 500;

  final AgentsStore _store;
  List<AgentProfile> _agents;
  List<AgentProfile> _agentsView;
  bool _isLoading;
  String? _errorMessage;
  AgentRuntimeAvailabilityProvider? _runtimeAvailabilityProvider;
  final ChangePulse _saveSuccessPulse = ChangePulse();

  List<AgentProfile> get agents => _agentsView;
  List<AgentProfile> get enabledAgents {
    if (!runtimeAvailability.canRun) return const <AgentProfile>[];
    return _agentsView.where((agent) => agent.enabled).toList(growable: false);
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ValueListenable<int> get saveSuccessSignal => _saveSuccessPulse.listenable;
  String get storageDirectoryPath => _store.storageDirectoryPath;
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
    return enqueueOperation(() async {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      try {
        _setAgents(await _store.load());
      } catch (error) {
        _errorMessage = '$error';
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<bool> saveAgent(AgentProfile draft) {
    return _commitMutation(() async {
      final now = DateTime.now().toUtc();
      final normalized = _normalizeAgent(
        draft.copyWith(
          id: draft.id.trim().isEmpty ? _uuid.v4() : draft.id.trim(),
          updatedAt: now,
          createdAt: draft.createdAt ?? now,
        ),
      );
      final index = _agents.indexWhere((agent) => agent.id == normalized.id);
      if (index < 0) {
        _setAgents(<AgentProfile>[normalized, ..._agents]);
      } else {
        _setAgents(<AgentProfile>[
          ..._agents.sublist(0, index),
          normalized,
          ..._agents.sublist(index + 1),
        ]);
      }
      await _store.save(_agents);
      return true;
    });
  }

  Future<bool> deleteAgent(String id) {
    return _commitMutation(() async {
      final before = _agents.length;
      _setAgents(_agents.where((agent) => agent.id != id).toList());
      if (_agents.length == before) return false;
      await _store.save(_agents);
      return true;
    });
  }

  Future<bool> setAgentEnabled(String id, {required bool enabled}) {
    final runtime = runtimeAvailability;
    if (enabled && !runtime.canRun) {
      _errorMessage = runtime.blockingReason;
      notifyListeners();
      return Future<bool>.value(false);
    }
    return updateAgent(id, (agent) {
      final now = DateTime.now().toUtc();
      final kind = enabled ? 'agent_started' : 'agent_stopped';
      final lifecycleState = enabled
          ? AgentLifecycleState.running
          : AgentLifecycleState.stopped;
      return agent.copyWith(
        enabled: enabled,
        lifecycleState: lifecycleState,
        activities: _prependActivity(
          agent.activities,
          AgentActivityEvent(
            id: _uuid.v4(),
            kind: kind,
            title: kind,
            createdAt: now,
          ),
        ),
        auditEvents: _prependAudit(
          agent.auditEvents,
          AgentAuditEvent(
            id: _uuid.v4(),
            kind: kind,
            summary: kind,
            toolName: 'AgentsController',
            requestCount: 1,
            createdAt: now,
            metadata: <String, Object?>{
              'enabled': enabled,
              'lifecycle_state': lifecycleState.storageValue,
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
    AgentTask? createdTask;
    final changed = await updateAgent(agentId, (agent) {
      if (!agent.enabled) return agent;
      final now = DateTime.now().toUtc();
      final task = AgentTask(
        id: _uuid.v4(),
        title: title.trim().isEmpty ? 'Untitled task' : title.trim(),
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
          AgentAuditEvent(
            id: _uuid.v4(),
            kind: 'task_published',
            summary: 'task_published: ${task.title}',
            toolName: auditToolName,
            requestCount: 1,
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
      return dispatched;
    });
    return changed ? createdTask : null;
  }

  Future<AgentTask?> updateTaskState(
    String agentId,
    String taskId, {
    AgentTaskStatus? status,
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
    if (normalizedTaskId.isEmpty) return null;
    return updateAgent(agentId, (agent) {
      if (!agent.enabled) return agent;
      final now = DateTime.now().toUtc();
      var found = false;
      final tasks = agent.tasks
          .map((task) {
            if (task.id != normalizedTaskId) return task;
            found = true;
            final nextProgress = progress == null
                ? status == AgentTaskStatus.completed
                      ? 1.0
                      : task.progress
                : progress.clamp(0, 1).toDouble();
            updatedTask = task.copyWith(
              status: status,
              progress: nextProgress,
              note: note,
              result: result,
              extra: extra == null
                  ? task.extra
                  : <String, Object?>{...task.extra, ...extra},
              updatedAt: now,
            );
            return updatedTask!;
          })
          .toList(growable: false);
      if (!found || updatedTask == null) return agent;
      final nextWorkers = status == null || !_taskStatusReleasesWorker(status)
          ? agent.workers
          : _releaseWorkersForTask(
              agent.workers,
              updatedTask!,
              now,
              countExecution: _taskStatusCountsExecution(status),
            );
      final updated = agent.copyWith(
        tasks: tasks,
        workers: nextWorkers,
        activities: _prependActivity(
          agent.activities,
          AgentActivityEvent(
            id: _uuid.v4(),
            kind: activityKind,
            title: activityTitle,
            content: updatedTask!.title,
            createdAt: now,
            metadata: <String, Object?>{
              'task_id': updatedTask!.id,
              'task_status': updatedTask!.status.storageValue,
            },
          ),
        ),
        auditEvents: _prependAudit(
          agent.auditEvents,
          AgentAuditEvent(
            id: _uuid.v4(),
            kind: activityKind,
            summary: '$activityTitle: ${updatedTask!.title}',
            toolName: auditToolName,
            requestCount: 1,
            createdAt: now,
            metadata: <String, Object?>{
              'task_id': updatedTask!.id,
              'task_status': updatedTask!.status.storageValue,
              'task_progress': updatedTask!.progress,
              if (extra != null && extra.containsKey('updated_by_session_id'))
                'updated_by_session_id': extra['updated_by_session_id'],
            },
          ),
        ),
      );
      final next = status == AgentTaskStatus.ready
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
      return next;
    }).then((changed) => changed ? updatedTask : null);
  }

  Future<bool> updateAgent(
    String id,
    AgentProfile Function(AgentProfile agent) mutate,
  ) {
    return _commitMutation(() async {
      final index = _agents.indexWhere((agent) => agent.id == id);
      if (index < 0) return false;
      final updated = _normalizeAgent(
        mutate(_agents[index]).copyWith(updatedAt: DateTime.now().toUtc()),
      );
      _setAgents(<AgentProfile>[
        ..._agents.sublist(0, index),
        updated,
        ..._agents.sublist(index + 1),
      ]);
      await _store.save(_agents);
      return true;
    });
  }

  Future<void> openStorageDirectory() => _store.openStorageDirectory();

  @override
  void dispose() {
    _saveSuccessPulse.dispose();
    super.dispose();
  }

  Future<bool> _commitMutation(Future<bool> Function() mutation) {
    return enqueueOperation(() async {
      final previous = List<AgentProfile>.from(_agents);
      try {
        final changed = await mutation();
        if (changed) _saveSuccessPulse.emit();
        notifyListeners();
        return changed;
      } catch (error) {
        _setAgents(previous);
        _errorMessage = '$error';
        notifyListeners();
        return false;
      }
    });
  }

  void _setAgents(List<AgentProfile> value) {
    _agents = value;
    _agentsView = List<AgentProfile>.unmodifiable(value);
  }

  AgentProfile _normalizeAgent(AgentProfile agent) {
    final workerTarget = agent.scaleSettings.minWorkers.clamp(
      0,
      agent.scaleSettings.maxWorkers,
    );
    final workers = List<AgentWorker>.from(agent.workers);
    while (workers.length < workerTarget) {
      final index = workers.length + 1;
      workers.add(
        AgentWorker(
          id: '${agent.id}-worker-$index',
          name: '${agent.name} Worker $index',
          updatedAt: DateTime.now().toUtc(),
          labels: agent.scaleSettings.tags,
        ),
      );
    }
    return agent.copyWith(
      name: agent.name.trim().isEmpty ? 'Unnamed Agent' : agent.name.trim(),
      skillNames: _dedupe(agent.skillNames),
      knowledgeSourceIds: _dedupe(agent.knowledgeSourceIds),
      memoryIds: _dedupe(agent.memoryIds),
      taskLabels: _dedupe(agent.taskLabels),
      mcpServerNames: _dedupe(agent.mcpServerNames),
      builtinToolNames: _dedupe(agent.builtinToolNames),
      cronIds: _dedupe(agent.cronIds),
      hookIds: _dedupe(agent.hookIds),
      activities: agent.activities.take(_maxActivityEvents).toList(),
      auditEvents: agent.auditEvents.take(_maxAuditEvents).toList(),
      workers: workers.take(agent.scaleSettings.maxWorkers).toList(),
    );
  }

  List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      final key = value.toLowerCase();
      if (seen.add(key)) result.add(value);
    }
    return result;
  }

  List<AgentActivityEvent> _prependActivity(
    List<AgentActivityEvent> existing,
    AgentActivityEvent event,
  ) {
    return <AgentActivityEvent>[
      event,
      ...existing,
    ].take(_maxActivityEvents).toList();
  }

  List<AgentAuditEvent> _prependAudit(
    List<AgentAuditEvent> existing,
    AgentAuditEvent event,
  ) {
    return <AgentAuditEvent>[event, ...existing].take(_maxAuditEvents).toList();
  }

  AgentProfile _dispatchReadyTasksForAgent(
    AgentProfile agent,
    DateTime now, {
    required String auditToolName,
  }) {
    if (!agent.enabled || agent.lifecycleState != AgentLifecycleState.running) {
      return agent;
    }
    final workers = List<AgentWorker>.from(agent.workers);
    if (workers.isEmpty) return agent;
    final tasks = <AgentTask>[];
    final activities = List<AgentActivityEvent>.from(agent.activities);
    final auditEvents = List<AgentAuditEvent>.from(agent.auditEvents);
    var changed = false;
    for (final task in agent.tasks) {
      if (task.status != AgentTaskStatus.ready) {
        tasks.add(task);
        continue;
      }
      final workerIndex = _selectWorkerIndex(workers, agent);
      if (workerIndex < 0) {
        tasks.add(task);
        continue;
      }
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
        },
      );
      tasks.add(assigned);
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
        AgentAuditEvent(
          id: _uuid.v4(),
          kind: 'task_assigned',
          summary: 'task_assigned: ${assigned.title}',
          toolName: auditToolName,
          requestCount: 1,
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
    return agent.copyWith(
      tasks: tasks,
      workers: workers,
      activities: activities.take(_maxActivityEvents).toList(growable: false),
      auditEvents: auditEvents.take(_maxAuditEvents).toList(growable: false),
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

  bool _workerRanksBefore(
    AgentWorker candidate,
    AgentWorker current,
    String schedulerPolicy,
  ) {
    final normalizedPolicy = schedulerPolicy.trim().toLowerCase();
    if (normalizedPolicy.contains('priority') &&
        candidate.priority != current.priority) {
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
              (assignedWorkerId.isNotEmpty && worker.id == assignedWorkerId);
          if (!ownsTask) return worker;
          return worker.copyWith(
            status: AgentWorkerStatus.idle,
            busyScore: 0,
            currentTaskId: '',
            executedTaskCount: countExecution
                ? worker.executedTaskCount + 1
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
