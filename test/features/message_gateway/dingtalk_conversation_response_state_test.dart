import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/dingtalk_message_gateway_controller.dart';

void main() {
  DingTalkConversationResponseState state({
    bool active = false,
    bool pending = false,
    bool approval = false,
    bool error = false,
  }) => DingTalkConversationResponseState.resolve(
    hasActiveResponse: active,
    hasPendingResponse: pending,
    awaitingApproval: approval,
    hasError: error,
  );

  test('一个任务执行、多个会话排队时，仅执行中的会话显示响应', () {
    final states = [
      state(active: true, pending: true),
      state(pending: true),
      state(pending: true),
      state(),
    ];
    expect(states, [
      DingTalkConversationResponseState.active,
      DingTalkConversationResponseState.queued,
      DingTalkConversationResponseState.queued,
      DingTalkConversationResponseState.idle,
    ]);
    expect(
      states.where((item) => item == DingTalkConversationResponseState.active),
      hasLength(1),
    );
  });

  test('入队、调度、完成后继续等待及清空队列的状态正确切换', () {
    expect(state(), DingTalkConversationResponseState.idle);
    expect(state(pending: true), DingTalkConversationResponseState.queued);
    expect(state(active: true), DingTalkConversationResponseState.active);
    expect(
      state(active: true, pending: true),
      DingTalkConversationResponseState.active,
    );
    expect(state(pending: true), DingTalkConversationResponseState.queued);
    expect(state(), DingTalkConversationResponseState.idle);
  });

  test('同会话仍有后续排队消息时，审批状态优先', () {
    expect(
      state(active: true, pending: true, approval: true),
      DingTalkConversationResponseState.awaitingApproval,
    );
    expect(
      state(active: true, pending: true),
      DingTalkConversationResponseState.active,
    );
  });

  test('新一轮排队或响应不被旧错误覆盖，空闲后保留错误提示', () {
    expect(state(error: true), DingTalkConversationResponseState.failed);
    expect(
      state(pending: true, error: true),
      DingTalkConversationResponseState.queued,
    );
    expect(
      state(active: true, pending: true, error: true),
      DingTalkConversationResponseState.active,
    );
    expect(state(error: true), DingTalkConversationResponseState.failed);
    expect(state(), DingTalkConversationResponseState.idle);
  });
}
