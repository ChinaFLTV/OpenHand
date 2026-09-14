import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/openhand_animated_sliver_list.dart';
import 'package:openhand/shared/ui/openhand_animated_title_text.dart';

void main() {
  const motion = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.springScale,
    exitStyle: DialogAnimationStyle.springScale,
    durationMs: 120,
  );
  Widget list(List<String> ids, {bool disabled = false}) => MaterialApp(
    home: CustomScrollView(
      slivers: [
        OpenHandAnimatedSliverList(
          settings: disabled ? OpenHandMotionDefaults.disabled : motion,
          children: [
            for (final id in ids)
              SizedBox(
                key: ValueKey(id),
                height: 48,
                child: TextButton(onPressed: () {}, child: Text(id)),
              ),
          ],
        ),
      ],
    ),
  );

  testWidgets('新增条目逐帧展开，删除保留内容直至退场结束', (tester) async {
    await tester.pumpWidget(list(['甲']));
    await tester.pumpAndSettle();
    final firstElement = find.text('甲').evaluate().single;
    await tester.pumpWidget(list(['乙', '甲']));
    final before = tester.getTopLeft(find.text('甲')).dy;
    await tester.pump(const Duration(milliseconds: 60));
    final during = tester.getTopLeft(find.text('甲')).dy;
    expect(during, greaterThan(before));
    await tester.pumpAndSettle();
    expect(find.text('甲').evaluate().single, same(firstElement));
    await tester.pumpWidget(list(['甲']));
    expect(find.text('乙'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('乙'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('乙'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('退场中重新显示沿原状态恢复，再次删除不会残留', (tester) async {
    await tester.pumpWidget(list(['甲', '乙']));
    await tester.pumpAndSettle();
    final element = find.text('乙').evaluate().single;
    await tester.pumpWidget(list(['甲']));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(list(['甲', '乙']));
    expect(find.text('乙').evaluate().single, same(element));
    await tester.pumpAndSettle();
    await tester.pumpWidget(list(['甲']));
    await tester.pumpAndSettle();
    expect(find.text('乙'), findsNothing);
  });

  testWidgets('重排保留条目状态并连续移动到新位置', (tester) async {
    await tester.pumpWidget(list(['甲', '乙', '丙']));
    await tester.pumpAndSettle();
    final element = find.text('丙').evaluate().single;
    final before = tester.getTopLeft(find.text('丙')).dy;
    await tester.pumpWidget(list(['丙', '甲', '乙']));
    expect(tester.getTopLeft(find.text('丙')).dy, closeTo(before, 0.01));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('丙')).dy, lessThan(before));
    expect(find.text('丙').evaluate().single, same(element));
  });

  testWidgets('关闭动效立即移除退场内容，离屏删除不会留下计时器', (tester) async {
    await tester.pumpWidget(list(List.generate(40, (i) => '$i')));
    expect(find.byType(TextButton).evaluate().length, lessThan(40));
    await tester.pumpAndSettle();
    await tester.pumpWidget(list(['0']));
    await tester.pumpWidget(list(['0'], disabled: true));
    final sliver = tester.widget<SliverList>(find.byType(SliverList));
    expect(sliver.delegate.estimatedChildCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  Widget title(String value, {bool disabled = false, bool initial = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disabled),
          child: Center(
            child: OpenHandAnimatedTitleText(
              text: value,
              tooltip: false,
              animateOnMount: initial,
            ),
          ),
        ),
      );

  testWidgets('快速连续改名只保留最新待显示标题，当前过渡不中断', (tester) async {
    await tester.pumpWidget(title('旧标题'));
    await tester.pumpWidget(title('中间标题'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(title('待合并标题'));
    await tester.pumpWidget(title('最终标题'));
    expect(find.text('旧标题'), findsOneWidget);
    expect(find.text('中间标题'), findsOneWidget);
    expect(find.text('待合并标题'), findsNothing);
    expect(find.byType(Text), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.text('最终标题'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('标题关闭动效立即同步最新值，首次显示支持淡入', (tester) async {
    await tester.pumpWidget(title('新窗口标题', initial: true));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(title('更新标题', initial: true));
    await tester.pumpWidget(title('最终标题', disabled: true));
    expect(find.text('最终标题'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
