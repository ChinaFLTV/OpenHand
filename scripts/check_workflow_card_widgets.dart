import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final view = File(
    '${root.path}/lib/features/workflows/widgets/workflows_view.dart',
  );
  final source = (await view.readAsString()).replaceAllMapped(
    RegExp("import '([^']+)';"),
    (match) {
      final uri = Uri.parse(match[1]!);
      return "import '${uri.hasScheme ? uri : view.uri.resolveUri(uri)}';";
    },
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'workflow_card',
    source:
        "import 'package:flutter_test/flutter_test.dart';\n$source\n$_checks",
  );
}

const _checks = '''
void main() {
  testWidgets('不同内容卡片等宽等高，窄窗口和大字体无溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workflows = [
      for (var index = 0; index < 4; index++)
        WorkflowDefinition(
          id: 'card-\$index',
          name: index.isEven ? '工作流' : '长标题工作流' * 20,
          description: index == 0 ? '' : '工作流描述' * (index * 30),
          tags: List.generate(index * 4, (tag) => '标签\$tag' * (tag + 1)),
          createdAt: DateTime(2026), updatedAt: DateTime(2026),
        ),
    ];
    var opened = 0;
    var details = 0;
    for (final width in [280.0, 453.0, 599.0, 600.0, 900.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SingleChildScrollView(child: Wrap(
            spacing: _workflowGridSpacing,
            runSpacing: _workflowGridSpacing,
            children: [
              for (final workflow in workflows)
                SizedBox(width: width, child: _WorkflowCard(
                  workflow: workflow,
                  onOpen: () => opened++, onDetails: () => details++,
                  onDelete: () {}, onExport: (_) {}, onToggleEnabled: () {},
                )),
            ],
          ))),
        )));
        await tester.pumpAndSettle();
        final rects = [
          for (final workflow in workflows)
            tester.getRect(find.byKey(ValueKey('workflow-card-\${workflow.id}'))),
        ];
        for (final rect in rects) {
          expect(rect.width, width);
          expect(rect.height, rects.first.height);
        }
        final previewOffsets = [
          for (var index = 0; index < workflows.length; index++)
            tester.getTopLeft(find.byKey(ValueKey('workflow-minimap-\${workflows[index].id}'))).dy - rects[index].top,
        ];
        expect(previewOffsets.every((offset) => offset == previewOffsets.first), isTrue);
        expect(tester.takeException(), isNull, reason: '宽度 \$width，字号倍率 \$scale');
        await tester.tap(find.byKey(const ValueKey('workflow-open-card-0')));
        await tester.tap(find.byKey(const ValueKey('workflow-details-card-0')));
      }
    }
    expect(opened, 15);
    expect(details, 15);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
''';
