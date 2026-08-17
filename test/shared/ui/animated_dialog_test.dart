import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  testWidgets('弹簧缩放与普通缩放保持不同的Q弹进场', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 360),
      value: 0.8,
    );
    controller.forward();

    const springSettings = DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.springScale,
      exitStyle: DialogAnimationStyle.springScale,
    );
    const fadeScaleSettings = DialogAnimationSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: <Widget>[
            buildAnimationStyleTransition(
              animation: controller,
              settings: springSettings,
              child: const SizedBox(key: ValueKey<String>('spring')),
            ),
            buildAnimationStyleTransition(
              animation: controller,
              settings: fadeScaleSettings,
              child: const SizedBox(key: ValueKey<String>('fade-scale')),
            ),
          ],
        ),
      ),
    );

    Finder transitionOf(String key) => find.ancestor(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_PaintMatrixTransition',
      ),
    );

    final springTransform = tester.renderObject<RenderObject>(
      transitionOf('spring'),
    );
    final fadeScaleTransform = tester.renderObject<RenderObject>(
      transitionOf('fade-scale'),
    );
    final springChild = tester.renderObject(
      find.byKey(const ValueKey('spring')),
    );
    final fadeScaleChild = tester.renderObject(
      find.byKey(const ValueKey('fade-scale')),
    );
    final springParent = springTransform.parent!;
    final fadeScaleParent = fadeScaleTransform.parent!;
    expect(springChild.getTransformTo(springParent).storage[0], greaterThan(1));
    expect(
      fadeScaleChild.getTransformTo(fadeScaleParent).storage[0],
      lessThan(1),
    );
    controller.dispose();
  });
}
