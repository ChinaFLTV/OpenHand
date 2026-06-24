int computeCacheHitDenominatorTokens({
  required int promptTokens,
  required int cacheReadTokens,
  required bool claudeStyle,
}) {
  if (promptTokens <= 0 && cacheReadTokens <= 0) {
    return 0;
  }
  if (claudeStyle) {
    return promptTokens + cacheReadTokens;
  }
  return promptTokens > 0 ? promptTokens : cacheReadTokens;
}

int computeUncachedPromptTokens({
  required int promptTokens,
  required int cacheReadTokens,
  required bool claudeStyle,
}) {
  if (claudeStyle) {
    return promptTokens < 0 ? 0 : promptTokens;
  }
  return (promptTokens - cacheReadTokens).clamp(0, promptTokens);
}

double computeCacheHitRatio({
  required int promptTokens,
  required int cacheReadTokens,
  required bool claudeStyle,
}) {
  final denominator = computeCacheHitDenominatorTokens(
    promptTokens: promptTokens,
    cacheReadTokens: cacheReadTokens,
    claudeStyle: claudeStyle,
  );
  if (denominator <= 0) {
    return 0.0;
  }
  final ratio = cacheReadTokens / denominator;
  if (ratio.isNaN || ratio.isInfinite) {
    return 0.0;
  }
  return ratio.clamp(0.0, 1.0).toDouble();
}
