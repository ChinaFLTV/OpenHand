import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_overlay.dart';

void main() {
  testWidgets('AnimatedOverlayContent applies custom scale begin', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedOverlayContent(
          customDuration: Duration(seconds: 1),
          scaleBegin: 0.82,
          child: SizedBox.shrink(),
        ),
      ),
    );

    final scale = tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byType(AnimatedOverlayContent),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(scale.scale.value, closeTo(0.82, 0.001));
  });

  testWidgets('AnimatedOverlayContent falls back for invalid scale begin', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedOverlayContent(
          customDuration: Duration(seconds: 1),
          scaleBegin: double.nan,
          child: SizedBox.shrink(),
        ),
      ),
    );

    final scale = tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byType(AnimatedOverlayContent),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(scale.scale.value, closeTo(0.95, 0.001));
  });

  testWidgets('AnimatedOverlayContent bounds extreme scale begin values', (
    tester,
  ) async {
    Future<double> scaleValueFor(double scaleBegin) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedOverlayContent(
            customDuration: const Duration(seconds: 1),
            scaleBegin: scaleBegin,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      final scale = tester.widget<ScaleTransition>(
        find.descendant(
          of: find.byType(AnimatedOverlayContent),
          matching: find.byType(ScaleTransition),
        ),
      );
      return scale.scale.value;
    }

    expect(await scaleValueFor(10), closeTo(1.0, 0.001));
    expect(await scaleValueFor(0.01), closeTo(0.5, 0.001));
  });

  testWidgets('AnimatedOverlayContent syncs updated animation settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedOverlayContent(
          customDuration: Duration(seconds: 1),
          child: Text('overlay'),
        ),
      ),
    );
    expect(find.byType(ScaleTransition), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedOverlayContent(
          customSettings: DialogAnimationSettings(
            entranceStyle: DialogAnimationStyle.none,
            exitStyle: DialogAnimationStyle.none,
          ),
          child: Text('overlay'),
        ),
      ),
    );

    expect(find.byType(ScaleTransition), findsNothing);
    expect(find.text('overlay'), findsOneWidget);
  });
}
