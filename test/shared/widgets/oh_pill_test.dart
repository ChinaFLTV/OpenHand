import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/shared/widgets/oh_pill.dart';

void main() {
  group('OhPill', () {
    testWidgets('renders icon + label without InkWell when onTap is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OhPill(icon: Icons.star_rounded, label: 'Hello'),
          ),
        ),
      );

      expect(find.text('Hello'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('wraps in InkWell and forwards onTap when callback provided', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OhPill(
              icon: Icons.history_toggle_off_rounded,
              label: 'Cancel 3s',
              onTap: () => taps += 1,
            ),
          ),
        ),
      );

      expect(find.byType(InkWell), findsOneWidget);
      await tester.tap(find.byType(OhPill));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('foregroundColor overrides icon color', (tester) async {
      const amber = Color(0xFFF57F17);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OhPill(
              icon: Icons.warning_rounded,
              label: 'Heads up',
              foregroundColor: amber,
            ),
          ),
        ),
      );

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.warning_rounded));
      expect(iconWidget.color, amber);
    });

    testWidgets('label uses single line with fade overflow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: OhPill(
                icon: Icons.label_outline_rounded,
                label: 'A long label',
              ),
            ),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.byType(Text));
      expect(textWidget.maxLines, 1);
      expect(textWidget.overflow, TextOverflow.fade);
      expect(textWidget.softWrap, isFalse);
    });
  });
}
