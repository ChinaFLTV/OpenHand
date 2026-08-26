import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';

void main() {
  group('钉钉消息过载配置', () {
    test('旧配置默认加入等待队列', () {
      final settings = DingTalkGatewaySettings.fromJson(
        const <String, Object?>{},
      );

      expect(settings.overloadStrategy, DingTalkOverloadStrategy.queue);
    });

    test('过载策略可序列化并恢复', () {
      const settings = DingTalkGatewaySettings(
        overloadStrategy: DingTalkOverloadStrategy.reject,
      );

      final restored = DingTalkGatewaySettings.fromJson(settings.toJson());

      expect(restored.overloadStrategy, DingTalkOverloadStrategy.reject);
      expect(restored.toJson()['overload_strategy'], 'reject');
    });
  });

  group('钉钉自动响应范围', () {
    const groupTarget = DingTalkConversationTarget(
      id: 'group-1',
      title: '测试群',
      type: DingTalkConversationType.group,
      aliases: <String>['group-alias'],
    );
    const contactTarget = DingTalkConversationTarget(
      id: 'contact-1',
      title: '测试联系人',
      type: DingTalkConversationType.direct,
      openDingTalkId: 'open-contact-1',
    );

    test('白名单按会话类型匹配标识与别名', () {
      const settings = DingTalkGatewaySettings(
        allowedGroupTargets: <DingTalkConversationTarget>[groupTarget],
        allowedContactTargets: <DingTalkConversationTarget>[contactTarget],
      );

      expect(
        settings.allowsAutomaticResponseFor(
          const DingTalkConversationTarget(
            id: 'group-alias',
            title: '测试群',
            type: DingTalkConversationType.group,
          ),
        ),
        isTrue,
      );
      expect(settings.allowsAutomaticResponseFor(contactTarget), isTrue);
      expect(
        settings.allowsAutomaticResponseFor(
          const DingTalkConversationTarget(
            id: 'other-group',
            title: '其他群',
            type: DingTalkConversationType.group,
          ),
        ),
        isFalse,
      );
    });

    test('全部响应模式允许任意有效会话', () {
      const settings = DingTalkGatewaySettings(
        responseMode: DingTalkResponseMode.all,
      );

      expect(settings.allowsAutomaticResponseFor(groupTarget), isTrue);
      expect(settings.allowsAutomaticResponseFor(contactTarget), isTrue);
      expect(
        settings.allowsAutomaticResponseFor(
          const DingTalkConversationTarget(
            id: '',
            title: '无效会话',
            type: DingTalkConversationType.group,
          ),
        ),
        isFalse,
      );
    });

    test('已读状态不影响群聊艾特和单聊响应资格', () {
      final mentioned = DingTalkGatewayMessage(
        id: 'message-group',
        conversationId: 'group-1',
        conversationType: DingTalkConversationType.group,
        role: DingTalkGatewayMessageRole.user,
        content: '@当前账号 测试',
        createdAt: DateTime.utc(2026, 8, 26, 16, 35),
        mentionedCurrentUser: true,
        readByPeer: true,
      );
      final direct = DingTalkGatewayMessage(
        id: 'message-direct',
        conversationId: 'contact-1',
        conversationType: DingTalkConversationType.direct,
        role: DingTalkGatewayMessageRole.user,
        content: '测试',
        createdAt: DateTime.utc(2026, 8, 26, 16, 36),
        readByPeer: true,
      );

      expect(isDingTalkAutomaticResponseCandidate(mentioned), isTrue);
      expect(isDingTalkAutomaticResponseCandidate(direct), isTrue);
      expect(
        isDingTalkAutomaticResponseCandidate(
          mentioned.copyWith(mentionedCurrentUser: false),
        ),
        isFalse,
      );
    });
  });

  test('消息 AI 响应状态可序列化并恢复', () {
    final message = DingTalkGatewayMessage(
      id: 'message-1',
      conversationId: 'conversation-1',
      conversationType: DingTalkConversationType.direct,
      role: DingTalkGatewayMessageRole.user,
      content: '测试消息',
      createdAt: DateTime.utc(2026, 8, 26, 10, 30),
      aiResponseState: DingTalkMessageAiResponseState.dropped,
    );

    final restored = DingTalkGatewayMessage.fromJson(message.toJson());

    expect(restored.aiResponseState, DingTalkMessageAiResponseState.dropped);
  });

  group('钉钉媒体正文规范化', () {
    const media = DingTalkGatewayMedia(
      resourceId: 'media-1',
      kind: DingTalkMediaKind.image,
      name: 'image_1787722595006703_0.png',
    );

    test('英文媒体投影和附件名不重复显示', () {
      const cases = <(String, String, DingTalkMediaKind)>[
        ('image', 'generated.png', DingTalkMediaKind.image),
        ('video', 'generated.mp4', DingTalkMediaKind.video),
        ('audio', 'generated.mp3', DingTalkMediaKind.audio),
        ('file', 'generated.pdf', DingTalkMediaKind.file),
      ];
      for (final (marker, name, kind) in cases) {
        expect(
          normalizeDingTalkMediaText('[$marker] $name', <DingTalkGatewayMedia>[
            DingTalkGatewayMedia(
              resourceId: 'media-$marker',
              kind: kind,
              name: name,
            ),
          ]),
          isEmpty,
        );
      }
    });

    test('媒体消息中的真实说明文字予以保留', () {
      expect(
        normalizeDingTalkMediaText(
          '[image] 星舰发射直播画面',
          const <DingTalkGatewayMedia>[media],
        ),
        '星舰发射直播画面',
      );
    });

    test('历史媒体消息恢复时清理冗余投影', () {
      final restored = DingTalkGatewayMessage.fromJson(<String, Object?>{
        'id': 'assistant-media-1',
        'conversation_id': 'conversation-1',
        'conversation_type': 'group',
        'role': 'assistant',
        'content': '[image] image_1787722595006703_0.png',
        'created_at': DateTime.utc(2026, 8, 26, 13, 36).toIso8601String(),
        'media': <Object?>[media.toJson()],
        'from_self': false,
      });

      expect(restored.content, '[image_1787722595006703_0.png]');
      expect(
        normalizeDingTalkMediaText(restored.content, restored.media),
        isEmpty,
      );
    });
  });
}
