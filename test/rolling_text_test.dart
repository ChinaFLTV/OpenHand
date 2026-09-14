import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/rolling_text.dart';

void main() {
  const style = TextStyle(fontSize: 20);

  Widget host(
    String value, {
    Duration duration = const Duration(milliseconds: 360),
    bool disableAnimations = false,
    bool tickerEnabled = true,
    TextStyle textStyle = style,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: disableAnimations,
          textScaler: textScaler,
        ),
        child: TickerMode(
          enabled: tickerEnabled,
          child: Center(
            child: RollingText(
              text: value,
              style: textStyle,
              duration: duration,
            ),
          ),
        ),
      ),
    );
  }

  String displayed(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(RollingText),
          matching: find.byType(Text),
        ),
      )
      .map((text) => text.data ?? '')
      .join();

  Future<void> queueValues(WidgetTester tester) async {
    await tester.pumpWidget(host('111'));
    await tester.pumpWidget(host('222'));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(host('333'));
  }

  testWidgets('关闭动效立即显示最后一次更新，不丢失合并值', (tester) async {
    await queueValues(tester);
    await tester.pumpWidget(host('333', disableAnimations: true));
    expect(displayed(tester), '333');
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('停用时钟后恢复，不重放旧值', (tester) async {
    await queueValues(tester);
    await tester.pumpWidget(host('333', tickerEnabled: false));
    expect(displayed(tester), '333');
    await tester.pumpWidget(host('333'));
    expect(displayed(tester), '333');
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('动画中将时长归零立即停止并显示最新值', (tester) async {
    await queueValues(tester);
    await tester.pumpWidget(host('333', duration: Duration.zero));
    expect(displayed(tester), '333');
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('长数字直接渲染，不创建逐位动画或大量子组件', (tester) async {
    await queueValues(tester);
    final value = '1234567890' * 3;
    await tester.pumpWidget(host(value));
    expect(displayed(tester), value);
    expect(tester.hasRunningAnimations, isFalse);
    expect(
      find.descendant(
        of: find.byType(RollingText),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );
  });

  testWidgets('高频更新最终收敛到最新值并释放时钟', (tester) async {
    await queueValues(tester);
    await tester.pumpAndSettle();
    expect(displayed(tester), '333');
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('位数缩减与小数切换完成后不残留旧数字', (tester) async {
    await tester.pumpWidget(host('1,000.25 MB'));
    await tester.pumpWidget(host('9.5 MB'));
    await tester.pumpAndSettle();
    expect(displayed(tester), '9.5 MB');
    await tester.pumpWidget(host(''));
    expect(displayed(tester), isEmpty);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('数字减少时无障碍标签立即更新，动画期间卸载无泄漏', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(host('99'));
      await tester.pumpWidget(host('12'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.bySemanticsLabel('12'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      expect(tester.hasRunningAnimations, isFalse);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('数字动画使用直接矩阵变换，不创建图像过滤层', (tester) async {
    await tester.pumpWidget(host('123'));
    await tester.pumpWidget(host('456'));
    await tester.pump(const Duration(milliseconds: 80));
    final transforms = tester.renderObjectList<RenderTransform>(
      find.descendant(
        of: find.byType(RollingText),
        matching: find.byType(Transform),
      ),
    );
    expect(transforms, isNotEmpty);
    expect(
      transforms.every((transform) => transform.filterQuality == null),
      isTrue,
    );
  });

  testWidgets('字宽缓存区分实际字号处的非线性缩放', (tester) async {
    Future<double> digitWidth(TextScaler scaler) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(host('1', textScaler: scaler));
      await tester.pumpWidget(host('2', textScaler: scaler));
      await tester.pump(const Duration(milliseconds: 80));
      final digit = find.descendant(
        of: find.byType(RollingText),
        matching: find.byType(ClipRect),
      );
      return tester.getSize(digit).width;
    }

    final regular = await digitWidth(TextScaler.noScaling);
    final enlarged = await digitWidth(const _NonlinearScaler());
    expect(enlarged, closeTo(regular * 2, 0.01));
  });
}

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double scale(double fontSize) => fontSize < 50 ? fontSize * 2 : fontSize;

  @override
  double get textScaleFactor => 2;
}
