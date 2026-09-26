import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final editor = File(
    '${root.path}/lib/features/workflows/widgets/workflow_development_parameter_dialog.dart',
  );
  // 在临时测试库中访问运行状态，避免给生产组件增加测试接口。
  final source = await readFlutterCheckSource(editor, root: root);
  await runFlutterWidgetCheck(
    root: root,
    name: 'workflow_development',
    source:
        "import 'package:flutter_test/flutter_test.dart';\n"
        "import 'package:flutter/gestures.dart';\n$source\n$_checks",
  );
}

const _checks = '''
void main() {
  testWidgets('清空参数需确认，取消保留，保留全部开始输入并置空；取值方式不裁切', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final parameters = [WorkflowDevelopmentParameter(
      id: 'input', field: const WorkflowOutputField(id: 'input', name: 'model'),
      source: WorkflowDevelopmentParameterSource.startInput, ownerNodeId: 'start', value: '测试机型',
    ), const WorkflowDevelopmentParameter(
      id: 'input2', field: WorkflowOutputField(id: 'input2', name: 'extra', required: true),
      source: WorkflowDevelopmentParameterSource.startInput, ownerNodeId: 'start',
    ), const WorkflowDevelopmentParameter(
      id: 'output', field: WorkflowOutputField(id: 'output', name: 'result'),
      source: WorkflowDevelopmentParameterSource.nodeOutput, ownerNodeId: 'other', value: '结果',
    ), const WorkflowDevelopmentParameter(
      id: 'manual', field: WorkflowOutputField(id: 'manual', name: 'temporary'),
      source: WorkflowDevelopmentParameterSource.manual, value: '临时值',
    )];
    List<WorkflowDevelopmentParameter>? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () async {
        saved = await showWorkflowDevelopmentParameterDialog(context,
          parameters: parameters, onRefresh: (values) => values,
          referencesFor: (_) => [], ownerLabelFor: (_) => '开始');
      }, child: const Text('打开')),
    ))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.text('字面量拼接'), findsWidgets);
    final mode = find.byType(AnimatedDropdownButtonFormField<WorkflowValueMode>).first;
    final modeRect = tester.getRect(mode);
    final textRect = tester.getRect(find.text('字面量拼接').first);
    expect(modeRect.contains(textRect.topLeft), isTrue);
    expect(modeRect.contains(textRect.bottomRight), isTrue);
    await tester.tap(find.byTooltip('清空变量'));
    await tester.pumpAndSettle();
    expect(find.text('清空全部临时变量？'), findsOneWidget);
    await tester.tap(find.text('保留变量'));
    await tester.pumpAndSettle();
    expect(find.text('测试机型'), findsOneWidget);
    await tester.tap(find.byTooltip('清空变量'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空变量'));
    await tester.pumpAndSettle();
    expect(find.text('测试机型'), findsNothing);
    await tester.tap(find.byTooltip('保存参数列表'));
    await tester.pumpAndSettle();
    expect(saved!.map((parameter) => parameter.id), ['input', 'input2']);
    expect(saved!.every((parameter) => parameter.value.isEmpty), isTrue);
    expect(saved!.last.field.required, isTrue);
    expect(saved!.every((parameter) => parameter.ownerNodeId == 'start'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
''';
