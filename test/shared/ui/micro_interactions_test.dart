import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/highlight_pulse.dart';
import 'package:openhand/shared/ui/hover_lift.dart';
import 'package:openhand/shared/ui/micro_press_feedback.dart';

void main() {
  testWidgets('MicroPressFeedback normalizes invalid scale values', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MicroPressFeedback(scale: double.nan, child: Text('press')),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('press'), findsOneWidget);
  });

  testWidgets('MicroPressFeedback bounds extreme pressed scales', (
    tester,
  ) async {
    Future<double> pressedScaleFor(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: MicroPressFeedback(scale: scale, child: const Text('press')),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('press')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.up();
      final transform = tester.widget<Transform>(
        find.byWidgetPredicate(
          (widget) => widget is Transform && widget.child is Text,
        ),
      );
      return transform.transform.storage.first;
    }

    expect(await pressedScaleFor(10), 1.0);
    expect(await pressedScaleFor(0.01), kOpenHandMicroPressMinScale);
  });

  testWidgets('HoverLift normalizes invalid lift distances', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HoverLift(liftDistance: double.nan, child: Text('hover')),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('hover'), findsOneWidget);
  });

  testWidgets('HighlightPulse normalizes invalid heights', (tester) async {
    final signal = ValueNotifier<int>(0);
    addTearDown(signal.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HighlightPulse(signal: signal, height: double.nan),
      ),
    );
    signal.value += 1;
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(HighlightPulse), findsOneWidget);
  });
}
