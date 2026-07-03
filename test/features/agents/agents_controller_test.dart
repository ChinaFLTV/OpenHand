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
