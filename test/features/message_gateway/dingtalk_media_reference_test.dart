import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';

void main() {
  test('普通链接中的 fileId 不应被识别为媒体资源', () {
    expect(
      isDingTalkResourceIdInUrlQuery(
        'https://docs.yukework.com/doc?fileId=2044348200458526721 更新下知识库文档吧',
        '2044348200458526721',
        resourceType: DingTalkMediaResourceType.fileId,
      ),
      isTrue,
    );
  });

  test('嵌入 JSON 的链接中的 fileId 也不应被识别为媒体资源', () {
    expect(
      isDingTalkResourceIdInUrlQuery(
        r'''{"url":"https://docs.zuoyebang.cc/doc?fileId=2048738787602165761","type":"link"}''',
        '2048738787602165761',
        resourceType: DingTalkMediaResourceType.fileId,
      ),
      isTrue,
    );
  });

  test('媒体投影中的 fileId 不应被当作普通链接参数', () {
    expect(
      isDingTalkResourceIdInUrlQuery(
        '[文件消息](fileId=R4GpnMqJzGaBP6rjhk4ZYv078Ke0xjE3)',
        'R4GpnMqJzGaBP6rjhk4ZYv078Ke0xjE3',
        resourceType: DingTalkMediaResourceType.fileId,
      ),
      isFalse,
    );
  });

  test('媒体和文件资源的查询参数不会混淆', () {
    const text = 'https://example.com/view?mediaId=media-1&fileId=file-1';
    expect(
      isDingTalkResourceIdInUrlQuery(
        text,
        'media-1',
        resourceType: DingTalkMediaResourceType.mediaId,
      ),
      isTrue,
    );
    expect(
      isDingTalkResourceIdInUrlQuery(
        text,
        'media-1',
        resourceType: DingTalkMediaResourceType.fileId,
      ),
      isFalse,
    );
  });

  test('读取历史消息时会丢弃链接误识别的媒体', () {
    final message = DingTalkGatewayMessage.fromJson({
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'conversation_type': 'group',
      'role': 'user',
      'content': 'https://docs.yukework.com/doc?fileId=2044348200458526721',
      'created_at': '2026-08-10T17:36:52.000',
      'media': [
        {'resource_id': '2044348200458526721', 'resource_type': 'fileId'},
      ],
    });
    expect(message.media, isEmpty);
  });
}
