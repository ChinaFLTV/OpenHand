import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/workflows/widgets/workflow_export_progress_dialog.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

Future<BuildContext> _pumpHost(
  WidgetTester tester, {
  bool disableAnimations = true,
}) async {
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
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

void main() {
  testWidgets('导出状态弹窗实时展示进度、结果并支持 ESC 退场', (tester) async {
    final context = await _pumpHost(tester);
    final task = Completer<String>();
    late void Function(double progress, String message) reportProgress;
    unawaited(
      showWorkflowExportProgressDialog(
        context: context,
        formatLabel: 'PNG 图片',
        task: (report) {
          reportProgress = report;
          return task.future;
        },
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('正在导出工作流'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('workflow-export-processing')),
      findsOneWidget,
    );
    final closeFinder = find.byKey(
      const ValueKey<String>('workflow-export-progress-close'),
    );
    expect(tester.getSize(closeFinder), const Size.square(42));
    final closeButton = tester.widget<IconButton>(closeFinder);
    final closeShape = closeButton.style?.shape?.resolve(const <WidgetState>{});
    expect(closeShape, isA<RoundedRectangleBorder>());
    expect(
      (closeShape! as RoundedRectangleBorder).borderRadius,
      kOpenHandBorderRadius12,
    );

    reportProgress(0.62, '正在绘制全部节点和连线…');
    await tester.pump();
    expect(find.text('正在绘制全部节点和连线…'), findsOneWidget);

    task.complete('/tmp/demo.png');
    await tester.pump();
    await tester.pump();
    expect(find.text('导出完成'), findsOneWidget);
    expect(find.text('/tmp/demo.png'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('workflow-export-succeeded')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('workflow-export-succeeded')),
        matching: find.byType(Container),
      ),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('导出完成'), findsNothing);
  });

  testWidgets('进度条平滑过渡到新的目标值', (tester) async {
    final context = await _pumpHost(tester, disableAnimations: false);
    final task = Completer<String>();
    late void Function(double progress, String message) reportProgress;
    unawaited(
      showWorkflowExportProgressDialog(
        context: context,
        formatLabel: 'PNG 图片',
        task: (report) {
          reportProgress = report;
          return task.future;
        },
      ),
    );
    await tester.pump();
    await tester.pump();

    reportProgress(0.72, '正在写入文件…');
    await tester.pump();
    final indicator = find.byType(LinearProgressIndicator);
    final start = tester.widget<LinearProgressIndicator>(indicator).value!;
    expect(start, closeTo(0.04, 0.01));

    await tester.pump(const Duration(milliseconds: 180));
    final middle = tester.widget<LinearProgressIndicator>(indicator).value!;
    expect(middle, greaterThan(start));
    expect(middle, lessThan(0.72));

    await tester.pump(const Duration(milliseconds: 240));
    final settled = tester.widget<LinearProgressIndicator>(indicator).value!;
    expect(settled, closeTo(0.72, 0.01));

    task.complete('/tmp/demo.png');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('导出异常在状态弹窗内展示详细原因', (tester) async {
    final context = await _pumpHost(tester);
    unawaited(
      showWorkflowExportProgressDialog(
        context: context,
        formatLabel: 'SVG 矢量图',
        task: (_) async => throw '磁盘空间不足',
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('导出失败'), findsOneWidget);
    expect(find.textContaining('磁盘空间不足'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('workflow-export-failed')),
      findsOneWidget,
    );
  });
}
