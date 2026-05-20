import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_menu.dart';

void main() {
  testWidgets('animated popup menu opens without a settings provider', (
    tester,
  ) async {
    int? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AnimatedPopupMenuButton<int>(
              tooltip: 'More',
              itemBuilder: (context) => const [
                PopupMenuItem<int>(value: 1, child: Text('First action')),
              ],
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('First action'), findsOneWidget);

    await tester.tap(find.text('First action'));
    await tester.pumpAndSettle();

    expect(selected, 1);
  });
}
