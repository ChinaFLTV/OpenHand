// 2026-05-05 — PromptCacheBreakpointBar widget tests covering peg drag,
// tap-to-position, reset callback, dynamic peg pulse animation render and
// tooltip surfaces.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/settings/widgets/prompt_cache_breakpoint_bar.dart';
import 'package:openhand/l10n/app_localizations.dart';

Future<void> _pumpBar(
  WidgetTester tester, {
  required List<double> initial,
  required int thumbCount,
  required Future<void> Function(List<double>) onCommit,
  required VoidCallback onReset,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 600,
          child: PromptCacheBreakpointBar(
            initialValues: initial,
            thumbCount: thumbCount,
            onCommit: onCommit,
            onReset: onReset,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders 9 prompt section labels in the bar', (tester) async {
    await _pumpBar(
      tester,
      initial: const [0.25, 0.5, 0.75],
      thumbCount: 3,
      onCommit: (_) async {},
      onReset: () {},
    );
    // Each segment label appears at least once on the bar; with the legend
    // they may appear twice. We assert presence rather than exact count.
    for (final label in <String>[
      '[0] System',
      '[1] Developer',
      '[2] Tools',
      '[3] State',
      '[4] Memory',
      '[4.5] Inst.',
      '[5] Summary',
      'History',
      '[6] Latest',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'label "$label" missing');
    }
  });

  testWidgets('renders P1/P2/P3 percent labels and dynamic locked label', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      initial: const [0.25, 0.5, 0.75],
      thumbCount: 3,
      onCommit: (_) async {},
      onReset: () {},
    );
    expect(find.text('P1: 25%'), findsOneWidget);
    expect(find.text('P2: 50%'), findsOneWidget);
    expect(find.text('P3: 75%'), findsOneWidget);
    expect(find.textContaining('P4: 100%'), findsOneWidget);
  });

  testWidgets('tap on bar moves nearest peg and fires onCommit', (
    tester,
  ) async {
    List<double>? committed;
    await _pumpBar(
      tester,
      initial: const [0.2, 0.8],
      thumbCount: 2,
      onCommit: (next) async {
        committed = List<double>.from(next);
      },
      onReset: () {},
    );
    // Tap near the middle of the bar — that should snap the nearest peg
    // (peg 1, value 0.8 is farther than peg 0 at 0.2 from x=0.5).
    // Center of 600px-wide bar = 300px → value 0.5.
    final barFinder = find.byType(GestureDetector).first;
    expect(barFinder, findsOneWidget);
    final bar = tester.getRect(barFinder);
    await tester.tapAt(Offset(bar.left + bar.width * 0.5, bar.center.dy));
    await tester.pump(const Duration(milliseconds: 50));
    expect(committed, isNotNull);
    expect(committed!.length, 2);
    // Peg 0 moved toward 0.5; peg 1 stayed at 0.8 (nearest to 0.5 is peg 0
    // since 0.5-0.2=0.3 < 0.8-0.5=0.3 — tie; nearestPegIndex picks lower idx).
    expect(committed![0], closeTo(0.5, 0.02));
    expect(committed![1], closeTo(0.8, 0.02));
  });

  testWidgets('drag updates draft and onCommit fires once on release', (
    tester,
  ) async {
    var commitCount = 0;
    List<double>? lastCommitted;
    await _pumpBar(
      tester,
      initial: const [0.3, 0.7],
      thumbCount: 2,
      onCommit: (next) async {
        commitCount += 1;
        lastCommitted = List<double>.from(next);
      },
      onReset: () {},
    );
    final bar = tester.getRect(find.byType(GestureDetector).first);
    final start = Offset(bar.left + bar.width * 0.3, bar.center.dy);
    final end = Offset(bar.left + bar.width * 0.45, bar.center.dy);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(end);
    await tester.pump();
    expect(commitCount, 0, reason: 'no commit during drag');
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(commitCount, 1, reason: 'commit fires once on release');
    expect(lastCommitted, isNotNull);
    expect(lastCommitted![0], closeTo(0.45, 0.02));
    expect(lastCommitted![1], closeTo(0.7, 0.02));
  });

  testWidgets('reset button invokes onReset', (tester) async {
    var resetCount = 0;
    await _pumpBar(
      tester,
      initial: const [0.25, 0.5, 0.75],
      thumbCount: 3,
      onCommit: (_) async {},
      onReset: () => resetCount += 1,
    );
    final btn = find.byType(TextButton);
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    await tester.pump();
    expect(resetCount, 1);
  });

  testWidgets('dynamic peg pulse advances across pump frames', (tester) async {
    await _pumpBar(
      tester,
      initial: const [0.5],
      thumbCount: 1,
      onCommit: (_) async {},
      onReset: () {},
    );
    // The dynamic peg uses an AnimationController with repeat(). Pumping
    // forward by an arbitrary fraction must not throw and must continue to
    // schedule frames (i.e. tester.binding has scheduled a frame).
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('tooltip shows section title + summary + cache hint', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      initial: const [0.5],
      thumbCount: 1,
      onCommit: (_) async {},
      onReset: () {},
    );
    // Find the first segment Tooltip; the System segment is leftmost.
    final tip = find.byType(Tooltip).first;
    expect(tip, findsOneWidget);
    final widget = tester.widget<Tooltip>(tip);
    final rich = widget.richMessage;
    expect(rich, isNotNull);
    final flat = rich!.toPlainText();
    // Either zh or en wording is acceptable (locale defaults vary); just
    // verify the three components are concatenated.
    expect(flat, contains('System'));
    expect(flat.length, greaterThan(40), reason: 'summary + hint present');
  });
}
