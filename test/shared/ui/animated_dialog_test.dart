import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

Future<BuildContext> _pumpDialogHost(WidgetTester tester) async {
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          pageContext = context;
          return const Scaffold(body: SizedBox.expand());
        },
      ),
    ),
  );
  return pageContext;
}

void main() {
  testWidgets('普通弹窗可通过 ESC 关闭', (tester) async {
    final context = await _pumpDialogHost(tester);
    final result = showAnimatedDialog<void>(
      context: context,
      settings: OpenHandMotionDefaults.disabled,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(title: Text('普通弹窗')),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('普通弹窗'), findsNothing);
    await result;
  });

  testWidgets('ESC 只关闭最顶层弹窗', (tester) async {
    final context = await _pumpDialogHost(tester);
    final outerResult = showAnimatedDialog<void>(
      context: context,
      settings: OpenHandMotionDefaults.disabled,
      builder: (_) => const AlertDialog(title: Text('外层弹窗')),
    );
    await tester.pump();
    final innerResult = showAnimatedDialog<void>(
      context: tester.element(find.text('外层弹窗')),
      settings: OpenHandMotionDefaults.disabled,
      builder: (_) => const AlertDialog(title: Text('内层弹窗')),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('内层弹窗'), findsNothing);
    expect(find.text('外层弹窗'), findsOneWidget);
    await innerResult;

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('外层弹窗'), findsNothing);
    await outerResult;
  });

  testWidgets('禁用 ESC 的审批弹窗保持打开', (tester) async {
    final context = await _pumpDialogHost(tester);
    final result = showAnimatedDialog<void>(
      context: context,
      settings: OpenHandMotionDefaults.disabled,
      barrierDismissible: false,
      dismissOnEscape: false,
      builder: (_) => const AlertDialog(title: Text('执行审批')),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.text('执行审批'), findsOneWidget);
    Navigator.of(tester.element(find.text('执行审批'))).pop();
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('遮罩关闭与 ESC 策略相互独立', (tester) async {
    final context = await _pumpDialogHost(tester);
    final result = showAnimatedDialog<void>(
      context: context,
      settings: OpenHandMotionDefaults.disabled,
      dismissOnEscape: false,
      builder: (_) => const AlertDialog(title: Text('独立关闭策略')),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('独立关闭策略'), findsNothing);
    await result;
  });

  testWidgets('确认弹窗默认不响应 ESC', (tester) async {
    final context = await _pumpDialogHost(tester);
    final result = showOpenHandConfirmDialog(
      context: context,
      title: '删除确认',
      confirmLabel: '删除',
    );
    await tester.pump();
    expect(find.text('删除确认'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.text('删除确认'), findsOneWidget);
    Navigator.of(tester.element(find.text('删除确认'))).pop(false);
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('自定义浮层 Scope 的 ESC 只触发自身关闭回调', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OpenHandEscapeDismissScope(
          onDismiss: () => dismissed = true,
          child: const Scaffold(body: Text('底层页面')),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(dismissed, isTrue);
    expect(find.text('底层页面'), findsOneWidget);
  });
}
