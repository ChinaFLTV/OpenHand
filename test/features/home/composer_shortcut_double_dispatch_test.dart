// Reproduces the production composer dispatch tree to verify a Ctrl+P press
// triggers the toggle action exactly once when:
//   - HardwareKeyboard handler fires (and returns false to defer)
//   - FocusNode.onKeyEvent fires
//   - An ancestor Shortcuts widget binds Ctrl+P
//   - macOS DefaultTextEditingShortcuts maps Ctrl+P to MoveSelectionUp
//
// 2026-04-28: Bug regression: user reports composer toggles "flash and do
// nothing" – this test pins down whether a duplicate dispatch causes the
// action to fire twice and visually cancel out.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'production-style tree: Ctrl+P toggle fires exactly once',
    (tester) async {
      var toggleInvocations = 0;

      final focusNode = FocusNode();
      // FocusNode handler returns handled to stop further dispatch.
      focusNode.onKeyEvent = (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyP &&
            HardwareKeyboard.instance.isControlPressed) {
          toggleInvocations += 1;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };

      // HardwareKeyboard handler returns false (defers to focus tree).
      bool hwHandler(KeyEvent event) {
        return false;
      }

      HardwareKeyboard.instance.addHandler(hwHandler);
      addTearDown(() => HardwareKeyboard.instance.removeHandler(hwHandler));

      await tester.pumpWidget(
        MaterialApp(
          // The MaterialApp internally installs DefaultTextEditingShortcuts,
          // which maps Ctrl+P to MoveSelectionUpTextIntent on macOS.
          home: Material(
            child: Shortcuts(
              shortcuts: <ShortcutActivator, Intent>{
                const SingleActivator(
                  LogicalKeyboardKey.keyP,
                  control: true,
                ): const _ToggleIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  _ToggleIntent: CallbackAction<_ToggleIntent>(
                    onInvoke: (_) {
                      toggleInvocations += 1;
                      return null;
                    },
                  ),
                },
                child: TextField(focusNode: focusNode),
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(
        toggleInvocations,
        1,
        reason:
            'Toggle action must fire exactly once when FocusNode returns '
            'handled; firing twice indicates Shortcuts widget also dispatched.',
      );
    },
  );
}

class _ToggleIntent extends Intent {
  const _ToggleIntent();
}
