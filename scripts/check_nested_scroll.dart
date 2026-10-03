import 'dart:io';
import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'nested_scroll',
  source: r'''
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
  for (final trackpad in [false, true]) {
    for (final reachesEdgeBeforeRelease in [false, true]) {
      testWidgets(
        '嵌套滚动：触边后抬手惯性继续进入外层，预先触边=$reachesEdgeBeforeRelease，触控板=$trackpad',
        (tester) async {
          final outer = ScrollController();
          final inner = ScrollController();
          await tester.pumpWidget(
            MaterialApp(
              scrollBehavior: const OpenHandImplicitScrollbarBehavior(),
              home: Scaffold(
                body: SingleChildScrollView(
                  controller: outer,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 200,
                        child: ListView(
                          controller: inner,
                          children: const [
                            SizedBox(height: 500, child: Text('内层正文')),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2200),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> fling(double direction) async {
            const point = Offset(100, 80);
            if (!trackpad) {
              await tester.flingFrom(point, Offset(0, 150 * direction), 3000);
              return;
            }
            final gesture = await tester.createGesture(
              kind: PointerDeviceKind.trackpad,
            );
            await gesture.panZoomStart(point);
            for (var step = 1; step <= 4; step++) {
              await gesture.panZoomUpdate(
                point,
                pan: Offset(0, 50 * step * direction),
                timeStamp: Duration(milliseconds: 16 * step),
              );
              await tester.pump(const Duration(milliseconds: 16));
            }
            await gesture.panZoomEnd(
              timeStamp: const Duration(milliseconds: 80),
            );
          }

          inner.jumpTo(
            reachesEdgeBeforeRelease ? inner.position.maxScrollExtent - 10 : 0,
          );
          await fling(-1);
          final releasedOffset = outer.offset;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(
            outer.position.activity,
            isA<BallisticScrollActivity>(),
            reason: '内层不能丢弃触控板或拖动抬手时的剩余速度',
          );
          await tester.pumpAndSettle();
          expect(inner.offset, closeTo(inner.position.maxScrollExtent, .001));
          expect(
            outer.offset,
            greaterThan(releasedOffset + 250),
            reason: '外层应沿原方向自然减速，不能只移动最后一帧的余量',
          );
          expect(outer.position.outOfRange, false);
          outer.jumpTo(100);
          inner.jumpTo(10);
          await tester.pumpAndSettle();
          await fling(1);
          await tester.pumpAndSettle();
          expect(outer.offset, 0, reason: '向上触边也应延续惯性，并在会话边界夹紧');
          await tester.pumpWidget(const SizedBox());
          outer.dispose();
          inner.dispose();
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({TargetPlatform.macOS}),
      );
    }
  }
  testWidgets('嵌套滚动：旧的内部惯性不能取消新的会话拖动', (tester) async {
    final outer = ScrollController();
    final inner = ScrollController();
    await tester.pumpWidget(MaterialApp(scrollBehavior: const OpenHandImplicitScrollbarBehavior(),
      home: Scaffold(body: SingleChildScrollView(controller: outer, child: Column(children: [
        SizedBox(height: 200, child: ListView(controller: inner,
          children: const [SizedBox(height: 500, child: Text('正文'))])),
        const SizedBox(height: 2200),
      ])))));
    await tester.pumpAndSettle();
    await tester.flingFrom(const Offset(100, 80), const Offset(0, -150), 3000);
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(100, 350));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -40));
    final userOffset = outer.offset;
    await tester.pump(const Duration(milliseconds: 150));
    expect(outer.position.activity, isA<DragScrollActivity>(),
      reason: '旧惯性触边后不能取消新手势');
    expect(outer.offset, closeTo(userOffset, .001),
      reason: '用户保持手势时旧惯性不能改写位置');
    await gesture.cancel();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    outer.dispose();
    inner.dispose();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));
}
''',
);
