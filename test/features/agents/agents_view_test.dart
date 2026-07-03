import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/features/agents/data/agents_store.dart';
import 'package:openhand/features/agents/index.dart';
import 'package:openhand/features/crons/index.dart';
import 'package:openhand/features/hooks/index.dart';
import 'package:openhand/features/knowledge_base/index.dart';
import 'package:openhand/features/mcp/index.dart';
import 'package:openhand/features/memory/index.dart';
import 'package:openhand/features/skills/index.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    testWidgets('keeps the editor open when metadata JSON is invalid', (
      tester,
    ) async {
      final dependencies = _AgentEditorDependencies.empty();
      addTearDown(dependencies.dispose);
      controller.setRuntimeAvailabilityProvider(
        () => const AgentRuntimeAvailability(
          isLoading: false,
          isInstalled: true,
          isEnabled: true,
          pluginName: 'Hermes Agent',
        ),
      );

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.text('创建智能体'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(
        find.widgetWithText(TextField, '名称 *'),
        'Ops Agent',
      );
      DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      ).animateTo(4, duration: Duration.zero);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '元数据 JSON'),
        '{bad json',
      );
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.textContaining('元数据 JSON 必须是有效对象'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.widgetWithText(TextField, '元数据 JSON'), findsOneWidget);
      expect(controller.agents, isEmpty);
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

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pump(const Duration(milliseconds: 300));
      navigator.pop();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}

class _AgentsViewHarness extends StatelessWidget {
  const _AgentsViewHarness({required this.controller, this.dependencies});

  final AgentsController controller;
  final _AgentEditorDependencies? dependencies;

  @override
  Widget build(BuildContext context) {
    final editorDependencies = dependencies;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AgentsController>.value(value: controller),
        if (editorDependencies != null) ...[
          ChangeNotifierProvider<SettingsController>.value(
            value: editorDependencies.settings,
          ),
          ChangeNotifierProvider<SkillsController>.value(
            value: editorDependencies.skills,
          ),
          ChangeNotifierProvider<KnowledgeBaseController>.value(
            value: editorDependencies.knowledgeBase,
          ),
          ChangeNotifierProvider<MemoryController>.value(
            value: editorDependencies.memory,
          ),
          ChangeNotifierProvider<McpController>.value(
            value: editorDependencies.mcp,
          ),
          ChangeNotifierProvider<CronsController>.value(
            value: editorDependencies.crons,
          ),
          ChangeNotifierProvider<HooksController>.value(
            value: editorDependencies.hooks,
          ),
        ],
      ],
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

class _AgentEditorDependencies {
  const _AgentEditorDependencies({
    required this.settings,
    required this.skills,
    required this.knowledgeBase,
    required this.memory,
    required this.mcp,
    required this.crons,
    required this.hooks,
  });

  factory _AgentEditorDependencies.empty() {
    return _AgentEditorDependencies(
      settings: _FakeSettingsController(),
      skills: _FakeSkillsController(),
      knowledgeBase: _FakeKnowledgeBaseController(),
      memory: _FakeMemoryController(),
      mcp: _FakeMcpController(),
      crons: _FakeCronsController(),
      hooks: _FakeHooksController(),
    );
  }

  final SettingsController settings;
  final SkillsController skills;
  final KnowledgeBaseController knowledgeBase;
  final MemoryController memory;
  final McpController mcp;
  final CronsController crons;
  final HooksController hooks;

  void dispose() {
    settings.dispose();
    skills.dispose();
    knowledgeBase.dispose();
    memory.dispose();
    mcp.dispose();
    crons.dispose();
    hooks.dispose();
  }
}

class _FakeSettingsController extends ChangeNotifier
    implements SettingsController {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return const <Never>[];
    return super.noSuchMethod(invocation);
  }
}

class _FakeSkillsController extends ChangeNotifier implements SkillsController {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #skills && invocation.isGetter) {
      return const <Never>[];
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeKnowledgeBaseController extends ChangeNotifier
    implements KnowledgeBaseController {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #sources && invocation.isGetter) {
      return const <Never>[];
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeMemoryController extends ChangeNotifier implements MemoryController {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #entries && invocation.isGetter) {
      return const <Never>[];
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeMcpController extends ChangeNotifier implements McpController {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #servers && invocation.isGetter) {
      return const <Never>[];
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeCronsController extends ChangeNotifier implements CronsController {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #entries && invocation.isGetter) {
      return const <Never>[];
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeHooksController extends ChangeNotifier implements HooksController {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #entries && invocation.isGetter) {
      return const <Never>[];
    }
    return super.noSuchMethod(invocation);
  }
}
