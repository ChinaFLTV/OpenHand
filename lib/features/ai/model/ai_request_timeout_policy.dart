import '../../../shared/util/input_value_parsing.dart';

class AiRequestTimeoutPolicy {
  const AiRequestTimeoutPolicy._();

  static const int defaultConnectTimeoutSeconds = 60;
  static const int minConnectTimeoutSeconds = 5;
  static const int maxConnectTimeoutSeconds = 300;

  static const int defaultResponseTimeoutSeconds = 120;
  static const int minResponseTimeoutSeconds = 10;
  static const int maxResponseTimeoutSeconds = 600;

  static const int defaultStreamIdleTimeoutSeconds = 120;
  static const int minStreamIdleTimeoutSeconds = 10;
  static const int maxStreamIdleTimeoutSeconds = 600;

  static const IntValueRange _connectTimeoutSecondsRange = IntValueRange(
    fallback: defaultConnectTimeoutSeconds,
    min: minConnectTimeoutSeconds,
    max: maxConnectTimeoutSeconds,
  );

  static const IntValueRange _responseTimeoutSecondsRange = IntValueRange(
    fallback: defaultResponseTimeoutSeconds,
    min: minResponseTimeoutSeconds,
    max: maxResponseTimeoutSeconds,
  );

  static const IntValueRange _streamIdleTimeoutSecondsRange = IntValueRange(
    fallback: defaultStreamIdleTimeoutSeconds,
    min: minStreamIdleTimeoutSeconds,
    max: maxStreamIdleTimeoutSeconds,
  );

  static int connectTimeoutSecondsFromValue(Object? value) {
    return _fromValueOrDefault(value, _connectTimeoutSecondsRange);
  }

  static int normalizeConnectTimeoutSeconds(int value) {
    return _normalizeOrDefault(value, _connectTimeoutSecondsRange);
  }

  static int responseTimeoutSecondsFromValue(Object? value) {
    return _fromValueOrDefault(value, _responseTimeoutSecondsRange);
  }

  static int normalizeResponseTimeoutSeconds(int value) {
    return _normalizeOrDefault(value, _responseTimeoutSecondsRange);
  }

  static int streamIdleTimeoutSecondsFromValue(Object? value) {
    return _fromValueOrDefault(value, _streamIdleTimeoutSecondsRange);
  }

  static int normalizeStreamIdleTimeoutSeconds(int value) {
    return _normalizeOrDefault(value, _streamIdleTimeoutSecondsRange);
  }
}

int _fromValueOrDefault(Object? value, IntValueRange range) {
  final parsed = optionalIntegralIntFromValue(value);
  if (parsed == null || parsed < range.min) {
    return range.fallback;
  }
  return range.normalize(parsed);
}

int _normalizeOrDefault(int value, IntValueRange range) {
  if (value < range.min) {
    return range.fallback;
  }
  return range.normalize(value);
}
