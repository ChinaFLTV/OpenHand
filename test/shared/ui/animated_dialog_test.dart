import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  testWidgets('none animation dialog uses a zero-duration route', (
    tester,
  ) async {
    Duration? transitionDuration;
    Duration? reverseTransitionDuration;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showAnimatedDialog<void>(
                    context: context,
                    settings: const DialogAnimationSettings(
                      entranceStyle: DialogAnimationStyle.none,
                      exitStyle: DialogAnimationStyle.none,
                      durationMs: 0,
                    ),
                    builder: (dialogContext) {
                      final route = ModalRoute.of(dialogContext);
                      transitionDuration = route?.transitionDuration;
                      reverseTransitionDuration =
                          route?.reverseTransitionDuration;
                      return const AlertDialog(content: Text('Instant dialog'));
                    },
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(find.text('Instant dialog'), findsOneWidget);
    expect(transitionDuration, Duration.zero);
    expect(reverseTransitionDuration, Duration.zero);
  });
}
