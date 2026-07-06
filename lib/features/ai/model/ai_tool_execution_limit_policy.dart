import '../../../shared/util/input_value_parsing.dart';

class AiToolExecutionLimitPolicy {
  const AiToolExecutionLimitPolicy._();

  static const int defaultMaxToolOutputChars = 150000;
  static const int minMaxToolOutputChars = 1000;
  static const int maxMaxToolOutputChars = 10000000;

  static const int defaultWriteConfirmationTimeoutMs = 300000;
  static const int minWriteConfirmationTimeoutMs = 1000;
  static const int maxWriteConfirmationTimeoutMs = 3600000;

  static const int defaultFastPathWriteAnalysisThreshold = 512;
  static const int minFastPathWriteAnalysisThreshold = 0;
  static const int maxFastPathWriteAnalysisThreshold = 100000;

  static const int defaultMaxHookTextCharacters = 4000;
  static const int minMaxHookTextCharacters = 100;
  static const int maxMaxHookTextCharacters = 1000000;

  static const int defaultSubprocessGracefulShutdownMs = 500;
  static const int minSubprocessGracefulShutdownMs = 100;
  static const int maxSubprocessGracefulShutdownMs = 5000;

  static const int defaultBashOutputMaxBytes = 200000;
  static const int minBashOutputMaxBytes = 16000;
  static const int maxBashOutputMaxBytes = 4000000;

  static const int defaultMaxConcurrentTools = 8;
  static const int minMaxConcurrentTools = 1;
  static const int maxMaxConcurrentTools = 64;

  static const IntValueRange _maxToolOutputCharsRange = IntValueRange(
    fallback: defaultMaxToolOutputChars,
    min: minMaxToolOutputChars,
    max: maxMaxToolOutputChars,
  );

  static const IntValueRange _writeConfirmationTimeoutMsRange = IntValueRange(
    fallback: defaultWriteConfirmationTimeoutMs,
    min: minWriteConfirmationTimeoutMs,
    max: maxWriteConfirmationTimeoutMs,
  );

  static const IntValueRange _fastPathWriteAnalysisThresholdRange =
      IntValueRange(
        fallback: defaultFastPathWriteAnalysisThreshold,
        min: minFastPathWriteAnalysisThreshold,
        max: maxFastPathWriteAnalysisThreshold,
      );

  static const IntValueRange _maxHookTextCharactersRange = IntValueRange(
    fallback: defaultMaxHookTextCharacters,
    min: minMaxHookTextCharacters,
    max: maxMaxHookTextCharacters,
  );

  static const IntValueRange _subprocessGracefulShutdownMsRange = IntValueRange(
    fallback: defaultSubprocessGracefulShutdownMs,
    min: minSubprocessGracefulShutdownMs,
    max: maxSubprocessGracefulShutdownMs,
  );

  static const IntValueRange _bashOutputMaxBytesRange = IntValueRange(
    fallback: defaultBashOutputMaxBytes,
    min: minBashOutputMaxBytes,
    max: maxBashOutputMaxBytes,
  );

  static const IntValueRange _maxConcurrentToolsRange = IntValueRange(
    fallback: defaultMaxConcurrentTools,
    min: minMaxConcurrentTools,
    max: maxMaxConcurrentTools,
  );

  static int maxToolOutputCharsFromValue(Object? value) {
    return _maxToolOutputCharsRange.fromValue(value);
  }

  static int normalizeMaxToolOutputChars(int value) {
    return _maxToolOutputCharsRange.normalize(value);
  }

  static int writeConfirmationTimeoutMsFromValue(Object? value) {
    return _writeConfirmationTimeoutMsRange.fromValue(value);
  }

  static int normalizeWriteConfirmationTimeoutMs(int value) {
    return _writeConfirmationTimeoutMsRange.normalize(value);
  }

  static int fastPathWriteAnalysisThresholdFromValue(Object? value) {
    return _fastPathWriteAnalysisThresholdRange.fromValue(value);
  }

  static int normalizeFastPathWriteAnalysisThreshold(int value) {
    return _fastPathWriteAnalysisThresholdRange.normalize(value);
  }

  static int maxHookTextCharactersFromValue(Object? value) {
    return _maxHookTextCharactersRange.fromValue(value);
  }

  static int normalizeMaxHookTextCharacters(int value) {
    return _maxHookTextCharactersRange.normalize(value);
  }

  static int subprocessGracefulShutdownMsFromValue(Object? value) {
    return _subprocessGracefulShutdownMsRange.fromValue(value);
  }

  static int normalizeSubprocessGracefulShutdownMs(int value) {
    return _subprocessGracefulShutdownMsRange.normalize(value);
  }

  static int bashOutputMaxBytesFromValue(Object? value) {
    return _bashOutputMaxBytesRange.fromValue(value);
  }

  static int normalizeBashOutputMaxBytes(int value) {
    return _bashOutputMaxBytesRange.normalize(value);
  }

  static int maxConcurrentToolsFromValue(Object? value) {
    return _maxConcurrentToolsRange.fromValue(value);
  }

  static int normalizeMaxConcurrentTools(int value) {
    return _maxConcurrentToolsRange.normalize(value);
  }
}
