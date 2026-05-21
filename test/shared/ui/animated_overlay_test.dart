import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_overlay.dart';

void main() {
  testWidgets(
    'animated overlay skips transitions when animations are disabled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: AnimatedOverlayContent(child: Text('Overlay')),
          ),
        ),
      );

      expect(find.text('Overlay'), findsOneWidget);
      final overlay = find.byType(AnimatedOverlayContent);
      expect(
        find.descendant(of: overlay, matching: find.byType(FadeTransition)),
        findsNothing,
      );
      expect(
        find.descendant(of: overlay, matching: find.byType(ScaleTransition)),
        findsNothing,
      );
    },
  );

  testWidgets('fade overlay skips transitions when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: FadeInOverlayContent(child: Text('Popup')),
        ),
      ),
    );

    expect(find.text('Popup'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FadeInOverlayContent),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });
}
