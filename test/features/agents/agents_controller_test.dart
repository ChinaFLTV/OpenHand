import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/data/agents_store.dart';
import 'package:openhand/features/agents/index.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AgentsController worker dispatch', () {
    late Directory tempDir;
    late AgentsController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'openhand_agents_controller_test_',
      );
      controller = AgentsController.uninitialized(
        store: AgentsStore(filePath: p.join(tempDir.path, 'agents.json')),
      );
      await controller.refresh();
    });

    tearDown(() async {
      controller.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saving enabled agent respects runtime availability gate', () async {
      controller.setRuntimeAvailabilityProvider(
        () => const AgentRuntimeAvailability(
          isLoading: false,
          isInstalled: true,
          isEnabled: false,
          pluginName: 'Hermes Agent',
        ),
      );

      final saved = await controller.saveAgent(_runningAgent());

      expect(saved, isTrue);
      final agent = controller.agentById('agent-1')!;
      expect(agent.enabled, isFalse);
      expect(agent.lifecycleState, AgentLifecycleState.stopped);
      expect(controller.enabledAgents, isEmpty);
      expect(controller.errorMessage, contains('disabled'));
    });

    test('loading runtime does not allow enabled agents to run', () async {
      controller.setRuntimeAvailabilityProvider(
        () => const AgentRuntimeAvailability(
          isLoading: true,
          isInstalled: true,
          isEnabled: true,
          pluginName: 'Hermes Agent',
        ),
      );

      final saved = await controller.saveAgent(_runningAgent());

      expect(saved, isTrue);
      final agent = controller.agentById('agent-1')!;
      expect(agent.enabled, isFalse);
      expect(agent.lifecycleState, AgentLifecycleState.stopped);
      expect(controller.enabledAgents, isEmpty);
      expect(controller.errorMessage, contains('loading'));
    });

    test(
      'starting an agent blocked by runtime does not poison page error',
      () async {
        controller.setRuntimeAvailabilityProvider(
          () => const AgentRuntimeAvailability(
            isLoading: false,
            isInstalled: true,
            isEnabled: false,
            pluginName: 'Hermes Agent',
          ),
        );
        await controller.saveAgent(
          const AgentProfile(id: 'agent-1', name: 'Ops Agent'),
        );

        final started = await controller.setAgentEnabled(
          'agent-1',
          enabled: true,
        );

        expect(started, isFalse);
        expect(controller.agentById('agent-1')!.enabled, isFalse);
        expect(controller.errorMessage, isNull);
      },
    );

    test('publishing a task assigns an idle worker', () async {
      await controller.saveAgent(_runningAgent());

      final task = await controller.publishTaskWithResult(
        'agent-1',
        title: 'Prepare weekly report',
      );

      expect(task, isNotNull);
      expect(task!.status, AgentTaskStatus.running);
      expect(task.progress, 0.05);
      expect(task.extra['assigned_worker_id'], 'worker-1');

      final agent = controller.agentById('agent-1')!;
      expect(agent.workers.single.status, AgentWorkerStatus.busy);
      expect(agent.workers.single.currentTaskId, task.id);
      expect(
        agent.activities.map((event) => event.kind),
        contains('task_assigned'),
      );
      expect(
        agent.auditEvents.map((event) => event.kind),
        contains('task_assigned'),
      );
    });

    test('publishing a task preserves caller extra metadata', () async {
      await controller.saveAgent(_runningAgent());

      final task = await controller.publishTaskWithResult(
        'agent-1',
        title: 'Prepare task with metadata',
        extra: const <String, Object?>{
          'priority': 'high',
          'retryable': true,
          'labels': <String>['report', 'urgent'],
        },
      );

      expect(task, isNotNull);
      expect(task!.extra['priority'], 'high');
      expect(task.extra['retryable'], isTrue);
      expect(task.extra['labels'], <Object?>['report', 'urgent']);
      expect(task.extra['assigned_worker_id'], 'worker-1');
      final agentTask = controller.taskById('agent-1', task.id)!;
      expect(agentTask.extra['priority'], 'high');
      expect(agentTask.extra['assigned_worker_name'], 'Worker 1');
    });

    test(
      'pausing a task releases the assigned worker without counting it',
      () async {
        await controller.saveAgent(_runningAgent());
        final task = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Prepare monthly report',
        );

        final paused = await controller.updateTaskState(
          'agent-1',
          task!.id,
          status: AgentTaskStatus.paused,
        );

        expect(paused, isNotNull);
        expect(paused!.status, AgentTaskStatus.paused);
        final worker = controller.agentById('agent-1')!.workers.single;
        expect(worker.status, AgentWorkerStatus.idle);
        expect(worker.currentTaskId, isEmpty);
        expect(worker.busyScore, 0);
        expect(worker.executedTaskCount, 0);
      },
    );

    test(
      'task state updates reject invalid transitions without side effects',
      () async {
        await controller.saveAgent(_runningAgent());
        final task = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Guard task state',
        );
        final paused = await controller.updateTaskState(
          'agent-1',
          task!.id,
          status: AgentTaskStatus.paused,
        );
        expect(paused, isNotNull);

        final beforePausedAgent = controller.agentById('agent-1')!;
        final invalidComplete = await controller.updateTaskState(
          'agent-1',
          task.id,
          status: AgentTaskStatus.completed,
          result: 'should not complete while paused',
        );
        final afterPausedAgent = controller.agentById('agent-1')!;
        expect(invalidComplete, isNull);
        expect(afterPausedAgent.tasks.single.status, AgentTaskStatus.paused);
        expect(afterPausedAgent.tasks.single.result, isEmpty);
        expect(
          afterPausedAgent.activities.length,
          beforePausedAgent.activities.length,
        );
        expect(
          afterPausedAgent.auditEvents.length,
          beforePausedAgent.auditEvents.length,
        );

        final resumed = await controller.updateTaskState(
          'agent-1',
          task.id,
          status: AgentTaskStatus.ready,
        );
        expect(resumed, isNotNull);
        final completed = await controller.updateTaskState(
          'agent-1',
          task.id,
          status: AgentTaskStatus.completed,
          result: 'done',
        );
        expect(completed, isNotNull);

        final beforeTerminalAgent = controller.agentById('agent-1')!;
        final invalidCancel = await controller.updateTaskState(
          'agent-1',
          task.id,
          status: AgentTaskStatus.canceled,
          note: 'late cancel',
        );
        final afterTerminalAgent = controller.agentById('agent-1')!;
        expect(invalidCancel, isNull);
        expect(
          afterTerminalAgent.tasks.single.status,
          AgentTaskStatus.completed,
        );
        expect(afterTerminalAgent.tasks.single.note, isEmpty);
        expect(
          afterTerminalAgent.activities.length,
          beforeTerminalAgent.activities.length,
        );
        expect(
          afterTerminalAgent.auditEvents.length,
          beforeTerminalAgent.auditEvents.length,
        );
        expect(afterTerminalAgent.workers.single.executedTaskCount, 1);
      },
    );

    test(
      'publishing queued work scales out workers within the max range',
      () async {
        await controller.saveAgent(
          _runningAgent(scaleSettings: const AgentScaleSettings(maxWorkers: 3)),
        );
        final first = await controller.publishTaskWithResult(
          'agent-1',
          title: 'First report',
        );

        final second = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Second report',
        );

        expect(first, isNotNull);
        expect(second, isNotNull);
        expect(second!.status, AgentTaskStatus.running);
        expect(second.extra['assigned_worker_id'], isNot('worker-1'));
        final agent = controller.agentById('agent-1')!;
        expect(agent.workers.length, 2);
        expect(
          agent.activities.map((event) => event.kind),
          contains('worker_scaled_out'),
        );
      },
    );

    test('completed work scales idle workers back to the minimum', () async {
      await controller.saveAgent(
        _runningAgent(scaleSettings: const AgentScaleSettings(maxWorkers: 3)),
      );
      final first = await controller.publishTaskWithResult(
        'agent-1',
        title: 'First report',
      );
      final second = await controller.publishTaskWithResult(
        'agent-1',
        title: 'Second report',
      );

      await controller.updateTaskState(
        'agent-1',
        first!.id,
        status: AgentTaskStatus.completed,
      );
      await controller.updateTaskState(
        'agent-1',
        second!.id,
        status: AgentTaskStatus.completed,
      );

      final agent = controller.agentById('agent-1')!;
      expect(agent.workers.length, 1);
      expect(
        agent.auditEvents.map((event) => event.kind),
        contains('worker_scaled_in'),
      );
    });

    test(
      'round robin scheduling prefers the least recently assigned worker',
      () async {
        final now = DateTime.now().toUtc();
        await controller.saveAgent(
          _runningAgent(
            scaleSettings: const AgentScaleSettings(
              minWorkers: 2,
              maxWorkers: 2,
              schedulerPolicy: 'round_robin',
            ),
            workers: <AgentWorker>[
              AgentWorker(
                id: 'worker-1',
                name: 'Worker 1',
                extra: <String, Object?>{
                  'last_assigned_at': now.toIso8601String(),
                },
              ),
              const AgentWorker(id: 'worker-2', name: 'Worker 2'),
            ],
          ),
        );

        final task = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Round robin task',
        );

        expect(task, isNotNull);
        expect(task!.extra['assigned_worker_id'], 'worker-2');
      },
    );

    test('bounded retry reschedules retryable failed work', () async {
      await controller.saveAgent(
        _runningAgent(scaleSettings: const AgentScaleSettings(maxRetries: 1)),
      );
      final task = await controller.publishTaskWithResult(
        'agent-1',
        title: 'Retryable task',
      );

      final retried = await controller.updateTaskState(
        'agent-1',
        task!.id,
        status: AgentTaskStatus.failed,
        result: 'transient failure',
        activityKind: 'task_failed',
        activityTitle: 'task_failed',
      );

      expect(retried, isNotNull);
      expect(retried!.status, AgentTaskStatus.running);
      expect(retried.extra['retry_count'], 1);
      final agent = controller.agentById('agent-1')!;
      expect(agent.workers.single.status, AgentWorkerStatus.busy);
      expect(agent.workers.single.executedTaskCount, 1);
      expect(
        agent.activities.map((event) => event.kind),
        contains('task_retry_scheduled'),
      );
    });

    test('resolving approval records status activity and audit', () async {
      await controller.saveAgent(
        _runningAgent(
          approvals: <AgentApprovalRequest>[
            AgentApprovalRequest(
              id: 'approval-1',
              title: 'Publish production change',
              reason: 'Needs mentor confirmation',
              requestedAction: 'deploy',
              createdAt: DateTime.utc(2026, 7, 3),
            ),
          ],
        ),
      );

      final resolved = await controller.resolveApproval(
        'agent-1',
        'approval-1',
        AgentApprovalStatus.approved,
        note: 'mentor approved',
        auditToolName: 'AgentApprovalTest',
      );

      expect(resolved, isNotNull);
      expect(resolved!.status, AgentApprovalStatus.approved);
      expect(resolved.resolvedAt, isNotNull);
      expect(resolved.extra['resolution_note'], 'mentor approved');

      final agent = controller.agentById('agent-1')!;
      expect(agent.approvals.single.status, AgentApprovalStatus.approved);
      expect(agent.approvals.single.resolvedAt, isNotNull);
      expect(agent.activities.first.kind, 'approval_approved');
      expect(agent.auditEvents.first.kind, 'approval_approved');
      expect(agent.auditEvents.first.toolName, 'AgentApprovalTest');
      expect(agent.auditEvents.first.metadata['approval_id'], 'approval-1');

      final rejectedAgain = await controller.resolveApproval(
        'agent-1',
        'approval-1',
        AgentApprovalStatus.rejected,
      );
      expect(rejectedAgain, isNull);
      expect(
        controller.agentById('agent-1')!.approvals.single.status,
        AgentApprovalStatus.approved,
      );
    });

    test(
      'requesting approval records pending request activity and audit',
      () async {
        await controller.saveAgent(_runningAgent());

        final approval = await controller.requestApproval(
          'agent-1',
          title: 'Access production logs',
          reason: 'Need mentor confirmation before reading sensitive logs',
          requestedAction: 'read_prod_logs',
          auditToolName: 'AgentApprovalRequestTest',
        );

        expect(approval, isNotNull);
        expect(approval!.id, isNotEmpty);
        expect(approval.status, AgentApprovalStatus.pending);
        expect(approval.reason, contains('mentor confirmation'));
        final agent = controller.agentById('agent-1')!;
        expect(agent.approvals.single.id, approval.id);
        expect(agent.pendingApprovalCount, 1);
        expect(agent.activities.first.kind, 'approval_requested');
        expect(agent.auditEvents.first.kind, 'approval_requested');
        expect(agent.auditEvents.first.toolName, 'AgentApprovalRequestTest');
        expect(agent.auditEvents.first.metadata['approval_id'], approval.id);
      },
    );

    test('saving and deleting KPI records activity and audit', () async {
      await controller.saveAgent(_runningAgent());

      final created = await controller.saveKpi(
        'agent-1',
        const AgentKpiItem(
          id: '',
          name: 'Weekly delivery',
          target: 'Ship 3 improvements',
          progress: 0.4,
          plan: 'Prioritize task loop gaps',
        ),
        auditToolName: 'AgentKpiTest',
      );

      expect(created, isNotNull);
      expect(created!.id, isNotEmpty);
      expect(created.progress, 0.4);
      var agent = controller.agentById('agent-1')!;
      expect(agent.kpis.single.id, created.id);
      expect(agent.activities.first.kind, 'kpi_created');
      expect(agent.auditEvents.first.kind, 'kpi_created');
      expect(agent.auditEvents.first.toolName, 'AgentKpiTest');

      final updated = await controller.saveKpi(
        'agent-1',
        created.copyWith(progress: 1, status: 'done'),
        auditToolName: 'AgentKpiTest',
      );

      expect(updated, isNotNull);
      expect(updated!.status, 'done');
      agent = controller.agentById('agent-1')!;
      expect(agent.kpis.single.progress, 1);
      expect(agent.activities.first.kind, 'kpi_updated');
      expect(agent.auditEvents.first.metadata['kpi_id'], created.id);

      final deleted = await controller.deleteKpi(
        'agent-1',
        created.id,
        auditToolName: 'AgentKpiTest',
      );

      expect(deleted, isTrue);
      agent = controller.agentById('agent-1')!;
      expect(agent.kpis, isEmpty);
      expect(agent.activities.first.kind, 'kpi_deleted');
      expect(agent.auditEvents.first.kind, 'kpi_deleted');
    });

    test('saving resource usage records activity and audit', () async {
      await controller.saveAgent(_runningAgent());

      final saved = await controller.saveResourceUsage(
        'agent-1',
        const AgentResourceUsage(
          cpuPercent: 1.4,
          memoryBytes: 1024,
          diskBytes: -20,
          persistedBytes: 512,
          tokenBudget: 1000,
          tokenUsed: 250,
          openHandles: -1,
        ),
        auditToolName: 'AgentResourcesTest',
      );

      expect(saved, isTrue);
      final agent = controller.agentById('agent-1')!;
      expect(agent.resourceUsage.cpuPercent, 1);
      expect(agent.resourceUsage.memoryBytes, 1024);
      expect(agent.resourceUsage.diskBytes, 0);
      expect(agent.resourceUsage.openHandles, 0);
      expect(agent.activities.first.kind, 'resource_updated');
      expect(agent.auditEvents.first.kind, 'resource_updated');
      expect(agent.auditEvents.first.toolName, 'AgentResourcesTest');
      expect(agent.auditEvents.first.metadata['token_used'], 250);
    });

    test('recording audit event stores capability metrics', () async {
      await controller.saveAgent(_runningAgent());

      final event = await controller.recordAuditEvent(
        'agent-1',
        kind: 'mcp_call',
        summary: 'mcp_call: fetch billing rows',
        toolName: 'billing.query',
        tokenUsage: 128,
        requestCount: 2,
        metadata: const <String, Object?>{
          'task_id': 'task-1',
          'worker_id': 'worker-1',
        },
        auditToolName: 'AgentAuditRecordTest',
      );

      expect(event, isNotNull);
      expect(event!.kind, 'mcp_call');
      expect(event.toolName, 'billing.query');
      expect(event.tokenUsage, 128);
      expect(event.requestCount, 2);
      final agent = controller.agentById('agent-1')!;
      expect(agent.auditEvents.first.id, event.id);
      expect(
        agent.auditEvents.first.metadata['recorded_by'],
        'AgentAuditRecordTest',
      );
      expect(agent.activities.first.kind, 'audit_recorded');
      expect(agent.activities.first.metadata['audit_id'], event.id);
    });

    test('saving scale settings resizes workers and records audit', () async {
      await controller.saveAgent(_runningAgent());

      final saved = await controller.saveScaleSettings(
        'agent-1',
        const AgentScaleSettings(
          minWorkers: 2,
          maxWorkers: 3,
          scaleOutThreshold: 0.6,
          scaleInThreshold: 0.2,
          workerRemovalPolicy: 'newest_first',
          maxRetries: 4,
          schedulerPolicy: 'round_robin',
          tags: <String>['ops', 'ops', 'urgent'],
        ),
        auditToolName: 'AgentClusterTest',
      );

      expect(saved, isTrue);
      final agent = controller.agentById('agent-1')!;
      expect(agent.scaleSettings.minWorkers, 2);
      expect(agent.scaleSettings.maxWorkers, 3);
      expect(agent.scaleSettings.tags, <String>['ops', 'urgent']);
      expect(agent.workers.length, 2);
      expect(
        agent.workers.every((worker) => worker.labels.length == 2),
        isTrue,
      );
      expect(agent.activities.first.kind, 'cluster_updated');
      expect(agent.auditEvents.first.kind, 'cluster_updated');
      expect(agent.auditEvents.first.toolName, 'AgentClusterTest');
      expect(
        agent.auditEvents.first.metadata['scheduler_policy'],
        'round_robin',
      );
    });

    test(
      'saving scale settings preserves busy workers when shrinking max',
      () async {
        await controller.saveAgent(
          _runningAgent(
            scaleSettings: const AgentScaleSettings(
              minWorkers: 0,
              maxWorkers: 3,
            ),
            workers: const <AgentWorker>[
              AgentWorker(
                id: 'worker-1',
                name: 'Busy Worker 1',
                status: AgentWorkerStatus.busy,
                currentTaskId: 'task-1',
              ),
              AgentWorker(
                id: 'worker-2',
                name: 'Busy Worker 2',
                status: AgentWorkerStatus.busy,
                currentTaskId: 'task-2',
              ),
              AgentWorker(
                id: 'worker-3',
                name: 'Busy Worker 3',
                status: AgentWorkerStatus.busy,
                currentTaskId: 'task-3',
              ),
              AgentWorker(id: 'worker-4', name: 'Idle Worker'),
            ],
            tasks: const <AgentTask>[
              AgentTask(
                id: 'task-1',
                title: 'Busy task 1',
                status: AgentTaskStatus.running,
                extra: <String, Object?>{'assigned_worker_id': 'worker-1'},
              ),
              AgentTask(
                id: 'task-2',
                title: 'Busy task 2',
                status: AgentTaskStatus.running,
                extra: <String, Object?>{'assigned_worker_id': 'worker-2'},
              ),
              AgentTask(
                id: 'task-3',
                title: 'Busy task 3',
                status: AgentTaskStatus.running,
                extra: <String, Object?>{'assigned_worker_id': 'worker-3'},
              ),
            ],
          ),
        );

        final saved = await controller.saveScaleSettings(
          'agent-1',
          const AgentScaleSettings(maxWorkers: 2),
          auditToolName: 'AgentClusterShrinkTest',
        );

        expect(saved, isTrue);
        final agent = controller.agentById('agent-1')!;
        final workerIds = agent.workers.map((worker) => worker.id).toList();
        final auditMetadata = agent.auditEvents.first.metadata;
        expect(agent.scaleSettings.maxWorkers, 3);
        expect(
          workerIds,
          containsAll(<String>['worker-1', 'worker-2', 'worker-3']),
        );
        expect(workerIds, isNot(contains('worker-4')));
        expect(
          agent.tasks.every(
            (task) => workerIds.contains(task.extra['assigned_worker_id']),
          ),
          isTrue,
        );
        expect(auditMetadata['requested_max_workers'], 2);
        expect(auditMetadata['protected_active_workers'], 3);
      },
    );
  });
}

AgentProfile _runningAgent({
  AgentScaleSettings scaleSettings = const AgentScaleSettings(),
  List<AgentWorker> workers = const <AgentWorker>[
    AgentWorker(id: 'worker-1', name: 'Worker 1'),
  ],
  List<AgentApprovalRequest> approvals = const <AgentApprovalRequest>[],
  List<AgentTask> tasks = const <AgentTask>[],
}) {
  return AgentProfile(
    id: 'agent-1',
    name: 'Ops Agent',
    enabled: true,
    lifecycleState: AgentLifecycleState.running,
    scaleSettings: scaleSettings,
    workers: workers,
    approvals: approvals,
    tasks: tasks,
  );
}
