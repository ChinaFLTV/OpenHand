import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_deferred_slider.dart';

void main() {
  testWidgets('previews locally and commits once when interaction ends', (
    tester,
  ) async {
    final committed = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenHandDeferredSlider(
            value: 2,
            min: 0,
            max: 10,
            divisions: 10,
            onCommit: committed.add,
          ),
        ),
      ),
    );

    var slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(5);
    await tester.pump();
    slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(8);
    await tester.pump();

    expect(committed, isEmpty);
    slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 8);
    slider.onChangeEnd!(8);
    expect(committed, <double>[8]);
  });

  testWidgets('does not commit when the value returns to its origin', (
    tester,
  ) async {
    final committed = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenHandDeferredSlider(
            value: 4,
            min: 0,
            max: 10,
            onCommit: committed.add,
          ),
        ),
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(7);
    slider.onChangeEnd!(4);
    await tester.pump();

    expect(committed, isEmpty);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 4);
  });

  testWidgets('is disabled when no commit callback is provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpenHandDeferredSlider(
            value: 4,
            min: 0,
            max: 10,
            onCommit: null,
          ),
        ),
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
    expect(slider.onChangeEnd, isNull);
  });
}
