enum AiApiDialect {
  openAiCompat('openai_compat'),
  anthropicNative('anthropic_native'),
  geminiNative('gemini_native');

  const AiApiDialect(this.storageValue);

  final String storageValue;

  static AiApiDialect fromStorage(String? value) {
    return AiApiDialect.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AiApiDialect.openAiCompat,
    );
  }
}

enum AiProviderKind {
  openai('openai'),
  claude('claude'),
  gemini('gemini'),
  qwen('qwen'),
  jimeng('jimeng'),
  kling('kling'),
  sora('sora'),
  minimax('minimax'),
  custom('custom');

  const AiProviderKind(this.storageValue);

  final String storageValue;

  static AiProviderKind fromStorage(String? value) {
    return AiProviderKind.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AiProviderKind.custom,
    );
  }
}
