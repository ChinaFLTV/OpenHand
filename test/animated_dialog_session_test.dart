import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  testWidgets('covered tracked dialog defers its animated dismissal', (
    tester,
  ) async {
    late OpenHandDialogSession trackedSession;
    late BuildContext hostContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    trackedSession = showTrackedAnimatedDialog(
      context: hostContext,
      builder: (_) => const Dialog(
        key: ValueKey<String>('tracked-dialog'),
        child: SizedBox(width: 180, height: 100),
      ),
    );
    await tester.pumpAndSettle();

    showAnimatedDialog<void>(
      context: hostContext,
      builder: (context) => Dialog(
        key: const ValueKey<String>('covering-dialog'),
        child: TextButton(
          key: const ValueKey<String>('close-covering-dialog'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(await trackedSession.dismiss(), isTrue);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('covering-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('tracked-dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('close-covering-dialog')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('covering-dialog')), findsNothing);
    expect(find.byKey(const ValueKey<String>('tracked-dialog')), findsNothing);
    expect(trackedSession.isClosed, isTrue);
  });
}
