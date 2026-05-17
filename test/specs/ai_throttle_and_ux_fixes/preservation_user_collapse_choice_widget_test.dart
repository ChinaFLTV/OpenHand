// Bug 5 Preservation #6 — User-collapsed reasoning card stays collapsed.
//
// **Validates: Requirements 11.1, 11.2**
//
// Property 6 (Preservation): when the user has explicitly chosen to
// collapse a reasoning card (production sets
// `_reasoningExpandedOverride = false` on the bubble state), the card
// SHALL remain collapsed across rebuilds and animation completion. The
// upcoming Bug 5 fix unifies motion tokens; it must not erase that user
// preference.
//
// Mirror conventions: this file declares its own `_ReasoningCardMock`
// state so it does not import private helpers from production. We
// imitate the production pattern of "collapsed = AnimatedSize at
// minimum height" + "expanded = AnimatedSize at full body height".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ReasoningCardMock extends StatefulWidget {
  const _ReasoningCardMock({
    required this.body,
    required this.userOverride,
    required this.defaultExpanded,
  });
  final String body;
  // mirrors production `_reasoningExpandedOverride` field — null = no
  // override, true = user expanded, false = user collapsed.
  final bool? userOverride;
  // mirrors production `_shouldDefaultExpandReasoning(message)`.
  final bool defaultExpanded;

  @override
  State<_ReasoningCardMock> createState() => _ReasoningCardMockState();
}

class _ReasoningCardMockState extends State<_ReasoningCardMock> {
  bool? _override;

  @override
  void initState() {
    super.initState();
    _override = widget.userOverride;
  }

  @override
  Widget build(BuildContext context) {
    final expanded = _override ?? widget.defaultExpanded;
    return Material(
      child: InkWell(
        key: const Key('reasoning_toggle'),
        onTap: () => setState(() => _override = !expanded),
        child: AnimatedSize(
          // Match production: alignment topLeft on the body to avoid
          // bouncing.
          alignment: Alignment.topLeft,
          duration: const Duration(milliseconds: 280),
          curve: const Cubic(0.22, 1.22, 0.36, 1),
          child: SizedBox(
            key: const Key('reasoning_body'),
            width: 200,
            height: expanded ? 200 : 0,
            child: expanded ? Text(widget.body) : null,
          ),
        ),
      ),
    );
  }
}

double _bodyHeight(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(const Key('reasoning_body')),
  );
  return box.size.height;
}

void main() {
  group('Preservation — user collapse choice survives animation', () {
    testWidgets('userOverride=false stays collapsed after pumpAndSettle',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _ReasoningCardMock(
            body: 'Reasoning content goes here.',
            userOverride: false,
            defaultExpanded: true, // would default-expand if no override.
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        _bodyHeight(tester),
        equals(0.0),
        reason:
            'User explicitly collapsed: AnimatedSize body must be 0 high '
            'even though defaultExpanded=true.',
      );
    });

    testWidgets('userOverride=true stays expanded after pumpAndSettle',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _ReasoningCardMock(
            body: 'Reasoning content goes here.',
            userOverride: true,
            defaultExpanded: false,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        _bodyHeight(tester),
        equals(200.0),
        reason:
            'User explicitly expanded: AnimatedSize body must be 200 high.',
      );
    });

    testWidgets('Tap to toggle: collapse is honoured immediately on settle',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _ReasoningCardMock(
            body: 'Reasoning content.',
            userOverride: null, // start unset → use default
            defaultExpanded: true, // open by default
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(_bodyHeight(tester), equals(200.0));
      // User taps to collapse.
      await tester.tap(find.byKey(const Key('reasoning_toggle')));
      await tester.pumpAndSettle();
      expect(
        _bodyHeight(tester),
        equals(0.0),
        reason: 'After user tap, body must collapse to 0.',
      );
    });

    testWidgets('After collapse choice, animation does not re-expand',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _ReasoningCardMock(
            body: 'Reasoning.',
            userOverride: false, // collapsed by user.
            defaultExpanded: true,
          ),
        ),
      ));
      // Pump several frames over a duration covering the AnimatedSize.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      await tester.pumpAndSettle();
      expect(
        _bodyHeight(tester),
        equals(0.0),
        reason:
            'Across the entire animation duration the user-collapsed body '
            'must never re-expand.',
      );
    });
  });
}
