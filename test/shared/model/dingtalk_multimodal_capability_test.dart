import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/model/dingtalk_multimodal_capability.dart';

void main() {
  group('钉钉多模态意图识别', () {
    test('识别明确的图片视频和音频生成请求', () {
      expect(
        detectDingTalkMultimodalGenerationRequest('生成一张星舰发射的直播画面截图！'),
        AiDingTalkMultimodalCapability.imageGeneration,
      );
      expect(
        detectDingTalkMultimodalGenerationRequest('制作一段产品发布视频'),
        AiDingTalkMultimodalCapability.videoGeneration,
      );
      expect(
        detectDingTalkMultimodalGenerationRequest('生成一段中国古风音乐！！！'),
        AiDingTalkMultimodalCapability.audioGeneration,
      );
    });

    test('不强制路由询问否定和多媒体混合请求', () {
      expect(detectDingTalkMultimodalGenerationRequest('如何生成一段音乐？'), isNull);
      expect(detectDingTalkMultimodalGenerationRequest('请告诉我怎么制作音乐'), isNull);
      expect(detectDingTalkMultimodalGenerationRequest('不要生成图片'), isNull);
      expect(detectDingTalkMultimodalGenerationRequest('生成一张图片和一段视频'), isNull);
    });

    test('提供简洁明确的工具约束', () {
      const capability = AiDingTalkMultimodalCapability.audioGeneration;
      expect(capability.routingReminder, contains(capability.toolName));
      expect(capability.routingReminder, contains('禁止先输出说明或计划'));
      expect(capability.toolDescription, contains('立即调用'));
      expect(capability.toolDescription, contains('成功后结束响应'));
    });

    test('依据工具结果判断本轮是否需要兜底', () {
      const capability = AiDingTalkMultimodalCapability.audioGeneration;
      expect(
        inspectDingTalkMultimodalRound(
          const <Map<String, Object?>>[],
          capability,
        ),
        (attempted: false, succeeded: false),
      );
      expect(
        inspectDingTalkMultimodalRound(<Map<String, Object?>>[
          <String, Object?>{
            'tool_name': capability.toolName,
            'status': 'failed',
          },
        ], capability),
        (attempted: true, succeeded: false),
      );
      expect(
        inspectDingTalkMultimodalRound(<Map<String, Object?>>[
          <String, Object?>{
            'dingtalk_media_capability': capability.storageValue,
            'dingtalk_media_response': true,
            'status': 'success',
          },
        ], capability),
        (attempted: true, succeeded: true),
      );
    });
  });

  group('钉钉媒体调用前导语', () {
    test('识别未完成的工具调用前导语', () {
      expect(isDingTalkMediaInvocationPreamble('调用音频生成工具生成中国古风音乐：'), isTrue);
      expect(isDingTalkMediaInvocationPreamble('现在使用图片生成工具：'), isTrue);
    });

    test('保留已完成或普通说明内容', () {
      expect(isDingTalkMediaInvocationPreamble('音频已生成并发送。'), isFalse);
      expect(isDingTalkMediaInvocationPreamble('可以在设置中选择音频生成模型。'), isFalse);
    });
  });
}
