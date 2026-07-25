import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_appearance.dart';

const _settings = DialogAnimationSettings(
  entranceStyle: DialogAnimationStyle.slideRight,
  exitStyle: DialogAnimationStyle.slideRight,
  durationMs: 400,
);

void main() {
  testWidgets('尺寸动画处于待布局状态时鼠标命中不会触发断言', (tester) async {
    final harnessKey = GlobalKey<_PointerHarnessState>();
    await tester.pumpWidget(_PointerHarness(key: harnessKey));
    await tester.pumpAndSettle();

    final appearance = find.byKey(const ValueKey<String>('appearance'));
    expect(
      find.descendant(of: appearance, matching: find.byType(SlideTransition)),
      findsNothing,
    );
    final target = tester.getCenter(find.byKey(const ValueKey('target')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: target);

    harnessKey.currentState!.hide();
    await tester.pump(Duration.zero, EnginePhase.build);
    await tester.pump(const Duration(milliseconds: 80), EnginePhase.build);
    await mouse.moveTo(target + const Offset(1, 0));

    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await mouse.removePointer();
  });

  testWidgets('胶囊退出时后项连续补位并在重新出现时平滑让位', (tester) async {
    final harnessKey = GlobalKey<_ChipSequenceHarnessState>();
    await tester.pumpWidget(_ChipSequenceHarness(key: harnessKey));
    await tester.pumpAndSettle();

    final chipC = find.byKey(const ValueKey<String>('chip-c'));
    final initialX = tester.getTopLeft(chipC).dx;

    harnessKey.currentState!.hideMiddle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final exitingX = tester.getTopLeft(chipC).dx;
    expect(exitingX, lessThan(initialX));

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('chip-b')), findsNothing);
    final compactX = tester.getTopLeft(chipC).dx;
    expect(compactX, lessThan(exitingX));

    harnessKey.currentState!.showMiddle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final enteringX = tester.getTopLeft(chipC).dx;
    expect(enteringX, greaterThan(compactX));
    expect(enteringX, lessThan(initialX));

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(chipC).dx, closeTo(initialX, 0.01));
    expect(tester.takeException(), isNull);
  });
}

class _PointerHarness extends StatefulWidget {
  const _PointerHarness({super.key});

  @override
  State<_PointerHarness> createState() => _PointerHarnessState();
}

class _PointerHarnessState extends State<_PointerHarness> {
  bool _present = true;

  void hide() => setState(() => _present = false);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            AnimatedAppearance(
              key: const ValueKey<String>('appearance'),
              present: _present,
              settings: _settings,
              child: const MouseRegion(
                child: SizedBox(
                  key: ValueKey<String>('target'),
                  height: 80,
                  width: 240,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipSequenceHarness extends StatefulWidget {
  const _ChipSequenceHarness({super.key});

  @override
  State<_ChipSequenceHarness> createState() => _ChipSequenceHarnessState();
}

class _ChipSequenceHarnessState extends State<_ChipSequenceHarness> {
  final List<String> _displayed = <String>['a', 'b', 'c'];
  final Set<String> _present = <String>{'a', 'b', 'c'};

  void hideMiddle() => setState(() => _present.remove('b'));

  void showMiddle() {
    setState(() {
      _present.add('b');
      _displayed.insert(1, 'b');
    });
  }

  void _remove(String id) {
    if (_present.contains(id)) return;
    setState(() => _displayed.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final id in _displayed)
                AnimatedAppearance(
                  key: ValueKey<String>('appearance-$id'),
                  present: _present.contains(id),
                  settings: _settings,
                  collapseAxis: Axis.horizontal,
                  onDismissed: () => _remove(id),
                  child: SizedBox(
                    key: ValueKey<String>('chip-$id'),
                    width: 100,
                    height: 40,
                    child: Text(id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
