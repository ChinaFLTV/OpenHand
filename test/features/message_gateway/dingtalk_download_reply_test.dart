import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';
import 'package:openhand/shared/model/dingtalk_multimodal_capability.dart';

void main() {
  test('网上找图与下载使用普通工具链，不误入图片生成通道', () {
    for (final request in [
      '来一张网上的明星照片',
      '帮我获取某个明星的网上写真图片',
      '找一张现成的壁纸下载下来',
      'Download an online photo',
    ]) {
      expect(detectDingTalkMultimodalGenerationRequest(request), isNull);
    }
    expect(
      detectDingTalkMultimodalGenerationRequest('生成一张星空壁纸'),
      AiDingTalkMultimodalCapability.imageGeneration,
    );
    expect(
      detectDingTalkMultimodalGenerationRequest('搜索参考后生成一张海报'),
      AiDingTalkMultimodalCapability.imageGeneration,
    );
  });

  test('附件发送失败状态可持久化，并保留助手身份和原文件信息', () {
    final message = DingTalkGatewayMessage(
      id: '附件',
      conversationId: '会话',
      conversationType: DingTalkConversationType.direct,
      role: DingTalkGatewayMessageRole.user,
      content: '[文件] 写真.png',
      createdAt: DateTime.utc(2026),
      media: const [
        DingTalkGatewayMedia(
          resourceId: '资源',
          kind: DingTalkMediaKind.image,
          name: '写真.png',
          localPath: '/tmp/写真.png',
          sizeBytes: 123,
        ),
      ],
    ).copyWith(role: DingTalkGatewayMessageRole.assistant, failed: true);
    final restored = DingTalkGatewayMessage.fromJson(message.toJson());
    expect(restored.isAssistant, isTrue);
    expect(restored.failed, isTrue);
    expect(restored.media.single.localPath, '/tmp/写真.png');
    expect(restored.media.single.sizeBytes, 123);
    expect(restored.copyWith(failed: false).failed, isFalse);
  });
}
