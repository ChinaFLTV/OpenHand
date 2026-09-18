import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';

void main() {
  DingTalkGatewayMessage message(String id) => DingTalkGatewayMessage(
    id: id,
    conversationId: 'conversation',
    conversationType: DingTalkConversationType.group,
    role: DingTalkGatewayMessageRole.user,
    content: id,
    createdAt: DateTime.utc(2026),
  );

  test('相同时间戳保留消息源顺序', () {
    final normalized = normalizeDingTalkConversationMessages([
      message('z-message'),
      message('a-message'),
    ]);

    expect(normalized.messages.map((item) => item.id), [
      'z-message',
      'a-message',
    ]);
  });
}
