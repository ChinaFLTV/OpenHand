import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/features/agents/data/agents_store.dart';
import 'package:openhand/features/agents/index.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';
import 'package:openhand/features/crons/index.dart';
import 'package:openhand/features/hooks/index.dart';
import 'package:openhand/features/knowledge_base/index.dart';
import 'package:openhand/features/mcp/index.dart';
import 'package:openhand/features/memory/index.dart';
import 'package:openhand/features/skills/index.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentsView empty board', () {
    late AgentsController controller;

    setUp(() async {
      controller = _testAgentsController();
      await controller.refresh();
    });

    tearDown(() async {
      controller.dispose();
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

    testWidgets('shows a snackbar when runtime blocks starting an agent', (
      tester,
    ) async {
      final dependencies = _AgentEditorDependencies.empty();
      addTearDown(dependencies.dispose);
      controller.dispose();
      controller = _testAgentsController(const <AgentProfile>[
        AgentProfile(id: 'agent-1', name: 'Ops Agent'),
      ]);
      controller.setRuntimeAvailabilityProvider(
        () => const AgentRuntimeAvailability(
          isLoading: false,
          isInstalled: true,
          isEnabled: false,
          pluginName: 'Hermes Agent',
        ),
      );
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('启动智能体'));
      await tester.pump();

      expect(find.text('Ops Agent'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
      expect(find.textContaining('请先启用 Hermes Agent 插件'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(controller.agentById('agent-1')!.enabled, isFalse);
    });

    testWidgets('saves structured routing and metadata fields', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
      await tester.enterText(
        find.widgetWithText(TextField, '路由名称'),
        'ops-triage',
      );
      await tester.enterText(find.widgetWithText(TextField, '优先级'), '80');

      DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      ).animateTo(4, duration: Duration.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('添加字段'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '键'), 'quota');
      await tester.enterText(find.widgetWithText(TextField, '值'), '42');
      final saveButton = find.ancestor(
        of: find.text('保存'),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(controller.agents, hasLength(1));
      final agent = controller.agents.single;
      final route = parseAgentRouteFrontMatter(agent.routeFrontMatter);
      expect(route['route'], 'ops-triage');
      expect(route['priority'], 80);
      expect(agent.metadata['quota'], 42);
    });

    testWidgets('preserves builtin selections across tool groups', (
      tester,
    ) async {
      final dependencies = _AgentEditorDependencies.empty(
        builtinToolConfigs: const <AiBuiltinToolConfig>[
          AiBuiltinToolConfig(kind: AiBuiltinToolKind.bash),
          AiBuiltinToolConfig(kind: AiBuiltinToolKind.agentTaskPublish),
        ],
      );
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
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '名称 *'),
        'Ops Agent',
      );
      await tester.pump();
      DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      ).animateTo(1, duration: Duration.zero);
      await tester.pumpAndSettle();

      final bashChip = find.widgetWithText(FilterChip, 'bash');
      final publishChip = find.widgetWithText(FilterChip, 'agentTaskPublish');
      await tester.ensureVisible(bashChip);
      await tester.tap(bashChip);
      await tester.pump();
      await tester.ensureVisible(publishChip);
      await tester.tap(publishChip);
      await tester.pump();

      expect(tester.widget<FilterChip>(bashChip).selected, isTrue);
      expect(tester.widget<FilterChip>(publishChip).selected, isTrue);
    });

    testWidgets('edits cluster worker tags with structured chips', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dependencies = _AgentEditorDependencies.empty();
      addTearDown(dependencies.dispose);
      controller.dispose();
      controller = _testAgentsController(const <AgentProfile>[
        AgentProfile(
          id: 'agent-1',
          name: 'Ops Agent',
          enabled: true,
          lifecycleState: AgentLifecycleState.running,
          scaleSettings: AgentScaleSettings(
            maxWorkers: 2,
            schedulerPolicy: 'round_robin',
            tags: <String>['ops'],
          ),
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('集群'));
      await tester.pumpAndSettle();

      expect(find.text('轮询分配'), findsOneWidget);
      expect(find.textContaining('有限重试'), findsOneWidget);

      await tester.tap(find.text('调整集群'));
      await tester.pumpAndSettle();
      expect(find.text('ops'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'urgent');
      await tester.tap(find.byTooltip('添加'));
      await tester.pump();
      expect(find.text('urgent'), findsOneWidget);

      final saveButton = find.ancestor(
        of: find.text('保存').last,
        matching: find.byType(FilledButton),
      );
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(controller.agentById('agent-1')!.scaleSettings.tags, <String>[
        'ops',
        'urgent',
      ]);
    });

    testWidgets('opens a complete task detail dialog from task desk', (
      tester,
    ) async {
      final dependencies = _AgentEditorDependencies.empty();
      addTearDown(dependencies.dispose);
      controller.dispose();
      controller = _testAgentsController(<AgentProfile>[
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
      ]);
      controller.setRuntimeAvailabilityProvider(
        () => const AgentRuntimeAvailability(
          isLoading: false,
          isInstalled: true,
          isEnabled: true,
          pluginName: 'Hermes Agent',
        ),
      );
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('任务台').first);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
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

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}

AgentsController _testAgentsController([
  List<AgentProfile> agents = const <AgentProfile>[],
]) {
  final controller = AgentsController.uninitialized(
    store: _MemoryAgentsStore(agents),
  );
  controller.setRuntimeAvailabilityProvider(
    () => const AgentRuntimeAvailability(
      isLoading: false,
      isInstalled: false,
      isEnabled: false,
      pluginName: 'Hermes Agent',
    ),
  );
  return controller;
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

  factory _AgentEditorDependencies.empty({
    List<AiBuiltinToolConfig> builtinToolConfigs =
        const <AiBuiltinToolConfig>[],
  }) {
    return _AgentEditorDependencies(
      settings: _FakeSettingsController(builtinToolConfigs: builtinToolConfigs),
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
  _FakeSettingsController({
    this.builtinToolConfigs = const <AiBuiltinToolConfig>[],
  });

  @override
  final List<AiBuiltinToolConfig> builtinToolConfigs;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #listItemAnimationSettings &&
        invocation.isGetter) {
      return OpenHandMotionDefaults.listItem;
    }
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

class _MemoryAgentsStore extends AgentsStore {
  _MemoryAgentsStore([List<AgentProfile> agents = const <AgentProfile>[]])
    : _agents = List<AgentProfile>.from(agents),
      super(filePath: 'memory://agents-view-test');

  List<AgentProfile> _agents;

  @override
  Future<List<AgentProfile>> load() async {
    return List<AgentProfile>.from(_agents);
  }

  @override
  Future<void> save(List<AgentProfile> agents) async {
    _agents = List<AgentProfile>.from(agents);
  }
}
