import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';
import 'package:openhand/features/message_gateway/widgets/dingtalk_image_gallery.dart';
import 'package:openhand/shared/ui/markdown_image_gallery.dart';

void main() {
  DingTalkGatewayMedia media(String name) => DingTalkGatewayMedia(
    resourceId: name,
    localPath: '/图库/$name.png',
    name: name,
    kind: DingTalkMediaKind.image,
  );
  DingTalkGatewayMessage message(String id, {bool quote = false}) =>
      DingTalkGatewayMessage(
        id: id,
        conversationId: '会话',
        conversationType: DingTalkConversationType.direct,
        role: DingTalkGatewayMessageRole.user,
        content: '',
        createdAt: DateTime.utc(2026),
        media: quote ? const [] : [media(id)],
        quotedMessage: quote
            ? DingTalkQuotedMessage(
                id: '原图',
                content: '',
                createdAt: DateTime.utc(2026),
                media: [media('原图')],
              )
            : null,
      );
  final messages = [message('原图'), message('引用', quote: true), message('后一张')];
  Iterable<OpenHandGalleryImage> gallery() sync* {
    for (final item in messages) {
      yield* collectDingTalkMessageImages(item);
    }
  }

  test('引用图片按所在消息定位，前后导航保留原图和相邻消息', () {
    final result = resolveOpenHandImageGallery(
      gallery(),
      OpenHandGalleryImage(uri: Uri.file('/图库/原图.png'), title: '原图'),
      messageId: '引用',
    );
    expect(result.found, true);
    expect(result.index, 1);
    expect(result.images.map((item) => item.messageId), ['原图', '引用', '后一张']);
  });

  test('原消息未加载时引用图仍入图库，同卡片重复资源只保留一次', () async {
    var located = false;
    final quoted = messages[1].copyWith(media: [media('原图'), media('附图')]);
    final images = collectDingTalkMessageImages(
      quoted,
      onLocate: () async => located = true,
    ).toList();
    expect(images.map((item) => item.title), ['原图', '附图']);
    expect(images.every((item) => item.messageId == quoted.id), true);
    await images.first.onLocate!();
    expect(located, true);
  });

  test('线程 Markdown 与 HTML 引用图均进入图库，正文附件重复去重', () {
    final images = collectOpenHandMessageImages(
      content:
          '> ![引用图](file:///图库/引用.png)\n\n'
          '<blockquote><img src="https://example.com/a.png?a=1&amp;b=2" alt="引用 HTML 图"></blockquote>',
      messageId: '线程消息',
      attachments: [
        OpenHandGalleryImage(uri: Uri.file('/图库/引用.png'), title: '引用图'),
      ],
    ).toList();
    expect(images, hasLength(2));
    expect(images.last.uri.toString(), 'https://example.com/a.png?a=1&b=2');
    expect(images.every((item) => item.messageId == '线程消息'), true);
  });

  testWidgets('点击引用图片打开真实图库，并可向前向后导航', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenHandImageMessageScope(
            messageId: '引用',
            galleryImages: gallery,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showOpenHandMessageImage(
                  context,
                  OpenHandGalleryImage(
                    uri: Uri.file('/图库/原图.png'),
                    title: '原图',
                  ),
                ),
                child: const Text('打开引用图片'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开引用图片'));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('下一张'));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('上一张'));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('2 / 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
