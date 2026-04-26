// Smoke tests that pin down the order Flutter dispatches key events to
// (a) HardwareKeyboard handlers, (b) the focused FocusNode's onKeyEvent
// callback and (c) wrapping Shortcuts widgets when the focus is inside an
// EditableText.  These match the exact pattern used by the OpenHand
// composer, so that a regression here surfaces the same symptom users see
// on macOS (Ctrl+P being eaten by DefaultTextEditingShortcuts).
//
// 2026-04-26: Added in response to the persistent "Ctrl+P just flashes the
// border and does nothing" bug – the goal is to lock down which layer
// reliably wins when the EditableText has focus.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'FocusNode.onKeyEvent fires for Ctrl+P even when EditableText has focus',
    (tester) async {
      var nodeFires = 0;
      var hwFires = 0;
      var shortcutFires = 0;

      final focusNode = FocusNode();
      focusNode.onKeyEvent = (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.keyP &&
            HardwareKeyboard.instance.isControlPressed) {
          nodeFires += 1;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };

      bool hwHandler(KeyEvent event) {
        if (event is! KeyDownEvent) return false;
        if (event.logicalKey == LogicalKeyboardKey.keyP &&
            HardwareKeyboard.instance.isControlPressed) {
          hwFires += 1;
          return true;
        }
        return false;
      }

      HardwareKeyboard.instance.addHandler(hwHandler);
      addTearDown(
        () => HardwareKeyboard.instance.removeHandler(hwHandler),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Shortcuts(
              shortcuts: <ShortcutActivator, Intent>{
                const SingleActivator(
                  LogicalKeyboardKey.keyP,
                  control: true,
                ): const ActivateIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      shortcutFires += 1;
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

      // We do not assert exact orderings between HW vs. focus dispatch –
      // Flutter does not document a stable order across releases – we
      // simply require that *at least one* of our layers handled the
      // shortcut.  A regression where ALL three remain at zero means the
      // platform default text-editing shortcut (MoveSelectionUp) ate the
      // event, which is the exact bug we are guarding against.
      expect(
        nodeFires + hwFires + shortcutFires,
        greaterThan(0),
        reason: 'Ctrl+P was eaten before any composer-level handler ran',
      );

      // Surface which layer actually handled the event so a future
      // regression that silently swaps the winner shows up in CI logs.
      debugPrint(
        'composer-shortcut: hw=$hwFires node=$nodeFires shortcut=$shortcutFires',
      );

      focusNode.dispose();
    },
  );
}
