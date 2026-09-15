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

  test('跨消息图片保留顺序、重复图片的归属和有界窗口', () {
    final images = List.generate(
      600,
      (index) => OpenHandGalleryImage(
        uri: Uri.file('/图片/${index % 2}.png'),
        title: '图片 $index',
        messageId: '$index',
      ),
    );
    final gallery = resolveOpenHandImageGallery(
      images,
      images[400],
      messageId: '400',
    );
    expect(gallery.images.length, kOpenHandImageGalleryLimit);
    expect(gallery.images[gallery.index].messageId, '400');
    expect(gallery.images[gallery.index - 1].messageId, '399');
    expect(gallery.images[gallery.index + 1].messageId, '401');
    final shortGallery = resolveOpenHandImageGallery(
      images.take(200),
      images[190],
      messageId: '190',
    );
    expect(shortGallery.images.length, 200);
    expect(shortGallery.index, 190);
    final last = resolveOpenHandImageGallery(
      images,
      images.last,
      messageId: '599',
    );
    expect(last.images[last.index], same(images.last));
    expect(last.index, greaterThan(0));
    final missing = OpenHandGalleryImage(uri: Uri.file('/缺失.png'), title: '缺失');
    final fallback = resolveOpenHandImageGallery(images, missing);
    expect(fallback.images, [missing]);
    expect(fallback.found, isFalse);
  });

  test('合并附件和正文图片，排除代码图片并保留定位', () async {
    var located = false;
    final images = collectOpenHandMessageImages(
      content:
          '![重复](file:///图片/1.png)\n![正文](https://example.com/2.png)\n```\n![代码](https://example.com/code.png)\n```',
      attachments: [
        OpenHandGalleryImage(uri: Uri.file('/图片/1.png'), title: '附件'),
      ],
      messageId: '消息',
      onLocate: () async {
        located = true;
      },
    ).toList();
    expect(images.map((image) => image.title), ['附件', '正文']);
    expect(images.every((image) => image.messageId == '消息'), isTrue);
    await images.last.onLocate!();
    expect(located, isTrue);
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
    String? locatedMessage;
    var collections = 0;
    final conversation = [
      OpenHandGalleryImage(
        uri: first.uri,
        title: '消息一',
        messageId: '一',
        onLocate: () async {
          locatedMessage = '一';
        },
      ),
      OpenHandGalleryImage(
        uri: second.uri,
        title: '消息二',
        messageId: '二',
        onLocate: () async {
          locatedMessage = '二';
        },
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OpenHandImageMessageScope(
            messageId: '二',
            images: [conversation.last],
            galleryImages: () {
              collections++;
              return conversation;
            },
            onLocate: () async {
              locatedMessage = '错误的原消息';
            },
            child: Column(
              children: [
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        showOpenHandMessageImage(context, conversation.last),
                    child: const Text('打开第二条消息'),
                  ),
                ),
                OpenHandThemedMarkdownBody(data: '![消息二](${second.uri})'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(collections, 0);
    await tester.tap(find.text('打开第二条消息'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(collections, 1);
    await tester.tap(find.byTooltip('上一张'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('定位到消息'));
    await tester.pumpAndSettle();
    expect(locatedMessage, '一');
    expect(find.text('1 / 2'), findsNothing);
    await tester.tap(find.bySemanticsLabel('预览图片：消息二'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
