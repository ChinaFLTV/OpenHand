// Bug 3 Preservation #5 — Scrollbar drawn while controller is properly
// attached.
//
// **Validates: Requirements 9.1, 9.2**
//
// Property 6 (Preservation): in the common case where a `ScrollController`
// is already attached to a `ScrollView`, the framework `Scrollbar`
// (and the future `OpenHandSafeScrollbar`) SHALL paint the thumb without
// throwing FlutterError, and basic interactions (hover, attach query)
// SHALL behave as today.
//
// On UNFIXED code this scenario already PASSES — the production
// Scrollbar errors only appear on lifecycle edge cases (Bug 3
// exploration). This file pins down the happy-path baseline so the fix
// (introducing `OpenHandSafeScrollbar`) does NOT regress it.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Preservation — Scrollbar paints when controller is attached', () {
    testWidgets('attached controller: no FlutterError, exactly one Scrollbar',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Scrollbar(
              controller: controller,
              thumbVisibility: true,
              child: ListView.builder(
                controller: controller,
                itemCount: 50,
                itemBuilder: (_, i) =>
                    ListTile(title: Text('row $i', key: ValueKey('row_$i'))),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'attached scrollbar must not throw. Production happy-path '
            'baseline regression prevention.',
      );

      // The Scrollbar widget is mounted and findable.
      expect(find.byType(Scrollbar), findsOneWidget);

      // Controller has positions (i.e. it IS attached to the ListView).
      expect(
        controller.hasClients,
        isTrue,
        reason: 'controller must report at least one attached ScrollPosition.',
      );
      expect(
        controller.positions.length,
        equals(1),
        reason: 'exactly one ScrollPosition expected for the ListView.',
      );
    });

    testWidgets('hover on the scrollbar does not throw', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Scrollbar(
              controller: controller,
              thumbVisibility: true,
              child: ListView.builder(
                controller: controller,
                itemCount: 100,
                itemBuilder: (_, i) => ListTile(title: Text('item $i')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Move the synthetic mouse pointer inside the Scrollbar bounds.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      final scrollbarRect = tester.getRect(find.byType(Scrollbar));
      await gesture.moveTo(scrollbarRect.centerRight - const Offset(2, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'hover over the scrollbar must not raise FlutterError on the '
            'attached happy-path.',
      );
    });

    testWidgets('scrolling the ListView updates position without errors',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Scrollbar(
              controller: controller,
              thumbVisibility: true,
              child: ListView.builder(
                controller: controller,
                itemCount: 200,
                itemBuilder: (_, i) =>
                    ListTile(title: Text('row $i', key: ValueKey('row_$i'))),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      controller.jumpTo(controller.position.maxScrollExtent / 2);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'programmatic scroll must not raise FlutterError.',
      );
      expect(
        controller.offset > 0,
        isTrue,
        reason: 'controller offset must reflect the jumpTo target.',
      );
    });
  });
}
