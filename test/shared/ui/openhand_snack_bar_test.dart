import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_snack_bar.dart';

void main() {
  testWidgets('plain text snackbars are upgraded and dismissible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  final messenger = ScaffoldMessenger.of(context);
                  OpenHandSnackBar.show(
                    context,
                    messenger,
                    const SnackBar(content: Text('Saved')),
                  );
                },
                child: const Text('show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Saved'), findsOneWidget);
    expect(find.byIcon(Icons.info_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('snackbars with actions still expose a close affordance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  final messenger = ScaffoldMessenger.of(context);
                  OpenHandSnackBar.show(
                    context,
                    messenger,
                    SnackBar(
                      content: const Text('Service unavailable'),
                      action: SnackBarAction(
                        label: 'Details',
                        onPressed: () {},
                      ),
                    ),
                  );
                },
                child: const Text('show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Service unavailable'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Service unavailable'), findsNothing);
  });
}
