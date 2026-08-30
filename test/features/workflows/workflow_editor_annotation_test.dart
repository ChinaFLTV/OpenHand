import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/plugin_service/plugin_service_controller.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/widgets/workflow_annotation_card.dart';
import 'package:openhand/features/workflows/widgets/workflow_editor_dialog.dart';
import 'package:openhand/features/workflows/widgets/workflow_node_configuration_panel.dart';

void main() {
  testWidgets('最小尺寸注释工具条自适应且无布局溢出', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: kWorkflowAnnotationMinWidth,
              height: kWorkflowAnnotationMinHeight,
              child: WorkflowAnnotationCard(
                annotation: const WorkflowAnnotation(
                  id: 'compact-note',
                  text: '紧凑注释',
                  x: 0,
                  y: 0,
                  width: kWorkflowAnnotationMinWidth,
                  height: kWorkflowAnnotationMinHeight,
                ),
                selected: true,
                onSelect: _noop,
                onChanged: (_) {},
                onMove: (_) {},
                onResize: (_) {},
                onDuplicate: _noop,
                onDelete: _noop,
                onEditingChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('注释配色'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('工具条可添加、编辑、移动、缩放和撤销删除注释', (tester) async {
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

    final addButton = find.byKey(
      const ValueKey<String>('workflow-add-annotation'),
    );
    expect(addButton, findsOneWidget);
    expect(find.byTooltip('添加工作流注释'), findsOneWidget);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    final cardFinder = find.byType(WorkflowAnnotationCard);
    expect(cardFinder, findsOneWidget);
    final card = tester.widget<WorkflowAnnotationCard>(cardFinder);
    final annotationId = card.annotation.id;
    final inputFinder = find.byKey(
      ValueKey<String>('workflow-annotation-input-$annotationId'),
    );
    await tester.enterText(inputFinder, '第一行\n第二行');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(cardFinder, findsOneWidget);
    expect(tester.widget<TextField>(inputFinder).controller!.text, '第一行\n第二');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(WorkflowEditorDialog), findsOneWidget);
    expect(find.byTooltip('粗体'), findsNothing);
    await tester.tap(inputFinder);
    await tester.pumpAndSettle();
    expect(find.byTooltip('粗体'), findsOneWidget);
    await tester.enterText(inputFinder, '第一行\n第二行');
    await tester.pump();

    await tester.tap(find.byTooltip('粗体'));
    await tester.pump();
    expect(
      tester.widget<TextField>(inputFinder).style?.fontWeight,
      FontWeight.w800,
    );
    await tester.tap(find.byTooltip('项目符号'));
    await tester.pump();
    expect(
      tester.widget<TextField>(inputFinder).controller!.text,
      '• 第一行\n• 第二行',
    );

    await tester.tap(find.byTooltip('注释配色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('绿色'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<WorkflowAnnotationCard>(cardFinder).annotation.theme,
      WorkflowAnnotationTheme.green,
    );

    final positionedFinder = find.byKey(
      ValueKey<String>('workflow-annotation-$annotationId'),
    );
    final beforeResize = tester.widget<Positioned>(positionedFinder);
    await tester.drag(
      find.byKey(ValueKey<String>('workflow-annotation-resize-$annotationId')),
      const Offset(64, 36),
    );
    await tester.pump();
    final afterResize = tester.widget<Positioned>(positionedFinder);
    expect(afterResize.width, greaterThan(beforeResize.width!));
    expect(afterResize.height, greaterThan(beforeResize.height!));

    final beforeMove = tester.widget<Positioned>(positionedFinder);
    await tester.drag(
      find.byKey(ValueKey<String>('workflow-annotation-move-$annotationId')),
      const Offset(90, 60),
    );
    await tester.pump();
    final afterMove = tester.widget<Positioned>(positionedFinder);
    expect(afterMove.left, greaterThan(beforeMove.left!));
    expect(afterMove.top, greaterThan(beforeMove.top!));

    await tester.tap(find.byTooltip('删除所选节点、连线或注释'));
    await tester.pumpAndSettle();
    expect(cardFinder, findsNothing);

    await tester.tap(find.byTooltip('撤销（⌘/Ctrl+Z）'));
    await tester.pumpAndSettle();
    expect(cardFinder, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('注释字体工具只修改选中的文本范围', (tester) async {
    WorkflowAnnotation? latest;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 220,
            child: StatefulBuilder(
              builder: (context, setState) => WorkflowAnnotationCard(
                annotation:
                    latest ??
                    const WorkflowAnnotation(
                      id: 'range-note',
                      text: '四个字文本',
                      x: 0,
                      y: 0,
                    ),
                selected: true,
                onSelect: _noop,
                onChanged: (value) => setState(() => latest = value),
                onMove: (_) {},
                onResize: (_) {},
                onDuplicate: _noop,
                onDelete: _noop,
                onEditingChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(
      find.byKey(
        const ValueKey<String>('workflow-annotation-input-range-note'),
      ),
    );
    input.controller!.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 3,
    );
    await tester.tap(find.byTooltip('粗体'));
    await tester.pump();

    expect(latest?.bold, isFalse);
    expect(latest?.styleRanges, hasLength(1));
    expect(latest?.styleRanges.single.start, 1);
    expect(latest?.styleRanges.single.end, 3);
    expect(latest?.styleRanges.single.bold, isTrue);

    final span = input.controller!.buildTextSpan(
      context: tester.element(
        find.byKey(
          const ValueKey<String>('workflow-annotation-input-range-note'),
        ),
      ),
      style: input.style,
      withComposing: false,
    );
    final children = span.children!.whereType<TextSpan>().toList();
    expect(children.map((child) => child.text).join(), '四个字文本');
    expect(children, hasLength(3));
    expect(children[0].style?.fontWeight, isNot(FontWeight.w800));
    expect(children[1].style?.fontWeight, FontWeight.w800);
    expect(children[2].style?.fontWeight, isNot(FontWeight.w800));
  });
}

void _noop() {}

final WorkflowDefinition _workflow = WorkflowDefinition(
  id: 'workflow-annotation',
  name: '注释测试',
  createdAt: DateTime.utc(2026, 8, 30),
  updatedAt: DateTime.utc(2026, 8, 30),
  nodes: const <WorkflowNode>[
    WorkflowNode(
      id: 'start',
      kind: WorkflowNodeKind.start,
      title: '开始',
      x: 180,
      y: 180,
    ),
    WorkflowNode(
      id: 'end',
      kind: WorkflowNodeKind.end,
      title: '结束',
      x: 620,
      y: 180,
    ),
  ],
  connections: const <WorkflowConnection>[
    WorkflowConnection(id: 'edge', sourceNodeId: 'start', targetNodeId: 'end'),
  ],
);
