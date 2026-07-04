import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
