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
  testWidgets('工作流卡片全宽展示且右上角操作按钮保持一致', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _MemoryWorkflowsStore(<WorkflowDefinition>[
      WorkflowDefinition(
        id: 'workflow-1',
        name: '重大新闻',
        createdAt: DateTime.utc(2026, 8, 30, 13, 53),
        updatedAt: DateTime.utc(2026, 8, 30, 13, 53),
      ),
    ]);
    final controller = await WorkflowsController.create(store: store);
    addTearDown(controller.dispose);

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

    const workflowId = 'workflow-1';
    final listFinder = find.byKey(const ValueKey<String>('workflows-list'));
    final cardFinder = find.byKey(
      const ValueKey<String>('workflow-card-$workflowId'),
    );
    final openFinder = find.byKey(
      const ValueKey<String>('workflow-open-$workflowId'),
    );
    final exportFinder = find.byKey(
      const ValueKey<String>('workflow-export-$workflowId'),
    );
    final deleteFinder = find.byKey(
      const ValueKey<String>('workflow-delete-$workflowId'),
    );

    expect(tester.getSize(cardFinder).width, tester.getSize(listFinder).width);
    expect(tester.getSize(openFinder), tester.getSize(deleteFinder));
    expect(tester.getSize(exportFinder), tester.getSize(openFinder));
    expect(
      tester.getTopLeft(exportFinder).dx,
      lessThan(tester.getTopLeft(openFinder).dx),
    );
    expect(
      tester.getTopLeft(openFinder).dx - tester.getTopRight(exportFinder).dx,
      8,
    );
    expect(
      tester.getTopLeft(openFinder).dx,
      lessThan(tester.getTopLeft(deleteFinder).dx),
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
    expect(
      openButton.style?.shape?.resolve(const <WidgetState>{}),
      isA<CircleBorder>(),
    );
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('workflow-import-button')),
      findsOneWidget,
    );
    expect(find.text('打开画布'), findsNothing);

    await tester.tap(exportFinder);
    await tester.pumpAndSettle();
    expect(find.text('YAML 配置文件'), findsOneWidget);
    expect(find.text('PNG 图片'), findsOneWidget);
    expect(find.text('JPEG 图片'), findsOneWidget);
    expect(find.text('SVG 矢量图'), findsOneWidget);
  });
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
