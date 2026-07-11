import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/shared/ui/reasoning_effort_selector.dart';

void main() {
  testWidgets('rapid cyclic effort changes never mount duplicate keys', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: Builder(
              builder: (anchorContext) => FilledButton(
                onPressed: () => unawaited(
                  showReasoningEffortSelector(
                    context: anchorContext,
                    anchorContext: anchorContext,
                    options: const <AiReasoningEffortOption>[
                      AiReasoningEffortOption(value: 'minimal', label: '极低'),
                      AiReasoningEffortOption(value: 'low', label: '低'),
                      AiReasoningEffortOption(value: 'medium', label: '中'),
                    ],
                    currentValue: 'minimal',
                    onChanged: (_) async => true,
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    for (final index in <double>[1, 0, 1, 0, 2, 0]) {
      tester.widget<Slider>(find.byType(Slider)).onChanged!(index);
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('persistence exceptions roll back without escaping the overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: Builder(
              builder: (anchorContext) => FilledButton(
                onPressed: () => unawaited(
                  showReasoningEffortSelector(
                    context: anchorContext,
                    anchorContext: anchorContext,
                    options: const <AiReasoningEffortOption>[
                      AiReasoningEffortOption(value: 'low', label: '低'),
                      AiReasoningEffortOption(value: 'high', label: '高'),
                    ],
                    currentValue: 'low',
                    onChanged: (_) => Future<bool>.error(StateError('save')),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    var slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(1);
    slider.onChangeEnd!(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 0);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets(
    'effort capsule keeps an opaque gradient across maximum changes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: Builder(
                builder: (anchorContext) => FilledButton(
                  onPressed: () => unawaited(
                    showReasoningEffortSelector(
                      context: anchorContext,
                      anchorContext: anchorContext,
                      options: const <AiReasoningEffortOption>[
                        AiReasoningEffortOption(value: 'low', label: '低'),
                        AiReasoningEffortOption(value: 'high', label: '高'),
                        AiReasoningEffortOption(value: 'maximum', label: '最高'),
                      ],
                      currentValue: 'low',
                      onChanged: (_) async => true,
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(find.byType(Slider));
      for (final index in <double>[2, 1, 2, 0]) {
        slider.onChanged!(index);
        await tester.pump(const Duration(milliseconds: 24));
        final label = index == 2
            ? '最高'
            : index == 1
            ? '高'
            : '低';
        // Capsule is a Container (or DecoratedBox) with a continuous 4-stop
        // gradient; max-tier may wrap an outer shadow-only DecoratedBox.
        final gradientBoxes = find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((widget) {
                if (widget is DecoratedBox) {
                  final decoration = widget.decoration;
                  return decoration is BoxDecoration &&
                      decoration.gradient is LinearGradient;
                }
                if (widget is Container) {
                  final decoration = widget.decoration;
                  return decoration is BoxDecoration &&
                      decoration.gradient is LinearGradient;
                }
                return false;
              }),
            )
            .evaluate()
            .toList(growable: false);
        expect(gradientBoxes, isNotEmpty);
        final host = gradientBoxes.first.widget;
        final BoxDecoration decoration;
        if (host is DecoratedBox) {
          decoration = host.decoration as BoxDecoration;
        } else {
          decoration = (host as Container).decoration! as BoxDecoration;
        }
        expect(decoration.color, isNull);
        expect(decoration.gradient, isA<LinearGradient>());
        final colors = (decoration.gradient! as LinearGradient).colors;
        expect(colors, hasLength(4));
        for (final color in colors) {
          expect(color.a, 1);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}
