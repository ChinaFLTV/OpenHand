import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_token_usage_capsule.dart';

void main() {
  testWidgets('缓存命中率未知时仅保留上下文圆环', (tester) async {
    Future<void> pumpCapsule(bool showCacheHitRate) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: OpenHandTokenUsageCapsule(
                showCacheHitRate: showCacheHitRate,
                cacheHitRatio: 0.76,
                contextWindowRatio: 0.24,
                contextWindowTooltip: '上下文窗口 24%',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpCapsule(false);
    final compactWidth = tester
        .getSize(find.byType(OpenHandTokenUsageCapsule))
        .width;
    expect(find.byIcon(Icons.bolt_rounded), findsNothing);
    expect(find.byIcon(Icons.savings_rounded), findsNothing);
    expect(find.byIcon(Icons.confirmation_number_rounded), findsNothing);
    expect(find.byType(OpenHandAnimatedContextUsageRing), findsOneWidget);

    await pumpCapsule(true);
    final expandedWidth = tester
        .getSize(find.byType(OpenHandTokenUsageCapsule))
        .width;
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.savings_rounded), findsOneWidget);
    expect(expandedWidth, greaterThan(compactWidth));

    await pumpCapsule(false);
    expect(
      tester.getSize(find.byType(OpenHandTokenUsageCapsule)).width,
      compactWidth,
    );
  });
}
