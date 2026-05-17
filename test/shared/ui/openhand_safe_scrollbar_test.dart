import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/shared/ui/openhand_safe_scrollbar.dart';

void main() {
  group('OpenHandSafeScrollbar', () {
    testWidgets(
      'case A: controller not attached — pump does not throw, child renders',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OpenHandSafeScrollbar(
                controller: controller,
                child: const Text('child-A'),
              ),
            ),
          ),
        );

        // 多 pump 一次，让 post-frame 二次评估也完整跑一次。
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('child-A'), findsOneWidget);
      },
    );

    testWidgets(
      'case B: controller attached via Scrollable — no throw, Scrollbar in tree',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OpenHandSafeScrollbar(
                controller: controller,
                child: SingleChildScrollView(
                  controller: controller,
                  child: const SizedBox(height: 1200, child: Text('child-B')),
                ),
              ),
            ),
          ),
        );

        // 第一次 build 时 controller 还未 attach；第二次 pump 后 attach 完成 → 重建。
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('child-B'), findsOneWidget);
        expect(find.byType(Scrollbar), findsOneWidget);
      },
    );

    testWidgets(
      'case C: thumbVisibility=true + unattached — pump does not throw',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OpenHandSafeScrollbar(
                controller: controller,
                thumbVisibility: true,
                child: const Text('child-C'),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));

        expect(tester.takeException(), isNull);
        expect(find.text('child-C'), findsOneWidget);
        // 未 attach 时不应该出现 Scrollbar。
        expect(find.byType(Scrollbar), findsNothing);
      },
    );

    testWidgets(
      'case D: thumbVisibility=true + attached — Scrollbar in tree, no throw',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OpenHandSafeScrollbar(
                controller: controller,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: controller,
                  child: const SizedBox(height: 1200, child: Text('child-D')),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('child-D'), findsOneWidget);
        expect(find.byType(Scrollbar), findsOneWidget);
      },
    );

    testWidgets(
      'case E: attached → detached (Scrollable removed) — no throw',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);

        Widget buildAttached() {
          return MaterialApp(
            home: Scaffold(
              body: OpenHandSafeScrollbar(
                controller: controller,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: controller,
                  child: const SizedBox(height: 1200, child: Text('child-E')),
                ),
              ),
            ),
          );
        }

        Widget buildDetached() {
          return MaterialApp(
            home: Scaffold(
              body: OpenHandSafeScrollbar(
                controller: controller,
                thumbVisibility: true,
                child: const Text('child-E-detached'),
              ),
            ),
          );
        }

        await tester.pumpWidget(buildAttached());
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollbar), findsOneWidget);

        await tester.pumpWidget(buildDetached());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));

        expect(tester.takeException(), isNull);
        expect(find.text('child-E-detached'), findsOneWidget);
        expect(find.byType(Scrollbar), findsNothing);
      },
    );
  });
}
