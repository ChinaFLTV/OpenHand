import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_animated_title_text.dart';

void main() {
  const firstTitle = '搜索星舰最新发射信息';
  const secondTitle = '整理本周产品发布计划与待办事项';
  const thirdTitle = '检查桌面端构建结果';

  Widget buildApp({
    required String title,
    double width = 186,
    bool disableAnimations = false,
    bool tickerEnabled = true,
    TextStyle? style,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: TickerMode(
          enabled: tickerEnabled,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: OpenHandAnimatedTitleText(
                  text: title,
                  style:
                      style ??
                      const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('固定宽度下平滑切换中文省略标题', (tester) async {
    await tester.pumpWidget(buildApp(title: firstTitle));
    await tester.pumpWidget(buildApp(title: secondTitle));

    expect(find.text(firstTitle), findsOneWidget);
    expect(find.text(secondTitle), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    expect(find.text(firstTitle), findsNothing);
    expect(find.text(secondTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('动画中连续和往返更新不会复用段落身份', (tester) async {
    await tester.pumpWidget(buildApp(title: firstTitle));
    await tester.pumpWidget(buildApp(title: secondTitle));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(buildApp(title: thirdTitle, width: 172));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(
      buildApp(
        title: firstTitle,
        width: 204,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    expect(find.text(firstTitle), findsOneWidget);
    expect(find.text(secondTitle), findsNothing);
    expect(find.text(thirdTitle), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动态效果时立即替换且不保留退出标题', (tester) async {
    await tester.pumpWidget(buildApp(title: firstTitle));
    await tester.pumpWidget(
      buildApp(title: secondTitle, disableAnimations: true),
    );

    expect(find.text(firstTitle), findsNothing);
    expect(find.text(secondTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TickerMode 关闭时立即替换且不启动动画', (tester) async {
    await tester.pumpWidget(buildApp(title: firstTitle));
    await tester.pumpWidget(buildApp(title: secondTitle, tickerEnabled: false));

    expect(find.text(firstTitle), findsNothing);
    expect(find.text(secondTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空标题不创建 Tooltip，非空标题保留完整提示', (tester) async {
    await tester.pumpWidget(buildApp(title: ''));
    expect(find.byType(Tooltip), findsNothing);

    await tester.pumpWidget(
      buildApp(title: firstTitle, disableAnimations: true),
    );
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, firstTitle);
    expect(tester.takeException(), isNull);
  });
}
