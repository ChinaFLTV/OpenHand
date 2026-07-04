import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  testWidgets('showAnimatedModalSheet normalizes invalid margins', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showAnimatedModalSheet<void>(
                  context: context,
                  margin: const EdgeInsets.fromLTRB(-8, double.nan, 12, -4),
                  builder: (_) => const SizedBox(
                    height: 80,
                    child: Center(child: Text('sheet')),
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('sheet'), findsOneWidget);
  });
}
