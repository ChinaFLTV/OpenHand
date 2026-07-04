import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_menu.dart';

void main() {
  testWidgets('showAnimatedMenu stays stable in a very narrow viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showAnimatedMenu<int>(
                  context: context,
                  position: const RelativeRect.fromLTRB(4, 4, 4, 4),
                  items: const <PopupMenuEntry<int>>[
                    PopupMenuItem<int>(value: 1, child: Text('first')),
                  ],
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(80, 120));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('first'), findsOneWidget);
  });
}
