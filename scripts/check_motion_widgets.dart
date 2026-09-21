import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'motion',
  source: _checks,
);

const _checks = '''
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';
import 'package:openhand/shared/ui/animated_expandable.dart';
import 'package:openhand/shared/ui/bounded_animation.dart';
import 'package:openhand/shared/ui/motion_preference.dart';
import 'package:openhand/shared/ui/openhand_image_reveal.dart';
import 'package:openhand/shared/ui/openhand_reveal_switcher.dart';
import 'package:openhand/shared/ui/spring_entrance.dart';

class _TrackedController extends AnimationController {
  _TrackedController() : super(vsync: const TestVSync(), duration: const Duration(seconds: 1));
  final listeners = <AnimationStatusListener>{};
  @override
  void addStatusListener(AnimationStatusListener listener) {
    listeners.add(listener);
    super.addStatusListener(listener);
  }
  @override
  void removeStatusListener(AnimationStatusListener listener) {
    listeners.remove(listener);
    super.removeStatusListener(listener);
  }
}

void main() {
  test('单向公共曲线重复创建不积累状态监听，回弹透明度保持有效', () {
    final controller = _TrackedController();
    final initialListeners = controller.listeners.length;
    for (var index = 0; index < 1000; index++) {
      final curve = openHandCurveAnimation(parent: controller, curve: kOpenHandEntranceCurve);
      controller.value = (index % 100) / 100;
      final opacity = OpenHandBoundedDoubleAnimation(curve).value;
      expect(opacity, inInclusiveRange(0.0, 1.0));
    }
    expect(controller.listeners.length, initialListeners);
    controller.dispose();
  });

  testWidgets('降低动效时展开箭头仍显示正确方向', (tester) async {
    for (final expanded in [true, false]) {
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: AnimatedExpandChevron(expanded: expanded),
      )));
      expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, expanded ? 1 : 0);
      expect(tester.binding.transientCallbackCount, 0);
    }
  });

  testWidgets('图片重建复用曲线，快速反向不中断进度，卸载释放监听', (tester) async {
    Widget content(String key, bool compact) => MaterialApp(home: Center(
      child: OpenHandImageRevealSwitcher(
        stateKey: key,
        compact: compact,
        child: const SizedBox(width: 100, height: 80),
      ),
    ));
    await tester.pumpWidget(content('加载', false));
    await tester.pumpWidget(content('就绪', false));
    await tester.pump(const Duration(milliseconds: 120));
    final finder = find.descendant(of: find.byType(OpenHandImageRevealSwitcher), matching: find.byType(FadeTransition));
    final before = tester.widgetList<FadeTransition>(finder).map((w) => w.opacity).toList();
    for (var index = 0; index < 20; index++) {
      await tester.pumpWidget(content('就绪', index.isEven));
    }
    final after = tester.widgetList<FadeTransition>(finder).map((w) => w.opacity).toList();
    expect(after, orderedEquals(before));
    final incoming = after.last as CurvedAnimation;
    final progress = incoming.value;
    await tester.pumpWidget(content('加载', false));
    expect(incoming.value, closeTo(progress, 0.0001));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(before.cast<CurvedAnimation>().every((curve) => curve.isDisposed), isTrue);
  });

  testWidgets('回弹切换与动态进场参数不产生透明度越界', (tester) async {
    for (var state = 0; state < 4; state++) {
      await tester.pumpWidget(MaterialApp(home: OpenHandCrossFadeSwitcher(
        switchInCurve: kOpenHandEntranceCurve,
        child: OpenHandSpringEntrance(
          key: ValueKey(state),
          scaleBegin: 0.92 + state * 0.01,
          child: const SizedBox(width: 80, height: 60),
        ),
      )));
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        for (final fade in tester.widgetList<FadeTransition>(find.byType(FadeTransition))) {
          expect(fade.opacity.value, inInclusiveRange(0.0, 1.0));
        }
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpAndSettle();
  });

  testWidgets('全部弹窗样式支持快速关闭并在退场后释放遮罩', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox.shrink();
    })));
    await tester.pumpAndSettle();
    final baselineBarriers = find.byType(ModalBarrier).evaluate().length;
    for (final style in DialogAnimationStyle.values) {
      for (final curve in [DialogAnimationCurve.easeOutCubic, DialogAnimationCurve.elasticOut]) {
        final result = showAnimatedDialog<int>(
          context: context,
          settings: DialogAnimationSettings(entranceStyle: style, exitStyle: style, curve: curve),
          builder: (_) => const Center(child: SizedBox(width: 180, height: 120)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        Navigator.of(context).pop(7);
        await tester.pumpAndSettle();
        expect(await result, 7);
        expect(find.byType(ModalBarrier), findsNWidgets(baselineBarriers));
        expect(find.byType(AnimatedModalBarrier), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
''';
