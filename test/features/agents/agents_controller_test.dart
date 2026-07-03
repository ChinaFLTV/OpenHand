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
  });
}

AgentProfile _runningAgent() {
  return const AgentProfile(
    id: 'agent-1',
    name: 'Ops Agent',
    enabled: true,
    lifecycleState: AgentLifecycleState.running,
    workers: <AgentWorker>[AgentWorker(id: 'worker-1', name: 'Worker 1')],
  );
}
