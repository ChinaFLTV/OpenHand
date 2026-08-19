import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';

void main() {
  group('DWS 文件投影', () {
    const fileName = 'odin-digital-employee-redesign-demo(2).html';
    const fileId = 'NDoBb60VLQXxjZpaHaq50nwxJlemrZQ3';

    test('解析文件名和 fileId', () {
      final projection = parseDingTalkDwsFileProjection(
        '[文件] $fileName fileId: $fileId '
        '注意：如需下载使用dws drive download命令下载',
      );

      expect(projection?.name, fileName);
      expect(projection?.resourceId, fileId);
    });

    test('兼容换行和中文冒号', () {
      final projection = parseDingTalkDwsFileProjection(
        '[文件] $fileName\nfileId： $fileId\n'
        '注意：如需下载使用dws drive download命令下载',
      );

      expect(projection?.name, fileName);
      expect(projection?.resourceId, fileId);
    });

    test('不把普通聊天内容识别为文件', () {
      expect(
        parseDingTalkDwsFileProjection('[文件] 示例.txt fileId: $fileId'),
        isNull,
      );
      expect(
        parseDingTalkDwsFileProjection(
          '请转发：[文件] 示例.txt fileId: $fileId '
          '注意：如需下载使用dws drive download命令下载',
        ),
        isNull,
      );
    });

    test('旧缓存自动迁移为文件媒体', () {
      final message = DingTalkGatewayMessage.fromJson(<String, Object?>{
        'id': 'message-id',
        'conversation_id': 'conversation-id',
        'conversation_type': 'group',
        'role': 'user',
        'content':
            '[文件] $fileName fileId: $fileId '
            '注意：如需下载使用dws drive download命令下载',
        'created_at': '2026-08-19T17:52:42.000',
        'media': <Object?>[],
      });

      expect(message.content, '[$fileName]');
      expect(message.media, hasLength(1));
      expect(message.media.single.resourceId, fileId);
      expect(
        message.media.single.resourceType,
        DingTalkMediaResourceType.fileId,
      );
      expect(message.media.single.kind, DingTalkMediaKind.file);
      expect(message.media.single.name, fileName);
      expect(message.media.single.messageId, 'message-id');
      expect(message.media.single.conversationId, 'conversation-id');
    });

    test('转发记录中的旧文件缓存进入父消息下载队列', () {
      final message = DingTalkGatewayMessage.fromJson(<String, Object?>{
        'id': 'forward-message-id',
        'conversation_id': 'conversation-id',
        'conversation_type': 'group',
        'role': 'user',
        'content': '转发的聊天记录',
        'created_at': '2026-08-19T17:52:42.000',
        'media': <Object?>[],
        'forwarded_messages': <Object?>[
          <String, Object?>{
            'id': 'child-message-id',
            'content':
                '[文件] $fileName fileId: $fileId '
                '注意：如需下载使用dws drive download命令下载',
            'created_at': '2026-08-19T17:50:00.000',
            'media': <Object?>[],
          },
        ],
      });

      expect(message.forwardedMessages.single.content, '[$fileName]');
      expect(message.forwardedMessages.single.media, hasLength(1));
      expect(message.media, hasLength(1));
      expect(message.media.single.resourceId, fileId);
      expect(message.media.single.messageId, 'child-message-id');
      expect(message.media.single.conversationId, 'conversation-id');
    });
  });
}
