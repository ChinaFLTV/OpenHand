import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/widgets/workflow_test_dialog.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

Future<BuildContext> _pumpDialogHost(WidgetTester tester) async {
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          pageContext = context;
          return const Scaffold(body: SizedBox.expand());
        },
      ),
    ),
  );
  return pageContext;
}

void _expectRoundedSquareCloseButton(WidgetTester tester) {
  final buttonFinder = find.ancestor(
    of: find.byIcon(Icons.close_rounded),
    matching: find.byType(IconButton),
  );
  expect(tester.getSize(buttonFinder), const Size.square(42));
  final button = tester.widget<IconButton>(buttonFinder);
  final shape = button.style?.shape?.resolve(const <WidgetState>{});
  expect(shape, isA<RoundedRectangleBorder>());
  expect(
    (shape! as RoundedRectangleBorder).borderRadius,
    kOpenHandBorderRadius12,
  );
}

void main() {
  testWidgets('测试输入弹窗使用纯色头部、圆角矩形输入框和方形关闭按钮', (tester) async {
    final context = await _pumpDialogHost(tester);
    final result = showWorkflowTestInputDialog(
      context,
      WorkflowNode(
        id: 'start',
        kind: WorkflowNodeKind.start,
        title: '开始',
        x: 0,
        y: 0,
        settings: <String, Object?>{
          WorkflowSettingKeys.inputFields: <Object?>[
            const WorkflowOutputField(
              id: 'wife',
              name: 'wife',
              description: '妻子',
              required: true,
            ).toJson(),
          ],
        },
      ),
    );
    await tester.pumpAndSettle();

    final header = tester.widget<Container>(
      find.byKey(const ValueKey<String>('workflow-test-input-header')),
    );
    final headerDecoration = header.decoration! as BoxDecoration;
    expect(headerDecoration.gradient, isNull);
    expect(headerDecoration.color, isNotNull);

    final textField = tester.widget<TextField>(find.byType(TextField));
    final enabledBorder =
        textField.decoration!.enabledBorder! as OutlineInputBorder;
    final focusedBorder =
        textField.decoration!.focusedBorder! as OutlineInputBorder;
    expect(enabledBorder.borderRadius, kOpenHandBorderRadius12);
    expect(focusedBorder.borderRadius, kOpenHandBorderRadius12);
    _expectRoundedSquareCloseButton(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('测试结果等宽铺满并按参数结构展示和复制输出', (tester) async {
    final context = await _pumpDialogHost(tester);
    final messenger = tester.binding.defaultBinaryMessenger;
    String? copiedText;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final result = showWorkflowTestResultDialog(
      context,
      const WorkflowTestReport(
        succeeded: true,
        hasWarnings: false,
        duration: Duration(milliseconds: 210),
        executedSteps: 3,
        succeededNodes: 3,
        warningNodes: 0,
        failedNodes: 0,
        skippedNodes: 0,
        output: <String, Object?>{
          'news': '鞠婧祎 fell in love with 李冠达',
          'count': 2,
        },
      ),
    );
    await tester.pumpAndSettle();

    final header = tester.widget<Container>(
      find.byKey(const ValueKey<String>('workflow-test-result-header')),
    );
    final headerDecoration = header.decoration! as BoxDecoration;
    expect(headerDecoration.gradient, isNull);
    expect(headerDecoration.color, isNotNull);
    _expectRoundedSquareCloseButton(tester);

    const metricKeys = <String>[
      'workflow-test-metric-success',
      'workflow-test-metric-warning',
      'workflow-test-metric-failure',
      'workflow-test-metric-skipped',
    ];
    final metricFinders = metricKeys
        .map((key) => find.byKey(ValueKey<String>(key)))
        .toList(growable: false);
    final metricWidths = metricFinders
        .map((finder) => tester.getSize(finder).width)
        .toList(growable: false);
    expect(metricWidths.toSet(), hasLength(1));
    final metrics = find.byKey(
      const ValueKey<String>('workflow-test-result-metrics'),
    );
    expect(
      tester.getTopLeft(metricFinders.first).dx,
      closeTo(tester.getTopLeft(metrics).dx, 0.01),
    );
    expect(
      tester.getTopRight(metricFinders.last).dx,
      closeTo(tester.getTopRight(metrics).dx, 0.01),
    );

    expect(find.text('news'), findsOneWidget);
    expect(find.text('鞠婧祎 fell in love with 李冠达'), findsOneWidget);
    expect(find.text('count'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('"news"'), findsNothing);

    await tester.tap(find.byTooltip('复制参数 news'));
    await tester.pump();
    expect(copiedText, '鞠婧祎 fell in love with 李冠达');

    final dialogCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('workflow-test-result-dialog')),
    );
    final finishCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('workflow-test-result-finish')),
    );
    expect(finishCenter.dx, closeTo(dialogCenter.dx, 0.01));

    await tester.tap(
      find.byKey(const ValueKey<String>('workflow-test-result-finish')),
    );
    await tester.pumpAndSettle();
    await result;
  });
}
