import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_safe_scrollbar.dart';

void main() {
  testWidgets('skips painting while controller is detached', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: OpenHandSafeScrollbar(
          controller: controller,
          thumbVisibility: true,
          child: const SizedBox(width: 120, height: 120),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });

  testWidgets('uses attached controller without falling back to primary', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 120,
          child: OpenHandSafeScrollbar(
            controller: controller,
            child: ListView(
              controller: controller,
              primary: false,
              children: List<Widget>.generate(
                20,
                (index) => SizedBox(height: 32, child: Text('row $index')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.drag(find.text('row 1'), const Offset(0, -80));
    await tester.pumpAndSettle();

    expect(controller.hasClients, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suppresses descendant implicit scrollbars', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        scrollBehavior: _FailingImplicitScrollbarBehavior(),
        home: OpenHandSafeScrollbar(
          child: SingleChildScrollView(
            primary: false,
            child: SizedBox(width: 120, height: 1000),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

class _FailingImplicitScrollbarBehavior extends MaterialScrollBehavior {
  const _FailingImplicitScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    throw StateError('implicit scrollbar should be disabled');
  }
}
