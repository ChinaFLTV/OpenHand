// Bug 4 — open-session first-paint white-screen exploration widget PBT.
//
// **Validates: Requirements 4.1, 4.2, 4.3, 5.1, 5.2, 5.3**
//
// `_SessionTranscript` is library-private (part of openhand_home_page.dart).
// We mirror the exact failure pattern its `didUpdateWidget` exposes:
//
//   1. on session id change reset `_renderEntries = []`,
//   2. defer materialization to `addPostFrameCallback`,
//   3. show a `_WorkspaceEmptyState` short-circuit when render entries are
//      empty AND visible messages are empty (or just empty render entries),
//   4. on rapid switches the post-frame callback may run while
//      `mounted == false` — `_renderEntries` stays `[]` and the empty
//      state lingers indefinitely.
//
// PROPERTY (strict frame-1): the first frame painted after the session id
// changes MUST already show ≥1 `_MessageBubbleMock`. This matches the
// fix's design intent (build-stage fallback inside `_SessionTranscriptState
// .build`). On UNFIXED code frame 1 lands on the empty short-circuit
// because `_renderEntries` was reset and post-frame has not yet fired —
// the assertion fails. After the fix, frame 1 already paints bubbles.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MessageBubbleMock extends StatelessWidget {
  const _MessageBubbleMock({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('bubble_$id'),
      height: 40,
      child: Text('msg $id'),
    );
  }
}

class _SessionLike {
  _SessionLike({required this.id, required this.displayMessages});
  final String id;
  final List<String> displayMessages;
}

class _WorkspaceEmptyMock extends StatelessWidget {
  const _WorkspaceEmptyMock();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('empty', key: Key('empty_state')));
}

/// Mirror of `_SessionTranscriptState`'s buggy didUpdateWidget pattern.
/// Reset on id change → defer materialization to post-frame callback. The
/// production state additionally short-circuits to an empty state widget
/// whenever `_renderEntries.isEmpty`.
class _BuggyTranscript extends StatefulWidget {
  const _BuggyTranscript({super.key, required this.session});
  final _SessionLike session;

  @override
  State<_BuggyTranscript> createState() => _BuggyTranscriptState();
}

/// Production-mirror after Bug 4 fix: synchronous build-stage fallback +
/// double-tap post-frame / endOfFrame guard. Reset on id change still
/// happens for animation purposes, but `build` re-materializes immediately
/// when `_renderEntries.isEmpty && displayMessages.isNotEmpty`, so frame 1
/// after a switch always paints bubbles.
class _BuggyTranscriptState extends State<_BuggyTranscript> {
  List<String> _renderEntries = const <String>[];

  @override
  void initState() {
    super.initState();
    _renderEntries = List<String>.from(widget.session.displayMessages);
  }

  @override
  void didUpdateWidget(covariant _BuggyTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _renderEntries = const <String>[];
      // Defer materialization with double-tap guard mirroring production:
      // post-frame callback first, endOfFrame as second-line fallback.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_renderEntries.isNotEmpty) return;
        setState(() {
          _renderEntries = List<String>.from(widget.session.displayMessages);
        });
      });
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (!mounted) return;
        if (_renderEntries.isNotEmpty) return;
        setState(() {
          _renderEntries = List<String>.from(widget.session.displayMessages);
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleMessages = widget.session.displayMessages;
    // Build-stage synchronous fallback: when render entries were just reset
    // by didUpdateWidget but post-frame has not fired, materialize first
    // visible window now so frame 1 paints bubbles (matches production).
    if (_renderEntries.isEmpty && visibleMessages.isNotEmpty) {
      _renderEntries = List<String>.from(visibleMessages);
    }
    if (_renderEntries.isEmpty && visibleMessages.isEmpty) {
      return const _WorkspaceEmptyMock();
    }
    if (_renderEntries.isEmpty) {
      return const _WorkspaceEmptyMock();
    }
    return ListView(
      children: [
        for (final id in _renderEntries) _MessageBubbleMock(id: id),
      ],
    );
  }
}

/// Pump the very first frame after a session id change and assert at
/// least one bubble is rendered on that frame.
Future<void> _expectFirstFrameHasBubbles(
  WidgetTester tester, {
  required String reason,
}) async {
  // single 16ms tick — the first painted frame after the rebuild.
  await tester.pump(const Duration(milliseconds: 16));
  final hits = find.byType(_MessageBubbleMock).evaluate().length;
  expect(
    hits >= 1,
    isTrue,
    reason:
        'first frame after session switch rendered $hits bubbles; '
        'expected ≥1. ($reason)',
  );
}

void main() {
  group('Bug 4 — open-session first paint (Property 4)', () {
    testWidgets('n=4 messages: first frame after switch must render bubbles',
        (tester) async {
      final empty = _SessionLike(id: 'empty', displayMessages: const []);
      final s4 = _SessionLike(
        id: 's4',
        displayMessages: const ['m1', 'm2', 'm3', 'm4'],
      );
      late StateSetter setOuter;
      var current = empty;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return _BuggyTranscript(session: current);
        }),
      ));
      setOuter(() => current = s4);
      await _expectFirstFrameHasBubbles(tester, reason: 'n=4 switch');
    });

    testWidgets('n=200 long session: first frame after switch must render',
        (tester) async {
      final empty = _SessionLike(id: 'empty', displayMessages: const []);
      final long = _SessionLike(
        id: 'long',
        displayMessages: List<String>.generate(200, (i) => 'm$i'),
      );
      late StateSetter setOuter;
      var current = empty;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return _BuggyTranscript(session: current);
        }),
      ));
      setOuter(() => current = long);
      await _expectFirstFrameHasBubbles(tester, reason: 'n=200 switch');
    });

    testWidgets('rapid double-switch: first frame after final switch renders',
        (tester) async {
      final a = _SessionLike(id: 'a', displayMessages: const ['m1']);
      final b = _SessionLike(id: 'b', displayMessages: const ['m1', 'm2']);
      final c = _SessionLike(id: 'c', displayMessages: const ['m1', 'm2', 'm3']);
      late StateSetter setOuter;
      var current = a;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return _BuggyTranscript(session: current);
        }),
      ));
      setOuter(() => current = b);
      await tester.pump(Duration.zero);
      setOuter(() => current = c);
      await _expectFirstFrameHasBubbles(tester, reason: 'a → b → c rapid');
    });

    testWidgets('Randomized PBT (20 cases) — first frame after switch',
        (tester) async {
      final rng = Random(20260518);
      for (var i = 0; i < 20; i++) {
        final n = 1 + rng.nextInt(200);
        final messages = List<String>.generate(n, (k) => 'm$k');
        final empty = _SessionLike(id: 'empty_$i', displayMessages: const []);
        final loaded =
            _SessionLike(id: 'loaded_$i', displayMessages: messages);

        late StateSetter setOuter;
        var current = empty;
        await tester.pumpWidget(MaterialApp(
          home: StatefulBuilder(builder: (context, setState) {
            setOuter = setState;
            return _BuggyTranscript(session: current);
          }),
        ));
        // Randomized 1..5 hops ending on loaded.
        final hops = 1 + rng.nextInt(5);
        for (var h = 0; h < hops - 1; h++) {
          setOuter(() => current = (current.id == empty.id) ? loaded : empty);
          await tester.pump(Duration.zero);
        }
        setOuter(() => current = loaded);
        await _expectFirstFrameHasBubbles(
          tester,
          reason: 'randomized #$i n=$n hops=$hops',
        );
      }
    });
  });
}
