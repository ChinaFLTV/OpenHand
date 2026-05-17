// Bug 3 — Scrollbar `ScrollController has no ScrollPosition attached`
// exploration widget PBT.
//
// **Validates: Requirements 3.1, 3.2, 4.1, 4.2**
//
// We reproduce three scenarios outlined in design.md:
//   1. dialog open → close race (controller.dispose collides with the
//      Scrollbar's frame callback);
//   2. AnimatedSwitcher cross-fade between an empty session and a session
//      with bubbles (two ScrollPositions briefly attached);
//   3. long-list first paint with `thumbVisibility: true` (RawScrollbar
//      drawn before the controller has attached any position).
//
// On UNFIXED code (no `OpenHandSafeScrollbar` wrapper) at least one of
// these scenarios surfaces a FlutterError reading
//     "Scrollbar's ScrollController has no ScrollPosition attached"
// or related "must have only one ScrollPosition" / "single ScrollPosition"
// flavour. After the fix, every scenario runs error-free.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_safe_scrollbar.dart';

void _expectNoScrollbarAttachmentError(WidgetTester tester) {
  final ex = tester.takeException();
  if (ex == null) return;
  final msg = ex.toString();
  final offending = <String>[
    'has no ScrollPosition attached',
    'no ScrollPosition attached',
    'A Scrollbar cannot be drawn without a ScrollPosition',
    'Multiple ScrollPositions',
    'single ScrollPosition',
  ];
  for (final marker in offending) {
    expect(
      msg.contains(marker),
      isFalse,
      reason: 'unexpected scrollbar lifecycle error: $msg',
    );
  }
  // Re-throw any unrelated exception so test still fails.
  throw ex;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('Bug 3 — Scrollbar lifecycle (Property 3)', () {
    testWidgets('dialog close race does not leak ScrollPosition errors',
        (tester) async {
      var dialogOpen = true;
      late StateSetter setOuter;
      ScrollController? controller;
      await tester.pumpWidget(_wrap(
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            if (!dialogOpen) {
              return const SizedBox.shrink();
            }
            // Simulate the inner dialog body owning a controller that
            // gets disposed when the dialog unmounts.
            return _DisposableScrollbarBody(
              onControllerCreated: (c) => controller = c,
            );
          },
        ),
      ));
      await tester.pump();
      // Force-close immediately on the next frame to race with the
      // RawScrollbar's first post-frame callback.
      setOuter(() => dialogOpen = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();
      // controller intentionally consumed by the disposed widget.
      expect(controller, isNotNull);
      _expectNoScrollbarAttachmentError(tester);
    });

    testWidgets('AnimatedSwitcher cross-fade between empty/full transcripts',
        (tester) async {
      late StateSetter setOuter;
      var sessionId = 'empty';
      await tester.pumpWidget(_wrap(
        StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _SessionLikeList(
              key: ValueKey(sessionId),
              messageCount: sessionId == 'empty' ? 0 : 4,
            ),
          );
        }),
      ));
      await tester.pump();
      // Trigger the cross-fade.
      setOuter(() => sessionId = 'full');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pumpAndSettle();
      _expectNoScrollbarAttachmentError(tester);
    });

    testWidgets('long-session first paint with thumbVisibility=true',
        (tester) async {
      const itemCount = 200;
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_wrap(
        OpenHandSafeScrollbar(
          controller: controller,
          thumbVisibility: true,
          child: ListView.builder(
            controller: controller,
            itemCount: itemCount,
            itemBuilder: (context, index) =>
                ListTile(title: Text('Item $index')),
          ),
        ),
      ));
      // Pump the very first frame and a few subsequent frames; the
      // RawScrollbar's `_debugCheckHasValidScrollPosition` runs in a
      // post-frame callback that may race against the ListView's first
      // attach.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pumpAndSettle();
      _expectNoScrollbarAttachmentError(tester);
    });

    testWidgets('Randomized lifecycle PBT (10 cases)', (tester) async {
      final rng = Random(31415);
      for (var i = 0; i < 10; i++) {
        final sequence = <String>[
          for (var k = 0; k < 1 + rng.nextInt(4); k++)
            ['mount', 'unmount', 'switch'][rng.nextInt(3)]
        ];
        var visible = true;
        late StateSetter setOuter;
        await tester.pumpWidget(_wrap(
          StatefulBuilder(builder: (context, setState) {
            setOuter = setState;
            return visible
                ? _DisposableScrollbarBody(onControllerCreated: (_) {})
                : const SizedBox.shrink();
          }),
        ));
        for (final step in sequence) {
          switch (step) {
            case 'mount':
              setOuter(() => visible = true);
              break;
            case 'unmount':
              setOuter(() => visible = false);
              break;
            case 'switch':
              setOuter(() => visible = !visible);
              break;
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        _expectNoScrollbarAttachmentError(tester);
      }
    });
  });
}

class _DisposableScrollbarBody extends StatefulWidget {
  const _DisposableScrollbarBody({required this.onControllerCreated});

  final ValueChanged<ScrollController> onControllerCreated;

  @override
  State<_DisposableScrollbarBody> createState() =>
      _DisposableScrollbarBodyState();
}

class _DisposableScrollbarBodyState extends State<_DisposableScrollbarBody> {
  late final ScrollController _c;

  @override
  void initState() {
    super.initState();
    _c = ScrollController();
    widget.onControllerCreated(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OpenHandSafeScrollbar(
      controller: _c,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _c,
        child: const SizedBox(height: 4000, width: double.infinity),
      ),
    );
  }
}

class _SessionLikeList extends StatefulWidget {
  const _SessionLikeList({super.key, required this.messageCount});

  final int messageCount;

  @override
  State<_SessionLikeList> createState() => _SessionLikeListState();
}

class _SessionLikeListState extends State<_SessionLikeList> {
  late final ScrollController _c = ScrollController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messageCount == 0) {
      // Empty state: no ScrollView at all; this is the lifecycle that
      // historically left the parent's Scrollbar controller without a
      // position the moment we cross-faded to it.
      return OpenHandSafeScrollbar(
        controller: _c,
        thumbVisibility: true,
        child: const SizedBox(width: double.infinity, height: 600),
      );
    }
    return OpenHandSafeScrollbar(
      controller: _c,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _c,
        itemCount: widget.messageCount,
        itemBuilder: (_, i) => ListTile(title: Text('msg $i')),
      ),
    );
  }
}
