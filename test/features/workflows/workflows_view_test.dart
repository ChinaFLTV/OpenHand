import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/data/workflows_store.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/service/workflow_portability_service.dart';
import 'package:openhand/features/workflows/widgets/workflows_view.dart';
import 'package:openhand/features/workflows/workflows_controller.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/animated_menu.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('宽屏工作流默认双栏且卡片展示全貌缩略图', (tester) async {
    _setViewport(tester, const Size(1400, 900));
    final controller = await _pumpWorkflows(tester);
    addTearDown(controller.dispose);

    const firstId = 'workflow-1';
    const secondId = 'workflow-2';
    final listFinder = find.byKey(const ValueKey<String>('workflows-list'));
    final firstCard = find.byKey(
      const ValueKey<String>('workflow-card-$firstId'),
    );
    final secondCard = find.byKey(
      const ValueKey<String>('workflow-card-$secondId'),
    );
    final openFinder = find.byKey(
      const ValueKey<String>('workflow-open-$firstId'),
    );
    final exportFinder = find.byKey(
      const ValueKey<String>('workflow-export-$firstId'),
    );
    final deleteFinder = find.byKey(
      const ValueKey<String>('workflow-delete-$firstId'),
    );

    expect(tester.getTopLeft(firstCard).dy, tester.getTopLeft(secondCard).dy);
    expect(tester.getSize(firstCard).width, tester.getSize(secondCard).width);
    expect(
      tester.getSize(firstCard).width,
      moreOrLessEquals((tester.getSize(listFinder).width - 14) / 2),
    );
    expect(
      tester.getTopLeft(secondCard).dx - tester.getTopRight(firstCard).dx,
      14,
    );
    expect(
      find.byKey(const ValueKey<String>('workflow-minimap-$firstId')),
      findsOneWidget,
    );
    expect(find.byType(Chip), findsNothing);

    expect(tester.getSize(openFinder), tester.getSize(deleteFinder));
    expect(tester.getSize(exportFinder), tester.getSize(openFinder));
    expect(
      tester.getTopLeft(openFinder).dx - tester.getTopRight(exportFinder).dx,
      8,
    );
    expect(
      tester.getTopLeft(deleteFinder).dx - tester.getTopRight(openFinder).dx,
      8,
    );
    final openButton = tester.widget<IconButton>(openFinder);
    final deleteButton = tester.widget<IconButton>(deleteFinder);
    final exportButton = tester
        .widget<AnimatedPopupMenuButton<WorkflowExportFormat>>(exportFinder);
    expect(identical(openButton.style, deleteButton.style), isTrue);
    expect(identical(exportButton.style, openButton.style), isTrue);
    expect(find.byIcon(Icons.edit_rounded), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('workflow-import-button')),
      findsOneWidget,
    );

    await tester.tap(exportFinder);
    await tester.pumpAndSettle();
    expect(find.text('YAML 配置文件'), findsOneWidget);
    expect(find.text('PNG 图片'), findsOneWidget);
    expect(find.text('JPEG 图片'), findsOneWidget);
    expect(find.text('SVG 矢量图'), findsOneWidget);
  });

  testWidgets('可用宽度不足时工作流自动退回单栏', (tester) async {
    _setViewport(tester, const Size(760, 900));
    final controller = await _pumpWorkflows(tester);
    addTearDown(controller.dispose);

    final listFinder = find.byKey(const ValueKey<String>('workflows-list'));
    final firstCard = find.byKey(
      const ValueKey<String>('workflow-card-workflow-1'),
    );
    final secondCard = find.byKey(
      const ValueKey<String>('workflow-card-workflow-2'),
    );
    expect(tester.getTopLeft(firstCard).dx, tester.getTopLeft(secondCard).dx);
    expect(tester.getSize(firstCard).width, tester.getSize(listFinder).width);
    expect(
      tester.getTopLeft(secondCard).dy - tester.getBottomLeft(firstCard).dy,
      14,
    );
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<WorkflowsController> _pumpWorkflows(WidgetTester tester) async {
  final store = _MemoryWorkflowsStore(<WorkflowDefinition>[
    _workflow('workflow-1', '重大新闻', 0),
    _workflow('workflow-2', '每日摘要', 80),
  ]);
  final controller = await WorkflowsController.create(store: store);
  await tester.pumpWidget(
    ChangeNotifierProvider<WorkflowsController>.value(
      value: controller,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(
          body: Padding(padding: EdgeInsets.all(24), child: WorkflowsView()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

WorkflowDefinition _workflow(String id, String name, double yOffset) {
  final startId = '$id-start';
  final codeId = '$id-code';
  final endId = '$id-end';
  return WorkflowDefinition(
    id: id,
    name: name,
    createdAt: DateTime.utc(2026, 8, 30, 13, 53),
    updatedAt: DateTime.utc(2026, 8, 30, 13, 53),
    nodes: <WorkflowNode>[
      WorkflowNode(
        id: startId,
        kind: WorkflowNodeKind.start,
        title: '开始',
        x: 80,
        y: 100 + yOffset,
      ),
      WorkflowNode(
        id: codeId,
        kind: WorkflowNodeKind.codeExecution,
        title: '代码执行',
        x: 480,
        y: 180 + yOffset,
      ),
      WorkflowNode(
        id: endId,
        kind: WorkflowNodeKind.end,
        title: '结束',
        x: 880,
        y: 120 + yOffset,
      ),
    ],
    connections: <WorkflowConnection>[
      WorkflowConnection(
        id: '$id-edge-1',
        sourceNodeId: startId,
        targetNodeId: codeId,
      ),
      WorkflowConnection(
        id: '$id-edge-2',
        sourceNodeId: codeId,
        targetNodeId: endId,
      ),
    ],
  );
}

class _MemoryWorkflowsStore extends WorkflowsStore {
  _MemoryWorkflowsStore(this._workflows);

  final List<WorkflowDefinition> _workflows;

  @override
  Future<void> ensureTable() async {}

  @override
  Future<List<WorkflowDefinition>> loadAll() async =>
      List<WorkflowDefinition>.of(_workflows);
}
