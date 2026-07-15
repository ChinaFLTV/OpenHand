import '../../../shared/util/input_value_parsing.dart';

typedef AiWebEngineResilienceValues = ({
  int cooldownTier1Failures,
  int cooldownTier1Seconds,
  int cooldownTier2Failures,
  int cooldownTier2Seconds,
  int cooldownTier3Failures,
  int cooldownTier3Seconds,
  int cooldownQuotaSeconds,
  int alertSuccessRatePct,
  int alertAvgDurationMs,
  int throttlePerMinute,
});

abstract final class AiWebEngineResiliencePolicy {
  static const int defaultCooldownTier1Failures = 3;
  static const int defaultCooldownTier1Seconds = 60;
  static const int defaultCooldownTier2Failures = 5;
  static const int defaultCooldownTier2Seconds = 300;
  static const int defaultCooldownTier3Failures = 7;
  static const int defaultCooldownTier3Seconds = 900;
  static const int defaultCooldownQuotaSeconds = 300;
  static const int minCooldownFailures = 2;
  static const int maxCooldownFailures = 50;
  static const int minCooldownSeconds = 5;
  static const int maxCooldownSeconds = 24 * 60 * 60;
  static const int maxAlertSuccessRatePct = 100;
  static const int maxAlertAvgDurationMs = 600 * 1000;
  static const int maxThrottlePerMinute = 600;

  static const IntValueRange _cooldownTier1FailuresRange = IntValueRange(
    fallback: defaultCooldownTier1Failures,
    min: minCooldownFailures,
    max: maxCooldownFailures,
  );
  static const IntValueRange _cooldownTier2FailuresRange = IntValueRange(
    fallback: defaultCooldownTier2Failures,
    min: minCooldownFailures,
    max: maxCooldownFailures,
  );
  static const IntValueRange _cooldownTier3FailuresRange = IntValueRange(
    fallback: defaultCooldownTier3Failures,
    min: minCooldownFailures,
    max: maxCooldownFailures,
  );
  static const IntValueRange _cooldownTier1SecondsRange = IntValueRange(
    fallback: defaultCooldownTier1Seconds,
    min: minCooldownSeconds,
    max: maxCooldownSeconds,
  );
  static const IntValueRange _cooldownTier2SecondsRange = IntValueRange(
    fallback: defaultCooldownTier2Seconds,
    min: minCooldownSeconds,
    max: maxCooldownSeconds,
  );
  static const IntValueRange _cooldownTier3SecondsRange = IntValueRange(
    fallback: defaultCooldownTier3Seconds,
    min: minCooldownSeconds,
    max: maxCooldownSeconds,
  );
  static const IntValueRange _cooldownQuotaSecondsRange = IntValueRange(
    fallback: defaultCooldownQuotaSeconds,
    min: minCooldownSeconds,
    max: maxCooldownSeconds,
  );
  static const IntValueRange _alertSuccessRatePctRange = IntValueRange(
    fallback: 0,
    min: 0,
    max: maxAlertSuccessRatePct,
  );
  static const IntValueRange _alertAvgDurationMsRange = IntValueRange(
    fallback: 0,
    min: 0,
    max: maxAlertAvgDurationMs,
  );
  static const IntValueRange _throttlePerMinuteRange = IntValueRange(
    fallback: 0,
    min: 0,
    max: maxThrottlePerMinute,
  );

  static AiWebEngineResilienceValues valuesFromJson(Map<String, Object?> json) {
    return (
      cooldownTier1Failures: _cooldownTier1FailuresRange.fromValue(
        json['cooldown_tier1_failures'],
      ),
      cooldownTier1Seconds: _cooldownTier1SecondsRange.fromValue(
        json['cooldown_tier1_seconds'],
      ),
      cooldownTier2Failures: _cooldownTier2FailuresRange.fromValue(
        json['cooldown_tier2_failures'],
      ),
      cooldownTier2Seconds: _cooldownTier2SecondsRange.fromValue(
        json['cooldown_tier2_seconds'],
      ),
      cooldownTier3Failures: _cooldownTier3FailuresRange.fromValue(
        json['cooldown_tier3_failures'],
      ),
      cooldownTier3Seconds: _cooldownTier3SecondsRange.fromValue(
        json['cooldown_tier3_seconds'],
      ),
      cooldownQuotaSeconds: _cooldownQuotaSecondsRange.fromValue(
        json['cooldown_quota_seconds'],
      ),
      alertSuccessRatePct: _alertSuccessRatePctRange.fromValue(
        json['alert_success_rate_pct'],
      ),
      alertAvgDurationMs: _alertAvgDurationMsRange.fromValue(
        json['alert_avg_duration_ms'],
      ),
      throttlePerMinute: _throttlePerMinuteRange.fromValue(
        json['throttle_per_minute'],
      ),
    );
  }
}
