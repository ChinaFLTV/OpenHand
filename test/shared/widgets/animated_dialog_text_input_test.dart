import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/widgets/animated_dialog.dart';

/// 回归保护：`showAnimatedDialog` 不应把对话框内 TextField 的焦点抢走，
/// 同时 Esc-to-dismiss 必须仍然有效。曾经一版用 `Focus(autofocus:true)`
/// 包裹整个对话框，导致 macOS / Web 端 TextField 拿不到键盘与剪贴板焦点。
void main() {
  testWidgets('dialog TextField still receives autofocus + keyboard input',
      (tester) async {
    late BuildContext rootContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            rootContext = ctx;
            return const Scaffold();
          },
        ),
      ),
    );

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    _showAndForget(
      rootContext,
      AlertDialog(
        content: TextField(
          autofocus: true,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);

    // 直接走 TextInput.updateEditingValue 模拟系统输入法/键盘把字符
    // 推给 EditableText —— 对话框没有抢走焦点时才会成功。
    await tester.enterText(textField, 'hello');
    expect(controller.text, equals('hello'));
  });

  testWidgets('Esc on focused button still dismisses the dialog',
      (tester) async {
    late BuildContext rootContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            rootContext = ctx;
            return const Scaffold();
          },
        ),
      ),
    );

    bool popped = false;
    _showAndForget(
      rootContext,
      AlertDialog(
        content: TextButton(
          autofocus: true,
          onPressed: () {},
          child: const Text('OK'),
        ),
      ),
    ).whenComplete(() => popped = true);
    await tester.pumpAndSettle();

    expect(find.text('OK'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(find.text('OK'), findsNothing);
  });
}

/// 简单的不必 await 的 helper，避免每个 case 重复样板。
Future<T?> _showAndForget<T>(BuildContext context, Widget body) {
  return showAnimatedDialog<T>(
    context: context,
    builder: (_) => body,
  );
}
