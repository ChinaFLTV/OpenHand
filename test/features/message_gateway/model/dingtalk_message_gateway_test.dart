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
}
