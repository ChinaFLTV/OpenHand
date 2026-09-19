import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final editor = File(
    '${root.path}/lib/features/workflows/widgets/workflow_editor_dialog.dart',
  );
  // 在临时测试库中访问运行状态，避免给生产组件增加测试接口。
  final source = (await editor.readAsString()).replaceAllMapped(
    RegExp("import '([^']+)';"),
    (match) {
      final path = match[1]!;
      return "import '${Uri.parse(path).hasScheme ? path : editor.uri.resolve(path)}';";
    },
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'workflow_canvas',
    source:
        "import 'package:flutter_test/flutter_test.dart';\n"
        "import 'package:flutter/gestures.dart';\n$source\n$_checks",
  );
}

const _checks = '''
void main() {
  testWidgets('工作流测试期间可浏览画布，编辑被锁定，结束后恢复', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final plugins = PluginServiceController();
    addTearDown(plugins.dispose);
    final key = GlobalKey<_WorkflowEditorDialogState>();
    await tester.pumpWidget(MaterialApp(home: WorkflowEditorDialog(
      key: key,
      catalog: const WorkflowEditorCatalog(
        models: [], recentModelSelections: [], templates: [], skills: [],
        memories: [], instructions: [], knowledgeSources: [], mcpServers: [],
        codeRuntimes: {},
      ),
      templateRepository: AiPromptTemplateRepository(),
      pluginController: plugins,
      workflow: WorkflowDefinition(
        id: 'canvas-check', name: '画布交互检查',
        createdAt: DateTime(2026), updatedAt: DateTime(2026),
        nodes: const [WorkflowNode(
          id: 'start', kind: WorkflowNodeKind.start,
          title: '开始', x: 250, y: 200,
        )],
      ),
    )));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final state = key.currentState!;
    final controller = state._transformationController;
    final addButton = find.byKey(const ValueKey<(String, String, String?)>(('node-add-visibility', 'start', null)));
    double addOpacity() => tester.widget<AnimatedOpacity>(addButton).opacity;
    expect(addOpacity(), 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('start'))));
    await tester.pump();
    expect(addOpacity(), 1);
    await mouse.moveTo(tester.getCenter(addButton));
    await tester.pump();
    expect(addOpacity(), 1);
    await mouse.moveTo(const Offset(10, 10));
    await tester.pump();
    expect(addOpacity(), 0);
    state.setState(() => state._selectedNodeId = 'start');
    await tester.pump();
    expect(addOpacity(), 1);
    state.setState(() {
      state._selectedNodeId = null;
      state._connectingSourceNodeId = 'start';
    });
    await tester.pump();
    expect(addOpacity(), 1);
    state.setState(() => state._connectingSourceNodeId = null);
    await mouse.removePointer();
    state._addAnnotation(const Size(1000, 800));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final fingerprint = state._currentDraftFingerprint();
    final historyIndex = state._historyIndex;
    state.setState(() {
      state._workflowTesting = true;
      state._nodeExecutions['start'] = const WorkflowNodeExecutionEvent(
        nodeId: 'start', phase: WorkflowNodeExecutionPhase.running,
      );
    });
    await tester.pump();

    expect(addOpacity(), 0);

    // 节点和注释上的拖拽也应交给画布，不能改动内容。
    for (final position in [const Offset(700, 250), const Offset(280, 290), const Offset(480, 490)]) {
      controller.value = Matrix4.identity();
      await tester.pump();
      await tester.dragFrom(position, const Offset(90, 40));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.value.getTranslation().x, greaterThan(0));
      expect(state._currentDraftFingerprint(), fingerprint);
    }
    expect(find.byType(WorkflowNodeElapsedBadge), findsOneWidget);
    expect(tester.takeException(), isNull);
    final beforeScroll = controller.value.getMaxScaleOnAxis();
    await tester.sendEventToBinding(PointerScrollEvent(
      position: const Offset(600, 350), scrollDelta: const Offset(0, -100),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(beforeScroll));

    final beforePinch = controller.value.getMaxScaleOnAxis();
    final first = await tester.startGesture(const Offset(500, 350), pointer: 1);
    final second = await tester.startGesture(const Offset(650, 350), pointer: 2);
    await first.moveBy(const Offset(-60, 0));
    await second.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(beforePinch));
    await first.up();
    await second.up();

    await tester.tap(find.byTooltip('放大'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final zoomed = controller.value.getMaxScaleOnAxis();
    await tester.tap(find.byTooltip('缩小'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.value.getMaxScaleOnAxis(), lessThan(zoomed));
    final beforeMap = controller.value.clone();
    await tester.tap(find.byType(WorkflowMiniMap));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.value, isNot(beforeMap));
    await tester.tap(find.byTooltip('隐藏缩略导航图'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(WorkflowMiniMap), findsNothing);
    await tester.tap(find.byTooltip('显示缩略导航图'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(WorkflowMiniMap), findsOneWidget);

    for (final tooltip in ['添加工作流注释', '整理节点布局', '删除所选节点、连线或注释', '撤销（⌘/Ctrl+Z）', '重做（⌘/Ctrl+Shift+Z 或 Ctrl+Y）']) {
      final button = tester.widget<IconButton>(find.descendant(
        of: find.byTooltip(tooltip), matching: find.byType(IconButton),
      ));
      expect(button.onPressed, isNull, reason: tooltip);
    }
    expect(tester.widget<AnimatedPopupMenuButton<int>>(
      find.byType(AnimatedPopupMenuButton<int>),
    ).enabled, isFalse);
    await tester.tap(find.byTooltip('重置视图'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.value, Matrix4.identity());
    state._restoreHistory(0);
    state._canvasFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(state._historyIndex, historyIndex);
    expect(state._currentDraftFingerprint(), fingerprint);

    state.setState(() => state._workflowTesting = false);
    controller.value = Matrix4.identity();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.dragFrom(const Offset(280, 290), const Offset(90, 40));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(state._nodes.single.x, greaterThan(250));
    expect(controller.value, Matrix4.identity());
    state.setState(() {
      state._nodes = [
        state._nodes.single,
        const WorkflowNode(id: 'condition', kind: WorkflowNodeKind.condition,
          title: '分支', x: 600, y: 200),
        const WorkflowNode(id: 'loop', kind: WorkflowNodeKind.loop,
          title: '循环', x: 100, y: 430),
      ];
      for (final node in state._nodes) {
        state._nodeExecutions[node.id] = WorkflowNodeExecutionEvent(
          nodeId: node.id, phase: WorkflowNodeExecutionPhase.running,
        );
      }
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(WorkflowNodeElapsedBadge), findsNWidgets(3));
    for (final node in state._nodes) {
      final card = find.byKey(ValueKey(node.id));
      final badge = find.descendant(of: card, matching: find.byType(WorkflowNodeElapsedBadge));
      final cardRect = tester.getRect(card);
      final badgeRect = tester.getRect(badge);
      if (!workflowNodeHasBranches(node) && !isWorkflowContainerKind(node.kind)) {
        final descriptor = workflowNodeDescriptor(node.kind, Theme.of(tester.element(card)).colorScheme);
        final label = find.descendant(of: card, matching: find.text(descriptor.label)).last;
        expect(tester.getCenter(label).dy, closeTo(badgeRect.center.dy, 0.01));
      }
      expect(cardRect.contains(badgeRect.topLeft), isTrue);
      expect(cardRect.contains(badgeRect.bottomRight), isTrue);
    }
    expect(tester.takeException(), isNull);
    for (final fontSize in [12.0, 13.0, 14.0]) {
      for (final phase in [WorkflowNodeExecutionPhase.running, WorkflowNodeExecutionPhase.succeeded]) {
        final node = WorkflowNode(id: 'llm-layout', kind: WorkflowNodeKind.llm,
          title: '获取机型测试结论', x: 0, y: 0,
          settings: {'prompt': '结合已有测试数据生成详细的机型对比结论。' * 20});
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(textTheme: TextTheme(bodySmall: TextStyle(fontSize: fontSize))),
          home: Scaffold(body: Center(child: SizedBox(width: 214, height: 98,
            child: Builder(builder: (context) => state._buildNodeCardContent(
              context, node, workflowNodeDescriptor(node.kind, Theme.of(context).colorScheme),
              WorkflowNodeExecutionEvent(nodeId: node.id, phase: phase, duration: const Duration(milliseconds: 26327)),
            )),
          ))),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '节点摘要字号 \$fontSize，状态 \$phase');
        final badge = tester.getRect(find.byType(WorkflowNodeElapsedBadge));
        final summary = tester.getRect(find.text(workflowNodeSummary(node)));
        expect(badge.top - summary.bottom, greaterThanOrEqualTo(6));
        final label = tester.getRect(find.text('LLM'));
        expect(badge.center.dy, closeTo(label.center.dy, 0.01));
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
''';
