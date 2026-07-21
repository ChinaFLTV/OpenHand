import '../../../shared/util/input_value_parsing.dart';

int computeCacheHitDenominatorTokens({
  required int promptTokens,
  required int cacheReadTokens,
  required bool claudeStyle,
  int cacheWriteTokens = 0,
}) {
  final safePromptTokens = _nonNegativeTokenCount(promptTokens);
  final safeCacheReadTokens = _nonNegativeTokenCount(cacheReadTokens);
  final safeCacheWriteTokens = _nonNegativeTokenCount(cacheWriteTokens);
  if (claudeStyle) {
    return safePromptTokens + safeCacheReadTokens + safeCacheWriteTokens;
  }
  return safePromptTokens > safeCacheReadTokens + safeCacheWriteTokens
      ? safePromptTokens
      : safeCacheReadTokens + safeCacheWriteTokens;
}

int computeUncachedPromptTokens({
  required int promptTokens,
  required int cacheReadTokens,
  required bool claudeStyle,
  int cacheWriteTokens = 0,
}) {
  final safePromptTokens = _nonNegativeTokenCount(promptTokens);
  if (claudeStyle) return safePromptTokens;
  return nonNegativeRemaining(
    nonNegativeRemaining(
      safePromptTokens,
      _nonNegativeTokenCount(cacheReadTokens),
    ),
    _nonNegativeTokenCount(cacheWriteTokens),
  );
}

double computeCacheHitRatio({
  required int promptTokens,
  required int cacheReadTokens,
  required bool claudeStyle,
  int cacheWriteTokens = 0,
}) {
  return unitRatio(
    cacheReadTokens,
    computeCacheHitDenominatorTokens(
      promptTokens: promptTokens,
      cacheReadTokens: cacheReadTokens,
      claudeStyle: claudeStyle,
      cacheWriteTokens: cacheWriteTokens,
    ),
  );
}

int? resolveAiTotalTokens({
  required int? promptTokens,
  required int? completionTokens,
  int? totalTokens,
}) {
  final validTotal = _nonNegativeNullableTokenCount(totalTokens);
  if (validTotal != null) return validTotal;
  final validPrompt = _nonNegativeNullableTokenCount(promptTokens);
  final validCompletion = _nonNegativeNullableTokenCount(completionTokens);
  if (validPrompt == null && validCompletion == null) return null;
  return (validPrompt ?? 0) + (validCompletion ?? 0);
}

int estimateAiTokensFromCharacters(
  int characterCount, {
  required int charactersPerToken,
}) {
  if (characterCount <= 0) return 0;
  final safeRatio = charactersPerToken < 1 ? 1 : charactersPerToken;
  return (characterCount + safeRatio - 1) ~/ safeRatio;
}

AiTokenUsage estimateAiTokenUsage({
  required int inputCharacters,
  required int outputCharacters,
  required int charactersPerToken,
}) {
  final promptTokens = estimateAiTokensFromCharacters(
    inputCharacters,
    charactersPerToken: charactersPerToken,
  );
  final completionTokens = estimateAiTokensFromCharacters(
    outputCharacters,
    charactersPerToken: charactersPerToken,
  );
  return AiTokenUsage(
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    totalTokens: promptTokens + completionTokens,
  );
}

