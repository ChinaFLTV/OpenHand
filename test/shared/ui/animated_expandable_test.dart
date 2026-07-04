import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_expandable.dart';

void main() {
  Finder expandableDescendant(Type type) {
    return find.descendant(
      of: find.byType(AnimatedExpandable),
      matching: find.byType(type),
    );
  }

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

  testWidgets('AnimatedExpandable renders directly when ticker is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: false,
          child: AnimatedExpandable(
            expanded: true,
            header: const Text('header'),
            body: (_) => const Text('body'),
          ),
        ),
      ),
    );

    expect(find.text('header'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
    expect(expandableDescendant(AnimatedSize), findsNothing);
    expect(expandableDescendant(AnimatedSwitcher), findsNothing);
  });

  testWidgets('AnimatedExpandable renders directly when animations disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: AnimatedExpandable(
            expanded: false,
            header: const Text('header'),
            body: (_) => const Text('body'),
          ),
        ),
      ),
    );

    expect(find.text('header'), findsOneWidget);
    expect(find.text('body'), findsNothing);
    expect(expandableDescendant(AnimatedSize), findsNothing);
    expect(expandableDescendant(AnimatedSwitcher), findsNothing);
  });

  testWidgets(
    'AnimatedExpandChevron renders directly when ticker is disabled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TickerMode(
            enabled: false,
            child: AnimatedExpandChevron(expanded: true),
          ),
        ),
      );

      expect(find.byIcon(Icons.keyboard_arrow_right_rounded), findsOneWidget);
      expect(find.byType(AnimatedRotation), findsNothing);
    },
  );
}
