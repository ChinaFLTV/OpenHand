import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_appearance.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';
import 'package:openhand/shared/ui/bounded_animation.dart';

void main() {
  group('OpenHand animation bounds', () {
    test('clamps finite and non-finite progress values', () {
      expect(
        const OpenHandBoundedDoubleAnimation(
          AlwaysStoppedAnimation<double>(1.0075821302831174),
        ).value,
        1.0,
      );
      expect(
        const OpenHandBoundedDoubleAnimation(
          AlwaysStoppedAnimation<double>(-0.05),
        ).value,
        0.0,
      );
      expect(
        const OpenHandBoundedDoubleAnimation(
          AlwaysStoppedAnimation<double>(double.nan),
        ).value,
        0.0,
      );
    });

    test('curves clamp input before transform', () {
      final opacity = openHandBoundedCurveAnimation(
        parent: const AlwaysStoppedAnimation<double>(1.0092810608446598),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      expect(opacity.value, 1.0);

      final motion = openHandCurveAnimation(
        parent: const AlwaysStoppedAnimation<double>(1.0092810608446598),
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      expect(motion.value.isFinite, isTrue);
    });

    testWidgets('shared dialog transitions tolerate overrange progress', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          buildAnimationStyleTransition(
            animation: const AlwaysStoppedAnimation<double>(1.0075821302831174),
            settings: const DialogAnimationSettings(
              entranceStyle: DialogAnimationStyle.expand,
              exitStyle: DialogAnimationStyle.expand,
              curve: DialogAnimationCurve.easeInOutCubicEmphasized,
            ),
            child: const SizedBox(
              key: ValueKey<String>('bounded-dialog-child'),
              width: 24,
              height: 24,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('bounded-dialog-child')),
        findsOneWidget,
      );
    });

    testWidgets('list appearances bound size and opacity progress', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AnimatedListAppearance(
            animation: AlwaysStoppedAnimation<double>(1.0075821302831174),
            settings: DialogAnimationSettings(
              entranceStyle: DialogAnimationStyle.springScale,
              curve: DialogAnimationCurve.elasticOut,
            ),
            phase: AnimatedAppearancePhase.enter,
            child: SizedBox(
              key: ValueKey<String>('bounded-list-child'),
              width: 24,
              height: 24,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('bounded-list-child')),
        findsOneWidget,
      );
    });

    testWidgets('shared transitions tolerate an already-overshooting parent', (
      tester,
    ) async {
      final overshootingParent = openHandCurveAnimation(
        parent: const AlwaysStoppedAnimation<double>(0.744),
        curve: const Cubic(0.22, 1.22, 0.36, 1.0),
      );

      await tester.pumpWidget(
        _host(
          buildAnimationStyleTransition(
            animation: overshootingParent,
            settings: const DialogAnimationSettings(),
            child: const SizedBox(
              key: ValueKey<String>('overshoot-parent-child'),
              width: 24,
              height: 24,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('overshoot-parent-child')),
        findsOneWidget,
      );
    });
  });
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}
