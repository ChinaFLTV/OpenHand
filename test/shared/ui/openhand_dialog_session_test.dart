import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  testWidgets('tracked dialog dismiss uses pop path and keeps host route', (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    late OpenHandDialogSession session;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('open'),
                  onPressed: () {
                    session = showTrackedAnimatedDialog(
                      context: context,
                      barrierDismissible: false,
                      dismissOnEscape: false,
                      builder: (dialogContext) {
                        return const AlertDialog(
                          title: Text('progress'),
                          content: Text('working'),
                        );
                      },
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('open'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.text('progress'), findsOneWidget);
    expect(find.text('open'), findsOneWidget);

    final removed = await session.dismiss();
    expect(removed, isTrue);
    // Allow reverse transition (pop, not hard removeRoute cut-out) to finish.
    await tester.pumpAndSettle();
    expect(find.text('progress'), findsNothing);
    expect(find.text('open'), findsOneWidget);

    // Second dismiss must be a no-op (must not pop home).
    final again = await session.dismiss();
    expect(again, isFalse);
    expect(find.text('open'), findsOneWidget);
    expect(navKey.currentState?.canPop() ?? false, isFalse);
  });

  testWidgets('dismiss waits for late route attach then closes dialog', (
    tester,
  ) async {
    late OpenHandDialogSession session;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () {
                  session = showTrackedAnimatedDialog(
                    context: context,
                    barrierDismissible: false,
                    dismissOnEscape: false,
                    builder: (_) => const AlertDialog(title: Text('progress')),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open')));
    // Intentionally do not pumpAndSettle: dialog route may not be built yet.
    // dismiss must wait for attach instead of permanently no-op'ing.
    final dismissFuture = session.dismiss(
      attachTimeout: const Duration(seconds: 1),
    );

    // Drive frames so the dialog builder attaches the route and pop runs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final removed = await dismissFuture;
    expect(removed, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('progress'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('dismiss is no-op after dialog already closed externally', (
    tester,
  ) async {
    late OpenHandDialogSession session;
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () {
                  session = showTrackedAnimatedDialog(
                    context: context,
                    barrierDismissible: false,
                    dismissOnEscape: false,
                    builder: (_) => const AlertDialog(title: Text('progress')),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.text('progress'), findsOneWidget);

    // External close of the dialog route only.
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('progress'), findsNothing);

    final dismissed = await session.dismiss();
    expect(dismissed, isFalse);
    // Host route must still be present — dismiss must not pop home.
    expect(find.text('open'), findsOneWidget);
    expect(navKey.currentState?.canPop() ?? false, isFalse);
  });

  testWidgets(
    'tracked loading dialog dismisses only itself before first frame',
    (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      late OpenHandDialogSession session;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  key: const Key('open-loading'),
                  onPressed: () {
                    session = showOpenHandTrackedLoadingDialog(
                      context: context,
                      message: 'working',
                    );
                  },
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-loading')));
      final dismissFuture = session.dismiss(
        attachTimeout: const Duration(seconds: 1),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(await dismissFuture, isTrue);
      await tester.pumpAndSettle();

      expect(find.text('working'), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(navKey.currentState?.canPop() ?? false, isFalse);
    },
  );
}
