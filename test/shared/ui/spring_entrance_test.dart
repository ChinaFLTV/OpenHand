import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/spring_entrance.dart';

void main() {
  Finder springDescendant(Type type) {
    return find.descendant(
      of: find.byType(OpenHandSpringEntrance),
      matching: find.byType(type),
    );
  }

  testWidgets('OpenHandSpringEntrance applies configured entrance geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OpenHandSpringEntrance(
          duration: Duration(seconds: 1),
          opacityIntervalEnd: 0.6,
          scaleBegin: 0.82,
          slideBegin: Offset(0, 0.08),
          child: Text('entry'),
        ),
      ),
    );

    final scale = tester.widget<ScaleTransition>(
      springDescendant(ScaleTransition),
    );
    final slide = tester.widget<SlideTransition>(
      springDescendant(SlideTransition),
    );

    expect(springDescendant(FadeTransition), findsOneWidget);
    expect(scale.scale.value, closeTo(0.82, 0.001));
    expect(slide.position.value.dy, closeTo(0.08, 0.001));
  });

  testWidgets('OpenHandSpringEntrance bounds extreme scale begin values', (
    tester,
  ) async {
    Future<double> scaleValueFor(double scaleBegin) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OpenHandSpringEntrance(
            duration: const Duration(seconds: 1),
            scaleBegin: scaleBegin,
            child: const Text('entry'),
          ),
        ),
      );
      final scale = tester.widget<ScaleTransition>(
        springDescendant(ScaleTransition),
      );
      return scale.scale.value;
    }

    expect(await scaleValueFor(12), closeTo(1.0, 0.001));
    expect(await scaleValueFor(0.01), closeTo(0.5, 0.001));
    expect(await scaleValueFor(double.nan), closeTo(1.0, 0.001));
  });

  testWidgets('OpenHandSpringEntrance respects disabled animations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: OpenHandSpringEntrance(child: Text('entry')),
        ),
      ),
    );

    expect(find.text('entry'), findsOneWidget);
    expect(springDescendant(FadeTransition), findsNothing);
    expect(springDescendant(ScaleTransition), findsNothing);
    expect(springDescendant(SlideTransition), findsNothing);
  });

  testWidgets(
    'OpenHandSpringEntrance renders directly when ticker is disabled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TickerMode(
            enabled: false,
            child: OpenHandSpringEntrance(child: Text('entry')),
          ),
        ),
      );

      expect(find.text('entry'), findsOneWidget);
      expect(springDescendant(FadeTransition), findsNothing);
      expect(springDescendant(ScaleTransition), findsNothing);
      expect(springDescendant(SlideTransition), findsNothing);
    },
  );
}
