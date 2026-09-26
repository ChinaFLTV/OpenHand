import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final dialog = File(
    '${root.path}/lib/features/workflows/widgets/workflow_test_dialog.dart',
  );
  final source = await readFlutterCheckSource(dialog, root: root);
  await runFlutterWidgetCheck(
    root: root,
    name: 'workflow_result',
    source:
        "import 'package:flutter_test/flutter_test.dart';\n$source\n$_checks",
  );
}

const _checks = '''
void main() {
  testWidgets('结果表格统一操作列，嵌套数据按需展开，复制保留完整数据', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final payload = <String, Object?>{
      '结果': <String, Object?>{'记录': [<String, Object?>{'名称': '机型', '指标': [1, true, null]}]},
      '空数组': [], '文本': '详细输出' * 30, '空值': null,
    };
    final entries = _workflowTestOutputEntries(payload, {'结果': '嵌套对象介绍'});
    for (final width in [380.0, 960.0]) {
      for (final dark in [false, true]) {
        for (final finalOutput in [false, true]) {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(width < 500 ? 1.5 : 1)),
              child: child!,
            ),
            home: Scaffold(body: Align(alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: SingleChildScrollView(
                child: finalOutput ? _WorkflowTestParameterTable(entries: entries)
                  : _WorkflowTestStructuredTable(value: payload,
                    descriptions: {'结果': '嵌套对象介绍'}, copyTooltipPrefix: '复制参数', emptyLabel: '空'),
              )),
            )),
          ));
          await tester.pumpAndSettle();
          expect(find.text('操作'), findsOneWidget);
          expect(find.text('参数介绍'), findsOneWidget);
          expect(find.byType(OpenHandJsonTreeView), findsNothing);
          final table = tester.widget<Table>(find.byType(Table));
          expect(table.children.every((row) => row.children.length == 5), isTrue);
          final copyButton = tester.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == '复制参数 结果'));
          copyButton.onPressed!();
          await tester.pumpAndSettle();
          expect(jsonDecode(copied!), payload['结果']);
          final expansion = find.byType(OpenHandExpansionTile).first;
          final ink = tester.widget<InkWell>(find.descendant(of: expansion, matching: find.byType(InkWell)).first);
          ink.onTap!();
          await tester.pumpAndSettle();
          expect(find.byType(OpenHandJsonTreeView), findsOneWidget);
          expect(tester.widget<OpenHandJsonTreeView>(find.byType(OpenHandJsonTreeView)).showCopyButton, isFalse);
          expect(find.byTooltip('复制 JSON'), findsNothing);
          expect(tester.takeException(), isNull);
          ink.onTap!();
          await tester.pumpAndSettle();
          expect(find.byType(OpenHandJsonTreeView), findsNothing);
        }
      }
    }
    final large = List.generate(10000, (index) => {'索引': index});
    expect(_structuredValueEntries(large, {}, scalarName: '值').length, 1);
    final cyclic = <String, Object?>{};
    cyclic['自身'] = cyclic;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 350,
      child: OpenHandJsonTreeView.fromValue(value: cyclic, showCopyButton: false),
    ))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
''';
