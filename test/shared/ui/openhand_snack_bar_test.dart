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

  testWidgets('snackbars with actions keep close button at the far right', (
    tester,
  ) async {
    var detailsTapped = false;
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
                        onPressed: () => detailsTapped = true,
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
    expect(
      tester.getCenter(find.byIcon(Icons.close_rounded)).dx,
      greaterThan(tester.getCenter(find.text('Details')).dx),
    );

    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(detailsTapped, isTrue);
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Service unavailable'), findsNothing);
  });

  testWidgets(
    'action snackbars still auto-dismiss with accessible navigation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(accessibleNavigation: true),
            child: ScaffoldMessenger(
              child: Scaffold(
                body: Builder(
                  builder: (context) {
                    return TextButton(
                      onPressed: () {
                        final messenger = ScaffoldMessenger.of(context);
                        OpenHandSnackBar.show(
                          context,
                          messenger,
                          SnackBar(
                            duration: const Duration(milliseconds: 900),
                            content: const Text('Timed detail'),
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
          ),
        ),
      );

      await tester.tap(find.text('show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Timed detail'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('Timed detail'), findsNothing);
    },
  );

  testWidgets('overlong snackbar durations are capped', (tester) async {
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
                    const SnackBar(
                      duration: Duration(days: 1),
                      content: Text('Not forever'),
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

    expect(find.text('Not forever'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Not forever'), findsNothing);
  });
}
