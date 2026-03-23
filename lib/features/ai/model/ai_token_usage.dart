class AiTokenUsage {
  const AiTokenUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  bool get isEmpty =>
      promptTokens == null && completionTokens == null && totalTokens == null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': totalTokens,
    };
  }

  factory AiTokenUsage.fromJson(Map<String, Object?> json) {
    return AiTokenUsage(
      promptTokens: _readInt(json['prompt_tokens']),
      completionTokens: _readInt(json['completion_tokens']),
      totalTokens: _readInt(json['total_tokens']),
    );
  }

  AiTokenUsage merge(AiTokenUsage other) {
    return AiTokenUsage(
      promptTokens: _sumNullable(promptTokens, other.promptTokens),
      completionTokens: _sumNullable(completionTokens, other.completionTokens),
      totalTokens: _sumNullable(totalTokens, other.totalTokens),
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
