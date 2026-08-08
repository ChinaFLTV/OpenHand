import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';

void main() {
  test('钉钉媒体消息可以安全持久化并恢复本地缓存路径', () {
    final message = DingTalkGatewayMessage(
      id: 'message-1',
      conversationId: 'conversation-1',
      conversationType: DingTalkConversationType.group,
      role: DingTalkGatewayMessageRole.user,
      content: '[图片] photo.png',
      createdAt: DateTime.utc(2026, 8, 8, 12),
      media: const <DingTalkGatewayMedia>[
        DingTalkGatewayMedia(
          resourceId: '@media-1',
          messageId: 'message-1',
          conversationId: 'conversation-1',
          kind: DingTalkMediaKind.image,
          name: 'photo.png',
          mimeType: 'image/png',
          sizeBytes: 128,
          localPath: '/tmp/openhand/photo.png',
        ),
      ],
    );

    final restored = DingTalkGatewayMessage.fromJson(message.toJson());

    expect(restored.media, hasLength(1));
    expect(restored.media.single.resourceId, '@media-1');
    expect(restored.media.single.messageId, 'message-1');
    expect(restored.media.single.conversationId, 'conversation-1');
    expect(restored.media.single.localPath, '/tmp/openhand/photo.png');
    expect(restored.media.single.kind, DingTalkMediaKind.image);
  });

  test('媒体类型可以从文件名推断', () {
    expect(
      DingTalkMediaKindX.fromFileName('recording.m4a'),
      DingTalkMediaKind.audio,
    );
    expect(
      DingTalkMediaKindX.fromFileName('clip.mp4'),
      DingTalkMediaKind.video,
    );
    expect(
      DingTalkMediaKindX.fromFileName('archive.zip'),
      DingTalkMediaKind.file,
    );
    expect(DingTalkMediaKind.image.isPreviewable, isTrue);
    expect(DingTalkMediaKind.video.isPreviewable, isTrue);
    expect(DingTalkMediaKind.audio.isPreviewable, isTrue);
    expect(DingTalkMediaKind.file.isPreviewable, isFalse);
  });

  test('旧格式 fileId 媒体字段可以恢复', () {
    final media = DingTalkGatewayMedia.fromJson(const <String, Object?>{
      'file_id': 'file-1',
      'file_name': 'report.pdf',
    });
    expect(media.resourceId, 'file-1');
    expect(media.resourceType, DingTalkMediaResourceType.fileId);
    expect(media.kind, DingTalkMediaKind.file);
  });
}
