import '../util/input_value_parsing.dart';
import '../util/text_normalization.dart';

final RegExp _dingTalkMediaGenerationActionPattern = RegExp(
  '(?:生成|制作|创作|绘制|画(?:一|个|张|幅)|合成|创建|做(?:一|个|张|段|首)?|来(?:一|个|张|段|首)|写(?:一|段|首)|generate|create|make|draw|compose|synthesize)',
  caseSensitive: false,
);
final RegExp _dingTalkMediaGenerationQuestionPattern = RegExp(
  r'(?:如何|怎么|怎样|为何|为什么|是否支持|能否|可否|可以吗|能不能|支不支持|教程|方法)|\b(?:how|why|can|could|would|does|is)\b',
  caseSensitive: false,
);
final RegExp _dingTalkMediaGenerationNegationPattern = RegExp(
  r'(?:不要|无需|不用|禁止|别)\s*.{0,6}(?:生成|制作|创作|绘制|合成|创建|做)',
);
final RegExp _dingTalkImageGenerationTargetPattern = RegExp(
  r'(?:图片|图像|照片|海报|插画|头像|壁纸|截图|画面|\bimage\b|\bphoto\b|\bpicture\b|\bposter\b|\billustration\b)',
  caseSensitive: false,
);
final RegExp _dingTalkVideoGenerationTargetPattern = RegExp(
  r'(?:视频|短片|动画|影片|录像|\bvideo\b|\bmovie\b|\bclip\b|\banimation\b)',
  caseSensitive: false,
);
final RegExp _dingTalkAudioGenerationTargetPattern = RegExp(
  r'(?:音频|音乐|歌曲|配乐|声音|语音|朗读|播报|音效|旋律|\baudio\b|\bmusic\b|\bsong\b|\bspeech\b|\bbgm\b)',
  caseSensitive: false,
);
final RegExp _dingTalkMediaInvocationPreamblePattern = RegExp(
  r'^(?:(?:我|现在|接下来|下面|立即|正在|即将|准备|先)\s*)?(?:调用|使用|启动).{0,160}(?:工具|生成).{0,80}[：:]?$',
  caseSensitive: false,
);
final RegExp _dingTalkMediaCompletionPattern = RegExp(
  '(?:已生成|已发送|生成失败|发送失败|成功完成)',
);

/// 钉钉网关可直接注入提示词的多模态生成能力。
enum AiDingTalkMultimodalCapability {
  imageGeneration('image_generation', '图片生成'),
  videoGeneration('video_generation', '视频生成'),
  audioGeneration('audio_generation', '音频生成');

  const AiDingTalkMultimodalCapability(this.storageValue, this.displayName);

  final String storageValue;
  final String displayName;

  static AiDingTalkMultimodalCapability? fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    return enumByStorageValue(values, normalized, (item) => item.storageValue);
  }

  String get toolName => switch (this) {
    AiDingTalkMultimodalCapability.imageGeneration =>
      'DingTalkImageGenerationTool',
    AiDingTalkMultimodalCapability.videoGeneration =>
      'DingTalkVideoGenerationTool',
    AiDingTalkMultimodalCapability.audioGeneration =>
      'DingTalkAudioGenerationTool',
  };

  String get routingReminder =>
      '本轮是$displayName请求。立即调用 $toolName；禁止先输出说明或计划；工具成功后结束响应。';

  String get resourceName => switch (this) {
    AiDingTalkMultimodalCapability.imageGeneration => '图片',
    AiDingTalkMultimodalCapability.videoGeneration => '视频',
    AiDingTalkMultimodalCapability.audioGeneration => '音频',
  };

  String get toolDescription =>
      '用户明确要求生成$resourceName时立即调用。同步生成并发送$resourceName到当前钉钉会话；不要先输出说明、计划或调用前导语，成功后结束响应。';
}

AiDingTalkMultimodalCapability? detectDingTalkMultimodalGenerationRequest(
  String value,
) {
  final text = value.trim();
  if (text.isEmpty ||
      !_dingTalkMediaGenerationActionPattern.hasMatch(text) ||
      _dingTalkMediaGenerationQuestionPattern.hasMatch(text) ||
      _dingTalkMediaGenerationNegationPattern.hasMatch(text)) {
    return null;
  }
  final matched = <AiDingTalkMultimodalCapability>[
    if (_dingTalkImageGenerationTargetPattern.hasMatch(text))
      AiDingTalkMultimodalCapability.imageGeneration,
    if (_dingTalkVideoGenerationTargetPattern.hasMatch(text))
      AiDingTalkMultimodalCapability.videoGeneration,
    if (_dingTalkAudioGenerationTargetPattern.hasMatch(text))
      AiDingTalkMultimodalCapability.audioGeneration,
  ];
  return matched.length == 1 ? matched.single : null;
}

bool isDingTalkMediaInvocationPreamble(String value) {
  final text = value.replaceAll(kInlineWhitespacePattern, ' ').trim();
  if (text.isEmpty || text.length > 180) return false;
  if (_dingTalkMediaCompletionPattern.hasMatch(text)) {
    return false;
  }
  return _dingTalkMediaInvocationPreamblePattern.hasMatch(text) &&
      (_dingTalkImageGenerationTargetPattern.hasMatch(text) ||
          _dingTalkVideoGenerationTargetPattern.hasMatch(text) ||
          _dingTalkAudioGenerationTargetPattern.hasMatch(text));
}

({bool attempted, bool succeeded}) inspectDingTalkMultimodalRound(
  Iterable<Map<String, Object?>> metadataItems,
  AiDingTalkMultimodalCapability capability,
) {
  var attempted = false;
  for (final metadata in metadataItems) {
    final matchesCapability =
        '${metadata['dingtalk_media_capability'] ?? ''}'.trim() ==
            capability.storageValue ||
        '${metadata['tool_name'] ?? ''}'.trim() == capability.toolName;
    if (!matchesCapability) continue;
    attempted = true;
    if (metadata['dingtalk_media_response'] == true &&
        '${metadata['status'] ?? ''}'.trim().toLowerCase() == 'success') {
      return (attempted: true, succeeded: true);
    }
  }
  return (attempted: attempted, succeeded: false);
}
