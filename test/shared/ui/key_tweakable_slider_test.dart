import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/key_tweakable_slider.dart';

void main() {
  testWidgets('KeyTweakableSlider orders reversed bounds safely', (
    tester,
  ) async {
    int? changedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: KeyTweakableSlider(
          value: 5,
          min: 10,
          max: 1,
          onChanged: (value) async {
            changedValue = value;
          },
          buildSlider: (_, value) {
            return Focus(
              autofocus: true,
              child: Text('value=$value', textDirection: TextDirection.ltr),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('value=5'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(changedValue, 6);
  });

  testWidgets('KeyTweakableSlider clamps displayed value into safe bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KeyTweakableSlider(
          value: 99,
          min: 1,
          max: 10,
          onChanged: (_) async {},
          buildSlider: (_, value) {
            return Text('value=$value', textDirection: TextDirection.ltr);
          },
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('value=10'), findsOneWidget);
  });
}
