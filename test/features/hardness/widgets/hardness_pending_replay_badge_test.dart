import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/hardness/widgets/hardness_pending_replay_badge.dart';
import 'package:openhand/shared/widgets/oh_pill.dart';

void main() {
  group('HardnessPendingReplayBadge', () {
    testWidgets('renders nothing when deadline is null', (tester) async {
      final notifier = ValueNotifier<DateTime?>(null);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HardnessPendingReplayBadge(
              isZh: false,
              deadlineListenable: notifier,
              tickInterval: const Duration(milliseconds: 50),
            ),
          ),
        ),
      );

      expect(find.byType(OhPill), findsNothing);
      expect(find.textContaining('Cancel'), findsNothing);
    });

    testWidgets(
      'shows decreasing countdown driven by injected nowProvider (3 -> 2 -> 1 -> hidden)',
      (tester) async {
        final base = DateTime.utc(2026, 1, 1, 12);
        DateTime fakeNow = base;
        final notifier = ValueNotifier<DateTime?>(
          base.add(const Duration(milliseconds: 2400)), // ceil → 3s
        );
        addTearDown(notifier.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HardnessPendingReplayBadge(
                isZh: false,
                deadlineListenable: notifier,
                tickInterval: const Duration(milliseconds: 50),
                nowProvider: () => fakeNow,
              ),
            ),
          ),
        );

        // Initial frame: 2400 ms remaining → ceil = 3s.
        expect(find.text('Cancel 3s'), findsOneWidget);

        // Advance fake time by 1s; pump a tick so the periodic Timer rebuilds.
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('Cancel 2s'), findsOneWidget);

        fakeNow = fakeNow.add(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('Cancel 1s'), findsOneWidget);

        // Past deadline: remaining ≤ 0 → label "Cancel 0s".
        fakeNow = fakeNow.add(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('Cancel 0s'), findsOneWidget);

        // Now clear the deadline (dispatcher fires onCancel) — chip vanishes.
        notifier.value = null;
        await tester.pump();
        expect(find.byType(OhPill), findsNothing);
      },
    );

    testWidgets('zh locale uses Chinese label', (tester) async {
      final base = DateTime.utc(2026, 1, 1, 12);
      final notifier = ValueNotifier<DateTime?>(
        base.add(const Duration(milliseconds: 1500)),
      );
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HardnessPendingReplayBadge(
              isZh: true,
              deadlineListenable: notifier,
              tickInterval: const Duration(milliseconds: 50),
              nowProvider: () => base,
            ),
          ),
        ),
      );

      expect(find.text('撤销 2s'), findsOneWidget);
    });

    testWidgets('tap forwards to onCancel and clears the deadline', (
      tester,
    ) async {
      final base = DateTime.utc(2026, 1, 1, 12);
      final notifier = ValueNotifier<DateTime?>(
        base.add(const Duration(seconds: 3)),
      );
      addTearDown(notifier.dispose);

      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HardnessPendingReplayBadge(
              isZh: false,
              deadlineListenable: notifier,
              tickInterval: const Duration(milliseconds: 50),
              nowProvider: () => base,
              onCancel: () {
                taps += 1;
                notifier.value = null;
              },
            ),
          ),
        ),
      );

      expect(find.text('Cancel 3s'), findsOneWidget);
      await tester.tap(find.byType(OhPill));
      await tester.pump();
      expect(taps, 1);
      expect(find.byType(OhPill), findsNothing);
    });
  });
}
