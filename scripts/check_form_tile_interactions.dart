import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'form_tile_interactions',
  source: r'''
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/shared/ui/animated_expandable.dart';
import 'package:openhand/shared/ui/openhand_form_fields.dart';

void main() {
  testWidgets('表单行长按不绘制覆盖色，点击、键盘和禁用行为保持正常', (tester) async {
    for (final brightness in Brightness.values) {
      for (final kind in ['switch', 'checkbox', 'animatedSwitch', 'select']) {
        final theme = brightness == Brightness.dark
            ? OpenHandTheme.dark(OpenHandThemePreset.tundraGreen)
            : OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
        final key = GlobalKey();
        var value = false;
        var enabled = true;
        var changes = 0;
        late StateSetter update;
        await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            update = setState;
            void change(bool next) => setState(() { value = next; changes++; });
            final row = switch (kind) {
              'switch' => OpenHandFormTile(child: SwitchListTile(
                title: const Text('表单选项'), value: value,
                onChanged: enabled ? change : null)),
              'checkbox' => OpenHandFormTile(child: CheckboxListTile(
                title: const Text('表单选项'), value: value,
                onChanged: enabled ? (next) => change(next!) : null)),
              'animatedSwitch' => OpenHandAnimatedSwitchTile(
                icon: Icons.settings, title: '表单选项', description: '',
                value: value, enabled: enabled, onChanged: change),
              _ => OpenHandSelectTile(icon: Icons.settings, label: '表单选项',
                selected: value, enabled: enabled, onTap: () => change(!value)),
            };
            return RepaintBoundary(key: key, child: Material(child: row));
          }),
        )));
        await tester.pumpAndSettle();
        Future<Uint8List> pixels() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
          return bytes!.buffer.asUint8List();
        }
        final before = await tester.runAsync(pixels);
        final press = await tester.startGesture(tester.getCenter(find.text('表单选项')));
        await tester.pump(const Duration(milliseconds: 700));
        final held = await tester.runAsync(pixels);
        expect(listEquals(before, held), isTrue, reason: '$kind / $brightness 长按不应出现整行矩形背景');
        expect(changes, 0);
        await press.up(); await tester.pumpAndSettle();
        expect(changes, 1); expect(value, isTrue);
        final ink = find.descendant(of: find.byKey(key), matching: find.byType(InkWell)).first;
        final localTheme = Theme.of(tester.element(ink));
        expect(localTheme.focusColor, theme.focusColor);
        Focus.of(tester.element(find.text('表单选项'))).requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
        expect(changes, 2); expect(value, isFalse);
        update(() => enabled = false); await tester.pumpAndSettle();
        await tester.tap(find.text('表单选项')); await tester.pumpAndSettle();
        expect(changes, 2); expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('原生与公共折叠卡片保留原有按压反馈和展开行为', (tester) async {
    final theme = OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
    for (final custom in [false, true]) {
      await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body:
        custom ? OpenHandExpansionTile(title: const Text('展开分组'), children: const [Text('分组内容')])
          : const ExpansionTile(title: Text('展开分组'), children: [Text('分组内容')]),
      )));
      await tester.pumpAndSettle();
      final title = find.text('展开分组');
      final inherited = Theme.of(tester.element(title));
      expect(inherited.highlightColor, theme.highlightColor);
      expect(inherited.splashFactory, theme.splashFactory);
      await tester.longPress(title); await tester.pumpAndSettle();
      expect(find.text('分组内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
''',
);
