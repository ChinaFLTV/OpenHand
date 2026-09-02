import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';

/// WebFetch 与 WebSearch 共用的故障降级、告警和限流配置。
final class AiWebEngineResilienceSettings {
  const AiWebEngineResilienceSettings({
    this.cooldownTier1Failures =
        AiWebEngineResiliencePolicy.defaultCooldownTier1Failures,
    this.cooldownTier1Seconds =
        AiWebEngineResiliencePolicy.defaultCooldownTier1Seconds,
    this.cooldownTier2Failures =
        AiWebEngineResiliencePolicy.defaultCooldownTier2Failures,
    this.cooldownTier2Seconds =
        AiWebEngineResiliencePolicy.defaultCooldownTier2Seconds,
    this.cooldownTier3Failures =
        AiWebEngineResiliencePolicy.defaultCooldownTier3Failures,
    this.cooldownTier3Seconds =
        AiWebEngineResiliencePolicy.defaultCooldownTier3Seconds,
    this.cooldownQuotaSeconds =
        AiWebEngineResiliencePolicy.defaultCooldownQuotaSeconds,
    this.alertSuccessRatePct = 0,
    this.alertAvgDurationMs = 0,
    this.throttlePerMinute = 0,
  });

  static const AiWebEngineResilienceSettings defaults =
      AiWebEngineResilienceSettings();

  final int cooldownTier1Failures;
  final int cooldownTier1Seconds;
  final int cooldownTier2Failures;
  final int cooldownTier2Seconds;
  final int cooldownTier3Failures;
  final int cooldownTier3Seconds;
  final int cooldownQuotaSeconds;
  final int alertSuccessRatePct;
  final int alertAvgDurationMs;
  final int throttlePerMinute;

  AiWebEngineResilienceSettings copyWith({
    int? cooldownTier1Failures,
    int? cooldownTier1Seconds,
    int? cooldownTier2Failures,
    int? cooldownTier2Seconds,
    int? cooldownTier3Failures,
    int? cooldownTier3Seconds,
    int? cooldownQuotaSeconds,
    int? alertSuccessRatePct,
    int? alertAvgDurationMs,
    int? throttlePerMinute,
  }) {
    return AiWebEngineResilienceSettings(
      cooldownTier1Failures:
          cooldownTier1Failures ?? this.cooldownTier1Failures,
      cooldownTier1Seconds: cooldownTier1Seconds ?? this.cooldownTier1Seconds,
      cooldownTier2Failures:
          cooldownTier2Failures ?? this.cooldownTier2Failures,
      cooldownTier2Seconds: cooldownTier2Seconds ?? this.cooldownTier2Seconds,
      cooldownTier3Failures:
          cooldownTier3Failures ?? this.cooldownTier3Failures,
      cooldownTier3Seconds: cooldownTier3Seconds ?? this.cooldownTier3Seconds,
      cooldownQuotaSeconds: cooldownQuotaSeconds ?? this.cooldownQuotaSeconds,
      alertSuccessRatePct: alertSuccessRatePct ?? this.alertSuccessRatePct,
      alertAvgDurationMs: alertAvgDurationMs ?? this.alertAvgDurationMs,
      throttlePerMinute: throttlePerMinute ?? this.throttlePerMinute,
    );
  }

  static AiWebEngineResilienceSettings fromJson(Map<String, Object?> json) {
    return AiWebEngineResilienceSettings(
      cooldownTier1Failures: AiWebEngineResiliencePolicy
          ._cooldownTier1FailuresRange
          .fromValue(json['cooldown_tier1_failures']),
      cooldownTier1Seconds: AiWebEngineResiliencePolicy
          ._cooldownTier1SecondsRange
          .fromValue(json['cooldown_tier1_seconds']),
      cooldownTier2Failures: AiWebEngineResiliencePolicy
          ._cooldownTier2FailuresRange
          .fromValue(json['cooldown_tier2_failures']),
      cooldownTier2Seconds: AiWebEngineResiliencePolicy
          ._cooldownTier2SecondsRange
          .fromValue(json['cooldown_tier2_seconds']),
      cooldownTier3Failures: AiWebEngineResiliencePolicy
          ._cooldownTier3FailuresRange
          .fromValue(json['cooldown_tier3_failures']),
      cooldownTier3Seconds: AiWebEngineResiliencePolicy
          ._cooldownTier3SecondsRange
          .fromValue(json['cooldown_tier3_seconds']),
      cooldownQuotaSeconds: AiWebEngineResiliencePolicy
          ._cooldownQuotaSecondsRange
          .fromValue(json['cooldown_quota_seconds']),
      alertSuccessRatePct: AiWebEngineResiliencePolicy._alertSuccessRatePctRange
          .fromValue(json['alert_success_rate_pct']),
      alertAvgDurationMs: AiWebEngineResiliencePolicy._alertAvgDurationMsRange
          .fromValue(json['alert_avg_duration_ms']),
      throttlePerMinute: AiWebEngineResiliencePolicy._throttlePerMinuteRange
          .fromValue(json['throttle_per_minute']),
    );
  }

