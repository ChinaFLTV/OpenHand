import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/data/agents_store.dart';
import 'package:openhand/features/agents/index.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  group('AgentsView empty board', () {
    late Directory tempDir;
    late AgentsController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'openhand_agents_view_test_',
      );
      controller = AgentsController.uninitialized(
        store: AgentsStore(filePath: p.join(tempDir.path, 'agents.json')),
      );
      controller.setRuntimeAvailabilityProvider(
        () => const AgentRuntimeAvailability(
          isLoading: false,
          isInstalled: false,
          isEnabled: false,
          pluginName: 'Hermes Agent',
        ),
      );
      await controller.refresh();
    });

    tearDown(() async {
      controller.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('shows only the centered empty card', (tester) async {
      await tester.pumpWidget(_AgentsViewHarness(controller: controller));

      expect(find.text('还没有智能体'), findsOneWidget);
      expect(find.text('Hermes Agent 工作台'), findsNothing);
      expect(find.textContaining('Hermes Agent 未就绪'), findsNothing);

      final emptyCardFinder = find.ancestor(
        of: find.text('还没有智能体'),
        matching: find.byType(Card),
      );
      expect(emptyCardFinder, findsOneWidget);

      final cardCenter = tester.getCenter(emptyCardFinder);
      final bodyCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('agents-empty')),
      );
      expect((cardCenter.dx - bodyCenter.dx).abs(), lessThan(1));
      expect((cardCenter.dy - bodyCenter.dy).abs(), lessThan(1));
    });

    testWidgets('shows a snackbar when runtime blocks creation', (
      tester,
    ) async {
      await tester.pumpWidget(_AgentsViewHarness(controller: controller));

      await tester.tap(find.text('创建智能体'));
      await tester.pump();

      expect(find.textContaining('Hermes Agent 未就绪'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('opens a complete task detail dialog from task desk', (
      tester,
    ) async {
      controller.setRuntimeAvailabilityProvider(
        () => const AgentRuntimeAvailability(
          isLoading: false,
          isInstalled: true,
          isEnabled: true,
          pluginName: 'Hermes Agent',
        ),
      );
      await controller.saveAgent(
        AgentProfile(
          id: 'agent-1',
          name: 'Ops Agent',
          enabled: true,
          lifecycleState: AgentLifecycleState.running,
          tasks: <AgentTask>[
            AgentTask(
              id: 'task-1',
              title: 'Quarterly report',
              description: 'Prepare the quarterly review.',
              content: 'Use invoices, tickets, and KPI evidence.',
              result: 'Draft report is ready.',
              note: 'Needs mentor review.',
              progress: 0.8,
              status: AgentTaskStatus.running,
              createdAt: DateTime.utc(2026, 7, 4, 1, 2),
              updatedAt: DateTime.utc(2026, 7, 4, 3, 4),
              extra: const <String, Object?>{
                'assigned_worker_id': 'worker-1',
                'assigned_worker_name': 'Worker 1',
                'agent_system_prompt': 'secret prompt body',
              },
            ),
          ],
          workers: const <AgentWorker>[
            AgentWorker(
              id: 'worker-1',
              name: 'Worker 1',
              status: AgentWorkerStatus.busy,
              currentTaskId: 'task-1',
            ),
          ],
        ),
      );

      await tester.pumpWidget(_AgentsViewHarness(controller: controller));
      await tester.tap(find.byTooltip('更多').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('任务台'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Quarterly report').first);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('任务详情'), findsOneWidget);
      expect(find.text('task-1'), findsOneWidget);
      expect(find.text('Prepare the quarterly review.'), findsOneWidget);
      expect(
        find.text('Use invoices, tickets, and KPI evidence.'),
        findsOneWidget,
      );
      expect(find.text('Draft report is ready.'), findsOneWidget);
      expect(find.text('Needs mentor review.'), findsOneWidget);
      expect(find.textContaining('"omitted": true'), findsOneWidget);
      expect(find.textContaining('secret prompt body'), findsNothing);
    });
  });
}

class _AgentsViewHarness extends StatelessWidget {
  const _AgentsViewHarness({required this.controller});

  final AgentsController controller;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AgentsController>.value(
      value: controller,
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox.expand(
            child: Padding(padding: EdgeInsets.all(24), child: AgentsView()),
          ),
        ),
      ),
    );
  }
}
