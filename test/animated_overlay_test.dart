import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_overlay.dart';

void main() {
  testWidgets('overlay exit is reversible and completes exactly once', (
    tester,
  ) async {
    final visibility = ValueNotifier<bool>(true);
    var exitCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedOverlayContent(
          customSettings: const DialogAnimationSettings(
            entranceStyle: DialogAnimationStyle.fade,
            exitStyle: DialogAnimationStyle.fade,
            durationMs: 120,
          ),
          visibility: visibility,
          onExitCompleted: () => exitCount += 1,
          child: const SizedBox(key: ValueKey<String>('overlay-content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    visibility.value = false;
    await tester.pump(const Duration(milliseconds: 60));
    expect(exitCount, 0);

    // Reopening while the reverse transition is in flight must cancel the
    // pending removal instead of allowing a stale completion to remove it.
    visibility.value = true;
    await tester.pumpAndSettle();
    expect(exitCount, 0);
    expect(
      find.byKey(const ValueKey<String>('overlay-content')),
      findsOneWidget,
    );

    visibility.value = false;
    await tester.pumpAndSettle();
    expect(exitCount, 1);

    // A settings rebuild while the owner is completing removal must not
    // deliver the same exit notification again.
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedOverlayContent(
          customSettings: const DialogAnimationSettings(
            entranceStyle: DialogAnimationStyle.fade,
            exitStyle: DialogAnimationStyle.fade,
            durationMs: 180,
          ),
          visibility: visibility,
          onExitCompleted: () => exitCount += 1,
          child: const SizedBox(key: ValueKey<String>('overlay-content')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(exitCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    visibility.dispose();
  });

  testWidgets('disabled motion completes dismissal without a stuck entry', (
    tester,
  ) async {
    final visibility = ValueNotifier<bool>(true);
    var exitCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedOverlayContent(
          customSettings: const DialogAnimationSettings(
            entranceStyle: DialogAnimationStyle.none,
            exitStyle: DialogAnimationStyle.none,
            durationMs: 0,
          ),
          visibility: visibility,
          onExitCompleted: () => exitCount += 1,
          child: const Text('visible'),
        ),
      ),
    );

    visibility.value = false;
    await tester.pump();
    expect(exitCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    visibility.dispose();
  });
}
