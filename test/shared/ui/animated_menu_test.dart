import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_menu.dart';

void main() {
  testWidgets(
    'bidirectional animated menu opens and selects without layout exceptions',
    (tester) async {
      String? selectedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Center(
                  child: TextButton(
                    onPressed: () async {
                      selectedValue = await showAnimatedMenu<String>(
                        context: context,
                        position: const RelativeRect.fromLTRB(
                          120,
                          120,
                          520,
                          220,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 240,
                          maxWidth: 520,
                          maxHeight: 220,
                        ),
                        enableBidirectionalScroll: true,
                        items: List<PopupMenuEntry<String>>.generate(
                          24,
                          (index) => PopupMenuItem<String>(
                            value: 'tool_$index',
                            child: Text(
                              'extremely_long_mcp_tool_name_for_scroll_validation_$index',
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open Menu'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(() async {
        await mouse.removePointer();
      });

      await mouse.addPointer(location: const Offset(20, 20));
      await tester.pump();

      await tester.tap(find.text('Open Menu'));
      await tester.pump();

      await mouse.moveTo(const Offset(160, 160));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(
        find.text('extremely_long_mcp_tool_name_for_scroll_validation_0'),
        findsOneWidget,
      );

      await tester.tap(
        find.text('extremely_long_mcp_tool_name_for_scroll_validation_3'),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(selectedValue, 'tool_3');
    },
  );
}
