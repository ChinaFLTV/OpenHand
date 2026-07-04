import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  testWidgets('buildOpenHandDialog normalizes invalid inset padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: buildOpenHandDialog(
            insetPadding: const EdgeInsets.fromLTRB(-4, 8, -6, -2),
            child: const SizedBox(
              width: 120,
              height: 80,
              child: Center(child: Text('dialog')),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('dialog'), findsOneWidget);
  });

  testWidgets('showAnimatedModalSheet normalizes invalid margins', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showAnimatedModalSheet<void>(
                  context: context,
                  margin: const EdgeInsets.fromLTRB(-8, double.nan, 12, -4),
                  builder: (_) => const SizedBox(
                    height: 80,
                    child: Center(child: Text('sheet')),
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('sheet'), findsOneWidget);
  });

  testWidgets('showAnimatedDialog disables motion when ticker is paused', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: false,
          child: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showAnimatedDialog<void>(
                    context: context,
                    settings: const DialogAnimationSettings(
                      entranceStyle: DialogAnimationStyle.slideUp,
                      exitStyle: DialogAnimationStyle.slideDown,
                      durationMs: DialogAnimationSettings.maxDurationMs,
                    ),
                    builder: (_) => const SizedBox(
                      width: 120,
                      height: 80,
                      child: Center(child: Text('paused ticker dialog')),
                    ),
                  );
                },
                child: const Text('open paused'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open paused'));
    await tester.pump();

    expect(find.text('paused ticker dialog'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}
