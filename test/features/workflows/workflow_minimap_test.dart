import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/widgets/workflow_minimap.dart';

void main() {
  testWidgets('空工作流缩略图安全展示空状态', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 120,
              child: WorkflowMiniMap(nodes: [], connections: []),
            ),
          ),
        ),
      ),
    );

    expect(find.text('尚未添加节点'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('交互缩略图支持点击定位、拖动平移和滚轮缩放', (tester) async {
    Offset? navigatedCenter;
    double? zoomFactor;
    const key = ValueKey<String>('interactive-minimap');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: key,
              width: 220,
              height: 120,
              child: WorkflowMiniMap(
                nodes: const <WorkflowNode>[
                  WorkflowNode(
                    id: 'start',
                    kind: WorkflowNodeKind.start,
                    title: '开始',
                    x: 100,
                    y: 100,
                  ),
                  WorkflowNode(
                    id: 'end',
                    kind: WorkflowNodeKind.end,
                    title: '结束',
                    x: 700,
                    y: 300,
                  ),
                ],
                connections: const <WorkflowConnection>[
                  WorkflowConnection(
                    id: 'edge',
                    sourceNodeId: 'start',
                    targetNodeId: 'end',
                  ),
                ],
                canvasSize: const Size(1000, 500),
                viewportRect: const Rect.fromLTWH(250, 125, 500, 250),
                selectedNodeId: 'end',
                onNavigate: (center) => navigatedCenter = center,
                onZoomFactor: (factor) => zoomFactor = factor,
              ),
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byKey(key));
    await tester.tapAt(center);
    await tester.pump();
    expect(navigatedCenter?.dx, moreOrLessEquals(500, epsilon: 0.1));
    expect(navigatedCenter?.dy, moreOrLessEquals(250, epsilon: 0.1));

    navigatedCenter = null;
    await tester.dragFrom(center, const Offset(36, 12));
    await tester.pump();
    expect(navigatedCenter, isNotNull);
    expect(navigatedCenter!.dx, greaterThan(500));

    tester.binding.handlePointerEvent(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -60)),
    );
    await tester.pump();
    expect(zoomFactor, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('仅包含注释时缩略图仍展示有效内容', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 120,
              child: WorkflowMiniMap(
                nodes: [],
                connections: [],
                annotations: <WorkflowAnnotation>[
                  WorkflowAnnotation(id: 'note', text: '流程说明', x: 100, y: 80),
                ],
                selectedAnnotationId: 'note',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('尚未添加节点'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('画布缩略图复用工具条浮层样式', (tester) async {
    const key = ValueKey<String>('canvas-style-minimap');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: key,
            width: 220,
            height: 120,
            child: WorkflowMiniMap(
              nodes: [],
              connections: [],
              useCanvasOverlayStyle: true,
            ),
          ),
        ),
      ),
    );

    final minimap = find.byKey(key);
    final material = tester.widget<Material>(
      find.descendant(of: minimap, matching: find.byType(Material)),
    );
    final colors = Theme.of(tester.element(minimap)).colorScheme;
    expect(material.color, workflowCanvasOverlayColor(colors));
    expect(material.elevation, kWorkflowCanvasOverlayElevation);
    expect(material.shape, workflowCanvasOverlayShape(colors));
    expect(tester.takeException(), isNull);
  });
}
