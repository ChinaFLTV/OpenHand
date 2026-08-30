import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/plugin_service/plugin_service_controller.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/widgets/workflow_editor_dialog.dart';
import 'package:openhand/features/workflows/widgets/workflow_node_configuration_panel.dart';

void main() {
  testWidgets('工具条整理按钮执行布局、写入历史并支持撤销', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plugins = PluginServiceController();
    addTearDown(plugins.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkflowEditorDialog(
            workflow: _workflow,
            catalog: const WorkflowEditorCatalog(
              models: [],
              recentModelSelections: [],
              templates: [],
              skills: [],
              memories: [],
              instructions: [],
              knowledgeSources: [],
              mcpServers: [],
              codeRuntimes: {},
            ),
            templateRepository: AiPromptTemplateRepository(
              loader: (_) async => '',
            ),
            pluginController: plugins,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('workflow-editor-title')),
      findsOneWidget,
    );
    expect(find.text('编辑工作流'), findsOneWidget);
    expect(find.text('新建工作流'), findsNothing);

    final toolbar = tester.widget<Material>(
      find.byKey(const ValueKey<String>('workflow-canvas-toolbar')),
    );
    final minimap = tester.widget<Material>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('workflow-editor-minimap')),
        matching: find.byType(Material),
      ),
    );
    expect(minimap.color, toolbar.color);
    expect(minimap.elevation, toolbar.elevation);
    expect(minimap.shape, toolbar.shape);

    final organize = find.byKey(
      const ValueKey<String>('workflow-organize-nodes'),
    );
    expect(organize, findsOneWidget);
    expect(find.byTooltip('整理节点布局'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(of: organize, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(organize);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byTooltip('撤销（⌘/Ctrl+Z）'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byTooltip('变更历史'));
    await tester.pumpAndSettle();
    expect(find.text('整理节点布局'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('撤销（⌘/Ctrl+Z）'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('重置视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始').first);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(700, 650);
    await tester.pumpAndSettle();
    expect(organize, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final WorkflowDefinition _workflow = WorkflowDefinition(
  id: 'workflow-organize',
  name: '整理测试',
  createdAt: DateTime.utc(2026, 8, 30),
  updatedAt: DateTime.utc(2026, 8, 30),
  nodes: const <WorkflowNode>[
    WorkflowNode(
      id: 'start',
      kind: WorkflowNodeKind.start,
      title: '开始',
      x: 900,
      y: 700,
    ),
    WorkflowNode(
      id: 'code',
      kind: WorkflowNodeKind.codeExecution,
      title: '代码执行',
      x: 100,
      y: 600,
    ),
    WorkflowNode(
      id: 'end',
      kind: WorkflowNodeKind.end,
      title: '结束',
      x: 400,
      y: 100,
    ),
  ],
  connections: const <WorkflowConnection>[
    WorkflowConnection(
      id: 'edge-1',
      sourceNodeId: 'start',
      targetNodeId: 'code',
    ),
    WorkflowConnection(id: 'edge-2', sourceNodeId: 'code', targetNodeId: 'end'),
  ],
);
