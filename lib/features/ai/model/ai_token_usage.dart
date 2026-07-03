import '../../../shared/util/input_value_parsing.dart';

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
    );
  }
  const AiTokenUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.cacheCreationTokens,
    this.cacheReadTokens,
    this.reasoningTokens,
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

  bool get isEmpty =>
      promptTokens == null &&
      completionTokens == null &&
      totalTokens == null &&
      cacheCreationTokens == null &&
      cacheReadTokens == null &&
      reasoningTokens == null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': totalTokens,
      'cache_creation_tokens': cacheCreationTokens,
      'cache_read_tokens': cacheReadTokens,
      'reasoning_tokens': reasoningTokens,
    };
  }

  AiTokenUsage merge(AiTokenUsage other) {
    return AiTokenUsage(
      promptTokens: _sumNullable(promptTokens, other.promptTokens),
      completionTokens: _sumNullable(completionTokens, other.completionTokens),
      totalTokens: _sumNullable(totalTokens, other.totalTokens),
      cacheCreationTokens: _sumNullable(
        cacheCreationTokens,
        other.cacheCreationTokens,
      ),
      cacheReadTokens: _sumNullable(cacheReadTokens, other.cacheReadTokens),
      reasoningTokens: _sumNullable(reasoningTokens, other.reasoningTokens),
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
