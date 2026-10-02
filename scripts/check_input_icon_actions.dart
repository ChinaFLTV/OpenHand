import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'input_icon_actions',
  source: '''
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/shared/ui/openhand_input_icon_action.dart';
import 'package:openhand/features/services/widgets/service_dialog_controls.dart';

void main() {
  setUpAll(()async {
    if(Platform.environment['INPUT_ICON_FONT'] case final String path) {
      await (FontLoader('MaterialIcons')..addFont(File(path).readAsBytes().then((bytes)=>ByteData.sublistView(bytes)))).load();
    }
  });
  testWidgets('输入框图标在明暗主题、双向布局和紧凑高度下保持四周间距', (tester) async {
    for (final brightness in Brightness.values) {
      for (final direction in TextDirection.values) {
        for (final height in [32.0, 36.0, 40.0, 48.0, 64.0, 120.0]) {
          for (final prefix in [false, true]) {
            final theme = brightness == Brightness.light
                ? OpenHandTheme.light(OpenHandThemePreset.tundraGreen)
                : OpenHandTheme.dark(OpenHandThemePreset.tundraGreen);
            var changes = 0;
            final button = OpenHandInputIconAction(child: IconButton(
              onPressed: () => changes++, tooltip: '搜索',
              icon: const Icon(Icons.search_rounded, size: 18),
            ));
            await tester.pumpWidget(MaterialApp(theme: theme, home: Directionality(
              textDirection: direction,
              child: Scaffold(body: Center(child: SizedBox(width: 300, height: height,
                child: TextField(decoration: InputDecoration(
                  isDense: true, contentPadding: EdgeInsets.zero,
                  prefixIcon: prefix ? button : null,
                  suffixIcon: prefix ? null : button,
                  prefixIconConstraints: BoxConstraints.tightFor(width: 40, height: height),
                  suffixIconConstraints: BoxConstraints.tightFor(width: 40, height: height),
                  border: const OutlineInputBorder(),
                )),
              ))),
            )));
            await tester.pumpAndSettle();
            final frame = tester.getRect(find.byType(TextField));
            final surface = find.descendant(of: find.byType(IconButton), matching: find.byType(Material)).last;
            void checkSpacing() {
              final rect = tester.getRect(surface);
              expect(rect.width, lessThanOrEqualTo(kOpenHandInputIconExtent));
              expect(rect.height, lessThanOrEqualTo(kOpenHandInputIconExtent));
              expect(rect.top - frame.top, greaterThanOrEqualTo(kOpenHandInputIconInset));
              expect(frame.bottom - rect.bottom, greaterThanOrEqualTo(kOpenHandInputIconInset));
              expect(rect.left - frame.left, greaterThanOrEqualTo(kOpenHandInputIconInset));
              expect(frame.right - rect.right, greaterThanOrEqualTo(kOpenHandInputIconInset));
            }
            checkSpacing();
            final press = await tester.startGesture(tester.getCenter(find.byType(IconButton)));
            await tester.pump(const Duration(milliseconds: 600));
            checkSpacing(); expect(changes, 0);
            await press.cancel(); await tester.pumpAndSettle();
            await tester.tap(find.byType(IconButton));await tester.pumpAndSettle();
            expect(changes, 1); expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          }
        }
      }
    }
  });

  testWidgets('多图标与现有紧凑按钮保留主题、键盘、禁用状态和文本选择', (tester) async {
    final controller = TextEditingController(text: 'hello');
    final focus = FocusNode();
    final key = GlobalKey();
    var changes = 0;
    await tester.binding.setSurfaceSize(const Size(520,240));
    await tester.pumpWidget(MaterialApp(theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
      home: Scaffold(body: Center(child: RepaintBoundary(key: key, child: SizedBox(width:440,
        child: TextField(controller: controller, decoration: InputDecoration(
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            OpenHandInputIconAction(child: IconButton(
              focusNode: focus, tooltip:'清空', onPressed:(){changes++;},
              icon:const Icon(Icons.clear_rounded,size:18))),
            OpenHandInputIconAction(child: ServiceDialogCompactIconButton(
              tooltip:'搜索', onPressed:(){changes++;}, icon:const Icon(Icons.search_rounded,size:18))),
            const OpenHandInputIconAction(child: IconButton(onPressed:null,
              tooltip:'禁用', icon:Icon(Icons.lock_outline_rounded,size:18))),
          ]),
        )),
      ))))));
    await tester.pumpAndSettle();
    for(final button in find.byType(IconButton).evaluate()) {
      final frame=tester.getRect(find.byType(TextField));
      final surface=find.descendant(of:find.byWidget(button.widget),matching:find.byType(Material)).last;
      final rect=tester.getRect(surface);
      expect(rect.width,lessThanOrEqualTo(32));expect(rect.height,lessThanOrEqualTo(32));
      expect(rect.top-frame.top,greaterThanOrEqualTo(4));expect(frame.bottom-rect.bottom,greaterThanOrEqualTo(4));
    }
    focus.requestFocus();await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);await tester.pumpAndSettle();expect(changes,1);
    await tester.tap(find.byTooltip('禁用'));await tester.pumpAndSettle();expect(changes,1);
    controller.selection=const TextSelection(baseOffset:0,extentOffset:5);
    await tester.tap(find.byTooltip('搜索'));await tester.pumpAndSettle();expect(changes,2);
    expect(controller.text,'hello');expect(controller.selection,const TextSelection(baseOffset:0,extentOffset:5));
    final press=await tester.startGesture(tester.getCenter(find.byTooltip('搜索')));
    await tester.pump(const Duration(milliseconds:600));
    if(Platform.environment['INPUT_ICON_PREVIEW'] case final String path) {
      await tester.runAsync(()async {
        final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image=await boundary.toImage(pixelRatio:2);
        final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
        await File(path).writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
      });
    }
    await press.up();await tester.pumpAndSettle();expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());controller.dispose();focus.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
''',
);
