import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';

void main() {
  test('链接增强投影只保留原始链接', () {
    const original =
        'https://docs.yukework.com/doc?fileId=2092530279373856769&from=dd_link_enhance';
    const desktop =
        'https://applink.dingtalk.com/page/link?url=https%3A%2F%2Fdocs.yukework.com%2FkuAppSlide%3Ffrom%3DdingCardSlide&targetDesktop=slide';
    const content =
        '周例会 - DEV - 20260827\n[$original]($original)\n[$desktop]($desktop)';

    expect(normalizeDingTalkMessageContent(content), original);

    final restored = DingTalkGatewayMessage.fromJson(<String, Object?>{
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'conversation_type': 'group',
      'role': 'user',
      'content': content,
      'created_at': '2026-08-27T15:10:20.000',
    });
    expect(restored.content, original);
  });

  test('普通多链接正文保持不变', () {
    const content =
        '请对比以下链接\n[https://example.com/a](https://example.com/a)\n[https://example.com/b](https://example.com/b)';

    expect(normalizeDingTalkMessageContent(content), content);
  });

  test('链接增强投影后的用户正文不会被误删', () {
    const original =
        'https://docs.yukework.com/doc?fileId=2092530279373856769&from=dd_link_enhance';
    const desktop =
        'https://applink.dingtalk.com/page/link?url=https%3A%2F%2Fdocs.yukework.com%2FkuAppSlide%3Ffrom%3DdingCardSlide&targetDesktop=slide';
    const content = '[$original]($original)\n[$desktop]($desktop)\n请同时查看会议纪要';

    expect(normalizeDingTalkMessageContent(content), content);
  });

  test('桌面链接仅接受准确的来源查询参数', () {
    const original =
        'https://docs.yukework.com/doc?fileId=2092530279373856769&from=dd_link_enhance';
    const misleadingDesktop =
        'https://applink.dingtalk.com/page/link?url=https%3A%2F%2Fdocs.yukework.com%2FkuAppSlide%3Ftransform%3DdingCardSlide&targetDesktop=slide';
    const content =
        '周例会\n[$original]($original)\n[$misleadingDesktop]($misleadingDesktop)';

    expect(normalizeDingTalkMessageContent(content), content);
  });
}
