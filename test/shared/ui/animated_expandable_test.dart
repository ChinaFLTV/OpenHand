import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_expandable.dart';

void main() {
  testWidgets('AnimatedExpandable normalizes invalid top padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedExpandable(
          expanded: true,
          bodyTopPadding: double.nan,
          header: const Text('header'),
          body: (_) => const Text('body'),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('header'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('AnimatedExpandChevron normalizes invalid icon size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedExpandChevron(expanded: true, size: double.nan),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.keyboard_arrow_right_rounded), findsOneWidget);
  });
}
