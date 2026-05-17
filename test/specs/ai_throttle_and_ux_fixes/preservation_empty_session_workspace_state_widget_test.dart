// Bug 4 Preservation #4 — Empty session still renders the workspace
// empty-state.
//
// **Validates: Requirements 10.1**
//
// Property 6 (Preservation): when `displayMessages.length == 0`, the
// `_SessionTranscript` SHALL render `_WorkspaceEmptyState` and NOT a
// bubble list. The Bug 4 fix introduces a build-stage fallback for
// `displayMessages.isNotEmpty` that synchronously materializes
// `_renderEntries` — that fallback must NOT alter the empty-session
// branch.
//
// Mirror conventions:
// - `_BuggyTranscriptMirror` reproduces the production
//   `_SessionTranscriptState` short-circuit:
//     if (_renderEntries.isEmpty && visibleMessages.isEmpty)
//       return _WorkspaceEmptyState(...);
//   The widget types are local to this file (no shared mirrors with
//   Task 1 to avoid coupling).
// - We use `find.byKey` with a stable key on the empty-state mock so
//   the assertion is not dependent on widget tree internals.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessionMock {
  _SessionMock({required this.id, required this.displayMessages});
  final String id;
  final List<String> displayMessages;
}

class _MessageBubbleMock extends StatelessWidget {
  const _MessageBubbleMock({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) =>
      SizedBox(key: ValueKey('bubble_$id'), height: 36, child: Text(id));
}

class _WorkspaceEmptyMock extends StatelessWidget {
  const _WorkspaceEmptyMock({super.key});
  @override
  Widget build(BuildContext context) => const Center(
        key: Key('preservation_empty_state'),
        child: Text('No messages yet'),
      );
}

class _BuggyTranscriptMirror extends StatefulWidget {
  const _BuggyTranscriptMirror({required this.session});
  final _SessionMock session;

  @override
  State<_BuggyTranscriptMirror> createState() =>
      _BuggyTranscriptMirrorState();
}

class _BuggyTranscriptMirrorState extends State<_BuggyTranscriptMirror> {
  List<String> _renderEntries = const <String>[];

  @override
  void initState() {
    super.initState();
    _renderEntries = List<String>.from(widget.session.displayMessages);
  }

  @override
  void didUpdateWidget(covariant _BuggyTranscriptMirror oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _renderEntries = const <String>[];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _renderEntries = List<String>.from(widget.session.displayMessages);
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleMessages = widget.session.displayMessages;
    if (_renderEntries.isEmpty && visibleMessages.isEmpty) {
      return const _WorkspaceEmptyMock(key: Key('emp'));
    }
    if (_renderEntries.isEmpty) {
      return const _WorkspaceEmptyMock(key: Key('emp'));
    }
    return ListView(
      children: [for (final id in _renderEntries) _MessageBubbleMock(id: id)],
    );
  }
}

Widget _wrap(_SessionMock s) =>
    MaterialApp(home: Scaffold(body: _BuggyTranscriptMirror(session: s)));

void main() {
  group('Preservation — empty session shows workspace empty-state', () {
    testWidgets('initial paint: 0 messages renders empty mock', (tester) async {
      final s = _SessionMock(id: 's0', displayMessages: const []);
      await tester.pumpWidget(_wrap(s));
      await tester.pump();
      expect(
        find.byKey(const Key('preservation_empty_state')),
        findsOneWidget,
        reason: 'empty session must render the workspace empty state.',
      );
      expect(
        find.byType(_MessageBubbleMock),
        findsNothing,
        reason: 'empty session must not render any bubble.',
      );
    });

    testWidgets('still empty after pumpAndSettle (no late bubbles)',
        (tester) async {
      final s = _SessionMock(id: 's1', displayMessages: const []);
      await tester.pumpWidget(_wrap(s));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('preservation_empty_state')), findsOneWidget);
      expect(find.byType(_MessageBubbleMock), findsNothing);
    });

    testWidgets('switching from non-empty back to empty re-shows empty state',
        (tester) async {
      late StateSetter setOuter;
      var current = _SessionMock(
        id: 'with_messages',
        displayMessages: const ['m1', 'm2'],
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            setOuter = setState;
            return _BuggyTranscriptMirror(session: current);
          }),
        ),
      ));
      await tester.pumpAndSettle();
      // Now switch to empty.
      setOuter(() => current = _SessionMock(
            id: 'now_empty',
            displayMessages: const [],
          ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('preservation_empty_state')), findsOneWidget);
      expect(find.byType(_MessageBubbleMock), findsNothing);
    });

    testWidgets('Randomized PBT (15 cases) — empty session never shows bubbles',
        (tester) async {
      final rng = Random(20260521);
      for (var i = 0; i < 15; i++) {
        final s = _SessionMock(id: 'rand_$i', displayMessages: const []);
        await tester.pumpWidget(_wrap(s));
        // pump a random number of frames between 1 and 8.
        final frames = 1 + rng.nextInt(8);
        for (var f = 0; f < frames; f++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          find.byKey(const Key('preservation_empty_state')),
          findsOneWidget,
          reason: 'PBT #$i (frames=$frames): empty mock must remain visible.',
        );
        expect(
          find.byType(_MessageBubbleMock),
          findsNothing,
          reason: 'PBT #$i: empty session must never spawn bubble widgets.',
        );
      }
    });
  });
}
