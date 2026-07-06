import '../../../shared/util/input_value_parsing.dart';

class AiToolCallLimitPolicy {
  const AiToolCallLimitPolicy._();

  static const int defaultSingleRoundToolCallLimit = 40;
  static const int minSingleRoundToolCallLimit = 1;
  static const int maxSingleRoundToolCallLimit = 1000;

  static const int defaultSequentialToolRoundLimit = 24;
  static const int minSequentialToolRoundLimit = 1;
  static const int maxSequentialToolRoundLimit = 1000;

  static const IntValueRange _singleRoundRange = IntValueRange(
    fallback: defaultSingleRoundToolCallLimit,
    min: minSingleRoundToolCallLimit,
    max: maxSingleRoundToolCallLimit,
  );

  static const IntValueRange _sequentialRoundRange = IntValueRange(
    fallback: defaultSequentialToolRoundLimit,
    min: minSequentialToolRoundLimit,
    max: maxSequentialToolRoundLimit,
  );

  static int singleRoundFromValue(Object? value) {
    final parsed = optionalIntegralIntFromValue(value);
    if (parsed == null || parsed <= 0) {
      return defaultSingleRoundToolCallLimit;
    }
    return normalizeSingleRound(parsed);
  }

  static int normalizeSingleRound(int value) {
    if (value <= 0) {
      return defaultSingleRoundToolCallLimit;
    }
    return _singleRoundRange.normalize(value);
  }

  static int sequentialRoundFromValue(Object? value) {
    final parsed = optionalIntegralIntFromValue(value);
    if (parsed == null || parsed <= 0) {
      return defaultSequentialToolRoundLimit;
    }
    return normalizeSequentialRound(parsed);
  }

  static int normalizeSequentialRound(int value) {
    if (value <= 0) {
      return defaultSequentialToolRoundLimit;
    }
    return _sequentialRoundRange.normalize(value);
  }
}
