import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_appearance.dart';

void main() {
  testWidgets('exit none dismisses post-frame without the entrance delay', (
    tester,
  ) async {
    late StateSetter update;
    var present = true;
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return AnimatedAppearance(
              settings: const DialogAnimationSettings(
                entranceStyle: DialogAnimationStyle.fade,
                exitStyle: DialogAnimationStyle.none,
                durationMs: 300,
              ),
              present: present,
              onDismissed: () => dismissed += 1,
              child: const Text('appearance-child'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    update(() => present = false);
    await tester.pump();

    expect(dismissed, 1);
    expect(find.text('appearance-child'), findsNothing);
  });

  testWidgets('entrance none still runs the configured exit', (tester) async {
    late StateSetter update;
    var present = true;
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return AnimatedAppearance(
              settings: const DialogAnimationSettings(
                entranceStyle: DialogAnimationStyle.none,
                exitStyle: DialogAnimationStyle.fade,
                durationMs: 120,
              ),
              present: present,
              onDismissed: () => dismissed += 1,
              child: const Text('animated-appearance-exit'),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('animated-appearance-exit'), findsOneWidget);

    update(() => present = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(dismissed, 0);
    await tester.pump(const Duration(milliseconds: 70));
    expect(dismissed, 1);
  });

  testWidgets('initially absent content never flashes in to animate out', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedAppearance(
          settings: const DialogAnimationSettings(
            entranceStyle: DialogAnimationStyle.fade,
            exitStyle: DialogAnimationStyle.fade,
            durationMs: 120,
          ),
          present: false,
          onDismissed: () => dismissed += 1,
          child: const Text('initially-absent-child'),
        ),
      ),
    );

    expect(find.text('initially-absent-child'), findsNothing);
    await tester.pump();
    expect(dismissed, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(dismissed, 1);
  });

  testWidgets('disabling an active exit completes it post-frame', (
    tester,
  ) async {
    late StateSetter update;
    var settings = const DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.fade,
      exitStyle: DialogAnimationStyle.fade,
      durationMs: 300,
    );
    var present = true;
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return AnimatedAppearance(
              settings: settings,
              present: present,
              onDismissed: () => dismissed += 1,
              child: const Text('dynamic-exit-child'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    update(() => present = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(dismissed, 0);

    update(() {
      settings = settings.copyWith(exitStyle: DialogAnimationStyle.none);
    });
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(dismissed, 1);
    expect(find.text('dynamic-exit-child'), findsNothing);
  });

  testWidgets('re-entering with disabled entrance resets dismissal state', (
    tester,
  ) async {
    late StateSetter update;
    var present = false;
    var settings = const DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.none,
      exitStyle: DialogAnimationStyle.none,
      durationMs: 240,
    );
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return AnimatedAppearance(
              settings: settings,
              present: present,
              onDismissed: () => dismissed += 1,
              child: const Text('resurrected-child'),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(dismissed, 1);

    update(() => present = true);
    await tester.pump();
    expect(find.text('resurrected-child'), findsOneWidget);

    update(() {
      settings = settings.copyWith(exitStyle: DialogAnimationStyle.fade);
      present = false;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(dismissed, 1);
    await tester.pump(const Duration(milliseconds: 130));
    expect(dismissed, 2);
  });

  testWidgets('re-entry cancels an in-flight exit completion', (tester) async {
    late StateSetter update;
    var present = true;
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return AnimatedAppearance(
              settings: const DialogAnimationSettings(
                entranceStyle: DialogAnimationStyle.fade,
                exitStyle: DialogAnimationStyle.fade,
                durationMs: 200,
              ),
              present: present,
              onDismissed: () => dismissed += 1,
              child: const Text('re-entry-child'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    update(() => present = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    update(() => present = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(dismissed, 0);
    expect(find.text('re-entry-child'), findsOneWidget);

    update(() => present = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 210));
    expect(dismissed, 1);
  });

  testWidgets('zero-progress exit lets the parent remove post-frame', (
    tester,
  ) async {
    late StateSetter update;
    var present = true;
    var mountedByParent = true;
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            if (!mountedByParent) return const SizedBox.shrink();
            return AnimatedAppearance(
              settings: const DialogAnimationSettings(
                entranceStyle: DialogAnimationStyle.fade,
                exitStyle: DialogAnimationStyle.fade,
                durationMs: 300,
              ),
              present: present,
              onDismissed: () {
                dismissed += 1;
                setState(() => mountedByParent = false);
              },
              child: const Text('zero-progress-child'),
            );
          },
        ),
      ),
    );

    update(() => present = false);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(dismissed, 1);
    expect(find.text('zero-progress-child'), findsNothing);
  });

  testWidgets('list appearance skips size motion for a disabled phase', (
    tester,
  ) async {
    const childKey = ValueKey<String>('list-child');
    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedListAppearance(
          animation: AlwaysStoppedAnimation<double>(0.5),
          settings: DialogAnimationSettings(
            entranceStyle: DialogAnimationStyle.fade,
            exitStyle: DialogAnimationStyle.none,
            durationMs: 300,
          ),
          phase: AnimatedAppearancePhase.exit,
          child: SizedBox(key: childKey),
        ),
      ),
    );

    expect(find.byKey(childKey), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(childKey),
        matching: find.byType(SizeTransition),
      ),
      findsNothing,
    );
  });
}
