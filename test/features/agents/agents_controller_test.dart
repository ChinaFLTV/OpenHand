import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/agents_controller.dart';
import 'package:openhand/features/agents/data/agents_store.dart';
import 'package:openhand/features/agents/model/agent_models.dart';

void main() {
  group('AgentsController resource usage', () {
    test('derives bounded queue pressure from active tasks', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_agents_controller_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final controller = AgentsController.uninitialized(
        store: AgentsStore(filePath: '${tempDir.path}/agents.json'),
      );
      addTearDown(controller.dispose);

      final saved = await controller.saveAgent(
        const AgentProfile(
          id: 'agent-1',
          name: 'Build Agent',
          scaleSettings: AgentScaleSettings(minWorkers: 0, maxWorkers: 4),
          tasks: <AgentTask>[
            AgentTask(
              id: 'task-1',
              title: 'One',
              status: AgentTaskStatus.running,
            ),
            AgentTask(
              id: 'task-2',
              title: 'Two',
              status: AgentTaskStatus.ready,
            ),
          ],
        ),
      );

      expect(saved, isTrue);
      expect(
        controller.agents.single.resourceUsage.cpuPercent,
        closeTo(0.175, 0.000001),
      );
    });
  });
}
