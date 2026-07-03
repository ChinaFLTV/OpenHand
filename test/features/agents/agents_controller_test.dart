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
  });
}

AgentProfile _runningAgent({
  AgentScaleSettings scaleSettings = const AgentScaleSettings(),
  List<AgentWorker> workers = const <AgentWorker>[
    AgentWorker(id: 'worker-1', name: 'Worker 1'),
  ],
  List<AgentApprovalRequest> approvals = const <AgentApprovalRequest>[],
}) {
  return AgentProfile(
    id: 'agent-1',
    name: 'Ops Agent',
    enabled: true,
    lifecycleState: AgentLifecycleState.running,
    scaleSettings: scaleSettings,
    workers: workers,
    approvals: approvals,
  );
}
