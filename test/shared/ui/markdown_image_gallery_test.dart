import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/markdown_image_gallery.dart';
import 'package:openhand/shared/ui/openhand_safe_markdown_body.dart';

void main() {
  test('从解析树收集图片，保留顺序、排除代码与不支持的协议，并限制数量', () {
    final nodes = md.Document().parseLines([
      '![第一张](https://example.com/1.png)',
      '![重复](https://example.com/1.png)',
      '![第二张](https://example.com/2.png)',
      '![无效](javascript:alert)',
      '```',
      '![代码](https://example.com/code.png)',
      '```',
    ]);
    final images = collectOpenHandMarkdownImages(nodes);
    expect(images.map((item) => item.title), ['第一张', '第二张']);
    final many = List.generate(
      300,
      (index) =>
          md.Element.empty('img')
            ..attributes['src'] = 'https://example.com/$index.png',
    );
    expect(
      collectOpenHandMarkdownImages(many).length,
      kOpenHandImageGalleryLimit,
    );
  });

  testWidgets('点击图片打开图片组，按钮与键盘切换，定位时关闭预览', (tester) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = Directory.systemTemp.createTempSync(
      'openhand-gallery-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAJUlEQVR4nGNw6Tjzn5aYYdSCUQtGLRi1YNSCUQtGLRi1YGhYAACfy9QMv3SBYAAAAABJRU5ErkJggg==',
    );
    final first = File('${directory.path}/first.png')..writeAsBytesSync(bytes);
    final second = File('${directory.path}/second.png')
      ..writeAsBytesSync(bytes);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() async {
      await precacheImage(
        ResizeImage(FileImage(first), width: 1280),
        tester.element(find.byType(SizedBox).first),
      );
      await precacheImage(
        ResizeImage(FileImage(second), width: 1280),
        tester.element(find.byType(SizedBox).first),
      );
      await precacheImage(
        FileImage(first),
        tester.element(find.byType(SizedBox).first),
      );
      await precacheImage(
        FileImage(second),
        tester.element(find.byType(SizedBox).first),
      );
    });
    var located = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OpenHandImageMessageScope(
            onLocate: () async {
              located = true;
            },
            child: OpenHandThemedMarkdownBody(
              data: '![第一张](${first.uri})\n\n![第二张](${second.uri})',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('预览图片：第一张'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('下一张'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('定位到消息'));
    await tester.pumpAndSettle();
    expect(located, isTrue);
    expect(find.text('1 / 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
