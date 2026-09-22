import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'motion',
  source: _checks,
);

const _checks = '''
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';
import 'package:openhand/shared/ui/animated_expandable.dart';
import 'package:openhand/shared/ui/animated_overlay.dart';
import 'package:openhand/shared/ui/auto_follow_scroll_guard.dart';
import 'package:openhand/shared/ui/choice_input_dialog.dart';
import 'package:openhand/shared/ui/bounded_animation.dart';
import 'package:openhand/shared/ui/list_removal_transition.dart';
import 'package:openhand/shared/ui/motion_preference.dart';
import 'package:openhand/shared/ui/openhand_image_reveal.dart';
import 'package:openhand/shared/ui/openhand_hover_state.dart';
import 'package:openhand/shared/ui/openhand_hover_overlay.dart';
import 'package:openhand/shared/ui/openhand_file_hover_popup.dart';
import 'package:openhand/shared/ui/openhand_reveal_switcher.dart';
import 'package:openhand/shared/ui/openhand_snack_bar.dart';
import 'package:openhand/shared/ui/spring_entrance.dart';

class _HoverProbe extends StatefulWidget {
  const _HoverProbe({super.key});
  @override
  State<_HoverProbe> createState() => _HoverProbeState();
}

class _HoverProbeState extends State<_HoverProbe> with OpenHandHoverState<_HoverProbe> {
  @override
  Widget build(BuildContext context) => Text(openHandHovered ? '悬停' : '空闲');
}

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

class _MotionSettings extends ChangeNotifier implements SettingsController {
  @override
  DialogAnimationSettings chipAnimationSettings = OpenHandMotionDefaults.chip;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedCancelFuture implements Future<void> {
  _ObservedCancelFuture(this.future);
  final Future<void> future;
  int listeners = 0;
  @override
  Future<R> then<R>(FutureOr<R> Function(void) onValue, {Function? onError}) {
    listeners++;
    return future.then<R>(onValue, onError: onError);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('输入选择支持空闲、首帧前及被覆盖时取消', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox.shrink();
      }),
    ));
    await tester.pumpAndSettle();
    for (final phase in ['被覆盖', '空闲', '首帧前']) {
      final cancellation = Completer<void>();
      final result = showChoiceInputDialog(
        context: context,
        title: '等待取消的选择',
        options: const [ChoiceInputOption(value: 'one', label: '唯一选项')],
        cancelSignal: cancellation.future,
      );
      Future<void>? cover;
      if (phase != '首帧前') await tester.pumpAndSettle();
      if (phase == '被覆盖') {
        await tester.pumpAndSettle();
        cover = showAnimatedDialog<void>(
          context: context,
          builder: (_) => const Center(child: Text('上层弹窗')),
        );
        await tester.pumpAndSettle();
      }
      cancellation.complete();
      await tester.idle();
      if (phase == '空闲') expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      if (phase == '被覆盖') {
        expect(find.text('上层弹窗'), findsOneWidget);
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
        await cover;
      }
      expect(await result, isNull);
      expect(find.text('等待取消的选择'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    final cancellation = Completer<void>();
    final signal = _ObservedCancelFuture(cancellation.future);
    for (var index = 0; index < 8; index++) {
      final result = showChoiceInputDialog(
        context: context,
        title: '共享取消信号',
        options: const [ChoiceInputOption(value: 'one', label: '唯一选项')],
        cancelSignal: signal,
      );
      await tester.pumpAndSettle();
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      await result;
    }
    expect(signal.listeners, 1);
    final remaining = showAnimatedDialog<void>(
      context: context,
      builder: (_) => const Center(child: Text('独立弹窗')),
    );
    await tester.pumpAndSettle();
    cancellation.complete();
    await tester.pumpAndSettle();
    expect(find.text('独立弹窗'), findsOneWidget);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await remaining;
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动贴底兼容零时长与负时长，空闲调度主动请求绘制帧', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final guard = AutoFollowScrollGuard();
    await tester.pumpWidget(MaterialApp(home: ListView(
      controller: controller,
      children: const [SizedBox(height: 2000)],
    )));
    await tester.pumpAndSettle();
    for (final duration in [Duration.zero, const Duration(milliseconds: -1)]) {
      controller.jumpTo(0);
      guard.followToBottom(controller, animated: true, animationDuration: duration);
      expect(controller.offset, controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    guard.scheduleFollowToBottom(controller);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('关闭动效的浮层仍响应独立可见性信号', (tester) async {
    final visibility = ValueNotifier(true);
    addTearDown(visibility.dispose);
    await tester.pumpWidget(MaterialApp(home: AnimatedOverlayContent(
      customSettings: OpenHandMotionDefaults.disabled,
      visibility: visibility,
      child: const Text('浮层内容'),
    )));
    visibility.value = false;
    await tester.pump();
    expect(find.text('浮层内容'), findsNothing);
    visibility.value = true;
    await tester.pump();
    expect(find.text('浮层内容'), findsOneWidget);
  });

  testWidgets('悬停浮层同步内容与全局动效设置', (tester) async {
    final settings = _MotionSettings();
    addTearDown(settings.dispose);
    var label = '初始内容';
    late StateSetter rebuild;
    await tester.pumpWidget(ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: MaterialApp(home: Center(child: StatefulBuilder(builder: (_, setState) {
        rebuild = setState;
        return OpenHandHoverOverlay(
          showDelay: Duration.zero,
          hideDelay: Duration.zero,
          builder: (_, _) => Material(child: Text(label)),
          child: const SizedBox(width: 100, height: 60, child: Text('悬停锚点')),
        );
      }))),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(tester.getCenter(find.text('悬停锚点')));
    await tester.pumpAndSettle();
    expect(find.text('初始内容'), findsOneWidget);
    rebuild(() => label = '最新内容');
    await tester.pump();
    await tester.pump();
    expect(find.text('最新内容'), findsOneWidget);
    settings.chipAnimationSettings = OpenHandMotionDefaults.disabled;
    settings.notifyListeners();
    await tester.pump();
    await mouse.moveTo(const Offset(10, 10));
    await tester.pump();
    await tester.pump();
    expect(find.text('最新内容'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await mouse.removePointer();
  });

  testWidgets('文件提示在空闲快捷键操作时请求帧，松键取消待显示内容', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: OpenHandFileHoverPopup(
      resolvedPath: '/不存在的悬停检查文件',
      child: SizedBox(width: 100, height: 60, child: Text('文件锚点')),
    ))));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(tester.getCenter(find.text('文件锚点')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    expect(find.byType(AnimatedOverlayContent), findsNothing);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('列表删除保留内容直至退场完成，失败恢复时连续展开', (tester) async {
    var collapsed = false;
    Widget content() => MaterialApp(home: Center(child: OpenHandListRemovalTransition(
      collapsed: collapsed,
      child: const SizedBox(width: 160, height: 100, child: Text('待删除条目')),
    )));
    await tester.pumpWidget(content());
    final transition = find.byType(OpenHandListRemovalTransition);
    expect(tester.getSize(transition).height, 100);
    collapsed = true;
    await tester.pumpWidget(content());
    expect(find.text('待删除条目'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 180));
    final height = tester.getSize(transition).height;
    expect(height, greaterThan(0));
    expect(height, lessThan(100));
    collapsed = false;
    await tester.pumpWidget(content());
    expect(tester.getSize(transition).height, closeTo(height, 0.001));
    await tester.pumpAndSettle();
    expect(tester.getSize(transition).height, 100);
    collapsed = true;
    await tester.pumpWidget(content());
    await tester.pumpAndSettle();
    expect(tester.getSize(transition).height, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空闲悬停变化主动请求绘制帧，并合并快速进出', (tester) async {
    final key = GlobalKey<_HoverProbeState>();
    await tester.pumpWidget(MaterialApp(home: _HoverProbe(key: key)));
    await tester.pumpAndSettle();
    key.currentState!.setOpenHandHovered(true);
    key.currentState!.setOpenHandHovered(false);
    key.currentState!.setOpenHandHovered(true);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('悬停'), findsOneWidget);
    key.currentState!.setOpenHandHovered(false);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('启动前排队的提示条在依赖就绪后展示', (tester) async {
    OpenHandGlobalSnackBarHost.showSnackBar(const SnackBar(content: Text('启动提示')));
    await tester.pumpWidget(const MaterialApp(home: OpenHandGlobalSnackBarHost()));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('启动提示'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('空闲时延迟提示主动请求绘制帧', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const OpenHandGlobalSnackBarHost();
    })));
    await tester.pumpAndSettle();
    flashOpenHandSnack(context, '延迟提示');
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('延迟提示'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('提示条退场时关闭动效，立即清理并展示下一条', (tester) async {
    var reduceMotion = false;
    Widget content() => MaterialApp(home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: const OpenHandGlobalSnackBarHost(),
    ));
    await tester.pumpWidget(content());
    OpenHandGlobalSnackBarHost.showSnackBar(const SnackBar(content: Text('第一条')));
    OpenHandGlobalSnackBarHost.showSnackBar(const SnackBar(content: Text('第二条')));
    await tester.pumpAndSettle();
    OpenHandGlobalSnackBarHost.hideCurrent();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    reduceMotion = true;
    await tester.pumpWidget(content());
    await tester.pump();
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('提示条可见回调失败仍会按时退场', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OpenHandGlobalSnackBarHost()));
    OpenHandGlobalSnackBarHost.showSnackBar(SnackBar(
      content: const Text('失败回调'),
      duration: kOpenHandSnackBarBriefDuration,
      onVisible: () => throw StateError('可见回调失败'),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isStateError);
    await tester.pump(kOpenHandSnackBarBriefDuration);
    await tester.pumpAndSettle();
    expect(find.text('失败回调'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
