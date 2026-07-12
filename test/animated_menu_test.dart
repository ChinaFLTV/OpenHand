import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_menu.dart';
import 'package:openhand/shared/ui/openhand_safe_scrollbar.dart';

void main() {
  const noMotion = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.none,
    exitStyle: DialogAnimationStyle.none,
  );
  const animatedExit = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.none,
    exitStyle: DialogAnimationStyle.fade,
    durationMs: 300,
  );
  const animatedSurface = DialogAnimationSettings(
    exitStyle: DialogAnimationStyle.none,
    durationMs: 300,
  );

  testWidgets('disabled menu motion preserves custom scrolling behavior', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 300);
    addTearDown(tester.view.reset);
    late BuildContext hostContext;
    await tester.pumpWidget(
      _testApp(onContext: (value) => hostContext = value),
    );

    final result = showAnimatedMenu<int>(
      context: hostContext,
      position: const RelativeRect.fromLTRB(12, 12, 12, 12),
      items: const <PopupMenuEntry<int>>[
        PopupMenuItem<int>(
          value: 1,
          child: SizedBox(width: 600, child: Text('wide-menu-entry')),
        ),
      ],
      settings: noMotion,
      enableBidirectionalScroll: true,
    );
    await tester.pump();

    expect(find.byType(OpenHandSafeScrollbar), findsNWidgets(2));
    Navigator.of(hostContext).pop(1);
    await tester.pump();
    expect(await result, 1);

    expect(
      await showAnimatedMenu<int>(
        context: hostContext,
        position: RelativeRect.fill,
        items: const <PopupMenuEntry<int>>[],
      ),
      isNull,
    );
  });

  testWidgets('nullable dropdown selection waits for its configured exit', (
    tester,
  ) async {
    String? selected = 'one';
    var itemTapped = false;
    await tester.pumpWidget(
      _testApp(
        childBuilder: (context) => StatefulBuilder(
          builder: (context, setState) {
            return AnimatedDropdownButton<String?>(
              value: selected,
              animationSettings: animatedExit,
              items: <DropdownMenuItem<String?>>[
                DropdownMenuItem<String?>(
                  onTap: () => itemTapped = true,
                  child: const Text('None'),
                ),
                const DropdownMenuItem<String?>(
                  value: 'one',
                  child: Text('One'),
                ),
              ],
              onChanged: (value) => setState(() => selected = value),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byType(AnimatedDropdownButton<String?>));
    await tester.pump();
    await tester.tap(find.text('None'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(selected, isNull);
    expect(itemTapped, isTrue);
    expect(find.text('None'), findsNWidgets(2));

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(selected, isNull);
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('menu transition wraps the anchored surface, not the viewport', (
    tester,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      _testApp(onContext: (value) => hostContext = value),
    );
    final result = showAnimatedMenu<int>(
      context: hostContext,
      position: const RelativeRect.fromLTRB(20, 20, 20, 20),
      settings: animatedSurface,
      items: const <PopupMenuEntry<int>>[
        PopupMenuItem<int>(value: 1, child: Text('surface-entry')),
      ],
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final viewportSize =
        tester.view.physicalSize / tester.view.devicePixelRatio;
    final transitions = find.byType(ScaleTransition);
    final transitionSizes = <Size>[
      for (var index = 0; index < transitions.evaluate().length; index++)
        tester.getSize(transitions.at(index)),
    ];
    expect(
      transitionSizes.any(
        (size) =>
            size.width < viewportSize.width &&
            size.height < viewportSize.height,
      ),
      isTrue,
    );

    Navigator.of(hostContext).pop(1);
    await tester.pump();
    expect(await result, 1);
  });

  testWidgets(
    'form dropdown validates, resets, and can block barrier dismissal',
    (tester) async {
      final formKey = GlobalKey<FormState>();
      String? changedValue;
      await tester.pumpWidget(
        _testApp(
          childBuilder: (context) => Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AnimatedDropdownButtonFormField<String>(
                  key: const ValueKey<String>('form-dropdown'),
                  initialValue: 'a',
                  animationSettings: noMotion,
                  barrierDismissible: false,
                  decoration: const InputDecoration(labelText: 'Choice'),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'a', child: Text('A')),
                    DropdownMenuItem<String>(value: 'b', child: Text('B')),
                  ],
                  validator: (value) => value == 'b' ? null : 'pick-b',
                  onChanged: (value) => changedValue = value,
                ),
                const Text('outside-target'),
              ],
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('pick-b'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('form-dropdown')));
      await tester.pump();
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(find.text('B'), findsOneWidget);

      await tester.tap(find.text('B'));
      await tester.pump();
      expect(changedValue, 'b');
      expect(formKey.currentState!.validate(), isTrue);

      formKey.currentState!.reset();
      await tester.pump();
      expect(changedValue, 'a');
      expect(find.text('A'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.text('B'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(changedValue, 'b');
    },
  );
}

Widget _testApp({
  ValueChanged<BuildContext>? onContext,
  WidgetBuilder? childBuilder,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        onContext?.call(context);
        return Scaffold(
          body: Center(
            child: childBuilder?.call(context) ?? const Text('host'),
          ),
        );
      },
    ),
  );
}
