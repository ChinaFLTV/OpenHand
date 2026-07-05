import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/agents_controller.dart';
import 'package:openhand/features/agents/data/agents_store.dart';
import 'package:openhand/features/agents/model/agent_models.dart';

const String _resourceTelemetryExtraKey = '_openhand_resource_telemetry';
const String _resourceTelemetryHistoryKey = 'history';

void main() {
  group('AgentsController resource usage', () {
    test('derives bounded queue pressure from active tasks', () async {
      final controller = await _createTempController();

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

    test(
      'trims telemetry history without duplicating recent samples',
      () async {
        final controller = await _createTempController();
        final futureSampledAt = DateTime.now().toUtc().add(
          const Duration(seconds: 10),
        );
        final history = List<Map<String, Object?>>.generate(40, (index) {
          return <String, Object?>{
            'sampled_at': futureSampledAt
                .add(Duration(milliseconds: index))
                .toIso8601String(),
            'token_used': index,
          };
        });

        final saved = await controller.saveAgent(
          AgentProfile(
            id: 'agent-telemetry',
            name: 'Telemetry Agent',
            resourceUsage: AgentResourceUsage(
              extra: <String, Object?>{
                _resourceTelemetryExtraKey: <String, Object?>{
                  _resourceTelemetryHistoryKey: history,
                },
              },
            ),
          ),
        );

        expect(saved, isTrue);
        final telemetry =
            controller
                    .agents
                    .single
                    .resourceUsage
                    .extra[_resourceTelemetryExtraKey]
                as Map<String, Object?>;
        final trimmedHistory =
            telemetry[_resourceTelemetryHistoryKey] as List<Object?>;
        expect(trimmedHistory, hasLength(36));
        expect(trimmedHistory.first, containsPair('token_used', 4));
        expect(trimmedHistory.last, containsPair('token_used', 39));
      },
    );
  });
}

Future<AgentsController> _createTempController() async {
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
  return controller;
}
