import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/widgets/dingtalk_message_content_transition.dart';

void main() {
  Widget scene({
    required bool expanded,
    bool reducedMotion = false,
    bool streaming = false,
    Alignment alignment = Alignment.topLeft,
    VoidCallback? onTap,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Align(
        alignment: alignment,
        child: DingTalkMessageContentTransition(
          expanded: expanded,
          streaming: streaming,
          alignment: alignment,
          child: GestureDetector(
            key: ValueKey(expanded),
            onTap: onTap,
            child: SizedBox(
              width: expanded ? 320 : 180,
              height: expanded ? 420 : 48,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('展开和折叠均逐帧改变尺寸，右侧锚点保持稳定', (tester) async {
    const alignment = Alignment.topRight;
    final size = find.byType(AnimatedSize);
    await tester.pumpWidget(scene(expanded: false, alignment: alignment));
    final right = tester.getTopRight(size).dx;
    await tester.pumpWidget(scene(expanded: true, alignment: alignment));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(size).height, greaterThan(48));
    expect(tester.getSize(size).height, lessThan(420));
    expect(tester.getTopRight(size).dx, closeTo(right, 0.01));
    await tester.pumpAndSettle();
    expect(tester.getSize(size), const Size(320, 420));

    await tester.pumpWidget(scene(expanded: false, alignment: alignment));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(size).height, greaterThan(48));
    expect(tester.getSize(size).height, lessThan(420));
    expect(tester.getTopRight(size).dx, closeTo(right, 0.01));
    await tester.pumpAndSettle();
    expect(tester.getSize(size), const Size(180, 48));
  });

  testWidgets('连续反向切换后释放退场内容且不遗留动画', (tester) async {
    await tester.pumpWidget(scene(expanded: false));
    for (var i = 0; i < 12; i++) {
      await tester.pumpWidget(scene(expanded: i.isEven));
      await tester.pump(const Duration(milliseconds: 35));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(true)), findsNothing);
    expect(find.byKey(const ValueKey(false)), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('退场正文不响应点击', (tester) async {
    var taps = 0;
    await tester.pumpWidget(scene(expanded: true, onTap: () => taps++));
    await tester.pumpWidget(scene(expanded: false));
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      tester.getSize(find.byKey(const ValueKey(true))),
      const Size(320, 420),
    );
    await tester.tapAt(const Offset(40, 120));
    expect(taps, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('减少动态效果和流式更新不播放尺寸动画', (tester) async {
    for (final streaming in [false, true]) {
      await tester.pumpWidget(
        scene(expanded: false, reducedMotion: !streaming, streaming: streaming),
      );
      await tester.pumpWidget(
        scene(expanded: true, reducedMotion: !streaming, streaming: streaming),
      );
      expect(find.byType(AnimatedSize), findsNothing);
      expect(find.byKey(const ValueKey(false)), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey(true))),
        const Size(320, 420),
      );
    }
  });
}
