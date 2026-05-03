import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/widgets/first_frame_pulse_box.dart';
import 'package:openhand/shared/widgets/highlight_pulse.dart';

void main() {
  testWidgets('renders child immediately and overlays a HighlightPulse',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FirstFramePulseBox(
            child: SizedBox(
              key: ValueKey('child'),
              width: 200,
              height: 40,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('child')), findsOneWidget);
    expect(find.byType(HighlightPulse), findsOneWidget);
  });

  testWidgets('fires pulse exactly once after the first frame',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FirstFramePulseBox(
            child: SizedBox(width: 200, height: 40),
          ),
        ),
      ),
    );

    final pulseFinder = find.byType(HighlightPulse);
    final HighlightPulse pulse = tester.widget(pulseFinder);
    // pumpWidget already runs the post-frame callback, so the signal has
    // incremented exactly once by now.
    expect(pulse.signal.value, 1, reason: 'first frame increments signal once');

    // Settle decay (~660ms). Signal must NOT increment again.
    await tester.pump(const Duration(milliseconds: 800));
    expect(pulse.signal.value, 1,
        reason: 'pulse only fires once per State instance');
  });

  testWidgets('honors reduceMotion via MediaQuery (HighlightPulse opts out)',
      (tester) async {
    // We don't assert the internal animation state — HighlightPulse already
    // tests its own reduceMotion path. Here we just confirm no exception is
    // thrown when disableAnimations is true and the box still renders both
    // child and pulse overlay.
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: FirstFramePulseBox(
              child: SizedBox(
                key: ValueKey('child-rm'),
                width: 100,
                height: 24,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byKey(const ValueKey('child-rm')), findsOneWidget);
    expect(find.byType(HighlightPulse), findsOneWidget);
  });

  testWidgets('disposing before the postFrameCallback runs is safe',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FirstFramePulseBox(
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      ),
    );
    // Replace with a different tree before pumping the post-frame callback.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    // Should not throw.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FirstFramePulseBox), findsNothing);
  });
}
