import '../../../shared/util/input_value_parsing.dart';

int computeCacheHitDenominatorTokens({
  required int promptTokens,
  required int cacheReadTokens,
  required bool claudeStyle,
}) {
  final safePromptTokens = _nonNegativeTokenCount(promptTokens);
  final safeCacheReadTokens = _nonNegativeTokenCount(cacheReadTokens);
  if (safePromptTokens <= 0 && safeCacheReadTokens <= 0) {
    return 0;
  }
  if (claudeStyle) {
    return safePromptTokens + safeCacheReadTokens;
  }
  return safePromptTokens > 0 ? safePromptTokens : safeCacheReadTokens;
}

int computeUncachedPromptTokens({
  required int promptTokens,
  required int cacheReadTokens,
  required bool claudeStyle,
}) {
  final safePromptTokens = _nonNegativeTokenCount(promptTokens);
  final safeCacheReadTokens = _nonNegativeTokenCount(cacheReadTokens);
  if (claudeStyle) {
    return safePromptTokens;
  }
  return nonNegativeRemaining(safePromptTokens, safeCacheReadTokens);
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
  return unitRatio(cacheReadTokens, denominator);
}

int _nonNegativeTokenCount(int value) => value < 0 ? 0 : value;
