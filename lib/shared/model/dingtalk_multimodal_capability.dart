import '../util/input_value_parsing.dart';

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
}
