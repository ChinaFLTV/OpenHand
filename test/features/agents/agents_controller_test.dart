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

    test('normalizes negative manual metrics and audit counters', () async {
      final controller = await _createTempController();

      expect(
        await controller.saveAgent(
          const AgentProfile(id: 'agent-negative', name: 'Negative Agent'),
        ),
        isTrue,
      );
      expect(
        await controller.saveResourceUsage(
          'agent-negative',
          const AgentResourceUsage(
            cpuPercent: -0.5,
            memoryBytes: -1,
            diskBytes: -2,
            persistedBytes: -3,
            tokenBudget: -4,
            tokenUsed: -5,
            openHandles: -6,
            extra: <String, Object?>{
              'public_note': 'kept',
              _resourceTelemetryExtraKey: <String, Object?>{'leak': true},
            },
          ),
        ),
        isTrue,
      );

      final usage = controller.agents.single.resourceUsage;
      expect(usage.cpuPercent, 0);
      expect(usage.memoryBytes, 0);
      expect(usage.diskBytes, 0);
      expect(usage.tokenBudget, 0);
      expect(usage.tokenUsed, 0);
      expect(usage.openHandles, 0);
      expect(usage.extra['public_note'], 'kept');
      final telemetry =
          usage.extra[_resourceTelemetryExtraKey] as Map<String, Object?>;
      expect(telemetry.containsKey('leak'), isFalse);

      final audit = await controller.recordAuditEvent(
        'agent-negative',
        kind: '',
        summary: 'Recorded',
        tokenUsage: -9,
        requestCount: -2,
      );

      expect(audit, isNotNull);
      expect(audit!.kind, 'audit');
      expect(audit.tokenUsage, 0);
      expect(audit.requestCount, 0);
    });
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
