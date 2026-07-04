import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/rolling_text.dart';

void main() {
  testWidgets('RollingText renders visible character clusters as slots', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: RollingText(text: 'A👍🏽é', style: TextStyle(fontSize: 14)),
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
    expect(find.text('👍🏽'), findsOneWidget);
    expect(find.text('é'), findsOneWidget);
    expect(find.byType(Text), findsNWidgets(3));
  });

  testWidgets('RollingText renders directly when ticker is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: TickerMode(
            enabled: false,
            child: RollingText(text: '123', style: TextStyle(fontSize: 14)),
          ),
        ),
      ),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsNothing);
  });

  testWidgets('RollingText renders directly when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: RollingText(text: 'OK', style: TextStyle(fontSize: 14)),
          ),
        ),
      ),
    );

    expect(find.text('O'), findsOneWidget);
    expect(find.text('K'), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsNothing);
  });
}
