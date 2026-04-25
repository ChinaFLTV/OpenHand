class AiTokenUsage {
  factory AiTokenUsage.fromJson(Map<String, Object?> json) {
    return AiTokenUsage(
      promptTokens: _readInt(json['prompt_tokens']),
      completionTokens: _readInt(json['completion_tokens']),
      totalTokens: _readInt(json['total_tokens']),
      cacheCreationTokens: _readInt(json['cache_creation_tokens']),
      cacheReadTokens: _readInt(json['cache_read_tokens']),
    );
  }
  const AiTokenUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.cacheCreationTokens,
    this.cacheReadTokens,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? cacheCreationTokens;
  final int? cacheReadTokens;

  bool get isEmpty =>
      promptTokens == null &&
      completionTokens == null &&
      totalTokens == null &&
      cacheCreationTokens == null &&
      cacheReadTokens == null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': totalTokens,
      'cache_creation_tokens': cacheCreationTokens,
      'cache_read_tokens': cacheReadTokens,
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
    );
  }

  static int? _readInt(Object? value) {
    return value is int ? value : null;
  }

  static int? _sumNullable(int? left, int? right) {
    if (left == null && right == null) {
      return null;
    }
    return (left ?? 0) + (right ?? 0);
  }
}
