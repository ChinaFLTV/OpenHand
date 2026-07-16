import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_animated_title_text.dart';

void main() {
  Widget buildTitle(String text, {bool disableAnimations = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: SizedBox(
            width: 260,
            child: OpenHandAnimatedTitleText(text: text),
          ),
        ),
      ),
    );
  }

  testWidgets('标题更新时旧标题平滑退场且新标题完整进场', (tester) async {
    await tester.pumpWidget(buildTitle('旧标题'));
    await tester.pumpWidget(buildTitle('新的会话标题'));

    expect(find.text('旧标题'), findsOneWidget);
    expect(find.text('新的会话标题'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('旧标题'), findsOneWidget);
    expect(find.text('新的会话标题'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('旧标题'), findsNothing);
    expect(find.text('新的会话标题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('连续标题更新只保留最近一组过渡文本', (tester) async {
    await tester.pumpWidget(buildTitle('标题 A'));
    await tester.pumpWidget(buildTitle('标题 B'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpWidget(buildTitle('标题 C'));

    expect(find.text('标题 A'), findsNothing);
    expect(find.text('标题 B'), findsOneWidget);
    expect(find.text('标题 C'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('标题 B'), findsNothing);
    expect(find.text('标题 C'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画时标题立即切换且不保留旧文本', (tester) async {
    await tester.pumpWidget(buildTitle('旧标题', disableAnimations: true));
    await tester.pumpWidget(buildTitle('新标题', disableAnimations: true));

    expect(find.text('旧标题'), findsNothing);
    expect(find.text('新标题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
