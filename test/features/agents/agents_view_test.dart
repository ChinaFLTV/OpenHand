import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/cron_config.dart';
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
import 'package:openhand/shared/ui/animated_appearance.dart';
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

    testWidgets('hides internal agent-tool empty binding from card summary', (
      tester,
    ) async {
      final dependencies = _AgentEditorDependencies.empty();
      addTearDown(dependencies.dispose);
      controller.dispose();
      controller = _testAgentsController(const <AgentProfile>[
        AgentProfile(
          id: 'agent-1',
          name: 'Ops Agent',
          builtinToolNames: <String>['bash', agentNoCoordinationToolsBinding],
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );

      expect(find.textContaining('工具 1'), findsOneWidget);
      expect(find.textContaining('工具 2'), findsNothing);
      expect(
        find.textContaining(agentNoCoordinationToolsBinding),
        findsNothing,
      );
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

    testWidgets('confirms full access execution mode before saving', (
      tester,
    ) async {
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
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '名称 *'),
        'Ops Agent',
      );

      DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      ).animateTo(2, duration: Duration.zero);
      await tester.pumpAndSettle();

      expect(find.text('审批策略'), findsOneWidget);
      expect(find.textContaining('特权能力'), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<AgentExecutionMode>>(
              find.byType(SegmentedButton<AgentExecutionMode>),
            )
            .selected,
        <AgentExecutionMode>{AgentExecutionMode.normal},
      );

      await tester.tap(find.text('完全访问模式'));
      await tester.pumpAndSettle();
      expect(find.text('启用完全访问模式？'), findsOneWidget);

      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<AgentExecutionMode>>(
              find.byType(SegmentedButton<AgentExecutionMode>),
            )
            .selected,
        <AgentExecutionMode>{AgentExecutionMode.normal},
      );

      await tester.tap(find.text('完全访问模式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('是，仍然继续'));
      await tester.pumpAndSettle();

      expect(find.textContaining('常规文件与命令操作可自动执行'), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<AgentExecutionMode>>(
              find.byType(SegmentedButton<AgentExecutionMode>),
            )
            .selected,
        <AgentExecutionMode>{AgentExecutionMode.fullAccess},
      );

      final saveButton = find.ancestor(
        of: find.text('保存').last,
        matching: find.byType(FilledButton),
      );
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(
        controller.agents.single.executionMode,
        AgentExecutionMode.fullAccess,
      );
    });

    testWidgets('rejects duplicate metadata keys before saving', (
      tester,
    ) async {
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

      DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      ).animateTo(4, duration: Duration.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('添加字段'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '值').first)
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.byTooltip('添加字段'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, '键').at(0),
        'quota',
      );
      await tester.enterText(find.widgetWithText(TextField, '值').at(0), '1');
      await tester.enterText(
        find.widgetWithText(TextField, '键').at(1),
        'QUOTA',
      );
      await tester.enterText(find.widgetWithText(TextField, '值').at(1), '2');

      final saveButton = find.ancestor(
        of: find.text('保存'),
        matching: find.byType(FilledButton),
      );
      await tester.tap(saveButton);
      await tester.pump();

      expect(find.textContaining('元数据字段重复：QUOTA'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(controller.agents, isEmpty);
      expect(find.text('创建智能体'), findsWidgets);
    });

    testWidgets('normalizes workspace scope paths when saving edits', (
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
          workspacePath: '/tmp/openhand/project',
          workspaceScopePaths: <String>[
            '/tmp/openhand/project',
            '/tmp/openhand/project/src',
            '/tmp/openhand/project/src',
            '  /tmp/openhand/project/docs  ',
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
      final editButton = find.byTooltip('编辑配置').last;
      await tester.ensureVisible(editButton);
      await tester.tap(editButton);
      await tester.pumpAndSettle();
      expect(find.text('编辑智能体'), findsOneWidget);

      final saveButton = find.ancestor(
        of: find.text('保存'),
        matching: find.byType(FilledButton),
      );
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      final agent = controller.agentById('agent-1')!;
      expect(agent.workspaceScopePaths, <String>[
        '/tmp/openhand/project/src',
        '/tmp/openhand/project/docs',
      ]);
      expect(
        agent.workspaceScope,
        '/tmp/openhand/project/src\n/tmp/openhand/project/docs',
      );
    });

    testWidgets('shows null metadata values as empty editor fields', (
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
          metadata: <String, Object?>{
            'nullable': null,
            'legacyNullable': 'null',
          },
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      final editButton = find.byTooltip('编辑配置').last;
      await tester.ensureVisible(editButton);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      ).animateTo(4, duration: Duration.zero);
      await tester.pumpAndSettle();

      expect(find.text('nullable'), findsOneWidget);
      expect(find.text('legacyNullable'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '值').first)
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '值').at(1))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('null'), findsNothing);
    });

    testWidgets('reorders workspace scope and governance chips in editor', (
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
          workspaceScopePaths: <String>[
            '/tmp/openhand/docs',
            '/tmp/openhand/src',
          ],
          cronIds: <String>['daily-report', 'weekly-report'],
          hookIds: <String>['pre-hook', 'post-hook'],
          taskLabels: <String>['slow', 'urgent'],
          scaleSettings: AgentScaleSettings(tags: <String>['ops', 'billing']),
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
      final editButton = find.byTooltip('编辑配置').last;
      await tester.ensureVisible(editButton);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      ).animateTo(2, duration: Duration.zero);
      await tester.pumpAndSettle();
      final srcScopeChip = find.byKey(
        const ValueKey<String>('agent-workspace-scope-body-/tmp/openhand/src'),
      );
      await tester.ensureVisible(srcScopeChip);
      await tester.pumpAndSettle();
      await tester.timedDrag(
        srcScopeChip,
        const Offset(-260, 0),
        const Duration(milliseconds: 450),
      );
      await tester.pumpAndSettle();

      DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      ).animateTo(3, duration: Duration.zero);
      await tester.pumpAndSettle();
      final weeklyCronChip = find.byKey(
        const ValueKey<String>('agent-cron-body-weekly-report'),
      );
      await tester.ensureVisible(weeklyCronChip);
      await tester.pumpAndSettle();
      await tester.timedDrag(
        weeklyCronChip,
        const Offset(-260, 0),
        const Duration(milliseconds: 450),
      );
      await tester.pumpAndSettle();
      final postHookChip = find.byKey(
        const ValueKey<String>('agent-hook-body-post-hook'),
      );
      await tester.ensureVisible(postHookChip);
      await tester.pumpAndSettle();
      await tester.timedDrag(
        postHookChip,
        const Offset(-260, 0),
        const Duration(milliseconds: 450),
      );
      await tester.pumpAndSettle();
      final billingTagChip = find.byKey(
        const ValueKey<String>('agent-worker-tag-body-billing'),
      );
      await tester.ensureVisible(billingTagChip);
      await tester.pumpAndSettle();
      await tester.timedDrag(
        billingTagChip,
        const Offset(-220, 0),
        const Duration(milliseconds: 450),
      );
      await tester.pumpAndSettle();
      final urgentLabelChip = find.byKey(
        const ValueKey<String>('agent-task-label-body-urgent'),
      );
      await tester.ensureVisible(urgentLabelChip);
      await tester.pumpAndSettle();
      await tester.timedDrag(
        urgentLabelChip,
        const Offset(-220, 0),
        const Duration(milliseconds: 450),
      );
      await tester.pumpAndSettle();

      final saveButton = find.ancestor(
        of: find.text('保存'),
        matching: find.byType(FilledButton),
      );
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      final agent = controller.agentById('agent-1')!;
      expect(agent.workspaceScopePaths, <String>[
        '/tmp/openhand/src',
        '/tmp/openhand/docs',
      ]);
      expect(agent.cronIds, <String>['weekly-report', 'daily-report']);
      expect(agent.hookIds, <String>['post-hook', 'pre-hook']);
      expect(agent.scaleSettings.tags, <String>['billing', 'ops']);
      expect(agent.taskLabels, <String>['urgent', 'slow']);
    });

    testWidgets('agent editor chip motion respects disabled animations', (
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
          workspaceScopePaths: <String>['/tmp/openhand/src'],
          taskLabels: <String>['urgent'],
          scaleSettings: AgentScaleSettings(tags: <String>['ops']),
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(
          controller: controller,
          dependencies: dependencies,
          disableAnimations: true,
        ),
      );
      final editButton = find.byTooltip('编辑配置').last;
      await tester.ensureVisible(editButton);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      ).animateTo(2, duration: Duration.zero);
      await tester.pumpAndSettle();

      final chipStripAnimatedSizes = tester
          .widgetList<AnimatedSize>(
            find.byKey(const ValueKey<String>('agent-chip-strip-list')),
          )
          .toList(growable: false);

      expect(chipStripAnimatedSizes, isNotEmpty);
      expect(
        chipStripAnimatedSizes.every(
          (widget) => widget.duration == Duration.zero,
        ),
        isTrue,
      );
    });

    testWidgets('preserves builtin selections across tool groups', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dependencies = _AgentEditorDependencies.empty(
        builtinToolConfigs: const <AiBuiltinToolConfig>[
          AiBuiltinToolConfig(kind: AiBuiltinToolKind.bash),
          AiBuiltinToolConfig(kind: AiBuiltinToolKind.agentList),
          AiBuiltinToolConfig(kind: AiBuiltinToolKind.agentTaskPublish),
          AiBuiltinToolConfig(kind: AiBuiltinToolKind.agentApprovalRequest),
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
      final publishChip = find.widgetWithText(FilterChip, '任务发布');
      expect(find.text('发现路由'), findsOneWidget);
      expect(find.text('任务生命周期'), findsOneWidget);
      expect(find.text('治理审计'), findsOneWidget);
      expect(find.text('agentTaskPublish'), findsNothing);
      expect(find.text('启用 1/1 · 变更 0'), findsOneWidget);
      expect(find.text('启用 1/1 · 变更 1'), findsAtLeastNWidgets(2));
      expect(find.textContaining('变更 1'), findsAtLeastNWidgets(1));
      await tester.ensureVisible(bashChip);
      await tester.tap(bashChip);
      await tester.pumpAndSettle();
      final listChip = find.widgetWithText(FilterChip, '智能体列表');
      final approvalChip = find.widgetWithText(FilterChip, '审批请求');
      await tester.ensureVisible(listChip);
      await tester.tap(listChip);
      await tester.pump();
      await tester.ensureVisible(publishChip);
      await tester.tap(publishChip);
      await tester.pump();
      await tester.ensureVisible(approvalChip);
      await tester.tap(approvalChip);
      await tester.pumpAndSettle();

      expect(tester.widget<FilterChip>(bashChip).selected, isTrue);
      expect(tester.widget<FilterChip>(listChip).selected, isFalse);
      expect(tester.widget<FilterChip>(publishChip).selected, isFalse);
      expect(tester.widget<FilterChip>(approvalChip).selected, isFalse);

      final saveButton = find.ancestor(
        of: find.text('保存'),
        matching: find.byType(FilledButton),
      );
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      final agent = controller.agents.single;
      expect(agent.builtinToolNames, contains('bash'));
      expect(agent.builtinToolNames, contains(agentNoCoordinationToolsBinding));
      expect(agent.builtinToolNames, isNot(contains('agentTaskPublish')));
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
      expect(find.text('ops'), findsAtLeastNWidgets(1));
      await tester.enterText(find.byType(TextField).last, 'urgent');
      final addButton = find.byKey(
        const ValueKey<String>('agent-cluster-tag-add'),
      );
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      expect(find.text('urgent'), findsOneWidget);
      expect(find.byType(AnimatedRemovableChip), findsAtLeastNWidgets(2));
      final urgentChip = find.byKey(
        const ValueKey<String>('cluster-tag-drag-urgent'),
      );
      await tester.ensureVisible(urgentChip);
      await tester.pumpAndSettle();
      await tester.timedDrag(
        urgentChip,
        const Offset(-260, 0),
        const Duration(milliseconds: 450),
      );
      await tester.pumpAndSettle();

      final saveButton = find.ancestor(
        of: find.text('保存').last,
        matching: find.byType(FilledButton),
      );
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(controller.agentById('agent-1')!.scaleSettings.tags, <String>[
        'urgent',
        'ops',
      ]);
    });

    testWidgets('renders worker execution details in cluster dialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dependencies = _AgentEditorDependencies.empty();
      addTearDown(dependencies.dispose);
      controller.dispose();
      controller = _testAgentsController(<AgentProfile>[
        AgentProfile(
          id: 'agent-1',
          name: 'Ops Agent',
          enabled: true,
          lifecycleState: AgentLifecycleState.running,
          scaleSettings: const AgentScaleSettings(maxWorkers: 3),
          workers: <AgentWorker>[
            AgentWorker(
              id: 'worker-1',
              name: 'Worker 1',
              status: AgentWorkerStatus.busy,
              currentTaskId: 'task-1',
              busyScore: 0.7,
              executedTaskCount: 4,
              priority: 8,
              labels: const <String>['ops', 'billing'],
              updatedAt: DateTime.utc(2026, 7, 4, 8, 30),
              extra: const <String, Object?>{
                'last_assigned_task_id': 'task-1',
                'last_finished_task_id': 'task-2',
                'last_finished_status': 'completed',
              },
            ),
          ],
          tasks: const <AgentTask>[
            AgentTask(
              id: 'task-1',
              title: 'Collect cloud billing evidence',
              status: AgentTaskStatus.running,
              progress: 0.45,
            ),
            AgentTask(
              id: 'task-2',
              title: 'Publish weekly report',
              status: AgentTaskStatus.completed,
              progress: 1,
            ),
          ],
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('集群'));
      await tester.pumpAndSettle();

      expect(find.text('Worker 1'), findsOneWidget);
      expect(
        find.textContaining('当前任务 Collect cloud billing evidence'),
        findsOneWidget,
      );
      expect(find.text('当前任务进度 45%'), findsOneWidget);
      expect(find.text('标签: ops, billing'), findsOneWidget);
      expect(find.text('上次分配: Collect cloud billing evidence'), findsOneWidget);
      expect(find.text('上次完成: Publish weekly report'), findsOneWidget);
      expect(find.text('完成状态: completed'), findsOneWidget);
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
                'priority': 'high',
                'retryable': true,
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

      expect(find.text('任务台 · Ops Agent'), findsOneWidget);
      expect(find.text('任务'), findsOneWidget);
      expect(find.text('进行中'), findsAtLeastNWidgets(1));
      expect(find.text('平均进度'), findsOneWidget);
      expect(find.text('80%'), findsAtLeastNWidgets(1));
      expect(find.text('下一步: 轮询进度'), findsOneWidget);
      expect(find.text('轮询: AgentTaskProgress · 1500ms'), findsOneWidget);
      expect(find.text('结果: Draft report is ready.'), findsOneWidget);
      expect(find.text('备注: Needs mentor review.'), findsOneWidget);
      expect(find.text('assigned_worker_id: worker-1'), findsOneWidget);
      expect(find.text('priority: high'), findsOneWidget);
      expect(find.text('retryable: true'), findsOneWidget);
      expect(find.textContaining('secret prompt body'), findsNothing);

      await tester.tap(find.text('Quarterly report').first);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('任务详情'), findsOneWidget);
      expect(find.text('task-1'), findsOneWidget);
      expect(find.text('交接状态'), findsOneWidget);
      expect(find.text('结果未就绪，建议定时轮询'), findsOneWidget);
      expect(find.text('AgentTaskProgress · 1500ms'), findsOneWidget);
      expect(
        find.text('Prepare the quarterly review.'),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.text('Use invoices, tickets, and KPI evidence.'),
        findsOneWidget,
      );
      expect(find.text('Draft report is ready.'), findsAtLeastNWidgets(1));
      expect(find.text('Needs mentor review.'), findsAtLeastNWidgets(1));
      expect(find.textContaining('"omitted": true'), findsOneWidget);
      expect(find.textContaining('secret prompt body'), findsNothing);

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('terminates a task from task desk with terminal metadata', (
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
          tasks: <AgentTask>[
            AgentTask(
              id: 'task-1',
              title: 'Stop stale task',
              status: AgentTaskStatus.running,
              progress: 0.35,
              extra: <String, Object?>{
                'assigned_worker_id': 'worker-1',
                'assigned_worker_name': 'Worker 1',
              },
            ),
          ],
          workers: <AgentWorker>[
            AgentWorker(
              id: 'worker-1',
              name: 'Worker 1',
              status: AgentWorkerStatus.busy,
              currentTaskId: 'task-1',
            ),
          ],
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('任务台').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('终止任务'));
      await tester.pumpAndSettle();
      expect(find.text('终止任务'), findsOneWidget);

      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      final agent = controller.agentById('agent-1')!;
      expect(agent.tasks.single.status, AgentTaskStatus.failed);
      expect(agent.tasks.single.extra['tool_action'], 'task_terminated');
      expect(agent.workers.single.status, AgentWorkerStatus.idle);
      expect(agent.activities.first.kind, 'task_terminated');
      expect(agent.auditEvents.first.kind, 'task_terminated');
      expect(find.text('下一步: 已终止'), findsOneWidget);
    });

    testWidgets('shows completed tasks without result as missing result', (
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
          tasks: <AgentTask>[
            AgentTask(
              id: 'task-1',
              title: 'Completed without handoff',
              status: AgentTaskStatus.completed,
              progress: 1,
            ),
          ],
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('任务台').first);
      await tester.pumpAndSettle();

      expect(find.text('下一步: 结果缺失'), findsOneWidget);
      expect(find.text('补充结果'), findsNothing);

      await tester.tap(find.text('Completed without handoff').first);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('已完成但缺少结果'), findsOneWidget);
      expect(find.text('AgentTaskTrack'), findsOneWidget);
      expect(find.text('AgentTaskResult'), findsNothing);
    });

    testWidgets('renders activities as a typed message stream', (tester) async {
      final dependencies = _AgentEditorDependencies.empty();
      addTearDown(dependencies.dispose);
      controller.dispose();
      controller = _testAgentsController(<AgentProfile>[
        AgentProfile(
          id: 'agent-1',
          name: 'Ops Agent',
          enabled: true,
          lifecycleState: AgentLifecycleState.running,
          activities: <AgentActivityEvent>[
            AgentActivityEvent(
              id: 'activity-1',
              kind: 'thought',
              title: '分析任务边界',
              messageType: AgentActivityMessageType.thought,
              content: '先检查日报所需的数据源和审批边界。',
              createdAt: DateTime.utc(2026, 7, 4, 1, 2),
              metadata: <String, Object?>{
                'task_id': 'task-1',
                'worker_id': 'worker-1',
              },
            ),
            const AgentActivityEvent(
              id: 'activity-2',
              kind: 'tool_call',
              title: '调用 SkillRunner',
              messageType: AgentActivityMessageType.toolCall,
              content: '读取账单采集技能。',
              metadata: <String, Object?>{
                'tool_name': 'SkillRunner',
                'skill_name': 'billing-report',
              },
            ),
          ],
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('历史活动').first);
      await tester.pumpAndSettle();

      expect(find.text('历史活动 · Ops Agent'), findsOneWidget);
      expect(find.text('思考'), findsOneWidget);
      expect(find.text('工具'), findsOneWidget);
      expect(find.text('分析任务边界'), findsOneWidget);
      expect(find.text('先检查日报所需的数据源和审批边界。'), findsOneWidget);
      expect(find.text('调用 SkillRunner'), findsOneWidget);
      expect(find.text('task_id: task-1'), findsOneWidget);
      expect(find.text('worker_id: worker-1'), findsOneWidget);
      expect(find.text('tool_name: SkillRunner'), findsOneWidget);
      expect(find.text('skill_name: billing-report'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('renders capability logs as structured audit records', (
      tester,
    ) async {
      final dependencies = _AgentEditorDependencies.empty();
      addTearDown(dependencies.dispose);
      controller.dispose();
      controller = _testAgentsController(const <AgentProfile>[
        AgentProfile(
          id: 'agent-1',
          name: 'Ops Agent',
          enabled: true,
          lifecycleState: AgentLifecycleState.running,
          auditEvents: <AgentAuditEvent>[
            AgentAuditEvent(
              id: 'audit-1',
              kind: 'skill_call',
              summary: 'skill_call: collect billing evidence',
              toolName: 'SkillRunner',
              requestCount: 2,
              tokenUsage: 100,
              metadata: <String, Object?>{
                'task_id': 'task-1',
                'worker_id': 'worker-1',
                'skill_name': 'billing-report',
              },
            ),
            AgentAuditEvent(
              id: 'audit-2',
              kind: 'mcp_call',
              summary: 'mcp_call: query tickets',
              toolName: 'TicketMcp',
              requestCount: 1,
              metadata: <String, Object?>{'mcp_server': 'ticketing'},
            ),
            AgentAuditEvent(
              id: 'audit-3',
              kind: 'memory_write',
              summary: 'memory_write: store report preference',
              toolName: 'Memory',
              metadata: <String, Object?>{'memory_id': 'memory-1'},
            ),
          ],
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('日志').first);
      await tester.pumpAndSettle();

      expect(find.text('能力调用日志 · Ops Agent'), findsOneWidget);
      expect(find.text('事件'), findsOneWidget);
      expect(find.text('请求量'), findsOneWidget);
      expect(find.text('Skill'), findsOneWidget);
      expect(find.text('MCP'), findsOneWidget);
      expect(find.text('记忆'), findsOneWidget);
      expect(find.text('SkillRunner'), findsOneWidget);
      expect(find.text('TicketMcp'), findsOneWidget);
      expect(find.text('Memory'), findsOneWidget);
      expect(find.text('2 请求'), findsOneWidget);
      expect(find.text('100 Token'), findsOneWidget);
      expect(find.text('task_id: task-1'), findsOneWidget);
      expect(find.text('worker_id: worker-1'), findsOneWidget);
      expect(find.text('skill_name: billing-report'), findsOneWidget);
      expect(find.text('mcp_server: ticketing'), findsOneWidget);
      expect(find.text('memory_id: memory-1'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('renders approval requests as governance cards', (
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
          approvals: <AgentApprovalRequest>[
            AgentApprovalRequest(
              id: 'approval-1',
              title: 'Allow workspace write',
              reason: 'Needs to update generated report files.',
              requestedAction: 'Write /tmp/openhand/report.md',
              extra: <String, Object?>{
                'risk_level': 'high',
                'permissions': <String>['filesystem', 'write'],
                'scope': '/tmp/openhand',
                'task_id': 'task-1',
              },
            ),
            AgentApprovalRequest(
              id: 'approval-2',
              title: 'Read knowledge base',
              requestedAction: 'Read kb://ops',
              status: AgentApprovalStatus.approved,
              extra: <String, Object?>{'risk_level': 'low'},
            ),
          ],
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('审批').first);
      await tester.pumpAndSettle();

      expect(find.text('审批 · Ops Agent'), findsOneWidget);
      expect(find.text('待审批'), findsAtLeastNWidgets(1));
      expect(find.text('已处理'), findsOneWidget);
      expect(find.text('高风险'), findsAtLeastNWidgets(1));
      expect(find.text('低风险'), findsOneWidget);
      expect(find.text('Allow workspace write'), findsOneWidget);
      expect(find.text('Write /tmp/openhand/report.md'), findsOneWidget);
      expect(
        find.text('Needs to update generated report files.'),
        findsOneWidget,
      );
      expect(find.text('permissions: filesystem, write'), findsOneWidget);
      expect(find.text('scope: /tmp/openhand'), findsOneWidget);
      expect(find.text('task_id: task-1'), findsOneWidget);

      await tester.tap(find.byTooltip('批准'));
      await tester.pumpAndSettle();

      final updated = controller
          .agentById('agent-1')!
          .approvals
          .firstWhere((item) => item.id == 'approval-1');
      expect(updated.status, AgentApprovalStatus.approved);

      await tester.tap(find.text('发起审批'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '名称'),
        'Write audit log',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '审批原因'),
        'Need to persist the audit evidence.',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '请求动作'),
        'Append audit.jsonl',
      );
      final addFieldButton = find.byTooltip('添加字段');
      await tester.ensureVisible(addFieldButton);
      await tester.pumpAndSettle();
      await tester.tap(addFieldButton);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '键').last,
        'risk_level',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '值').last,
        'medium',
      );
      await tester.ensureVisible(addFieldButton);
      await tester.tap(addFieldButton);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '键').last,
        'permissions',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '值').last,
        '["filesystem","write"]',
      );
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      final created = controller.agentById('agent-1')!.approvals.first;
      expect(created.title, 'Write audit log');
      expect(created.extra['risk_level'], 'medium');
      expect(created.extra['permissions'], <Object?>['filesystem', 'write']);

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('renders kpis as operational progress cards', (tester) async {
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
          kpis: <AgentKpiItem>[
            AgentKpiItem(
              id: 'kpi-1',
              name: 'Weekly report SLA',
              target: 'Publish every Friday before 18:00.',
              plan: 'Collect evidence, draft, review, then publish.',
              progress: 0.6,
              extra: <String, Object?>{
                'owner': 'Worker 1',
                'cadence': 'weekly',
                'task_id': 'task-1',
              },
            ),
            AgentKpiItem(
              id: 'kpi-2',
              name: 'Incident response',
              target: 'Close P1 triage within 15 minutes.',
              progress: 0.25,
              status: 'at_risk',
              extra: <String, Object?>{'deadline': '2026-07-05'},
            ),
          ],
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('KPI').first);
      await tester.pumpAndSettle();

      expect(find.text('KPI · Ops Agent'), findsOneWidget);
      expect(find.text('跟进中'), findsAtLeastNWidgets(1));
      expect(find.text('有风险'), findsAtLeastNWidgets(1));
      expect(find.text('平均进度'), findsOneWidget);
      expect(find.text('Weekly report SLA'), findsOneWidget);
      expect(find.text('Publish every Friday before 18:00.'), findsOneWidget);
      expect(
        find.text('Collect evidence, draft, review, then publish.'),
        findsOneWidget,
      );
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('owner: Worker 1'), findsOneWidget);
      expect(find.text('cadence: weekly'), findsOneWidget);
      expect(find.text('task_id: task-1'), findsOneWidget);
      expect(find.text('deadline: 2026-07-05'), findsOneWidget);
      expect(find.byTooltip('编辑 KPI'), findsAtLeastNWidgets(1));

      await tester.tap(find.byTooltip('编辑 KPI').first);
      await tester.pumpAndSettle();
      expect(find.text('KPI 元数据'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, '值').first,
        'Worker 2',
      );
      final addFieldButton = find.byTooltip('添加字段');
      await tester.ensureVisible(addFieldButton);
      await tester.pumpAndSettle();
      await tester.tap(addFieldButton);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '键').last,
        'deadline',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '值').last,
        '2026-07-11',
      );
      final saveButton = find.ancestor(
        of: find.text('保存').last,
        matching: find.byType(FilledButton),
      );
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      final updatedKpi = controller
          .agentById('agent-1')!
          .kpis
          .firstWhere((item) => item.id == 'kpi-1');
      expect(updatedKpi.extra['owner'], 'Worker 2');
      expect(updatedKpi.extra['deadline'], '2026-07-11');

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('renders resource usage as pressure cards', (tester) async {
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
          resourceUsage: AgentResourceUsage(
            cpuPercent: 0.7,
            memoryBytes: 1048576,
            diskBytes: 4096,
            persistedBytes: 3584,
            tokenBudget: 1000,
            tokenUsed: 900,
            openHandles: 12,
            extra: <String, Object?>{
              'workspace_path': '/tmp/openhand',
              'artifact_count': 5,
              'cache_bytes': 2048,
            },
          ),
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('资源管理').first);
      await tester.pumpAndSettle();

      expect(find.text('资源管理 · Ops Agent'), findsOneWidget);
      expect(find.text('资源压力'), findsOneWidget);
      expect(find.text('高压力'), findsAtLeastNWidgets(1));
      expect(find.text('预警'), findsAtLeastNWidgets(1));
      expect(find.text('70%'), findsAtLeastNWidgets(1));
      expect(find.text('900/1000'), findsOneWidget);
      expect(find.text('剩余 Token'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('900 / 1000'), findsOneWidget);
      expect(find.text('3.5 KB / 4 KB'), findsOneWidget);
      expect(find.text('剩余空间'), findsOneWidget);
      expect(find.text('512 B'), findsOneWidget);
      expect(find.text('1 MB'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('12 / 128'), findsOneWidget);
      expect(find.text('workspace_path: /tmp/openhand'), findsOneWidget);
      expect(find.text('artifact_count: 5'), findsOneWidget);
      expect(find.text('cache_bytes: 2048'), findsOneWidget);

      await tester.tap(find.text('校准资源'));
      await tester.pumpAndSettle();
      expect(find.text('资源元数据'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, '值').first,
        '/tmp/openhand-v2',
      );
      final addFieldButton = find.byTooltip('添加字段');
      await tester.ensureVisible(addFieldButton);
      await tester.pumpAndSettle();
      await tester.tap(addFieldButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '键').last, 'quota');
      await tester.enterText(find.widgetWithText(TextField, '值').last, 'soft');
      final saveButton = find.ancestor(
        of: find.text('保存').last,
        matching: find.byType(FilledButton),
      );
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      final updatedResource = controller.agentById('agent-1')!.resourceUsage;
      expect(updatedResource.extra['workspace_path'], '/tmp/openhand-v2');
      expect(updatedResource.extra['quota'], 'soft');

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('publishes a task with structured extra fields', (
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
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('任务台').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布任务').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '任务标题'),
        'Prepare weekly report',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '介绍'),
        'Collect weekly evidence.',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '输入任务标签后添加'),
        'ops',
      );
      final addLabelButton = find.byKey(
        const ValueKey<String>('agent-publish-task-label-add'),
      );
      await tester.ensureVisible(addLabelButton);
      await tester.pumpAndSettle();
      await tester.tap(addLabelButton);
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, '输入任务标签后添加'),
        'report',
      );
      await tester.ensureVisible(addLabelButton);
      await tester.pumpAndSettle();
      await tester.tap(addLabelButton);
      await tester.pump();
      final addFieldButton = find.byTooltip('添加字段').last;
      await tester.ensureVisible(addFieldButton);
      await tester.pumpAndSettle();
      await tester.tap(addFieldButton);
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '键'), 'retryable');
      await tester.enterText(find.widgetWithText(TextField, '值'), 'true');

      final publishButton = find.ancestor(
        of: find.text('发布').last,
        matching: find.byType(FilledButton),
      );
      await tester.tap(publishButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      final tasks = controller.agentById('agent-1')!.tasks;
      expect(tasks, hasLength(1));
      expect(tasks.single.title, 'Prepare weekly report');
      expect(tasks.single.description, 'Collect weekly evidence.');
      expect(tasks.single.extra['labels'], <String>['ops', 'report']);
      expect(tasks.single.extra['retryable'], isTrue);
    });

    testWidgets('shows an error when publishing to a stopped agent', (
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
          scaleSettings: AgentScaleSettings(minWorkers: 0),
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('任务台').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布任务').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '任务标题'),
        'Prepare weekly report',
      );
      final publishButton = find.ancestor(
        of: find.text('发布').last,
        matching: find.byType(FilledButton),
      );
      await tester.tap(publishButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(controller.agentById('agent-1')!.tasks, isEmpty);
      expect(find.textContaining('任务未发布'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('keeps publish task dialog open when title is blank', (
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
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      await tester.tap(find.byTooltip('任务台').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布任务').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '介绍'),
        'This should stay in the draft.',
      );

      final publishButton = find.ancestor(
        of: find.text('发布').last,
        matching: find.byType(FilledButton),
      );
      await tester.tap(publishButton);
      await tester.pump();

      expect(find.text('请先填写任务标题。'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('发布任务 · Ops Agent'), findsOneWidget);
      expect(find.text('This should stay in the draft.'), findsOneWidget);
      expect(controller.agentById('agent-1')!.tasks, isEmpty);
    });

    testWidgets('audit dialog renders capability and worker reports', (
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
          workers: <AgentWorker>[
            AgentWorker(
              id: 'worker-1',
              name: 'Worker 1',
              status: AgentWorkerStatus.busy,
              currentTaskId: 'task-1',
              busyScore: 0.7,
              executedTaskCount: 4,
            ),
          ],
          tasks: <AgentTask>[
            AgentTask(
              id: 'task-1',
              title: 'Collect cloud billing evidence',
              status: AgentTaskStatus.running,
              extra: <String, Object?>{'assigned_worker_id': 'worker-1'},
            ),
            AgentTask(
              id: 'task-2',
              title: 'Publish weekly report',
              status: AgentTaskStatus.completed,
              extra: <String, Object?>{'assigned_worker_id': 'worker-1'},
            ),
            AgentTask(
              id: 'task-3',
              title: 'Wait for approval',
              status: AgentTaskStatus.waitingApproval,
            ),
          ],
          resourceUsage: AgentResourceUsage(
            cpuPercent: 0.4,
            tokenBudget: 1000,
            tokenUsed: 250,
            diskBytes: 4096,
            persistedBytes: 1024,
          ),
          auditEvents: <AgentAuditEvent>[
            AgentAuditEvent(
              id: 'audit-1',
              kind: 'skill_call',
              summary: 'skill_call: collect billing evidence',
              toolName: 'SkillRunner',
              requestCount: 2,
              tokenUsage: 100,
              metadata: <String, Object?>{
                'task_id': 'task-1',
                'worker_id': 'worker-1',
              },
            ),
          ],
        ),
      ]);
      await controller.refresh();

      await tester.pumpWidget(
        _AgentsViewHarness(controller: controller, dependencies: dependencies),
      );
      expect(find.text('Ops Agent'), findsOneWidget);
      await tester.tap(find.byTooltip('审计报表').first);
      await tester.pumpAndSettle();

      expect(find.text('能力使用画像'), findsOneWidget);
      expect(find.text('Worker 执行画像'), findsOneWidget);
      expect(find.text('负载与资源压力'), findsOneWidget);
      expect(find.text('任务完成画像'), findsOneWidget);
      expect(find.text('已完成'), findsAtLeastNWidgets(1));
      expect(find.text('执行中'), findsAtLeastNWidgets(1));
      expect(find.text('待处理'), findsAtLeastNWidgets(1));
      expect(find.text('SkillRunner'), findsAtLeastNWidgets(1));
      expect(find.text('Worker 1'), findsOneWidget);
      expect(find.textContaining('100 Token'), findsAtLeastNWidgets(1));
      expect(find.textContaining('2 请求'), findsAtLeastNWidgets(1));

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
  const _AgentsViewHarness({
    required this.controller,
    this.dependencies,
    this.disableAnimations = false,
  });

  final AgentsController controller;
  final _AgentEditorDependencies? dependencies;
  final bool disableAnimations;

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
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) {
          final media = MediaQuery.maybeOf(context) ?? const MediaQueryData();
          return MediaQuery(
            data: media.copyWith(disableAnimations: disableAnimations),
            child: child!,
          );
        },
        home: const Scaffold(
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
    List<CronEntry> cronEntries = const <CronEntry>[
      CronEntry(
        id: 'daily-report',
        name: 'Daily Report',
        cronExpression: '0 9 * * *',
      ),
      CronEntry(
        id: 'weekly-report',
        name: 'Weekly Report',
        cronExpression: '0 9 * * 1',
      ),
    ],
    List<HookEntry> hookEntries = const <HookEntry>[
      HookEntry(id: 'pre-hook', label: 'Pre Hook', event: HookEvent.preToolUse),
      HookEntry(
        id: 'post-hook',
        label: 'Post Hook',
        event: HookEvent.postToolUse,
      ),
    ],
  }) {
    return _AgentEditorDependencies(
      settings: _FakeSettingsController(builtinToolConfigs: builtinToolConfigs),
      skills: _FakeSkillsController(),
      knowledgeBase: _FakeKnowledgeBaseController(),
      memory: _FakeMemoryController(),
      mcp: _FakeMcpController(),
      crons: _FakeCronsController(cronEntries),
      hooks: _FakeHooksController(hookEntries),
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
    if (invocation.memberName == #chipAnimationSettings &&
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
  _FakeCronsController(this.entries);

  @override
  final List<CronEntry> entries;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _FakeHooksController extends ChangeNotifier implements HooksController {
  _FakeHooksController(this.entries);

  @override
  final List<HookEntry> entries;

  @override
  dynamic noSuchMethod(Invocation invocation) {
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
