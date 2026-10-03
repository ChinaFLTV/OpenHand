import 'dart:io';

import 'support/flutter_widget_check.dart';

/// 验证真实详情与日志弹窗的内容高度、滚动上限和资源释放。
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final source = await readFlutterCheckSource(
    File(
      '${root.path}/lib/features/mcp/widgets/tool_search_loaded_dialog.dart',
    ),
    root: root,
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'dialog_layout',
    source:
        "import 'package:flutter_test/flutter_test.dart';\n"
        "import 'package:provider/provider.dart';\n"
        "import 'package:openhand/app/state/settings_controller.dart';\n"
        "import 'package:openhand/app/model/dialog_animation_settings.dart';\n"
        "import 'package:openhand/shared/ui/runtime_log_dialog.dart';\n"
        "import 'package:openhand/features/services/widgets/service_dialog_controls.dart';\n"
        "import 'package:openhand/features/workflows/widgets/workflow_details_dialog.dart';\n"
        "import 'package:openhand/features/workflows/model/workflow_definition.dart';\n"
        '$source\n$_checks',
  );
}

const _checks = r'''
class _DialogSizingSettings extends ChangeNotifier implements SettingsController {
  @override
  DialogAnimationSettings dialogAnimationSettings = OpenHandMotionDefaults.disabled;
  @override
  DialogAnimationSettings chipAnimationSettings = OpenHandMotionDefaults.disabled;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder get _dialogSurface => find.byWidgetPredicate((widget) => widget is Material && widget.type == MaterialType.card).first;

Widget _dialogHost(_DialogSizingSettings settings, WidgetBuilder builder) => ChangeNotifierProvider<SettingsController>.value(
  value: settings,
  child: MaterialApp(locale: const Locale('zh'), supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: Builder(builder: builder))),
);

void main() {
  testWidgets('服务详情：短记录与空态按内容收缩，长记录有界滚动', (tester) async {
    tester.view.physicalSize = const Size(960, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = _DialogSizingSettings();
    addTearDown(settings.dispose);
    final heights = <double>[];
    for (final count in [0, 1, 100]) {
      await tester.pumpWidget(_dialogHost(settings, (context) => TextButton(
        onPressed: () => showServiceDetailsDialog(context, title: '详情', presentation: ServiceDetailPresentation.record,
          fields: List.generate(count, (index) => ServiceDetailField(label: '字段 $index', value: '记录内容'))),
        child: const Text('打开详情'))));
      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();
      final height = tester.getSize(_dialogSurface).height;
      heights.add(height);
      expect(height, lessThanOrEqualTo(kOpenHandDialogHeightTall));
      if (count == 100) {
        final scroll = tester.state<ScrollableState>(find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)).first);
        expect(scroll.position.maxScrollExtent, greaterThan(0));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    expect(heights[0], lessThan(300));
    expect(heights[1], lessThan(heights.last - 100));
  });

  testWidgets('运行日志：空态及短日志自适应，追加长日志保留惰性滚动', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = _DialogSizingSettings();
    addTearDown(settings.dispose);
    final changes = ValueNotifier<int>(0);
    addTearDown(changes.dispose);
    var logs = <String>[];
    await tester.pumpWidget(_dialogHost(settings, (context) => TextButton(
      onPressed: () => showOpenHandRuntimeLogDialog(context: context, title: '运行日志', listenable: changes,
        logs: () => logs, revision: () => changes.value, clearLogs: () { logs = []; changes.value++; }),
      child: const Text('打开日志'))));
    await tester.tap(find.text('打开日志'));
    await tester.pumpAndSettle();
    final emptyHeight = tester.getSize(_dialogSurface).height;
    expect(emptyHeight, lessThan(320));
    logs = List.filled(2, '日志内容');
    changes.value++;
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(tester.getSize(_dialogSurface).height, lessThan(320));
    logs = List.generate(2000, (index) => '日志 $index');
    changes.value++;
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(tester.getSize(_dialogSurface).height, closeTo(kOpenHandDialogHeightStandard, 1));
    expect(find.byWidgetPredicate((widget) => widget is Text && widget.data?.startsWith('日志 ') == true).evaluate().length, lessThan(100));
    final scroll = tester.state<ScrollableState>(find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)).first);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.tap(find.byTooltip('清屏'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(tester.getSize(_dialogSurface).height, closeTo(emptyHeight, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('工具搜索历史预览：条目决定高度，大列表限制高度', (tester) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = _DialogSizingSettings();
    addTearDown(settings.dispose);
    final heights = <double>[];
    for (final count in [0, 1, 2000]) {
      await tester.pumpWidget(_dialogHost(settings, (context) => _ToolSearchHistoryImportPreviewDialog(entries:
        List.generate(count, (index) => AiToolSearchLoadHistoryEntry(timestamp: DateTime.utc(2026), query: '搜索 $index', addedNames: ['工具'], totalDeferred: 10)))));
      await tester.pumpAndSettle();
      heights.add(tester.getSize(_dialogSurface).height);
      expect(heights.last, lessThanOrEqualTo(kOpenHandDialogHeightCompact));
      if (count == 2000) {
        expect(find.byType(ListTile).evaluate().length, lessThan(100));
        expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent, greaterThan(0));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    expect(heights.first, lessThan(300));
    expect(heights[1], lessThan(heights.last - 100));
  });

  testWidgets('工作流详情：完整面板有界滚动且保留所有信息', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = _DialogSizingSettings();
    addTearDown(settings.dispose);
    final directory = Directory.systemTemp.createTempSync('dialog-workflow-');
    final store = AiToolUsagePromotionStore(filePath: '${directory.path}/usage.json');
    addTearDown(() async { await tester.runAsync(() => store.shutdown()); directory.deleteSync(recursive: true); });
    await tester.pumpWidget(_dialogHost(settings, (context) => TextButton(onPressed: () => showWorkflowDetailsDialog(context,
      workflow: WorkflowDefinition(id: '检查', name: '工作流', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026)), usageStore: store),
      child: const Text('打开工作流'))));
    await tester.tap(find.text('打开工作流'));
    await tester.pumpAndSettle();
    expect(tester.getSize(_dialogSurface).height, lessThanOrEqualTo(860));
    final scroll = tester.state<ScrollableState>(find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)).first);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(find.text('最近的调用记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
''';
