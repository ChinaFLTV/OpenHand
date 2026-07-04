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
}
