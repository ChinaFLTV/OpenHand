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
