import '../../../shared/util/input_value_parsing.dart';

class AiStreamThrottlePolicy {
  const AiStreamThrottlePolicy._();

  static const int defaultMaxCharsPerSecond = 10;
  static const int minMaxCharsPerSecond = 0;
  static const int maxMaxCharsPerSecond = 100000;

  static const int defaultMaxMessageCardsPerSecond = 1;
  static const int minMaxMessageCardsPerSecond = 0;
  static const int maxMaxMessageCardsPerSecond = 60;

  static const int defaultDurationSeconds = 0;
  static const int minDurationSeconds = 0;
  static const int maxDurationSeconds = 600;

  static const int autoMaxCharsPerSecondDesktop = 12;
  static const int autoMaxCharsPerSecondMobile = 6;
  static const int autoMaxMessageCardsPerSecond = 2;

  static const IntValueRange _maxCharsPerSecondRange = IntValueRange(
    fallback: defaultMaxCharsPerSecond,
    min: minMaxCharsPerSecond,
    max: maxMaxCharsPerSecond,
  );

  static const IntValueRange _maxMessageCardsPerSecondRange = IntValueRange(
    fallback: defaultMaxMessageCardsPerSecond,
    min: minMaxMessageCardsPerSecond,
    max: maxMaxMessageCardsPerSecond,
  );

  static const IntValueRange _durationSecondsRange = IntValueRange(
    fallback: defaultDurationSeconds,
    min: minDurationSeconds,
    max: maxDurationSeconds,
  );

  static int maxCharsPerSecondFromValue(Object? value) {
    final parsed = optionalIntegralIntFromValue(value);
    if (parsed == null || parsed < minMaxCharsPerSecond) {
      return defaultMaxCharsPerSecond;
    }
    return normalizeMaxCharsPerSecond(parsed);
  }

  static int normalizeMaxCharsPerSecond(int value) {
    if (value < minMaxCharsPerSecond) {
      return defaultMaxCharsPerSecond;
    }
    return _maxCharsPerSecondRange.normalize(value);
  }

  static int maxMessageCardsPerSecondFromValue(Object? value) {
    final parsed = optionalIntegralIntFromValue(value);
    if (parsed == null || parsed < minMaxMessageCardsPerSecond) {
      return defaultMaxMessageCardsPerSecond;
    }
    return normalizeMaxMessageCardsPerSecond(parsed);
  }

  static int normalizeMaxMessageCardsPerSecond(int value) {
    if (value < minMaxMessageCardsPerSecond) {
      return defaultMaxMessageCardsPerSecond;
    }
    return _maxMessageCardsPerSecondRange.normalize(value);
  }

  static int durationSecondsFromValue(Object? value) {
    return _durationSecondsRange.fromValue(value);
  }

  static int normalizeDurationSeconds(int value) {
    return _durationSecondsRange.normalize(value);
  }
}