class AiTokenUsage {
  factory AiTokenUsage.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return AiTokenUsage(
      promptTokens: _readInt(json['prompt_tokens']),
      completionTokens: _readInt(json['completion_tokens']),
      totalTokens: _readInt(json['total_tokens']),
      cacheCreationTokens: _readInt(json['cache_creation_tokens']),
      cacheReadTokens: _readInt(json['cache_read_tokens']),
      reasoningTokens: _readInt(json['reasoning_tokens']),
      audioInputTokens: _readInt(json['audio_input_tokens']),
      imageInputTokens: _readInt(json['image_input_tokens']),
      videoInputTokens: _readInt(json['video_input_tokens']),
      webSearchToolUsage: _readInt(json['web_search_tool_usage']),
      webSearchPageUsage: _readInt(json['web_search_page_usage']),
    );
  }
  const AiTokenUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.cacheCreationTokens,
    this.cacheReadTokens,
    this.reasoningTokens,
    this.audioInputTokens,
    this.imageInputTokens,
    this.videoInputTokens,
    this.webSearchToolUsage,
    this.webSearchPageUsage,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? cacheCreationTokens;
  final int? cacheReadTokens;

  /// Reasoning / thinking 阶段消耗的 token 数。
  /// - OpenAI o-系列：completion_tokens_details.reasoning_tokens（已被
  ///   completion_tokens 包含，此处仅作可视化）。
  /// - DeepSeek-R1 / Z.AI 思考模式：completion_tokens_details.reasoning_tokens
  ///   或 reasoning_tokens 平铺；约定同上。
  /// - Gemini 2.5 思考模型：usageMetadata.thoughtsTokenCount（被
  ///   candidatesTokenCount 包含）。
  /// - Anthropic：thinking_delta 的字符数已计入 output_tokens；目前 API 不
  ///   单独区分 reasoning_tokens，此字段保持为 null。
  final int? reasoningTokens;

  final int? audioInputTokens;
  final int? imageInputTokens;
  final int? videoInputTokens;

  /// 供应商原生网页搜索 API 在本次响应中的调用次数。
  final int? webSearchToolUsage;

  /// 供应商原生网页搜索 API 在本次响应中返回的页面数。
  final int? webSearchPageUsage;

  int? get resolvedTotalTokens => resolveAiTotalTokens(
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    totalTokens: totalTokens,
  );

  bool get isEmpty =>
      promptTokens == null &&
      completionTokens == null &&
      totalTokens == null &&
      cacheCreationTokens == null &&
      cacheReadTokens == null &&
      reasoningTokens == null &&
      audioInputTokens == null &&
      imageInputTokens == null &&
      videoInputTokens == null &&
      webSearchToolUsage == null &&
      webSearchPageUsage == null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': totalTokens,
      'cache_creation_tokens': cacheCreationTokens,
      'cache_read_tokens': cacheReadTokens,
      'reasoning_tokens': reasoningTokens,
      'audio_input_tokens': audioInputTokens,
      'image_input_tokens': imageInputTokens,
      'video_input_tokens': videoInputTokens,
      'web_search_tool_usage': webSearchToolUsage,
      'web_search_page_usage': webSearchPageUsage,
    };
  }

  AiTokenUsage merge(AiTokenUsage other) {
    return AiTokenUsage(
      promptTokens: _sumNullable(promptTokens, other.promptTokens),
      completionTokens: _sumNullable(completionTokens, other.completionTokens),
      totalTokens: _sumNullable(resolvedTotalTokens, other.resolvedTotalTokens),
      cacheCreationTokens: _sumNullable(
        cacheCreationTokens,
        other.cacheCreationTokens,
      ),
      cacheReadTokens: _sumNullable(cacheReadTokens, other.cacheReadTokens),
      reasoningTokens: _sumNullable(reasoningTokens, other.reasoningTokens),
      audioInputTokens: _sumNullable(audioInputTokens, other.audioInputTokens),
      imageInputTokens: _sumNullable(imageInputTokens, other.imageInputTokens),
      videoInputTokens: _sumNullable(videoInputTokens, other.videoInputTokens),
      webSearchToolUsage: _sumNullable(
        webSearchToolUsage,
        other.webSearchToolUsage,
      ),
      webSearchPageUsage: _sumNullable(
        webSearchPageUsage,
        other.webSearchPageUsage,
      ),
    );
  }

  static int? _readInt(Object? value) {
    return optionalNonNegativeIntegralIntFromValue(value);
  }

  static int? _sumNullable(int? left, int? right) {
    if (left == null && right == null) {
      return null;
    }
    return (left ?? 0) + (right ?? 0);
  }
}

int _nonNegativeTokenCount(int value) => value < 0 ? 0 : value;

int? _nonNegativeNullableTokenCount(int? value) {
  return value == null || value < 0 ? null : value;
}