  /// 将配置写入父对象，保持既有扁平 JSON 结构。
  void writeJsonTo(Map<String, Object?> json) {
    json.addAll({
      'cooldown_tier1_failures': cooldownTier1Failures,
      'cooldown_tier1_seconds': cooldownTier1Seconds,
      'cooldown_tier2_failures': cooldownTier2Failures,
      'cooldown_tier2_seconds': cooldownTier2Seconds,
      'cooldown_tier3_failures': cooldownTier3Failures,
      'cooldown_tier3_seconds': cooldownTier3Seconds,
      'cooldown_quota_seconds': cooldownQuotaSeconds,
      'alert_success_rate_pct': alertSuccessRatePct,
      'alert_avg_duration_ms': alertAvgDurationMs,
      'throttle_per_minute': throttlePerMinute,
    });
  }
}

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
}

/// Web 引擎单次调用的统一执行上限与并发取值。
abstract final class AiWebEngineExecutionPolicy {
  static const int maxAttempts = 8;
  static const int maxRetries = maxAttempts - 1;

  static const int defaultParallelWorkers = 3;
  static const int minParallelWorkers = 1;
  static const int maxParallelWorkers = 9;

  static const IntValueRange parallelWorkersRange = IntValueRange(
    fallback: defaultParallelWorkers,
    min: minParallelWorkers,
    max: maxParallelWorkers,
  );
}

/// WebFetch 与 WebSearch 单引擎配置的公共边界。
abstract final class AiWebEngineConfigPolicy {
  static const int defaultWeight = 50;
  static const int minWeight = 1;
  static const int maxWeight = 100;
  static const int defaultMaxRetries = 3;
  static const int minTruncationChars = 1000;
  static const int maxTruncationChars = 400000;
  static const int maxSerializedEngineEntries = 128;

  static const IntValueRange weightRange = IntValueRange(
    fallback: defaultWeight,
    min: minWeight,
    max: maxWeight,
  );
  static const IntValueRange maxRetriesRange = IntValueRange(
    fallback: defaultMaxRetries,
    min: 0,
    max: AiWebEngineExecutionPolicy.maxRetries,
  );
}

/// 按持久化顺序解码、去重并补齐全部 Web 引擎配置。
List<C> decodeOrderedAiWebEngineConfigs<E, C>({
  required Object? raw,
  required List<E> kinds,
  required C? Function(Map<String, Object?> json) decode,
  required E Function(C config) kindOf,
  required C Function(E kind) createDefault,
}) {
  final configs = <C>[];
  final seenKinds = <E>{};
  if (raw is List) {
    for (final entry in raw.take(
      AiWebEngineConfigPolicy.maxSerializedEngineEntries,
    )) {
      if (entry is! Map) continue;
      final config = decode(stringKeyedMapFromValue(entry));
      if (config != null && seenKinds.add(kindOf(config))) {
        configs.add(config);
        if (seenKinds.length == kinds.length) break;
      }
    }
  }
  for (final kind in kinds) {
    if (seenKinds.add(kind)) configs.add(createDefault(kind));
  }
  return configs;
}

/// WebFetch 与 WebSearch 共用的本地缓存取值边界。
///
/// 默认 TTL 因用途不同由各自的设置类定义（抓取的正文变化慢、搜索的结果变化快），
/// 其余上下限两者一致，集中在此处以免两边各改一半。
abstract final class AiWebEngineCachePolicy {
  static const int minTtlSeconds = 0;
  static const int maxTtlSeconds = 60 * 60 * 24 * 7;

  static const int defaultMaxBytes = 50 * kBytesPerMiB;
  static const int minMaxBytes = kBytesPerMiB;
  static const int maxMaxBytes = 2 * kBytesPerGiB;

  static const IntValueRange maxBytesRange = IntValueRange(
    fallback: defaultMaxBytes,
    min: minMaxBytes,
    max: maxMaxBytes,
  );
}
