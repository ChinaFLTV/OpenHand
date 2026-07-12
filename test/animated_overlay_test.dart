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
    await tester.pump();
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

  testWidgets('exit none completes without waiting for entrance duration', (
    tester,
  ) async {
    final visibility = ValueNotifier<bool>(true);
    var exitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedOverlayContent(
          customSettings: const DialogAnimationSettings(
            entranceStyle: DialogAnimationStyle.fade,
            exitStyle: DialogAnimationStyle.none,
            durationMs: 300,
          ),
          visibility: visibility,
          onExitCompleted: () => exitCount += 1,
          child: const Text('instant-overlay-exit'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    visibility.value = false;
    await tester.pump();

    expect(exitCount, 1);
    visibility.dispose();
  });

  testWidgets('entrance none keeps the configured animated exit', (
    tester,
  ) async {
    final visibility = ValueNotifier<bool>(true);
    var exitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedOverlayContent(
          customSettings: const DialogAnimationSettings(
            entranceStyle: DialogAnimationStyle.none,
            exitStyle: DialogAnimationStyle.fade,
            durationMs: 120,
          ),
          visibility: visibility,
          onExitCompleted: () => exitCount += 1,
          child: const Text('animated-overlay-exit'),
        ),
      ),
    );
    await tester.pump();

    visibility.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(exitCount, 0);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.pump();
    expect(exitCount, 1);
    visibility.dispose();
  });

  testWidgets('entry controller reopens and rejects stale exit callbacks', (
    tester,
  ) async {
    final controller = AnimatedOverlayEntryController();
    late BuildContext hostContext;
    VoidCallback? firstSessionCompletion;
    VoidCallback? replacementCompletion;
    var animatedExitCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    AnimatedOverlayEntryBuilder entryBuilder({required bool replacement}) {
      return (context, visibility, onExitCompleted) {
        if (replacement) {
          replacementCompletion = onExitCompleted;
        } else {
          firstSessionCompletion ??= onExitCompleted;
        }
        return AnimatedOverlayContent(
          customSettings: const DialogAnimationSettings(
            entranceStyle: DialogAnimationStyle.fade,
            exitStyle: DialogAnimationStyle.fade,
            durationMs: 120,
          ),
          visibility: visibility,
          onExitCompleted: () {
            animatedExitCount += 1;
            onExitCompleted();
          },
          child: Text(replacement ? 'replacement' : 'first'),
        );
      };
    }

    controller.show(
      overlay: Overlay.of(hostContext, rootOverlay: true),
      builder: entryBuilder(replacement: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);

    controller.close();
    await tester.pump(const Duration(milliseconds: 60));
    controller.show(
      overlay: Overlay.of(hostContext, rootOverlay: true),
      builder: entryBuilder(replacement: false),
    );
    await tester.pumpAndSettle();
    expect(animatedExitCount, 0);
    expect(controller.hasEntry, isTrue);
    expect(find.text('first'), findsOneWidget);

    controller.close();
    await tester.pumpAndSettle();
    expect(animatedExitCount, 1);
    expect(controller.hasEntry, isFalse);
    expect(find.text('first'), findsNothing);

    controller.show(
      overlay: Overlay.of(hostContext, rootOverlay: true),
      builder: entryBuilder(replacement: true),
    );
    await tester.pumpAndSettle();
    firstSessionCompletion!.call();
    await tester.pump();
    expect(controller.hasEntry, isTrue);
    expect(find.text('replacement'), findsOneWidget);
    expect(replacementCompletion, isNotNull);

    controller.dispose();
    await tester.pump();
  });

  testWidgets('entry controller removes disabled motion without delay', (
    tester,
  ) async {
    final controller = AnimatedOverlayEntryController();
    late BuildContext hostContext;
    var removedCount = 0;
    var exitCompletionCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    controller.show(
      overlay: Overlay.of(hostContext, rootOverlay: true),
      onRemoved: () => removedCount += 1,
      builder: (context, visibility, onExitCompleted) => AnimatedOverlayContent(
        customSettings: const DialogAnimationSettings(
          entranceStyle: DialogAnimationStyle.none,
          exitStyle: DialogAnimationStyle.none,
          durationMs: 0,
        ),
        visibility: visibility,
        onExitCompleted: () {
          exitCompletionCount += 1;
          onExitCompleted();
        },
        child: const Text('no-motion-entry'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('no-motion-entry'), findsOneWidget);

    controller.close();
    await tester.pumpAndSettle();
    expect(exitCompletionCount, 1);
    expect(controller.hasEntry, isFalse);
    expect(removedCount, 1);
    expect(find.text('no-motion-entry'), findsNothing);

    controller.close();
    controller.dispose();
    controller.dispose();
    expect(removedCount, 1);
  });

  testWidgets('entry controller dispose cancels an in-flight close', (
    tester,
  ) async {
    final controller = AnimatedOverlayEntryController();
    late BuildContext hostContext;
    VoidCallback? completion;
    var removedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    controller.show(
      overlay: Overlay.of(hostContext, rootOverlay: true),
      onRemoved: () => removedCount += 1,
      builder: (context, visibility, onExitCompleted) {
        completion = onExitCompleted;
        return AnimatedOverlayContent(
          customSettings: const DialogAnimationSettings(durationMs: 300),
          visibility: visibility,
          onExitCompleted: onExitCompleted,
          child: const Text('disposing-entry'),
        );
      },
    );
    await tester.pumpAndSettle();

    controller.close();
    await tester.pump(const Duration(milliseconds: 80));
    controller.dispose();
    controller.close();
    controller.dispose();
    await tester.pumpAndSettle();
    expect(controller.hasEntry, isFalse);
    expect(removedCount, 1);
    expect(find.text('disposing-entry'), findsNothing);

    // A completion retained by the unmounted animation is harmless, and a
    // disposed controller can never allocate another entry.
    completion!.call();
    expect(
      controller.show(
        overlay: Overlay.of(hostContext, rootOverlay: true),
        builder: (context, visibility, onExitCompleted) => const SizedBox(),
      ),
      isFalse,
    );
    expect(removedCount, 1);
  });
}
