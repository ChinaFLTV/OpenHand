import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_appearance.dart';

void main() {
  testWidgets('AnimatedAppearance renders directly when ticker is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: false,
          child: AnimatedAppearance(
            settings: DialogAnimationSettings.defaults,
            child: Text('entry'),
          ),
        ),
      ),
    );

    expect(find.text('entry'), findsOneWidget);
    expect(find.byType(SizeTransition), findsNothing);
    expect(find.byType(FadeTransition), findsNothing);
  });

  testWidgets('AnimatedAppearance dismisses immediately without motion', (
    tester,
  ) async {
    var present = true;
    var dismissed = 0;

    Widget build() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: false,
          child: AnimatedAppearance(
            present: present,
            settings: DialogAnimationSettings.defaults,
            onDismissed: () => dismissed += 1,
            child: const Text('entry'),
          ),
        ),
      );
    }

    await tester.pumpWidget(build());
    expect(find.text('entry'), findsOneWidget);

    present = false;
    await tester.pumpWidget(build());
    await tester.pump();

    expect(find.text('entry'), findsNothing);
    expect(dismissed, 1);
  });

  testWidgets('AnimatedAppearance renders directly for disabled settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AnimatedAppearance(
          settings: OpenHandMotionDefaults.disabled,
          child: Text('entry'),
        ),
      ),
    );

    expect(find.text('entry'), findsOneWidget);
    expect(find.byType(SizeTransition), findsNothing);
    expect(find.byType(FadeTransition), findsNothing);
  });

  testWidgets('AnimatedListAppearance renders directly without motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: false,
          child: AnimatedListAppearance(
            animation: AlwaysStoppedAnimation<double>(0),
            settings: DialogAnimationSettings.defaults,
            phase: AnimatedAppearancePhase.enter,
            child: Text('row'),
          ),
        ),
      ),
    );

    expect(find.text('row'), findsOneWidget);
    expect(find.byType(SizeTransition), findsNothing);
    expect(find.byType(FadeTransition), findsNothing);
  });

  testWidgets(
    'AnimatedListAppearance ignores collapsed animation when disabled',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AnimatedListAppearance(
            animation: AlwaysStoppedAnimation<double>(0),
            settings: OpenHandMotionDefaults.disabled,
            phase: AnimatedAppearancePhase.exit,
            child: Text('row'),
          ),
        ),
      );

      expect(find.text('row'), findsOneWidget);
      expect(find.byType(SizeTransition), findsNothing);
      expect(find.byType(FadeTransition), findsNothing);
    },
  );
}
