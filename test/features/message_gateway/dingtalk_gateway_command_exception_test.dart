import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/service/dingtalk_message_gateway_service.dart';

void main() {
  group('钉钉网关编辑异常分类', () {
    test('识别不支持的消息编辑类型', () {
      const error = DingTalkGatewayCommandException(
        message: '[UNCLASSIFIED] 仅支持编辑文本、富文本、回复消息',
        operation: 'im/edit_message',
      );

      expect(error.isUnsupportedMessageEditType, isTrue);
      expect(error.isRetryable, isFalse);
      expect(error.isMessageEditLimitReached, isFalse);
    });

    test('识别英文不支持消息类型错误', () {
      const error = DingTalkGatewayCommandException(
        message: 'Only supports editing text, rich text, and reply messages.',
        operation: 'im/edit_message',
      );

      expect(error.isUnsupportedMessageEditType, isTrue);
    });

    test('其他编辑业务错误不应被误判为能力降级', () {
      const error = DingTalkGatewayCommandException(
        message: '消息不存在。',
        operation: 'im/edit_message',
        reason: 'business_error',
      );

      expect(error.isUnsupportedMessageEditType, isFalse);
    });

    test('编辑次数超限仍单独分类', () {
      const error = DingTalkGatewayCommandException(
        message: '编辑次数已达上限。',
        operation: 'im/edit_message',
      );

      expect(error.isMessageEditLimitReached, isTrue);
      expect(error.isUnsupportedMessageEditType, isFalse);
    });

    test('缺少编辑操作标识时不吞掉同名文案', () {
      const error = DingTalkGatewayCommandException(
        message: '仅支持编辑文本、富文本、回复消息',
      );

      expect(error.isUnsupportedMessageEditType, isFalse);
    });
  });
}
