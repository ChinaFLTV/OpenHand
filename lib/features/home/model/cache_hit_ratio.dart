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
  if (safePromptTokens <= 0 &&
      safeCacheReadTokens <= 0 &&
      safeCacheWriteTokens <= 0) {
    return 0;
  }
  if (claudeStyle) {
    return safePromptTokens + safeCacheReadTokens + safeCacheWriteTokens;
  }
  if (safePromptTokens > 0) {
    final observedCacheTokens = safeCacheReadTokens + safeCacheWriteTokens;
    return observedCacheTokens > safePromptTokens
        ? observedCacheTokens
        : safePromptTokens;
  }
  return safeCacheReadTokens + safeCacheWriteTokens;
}

int computeUncachedPromptTokens({
  required int promptTokens,
  required int cacheReadTokens,
  required bool claudeStyle,
  int cacheWriteTokens = 0,
}) {
  final safePromptTokens = _nonNegativeTokenCount(promptTokens);
  final safeCacheReadTokens = _nonNegativeTokenCount(cacheReadTokens);
  final safeCacheWriteTokens = _nonNegativeTokenCount(cacheWriteTokens);
  if (claudeStyle) {
    return safePromptTokens;
  }
  return nonNegativeRemaining(
    nonNegativeRemaining(safePromptTokens, safeCacheReadTokens),
    safeCacheWriteTokens,
  );
}

double computeCacheHitRatio({
  required int promptTokens,
  required int cacheReadTokens,
  required bool claudeStyle,
  int cacheWriteTokens = 0,
}) {
  final denominator = computeCacheHitDenominatorTokens(
    promptTokens: promptTokens,
    cacheReadTokens: cacheReadTokens,
    claudeStyle: claudeStyle,
    cacheWriteTokens: cacheWriteTokens,
  );
  return unitRatio(cacheReadTokens, denominator);
}

int _nonNegativeTokenCount(int value) => value < 0 ? 0 : value;
