import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  testWidgets('上下文卸载后显示弹窗会安全返回', (tester) async {
    late BuildContext staleContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            staleContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    final result = await showAnimatedDialog<bool>(
      context: staleContext,
      builder: (_) => const Dialog(child: Text('不应显示')),
    );

    expect(result, isNull);
    expect(find.text('不应显示'), findsNothing);
  });

  testWidgets('PopScope 拒绝首次 ESC 后仍可再次关闭弹窗', (tester) async {
    final canPop = ValueNotifier<bool>(false);
    addTearDown(canPop.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () {
                showAnimatedDialog<void>(
                  context: context,
                  settings: OpenHandMotionDefaults.disabled,
                  builder: (_) => ValueListenableBuilder<bool>(
                    valueListenable: canPop,
                    builder: (context, allowed, child) =>
                        PopScope<void>(canPop: allowed, child: child!),
                    child: const Dialog(child: Text('测试弹窗')),
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('测试弹窗'), findsOneWidget);

    canPop.value = true;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('测试弹窗'), findsNothing);
  });
}
