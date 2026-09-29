import 'dart:io';
import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'nested_scroll',
  source: '''
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_scroll_behaviors.dart';

void main() {
  testWidgets('嵌套滚动保留边界余量和斜向输入且不重复消费', (tester) async {
    final outer = ScrollController();
    final horizontal = ScrollController();
    final inner = ScrollController();
    await tester.pumpWidget(MaterialApp(scrollBehavior: const OpenHandImplicitScrollbarBehavior(),
      home: Scaffold(body: ListView(controller: outer, children: [
        SizedBox(height: 200, child: SingleChildScrollView(controller: horizontal, scrollDirection: Axis.horizontal,
          child: SizedBox(width: 1200, child: ListView(controller: inner,
            children: const [SizedBox(height: 500, child: Text('列表'))])))),
        const SizedBox(height: 1800),
      ]))));
    await tester.pumpAndSettle();
    Future<void> wheel(Offset delta) async {
      await tester.sendEventToBinding(PointerScrollEvent(position: const Offset(100, 50), scrollDelta: delta));
      await tester.pump();
    }
    await wheel(const Offset(0, 50));
    expect(inner.offset, 50); expect(outer.offset, 0);
    inner.jumpTo(inner.position.maxScrollExtent - 10);
    await wheel(const Offset(0, 40));
    expect(inner.offset, inner.position.maxScrollExtent); expect(outer.offset, 30);
    outer.jumpTo(0);
    await wheel(const Offset(1, 40));
    expect(outer.offset, 40, reason: '横向轻微抖动不应吞掉垂直滚动');
    expect(horizontal.offset, 1);
    outer.jumpTo(50); inner.jumpTo(10);
    await wheel(const Offset(0, -40));
    expect(inner.offset, 0); expect(outer.offset, 20);
    outer.jumpTo(0); inner.jumpTo(0);
    await wheel(const Offset(0, -40));
    expect(outer.offset, 0); expect(inner.offset, 0);
    final horizontalBefore = horizontal.offset;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await wheel(const Offset(0, 40));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(horizontal.offset, horizontalBefore + 40);
    expect(outer.offset, 0, reason: 'Shift 滚轮应保持横向操作');
    inner.jumpTo(inner.position.maxScrollExtent);
    final trackpad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await trackpad.panZoomStart(const Offset(100, 50));
    await trackpad.panZoomUpdate(const Offset(100, 50), pan: const Offset(0, -80));
    await tester.pump();
    final beforePan = outer.offset;
    await trackpad.panZoomUpdate(const Offset(100, 50), pan: const Offset(0, -140));
    await tester.pump();
    expect(outer.offset, closeTo(beforePan + 60, 0.001), reason: '触控板余量应交给外层且只消费一次');
    await trackpad.panZoomEnd();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    outer.dispose(); horizontal.dispose(); inner.dispose();
    expect(tester.takeException(), isNull);
  });
}
''',
);
