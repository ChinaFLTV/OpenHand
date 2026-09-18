import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/oh_pill.dart';
import 'package:openhand/shared/ui/openhand_animated_chip_wrap.dart';
import 'package:openhand/shared/ui/openhand_form_fields.dart';

const _motion = DialogAnimationSettings(
  entranceStyle: DialogAnimationStyle.springScale,
  exitStyle: DialogAnimationStyle.fade,
  durationMs: 300,
);

Widget _scene(
  List<String> ids, {
  double width = 220,
  bool reducedMotion = false,
  bool tickers = true,
  DialogAnimationSettings settings = _motion,
  String suffix = '',
  VoidCallback? onTap,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: TickerMode(
      enabled: tickers,
      child: Directionality(
        textDirection: direction,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: OpenHandAnimatedChipWrap(
              key: const ValueKey('group'),
              settings: settings,
              topSpacing: 12,
              children: [
                for (final id in ids)
                  GestureDetector(
                    key: ValueKey(id),
                    onTap: onTap,
                    child: SizedBox(
                      width: 100,
                      height: 32,
                      child: Text('$id$suffix'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('全部胶囊样式都能完成进退场与中途反转', (tester) async {
    for (final style in DialogAnimationStyle.values) {
      final settings = _motion.copyWith(entranceStyle: style, exitStyle: style);
      await tester.pumpWidget(_scene([], settings: settings));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_scene(['a', 'b'], settings: settings));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(_scene(['b'], settings: settings));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpWidget(_scene(['a', 'b'], settings: settings));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget, reason: style.name);
      await tester.pumpWidget(_scene([], settings: settings));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('group'))).height, 0);
      expect(tester.takeException(), isNull, reason: style.name);
      expect(tester.binding.transientCallbackCount, 0);
    }
  });

  testWidgets('仅启用退场时，空白回收仍遵循退场动画', (tester) async {
    final settings = _motion.copyWith(entranceStyle: DialogAnimationStyle.none);
    await tester.pumpWidget(_scene(['a'], settings: settings));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_scene([], settings: settings));
    await tester.pump();
    await tester.pump(settings.exitDuration + const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final height = tester.getSize(find.byKey(const ValueKey('group'))).height;
    expect(height, greaterThan(0));
    expect(height, lessThan(44));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('group'))).height, 0);
  });

  testWidgets('实际卡片在窄窗口和大字号下换行，空组不留下间距', (tester) async {
    Widget card(bool visible) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 260,
            child: OpenHandFeatureListCard(
              identity: const Text('卡片标题'),
              statusPills: [
                if (visible)
                  const OpenHandStatusPill(
                    key: ValueKey('status'),
                    icon: Icons.check_circle_outline,
                    label: '服务运行中',
                    color: Colors.green,
                  ),
              ],
              factChips: [
                if (visible)
                  const OpenHandFactChip(
                    key: ValueKey('directory'),
                    icon: Icons.folder_outlined,
                    label: '/很长的目录路径/需要正确约束宽度/配置文件',
                    color: Colors.blue,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(card(false));
    await tester.pumpAndSettle();
    final originalSize = tester.getSize(find.byType(OpenHandFeatureListCard));
    await tester.pumpWidget(card(true));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(OpenHandFeatureListCard)).height,
      greaterThan(originalSize.height),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(card(false));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(OpenHandFeatureListCard)), originalSize);
    expect(tester.takeException(), isNull);
  });

  testWidgets('退场保留内容、禁止点击，结束后回收顶部留白', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_scene(['a'], onTap: () => taps++));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a'));
    expect(taps, 1);
    await tester.pumpWidget(_scene([], onTap: () => taps++));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('a'), findsOneWidget);
    await tester.tap(find.text('a'), warnIfMissed: false);
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(find.text('a'), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('group'))).height, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('同帧增删立即进场，快速反转不重复、不误删', (tester) async {
    await tester.pumpWidget(_scene(['a', 'b']));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_scene(['b', 'c']));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('a'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
    await tester.pumpWidget(_scene(['a', 'c']));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(_scene(['a', 'b']));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(find.text('c'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('同键内容更新保留状态，不重播进场', (tester) async {
    await tester.pumpWidget(_scene(['a']));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_scene(['a'], suffix: '-更新'));
    expect(find.text('a-更新'), findsOneWidget);
    expect(find.text('a'), findsNothing);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('首屏胶囊随卡片稳定落位，后续新增才播放进场', (tester) async {
    await tester.pumpWidget(_scene(['a']));
    await tester.pump();
    expect(find.text('a'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_scene(['a', 'b']));
    await tester.pump();
    expect(find.text('b'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('删除触发的换行逐帧移动，最终没有残留占位', (tester) async {
    await tester.pumpWidget(_scene(['a', 'b', 'c']));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('c'));
    await tester.pumpWidget(_scene(['b', 'c']));
    await tester.pump();
    await tester.pump(_motion.exitDuration + const Duration(milliseconds: 1));
    final start = tester.getTopLeft(find.text('c'));
    expect(start.dy, before.dy);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final during = tester.getTopLeft(find.text('c'));
    expect(during.dy, lessThan(start.dy));
    expect(during.dy, greaterThan(12));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('c')).dy, 12);
    expect(tester.getSize(find.byKey(const ValueKey('group'))).height, 44);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭动画或 TickerMode 时即时收尾，不留下运行中的动画', (tester) async {
    for (final mode in ['reduce', 'ticker', 'setting']) {
      await tester.pumpWidget(_scene(['a', 'b']));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_scene(['b']));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(
        _scene(
          ['b'],
          reducedMotion: mode == 'reduce',
          tickers: mode != 'ticker',
          settings: mode == 'setting'
              ? OpenHandMotionDefaults.disabled
              : _motion,
        ),
      );
      await tester.pump();
      expect(find.text('a'), findsNothing);
      expect(
        await tester.pumpAndSettle(const Duration(milliseconds: 1)),
        lessThanOrEqualTo(2),
      );
      expect(tester.getTopLeft(find.text('b')).dx, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('窄窗口与从右至左布局可以重排，中途卸载无资源残留', (tester) async {
    await tester.pumpWidget(_scene(['a', 'b', 'c']));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _scene(['a', 'b', 'c'], width: 110, direction: TextDirection.rtl),
    );
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('c')).dy,
      greaterThan(tester.getTopLeft(find.text('b')).dy),
    );
    await tester.pumpWidget(_scene(['b']));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
