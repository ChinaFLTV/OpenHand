import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/widgets/appear_once.dart';

void main() {
  group('AppearOnce', () {
    testWidgets('fades in from 0 to full opacity over its duration', (
      tester,
    ) async {
      const duration = Duration(milliseconds: 200);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppearOnce(
            duration: duration,
            child: SizedBox(width: 100, height: 50),
          ),
        ),
      );

      // First frame: opacity should start at (or very near) 0.
      final initialOpacity = _findFadeOpacity(tester);
      expect(initialOpacity, isNotNull);
      expect(initialOpacity, lessThan(0.05));

      // Halfway through.
      await tester.pump(const Duration(milliseconds: 100));
      final midOpacity = _findFadeOpacity(tester);
      expect(midOpacity, isNotNull);
      expect(midOpacity, greaterThan(0.2));
      expect(midOpacity, lessThan(0.95));

      // After the animation finishes the wrapper should drop both the
      // FadeTransition and its internal paint-time translate render
      // object so it adds zero baseline cost.
      await tester.pump(duration + const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.byType(FadeTransition), findsNothing);
    });

    testWidgets('disposes its ticker after completing', (tester) async {
      const duration = Duration(milliseconds: 120);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppearOnce(
            duration: duration,
            child: SizedBox(width: 1, height: 1),
          ),
        ),
      );

      await tester.pump(duration + const Duration(milliseconds: 50));
      await tester.pump();

      // After completion no Tickers should still be active for AppearOnce.
      // tester.binding.transientCallbackCount ticks include any frame
      // callbacks scheduled by the ticker; settle confirms no scheduled
      // frames remain.
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('does NOT re-trigger animation when parent rebuilds with '
        'the same key', (tester) async {
      final key = GlobalKey();
      Widget build(int label) => Directionality(
        textDirection: TextDirection.ltr,
        child: AppearOnce(
          key: key,
          duration: const Duration(milliseconds: 80),
          child: Text('$label'),
        ),
      );

      await tester.pumpWidget(build(1));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byType(FadeTransition), findsNothing);

      // Rebuild parent with the same key + a different child label.
      await tester.pumpWidget(build(2));
      await tester.pump();
      // Should NOT have introduced a new FadeTransition — the State is
      // preserved, the animation already completed and the fast-path
      // returns the child directly.
      expect(find.byType(FadeTransition), findsNothing);
      expect(find.text('2'), findsOneWidget);
    });
  });
}

double? _findFadeOpacity(WidgetTester tester) {
  final fades = find.byType(FadeTransition).evaluate();
  if (fades.isEmpty) return null;
  final widget = fades.first.widget as FadeTransition;
  return widget.opacity.value;
}
