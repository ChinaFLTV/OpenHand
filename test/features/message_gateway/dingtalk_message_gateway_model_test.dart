import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';

void main() {
  group('钉钉链接卡片投影', () {
    const link = 'https://http.cat/';

    test('清理纯链接重复的 url 和 uri 字段', () {
      expect(normalizeDingTalkMessageContent('$link url: $link'), link);
      expect(normalizeDingTalkMessageContent('$link\nURI： $link'), link);
    });

    test('清理带分享标题的重复链接投影', () {
      expect(
        normalizeDingTalkMessageContent(
          '[分享] HTTP Cats API for HTTP Cats $link url: $link',
        ),
        link,
      );
      expect(
        normalizeDingTalkMessageContent(
          '【网页】 HTTP Cats API for HTTP Cats\n$link\nurl：$link',
        ),
        link,
      );
    });

    test('保留普通文本和不一致的链接', () {
      expect(
        normalizeDingTalkMessageContent('请访问 $link url: $link'),
        '请访问 $link url: $link',
      );
      expect(
        normalizeDingTalkMessageContent('$link url: https://example.com/'),
        '$link url: https://example.com/',
      );
      expect(
        normalizeDingTalkMessageContent('[分享] 这是普通文本 $link'),
        '[分享] 这是普通文本 $link',
      );
    });

    test('反序列化分享链接投影后只保留原始 URL', () {
      final message = DingTalkGatewayMessage.fromJson({
        'id': 'link-message-1',
        'conversation_id': 'conversation-1',
        'conversation_type': 'group',
        'role': 'user',
        'content': '[分享] HTTP Cats API for HTTP Cats $link uri: $link',
        'created_at': '2026-08-25T10:00:00.000Z',
      });

      expect(message.content, link);
      expect(message.media, isEmpty);
    });
  });

  group('钉钉媒体复合消息', () {
    test('移除图片投影但保留同一条消息中的文本', () {
      expect(stripDingTalkMediaPlaceholder('[图片] 坏菜了，我也'), '坏菜了，我也');
      expect(stripDingTalkMediaPlaceholder('[图片消息](mediaId=abc)'), isEmpty);
      expect(
        stripDingTalkMediaPlaceholder(
          '[图片消息](mediaId=\$iwEcAqNwbmcDAQTRA1QF0QHABrDrJOLzLL8DpgpfYzr3pIUAB9IkGT5ICAAJomltCgAL0gAA-bk) 注意：如需下载使用dws chat message download-media命令下载',
        ),
        isEmpty,
      );
      expect(
        stripDingTalkMediaPlaceholder(
          '[图片消息](mediaId=abc) 坏菜了，我也 注意：如需下载使用dws chat message download-media命令下载',
        ),
        '坏菜了，我也',
      );
      expect(
        stripDingTalkMediaPlaceholder(
          '注意：如需下载使用dws chat message download-media命令下载',
        ),
        '注意：如需下载使用dws chat message download-media命令下载',
      );
      expect(
        stripDingTalkMediaPlaceholder('图片前缀 [图片消息](mediaId=abc) 图片后缀'),
        '图片前缀 图片后缀',
      );
      expect(stripDingTalkMediaPlaceholder('[文件消息](fileId=file-1) 请查收'), '请查收');
      expect(stripDingTalkMediaPlaceholder('普通文本'), '普通文本');
    });

    test('反序列化时保留图片消息对应的文本正文', () {
      final message = DingTalkGatewayMessage.fromJson({
        'id': 'message-1',
        'conversation_id': 'conversation-1',
        'conversation_type': 'direct',
        'role': 'user',
        'content': '[图片] 坏菜了，我也',
        'created_at': '2026-08-25T10:00:00.000Z',
        'media': [
          {
            'resource_id': 'media-1',
            'resource_type': 'mediaId',
            'kind': 'image',
          },
        ],
      });

      expect(message.content, '坏菜了，我也');
      expect(message.media, hasLength(1));
      expect(message.media.single.kind, DingTalkMediaKind.image);
    });

    test('转发聊天记录中的图片消息也保留文本正文', () {
      final message = DingTalkForwardedMessage.fromJson({
        'id': 'forwarded-1',
        'content': '[图片消息](mediaId=abc) 请查收',
        'created_at': '2026-08-25T10:00:00.000Z',
        'media': [
          {
            'resource_id': 'media-3',
            'resource_type': 'mediaId',
            'kind': 'image',
          },
        ],
      });

      expect(message.content, '请查收');
      expect(message.media, hasLength(1));
    });

    test('纯图片消息仍保留媒体占位摘要', () {
      final message = DingTalkGatewayMessage.fromJson({
        'id': 'message-2',
        'conversation_id': 'conversation-1',
        'conversation_type': 'direct',
        'role': 'user',
        'content': '[图片]',
        'created_at': '2026-08-25T10:00:00.000Z',
        'media': [
          {
            'resource_id': 'media-2',
            'resource_type': 'mediaId',
            'kind': 'image',
          },
        ],
      });

      expect(message.content, '[图片]');
      expect(message.media.single.kind, DingTalkMediaKind.image);
    });
  });
}
