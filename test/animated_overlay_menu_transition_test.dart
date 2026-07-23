import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_menu.dart';
import 'package:openhand/shared/ui/animated_overlay.dart';

const _kDirectionalSettings = DialogAnimationSettings(
  entranceStyle: DialogAnimationStyle.slideUp,
  exitStyle: DialogAnimationStyle.fade,
  durationMs: 120,
);

Widget _nearestStyleTransition(WidgetTester tester, Finder finder) {
  Widget? transition;
  tester.element(finder).visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is FadeTransition || widget is SlideTransition) {
      transition = widget;
      return false;
    }
    return true;
  });
  return transition!;
}

void main() {
  testWidgets('浮层默认使用菜单动画设置', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedOverlayContent(
          child: SizedBox(
            key: ValueKey<String>('default-overlay-content'),
            width: 20,
            height: 20,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 180));

    final overlayContent = find.byKey(
      const ValueKey<String>('default-overlay-content'),
    );
    final transition =
        _nearestStyleTransition(tester, overlayContent) as FadeTransition;
    expect(transition.opacity.value, lessThan(1));
  });

  testWidgets('浮层退场使用配置的退场样式', (tester) async {
    final visibility = ValueNotifier<bool>(true);
    addTearDown(visibility.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedOverlayContent(
          customSettings: _kDirectionalSettings,
          visibility: visibility,
          child: const SizedBox(
            key: ValueKey<String>('overlay-content'),
            width: 20,
            height: 20,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final overlayContent = find.byKey(
      const ValueKey<String>('overlay-content'),
    );
    expect(
      _nearestStyleTransition(tester, overlayContent),
      isA<SlideTransition>(),
    );

    visibility.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      _nearestStyleTransition(tester, overlayContent),
      isA<FadeTransition>(),
    );
  });

  testWidgets('菜单退场使用配置的退场样式', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              unawaited(
                showAnimatedMenu<String>(
                  context: context,
                  position: RelativeRect.fill,
                  settings: _kDirectionalSettings,
                  items: const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'value',
                      child: Text('菜单项', key: ValueKey<String>('menu-item')),
                    ),
                  ],
                ),
              );
            },
            child: const Text('打开菜单'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开菜单'));
    await tester.pump();

    final menuItem = find.byKey(const ValueKey<String>('menu-item'));
    expect(_nearestStyleTransition(tester, menuItem), isA<SlideTransition>());

    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(_nearestStyleTransition(tester, menuItem), isA<FadeTransition>());
  });
}
