import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';
import 'package:openhand/shared/ui/bounded_animation.dart';

const _matrixStyles = <DialogAnimationStyle>[
  DialogAnimationStyle.fadeScale,
  DialogAnimationStyle.expand,
  DialogAnimationStyle.rotateScale,
  DialogAnimationStyle.elastic,
  DialogAnimationStyle.springScale,
  DialogAnimationStyle.flipX,
];

void main() {
  test('回弹曲线超调值再次进入曲线前会被限制', () {
    final overshooting = openHandCurveAnimation(
      parent: const AlwaysStoppedAnimation<double>(0.8),
      curve: Curves.easeOutBack,
    );
    expect(overshooting.value, greaterThan(1.0));

    final nested = openHandCurveAnimation(
      parent: overshooting,
      curve: Curves.easeInOut,
    );
    expect(() => nested.value, returnsNormally);
    expect(nested.value, 1.0);
  });

  for (final style in _matrixStyles) {
    testWidgets('${style.name} 在 LayoutBuilder 内不逐帧请求重建', (tester) async {
      final key = GlobalKey<_TransitionHarnessState>();
      await tester.pumpWidget(_TransitionHarness(key: key, style: style));

      key.currentState!.toggle();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      final transition = find.descendant(
        of: find.byKey(const ValueKey<String>('switcher')),
        matching: find.byWidgetPredicate((widget) {
          return widget is ScaleTransition ||
              widget is RotationTransition ||
              widget is AnimatedBuilder;
        }),
      );
      expect(transition, findsNothing);
      expect(tester.takeException(), isNull);

      key.currentState!.toggle();
      await tester.pump(const Duration(milliseconds: 40));
      key.currentState!.toggle();
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

class _TransitionHarness extends StatefulWidget {
  const _TransitionHarness({super.key, required this.style});

  final DialogAnimationStyle style;

  @override
  State<_TransitionHarness> createState() => _TransitionHarnessState();
}

class _TransitionHarnessState extends State<_TransitionHarness> {
  bool _second = false;

  void toggle() => setState(() => _second = !_second);

  @override
  Widget build(BuildContext context) {
    final settings = DialogAnimationSettings(
      entranceStyle: widget.style,
      exitStyle: widget.style,
      durationMs: 320,
      curve: DialogAnimationCurve.elasticOut,
    );
    return MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            return AnimatedSwitcher(
              key: const ValueKey<String>('switcher'),
              duration: settings.entranceDuration,
              reverseDuration: settings.exitDuration,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                return buildAnimationStyleTransition(
                  animation: animation,
                  settings: settings,
                  child: child,
                );
              },
              child: SizedBox.expand(
                key: ValueKey<bool>(_second),
                child: ColoredBox(color: _second ? Colors.blue : Colors.orange),
              ),
            );
          },
        ),
      ),
    );
  }
}
