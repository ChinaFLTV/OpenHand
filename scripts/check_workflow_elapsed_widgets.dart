import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'workflow_elapsed',
  source: _checks,
);

const _checks = '''
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/widgets/workflow_node_elapsed_badge.dart';
import 'package:openhand/features/workflows/service/workflow_node_executor.dart';

void main() {
  testWidgets('耗时更新局限于徽章，完成定格、重跑归零、隐藏和卸载释放定时器', (tester) async {
    Widget scene(WorkflowNodeExecutionEvent? event, {bool enabled = true, bool reduce = false}) =>
      MaterialApp(home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: TickerMode(enabled: enabled, child: Center(
          child: WorkflowNodeElapsedBadge(event: event),
        )),
      ));
    WorkflowNodeExecutionEvent event(WorkflowNodeExecutionPhase phase, [int milliseconds = 0]) =>
      WorkflowNodeExecutionEvent(nodeId: '节点', phase: phase, duration: Duration(milliseconds: milliseconds));
    String displayedTime() => tester.widgetList<Text>(
      find.descendant(of: find.byType(WorkflowNodeElapsedBadge), matching: find.byType(Text)),
    ).map((text) => text.data ?? '').join();
    int milliseconds() {
      final semantics = tester.widgetList<Semantics>(find.byType(Semantics))
          .map((widget) => widget.properties.label ?? '')
          .firstWhere((label) => label.startsWith('执行耗时'));
      return int.parse(semantics.split(' ')[1]);
    }
    await tester.pumpWidget(scene(event(WorkflowNodeExecutionPhase.pending)));
    await tester.pumpAndSettle();
    final running = event(WorkflowNodeExecutionPhase.running);
    await tester.pumpWidget(scene(running));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(milliseconds(), greaterThanOrEqualTo(200));
    final previous = milliseconds();
    await tester.pumpWidget(scene(running));
    expect(milliseconds(), greaterThanOrEqualTo(previous));

    final finished = event(WorkflowNodeExecutionPhase.succeeded, 12345);
    await tester.pumpWidget(scene(finished));
    await tester.pumpAndSettle();
    expect(milliseconds(), 12345);
    expect(displayedTime(), '12.345 秒');
    await tester.pump(const Duration(seconds: 2));
    expect(milliseconds(), 12345);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(scene(event(WorkflowNodeExecutionPhase.running), reduce: true));
    expect(milliseconds(), lessThan(100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(scene(running, enabled: false));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(scene(event(WorkflowNodeExecutionPhase.failed, 900), reduce: true));
    expect(milliseconds(), 900);
    expect(displayedTime(), '0.900 秒');
    expect(find.descendant(of: find.byType(WorkflowNodeElapsedBadge), matching: find.byType(SlideTransition)), findsNothing);
    await tester.pumpWidget(scene(null));
    await tester.pumpAndSettle();
    await tester.pumpWidget(scene(event(WorkflowNodeExecutionPhase.running)));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
''';
