import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/data/workflows_store.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/widgets/workflows_view.dart';
import 'package:openhand/features/workflows/workflows_controller.dart';
import 'package:openhand/l10n/app_localizations.dart';
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
    final deleteFinder = find.byKey(
      const ValueKey<String>('workflow-delete-$workflowId'),
    );

    expect(tester.getSize(cardFinder).width, tester.getSize(listFinder).width);
    expect(tester.getSize(openFinder), tester.getSize(deleteFinder));
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
    expect(identical(openButton.style, deleteButton.style), isTrue);
    expect(
      openButton.style?.shape?.resolve(const <WidgetState>{}),
      isA<CircleBorder>(),
    );
    expect(find.text('打开画布'), findsNothing);
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
