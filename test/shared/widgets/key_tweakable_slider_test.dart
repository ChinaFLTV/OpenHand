import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/widgets/key_tweakable_slider.dart';

Future<void> _pumpHarness(
  WidgetTester tester, {
  required int initial,
  required int min,
  required int max,
  required void Function(int) onChanged,
}) async {
  int current = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            return KeyTweakableSlider(
              value: current,
              min: min,
              max: max,
              onChanged: (next) async {
                onChanged(next);
                setState(() => current = next);
              },
              buildSlider: (context, value) => Slider(
                value: value.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min,
                onChanged: (v) => setState(() => current = v.round()),
              ),
            );
          },
        ),
      ),
    ),
  );
  // Take focus on our wrapper's Focus node (not Slider's internal one).
  final focusFinder = find.descendant(
    of: find.byType(KeyTweakableSlider),
    matching: find.byType(Focus),
  );
  final Focus focusWidget = tester.widget<Focus>(focusFinder.first);
  focusWidget.focusNode!.requestFocus();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('arrowRight increments value by 1', (tester) async {
    final emitted = <int>[];
    await _pumpHarness(
      tester,
      initial: 5,
      min: 1,
      max: 10,
      onChanged: emitted.add,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(emitted, [6]);
  });

  testWidgets('arrowUp also increments by 1', (tester) async {
    final emitted = <int>[];
    await _pumpHarness(
      tester,
      initial: 5,
      min: 1,
      max: 10,
      onChanged: emitted.add,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(emitted, [6]);
  });

  testWidgets('arrowLeft decrements by 1', (tester) async {
    final emitted = <int>[];
    await _pumpHarness(
      tester,
      initial: 5,
      min: 1,
      max: 10,
      onChanged: emitted.add,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(emitted, [4]);
  });

  testWidgets('arrowDown also decrements by 1', (tester) async {
    final emitted = <int>[];
    await _pumpHarness(
      tester,
      initial: 5,
      min: 1,
      max: 10,
      onChanged: emitted.add,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(emitted, [4]);
  });

  testWidgets('clamps at max — no emission when already at max', (tester) async {
    final emitted = <int>[];
    await _pumpHarness(
      tester,
      initial: 10,
      min: 1,
      max: 10,
      onChanged: emitted.add,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(emitted, isEmpty);
  });

  testWidgets('clamps at min — no emission when already at min', (tester) async {
    final emitted = <int>[];
    await _pumpHarness(
      tester,
      initial: 1,
      min: 1,
      max: 10,
      onChanged: emitted.add,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(emitted, isEmpty);
  });

  testWidgets('Tab and other keys are ignored (not consumed)', (tester) async {
    final emitted = <int>[];
    await _pumpHarness(
      tester,
      initial: 5,
      min: 1,
      max: 10,
      onChanged: emitted.add,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(emitted, isEmpty,
        reason: 'only arrow keys trigger onChanged; Tab must bubble to focus traversal');
  });
}
