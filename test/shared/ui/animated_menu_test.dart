import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
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

  testWidgets('none animation popup menu uses a zero-duration route', (
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
                  showAnimatedMenu<int>(
                    context: context,
                    position: const RelativeRect.fromLTRB(20, 20, 20, 20),
                    settings: const DialogAnimationSettings(
                      entranceStyle: DialogAnimationStyle.none,
                      exitStyle: DialogAnimationStyle.none,
                      durationMs: 0,
                    ),
                    items: [
                      PopupMenuItem<int>(
                        value: 1,
                        child: Builder(
                          builder: (itemContext) {
                            final route = ModalRoute.of(itemContext);
                            transitionDuration = route?.transitionDuration;
                            reverseTransitionDuration =
                                route?.reverseTransitionDuration;
                            return const Text('Instant action');
                          },
                        ),
                      ),
                    ],
                  );
                },
                child: const Text('Open instant'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open instant'));
    await tester.pump();

    expect(find.text('Instant action'), findsOneWidget);
    expect(transitionDuration, Duration.zero);
    expect(reverseTransitionDuration, Duration.zero);
  });
}
