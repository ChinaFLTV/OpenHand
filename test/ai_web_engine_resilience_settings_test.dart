import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_web_engine_resilience.dart';
import 'package:openhand/features/ai/model/ai_web_fetch_settings.dart';
import 'package:openhand/features/ai/model/ai_web_search_settings.dart';

void main() {
  test('韧性配置解析保持既有默认值与取值范围', () {
    final resilience = AiWebEngineResilienceSettings.fromJson({
      'cooldown_tier1_failures': 1,
      'cooldown_tier1_seconds': 4,
      'cooldown_tier2_failures': 51,
      'cooldown_tier2_seconds': 24 * 60 * 60 + 1,
      'alert_success_rate_pct': -1,
      'alert_avg_duration_ms': 600 * 1000 + 1,
      'throttle_per_minute': 601,
    });

    expect(resilience.cooldownTier1Failures, 2);
    expect(resilience.cooldownTier1Seconds, 5);
    expect(resilience.cooldownTier2Failures, 50);
    expect(resilience.cooldownTier2Seconds, 24 * 60 * 60);
    expect(
      resilience.cooldownTier3Failures,
      AiWebEngineResiliencePolicy.defaultCooldownTier3Failures,
    );
    expect(
      resilience.cooldownQuotaSeconds,
      AiWebEngineResiliencePolicy.defaultCooldownQuotaSeconds,
    );
    expect(resilience.alertSuccessRatePct, 0);
    expect(resilience.alertAvgDurationMs, 600 * 1000);
    expect(resilience.throttlePerMinute, 600);
  });

  test('韧性配置以扁平键写入父配置', () {
    const resilience = AiWebEngineResilienceSettings(
      cooldownTier1Failures: 4,
      cooldownTier1Seconds: 61,
      cooldownTier2Failures: 6,
      cooldownTier2Seconds: 301,
      cooldownTier3Failures: 8,
      cooldownTier3Seconds: 901,
      cooldownQuotaSeconds: 302,
      alertSuccessRatePct: 71,
      alertAvgDurationMs: 1234,
      throttlePerMinute: 42,
    );
    final json = <String, Object?>{};

    resilience.writeJsonTo(json);

    expect(json, {
      'cooldown_tier1_failures': 4,
      'cooldown_tier1_seconds': 61,
      'cooldown_tier2_failures': 6,
      'cooldown_tier2_seconds': 301,
      'cooldown_tier3_failures': 8,
      'cooldown_tier3_seconds': 901,
      'cooldown_quota_seconds': 302,
      'alert_success_rate_pct': 71,
      'alert_avg_duration_ms': 1234,
      'throttle_per_minute': 42,
    });
  });

  test('WebFetch 与 WebSearch 保持旧版扁平持久化格式', () {
    const resilience = AiWebEngineResilienceSettings(
      cooldownTier1Failures: 4,
      cooldownTier1Seconds: 61,
      cooldownTier2Failures: 6,
      cooldownTier2Seconds: 301,
      cooldownTier3Failures: 8,
      cooldownTier3Seconds: 901,
      cooldownQuotaSeconds: 302,
      alertSuccessRatePct: 71,
      alertAvgDurationMs: 1234,
      throttlePerMinute: 42,
    );
    const fetch = AiWebFetchSettings(
      engines: <AiWebFetchEngineConfig>[],
      resilience: resilience,
    );
    const search = AiWebSearchSettings(
      engines: <AiWebSearchEngineConfig>[],
      resilience: resilience,
    );

    for (final json in [fetch.toJson(), search.toJson()]) {
      expect(json.containsKey('resilience'), isFalse);
      expect(json['cooldown_tier1_failures'], 4);
      expect(json['cooldown_tier3_seconds'], 901);
      expect(json['alert_success_rate_pct'], 71);
      expect(json['throttle_per_minute'], 42);
    }

    final restoredFetch = AiWebFetchSettings.fromJson(fetch.toJson())!;
    final restoredSearch = AiWebSearchSettings.fromJson(search.toJson())!;
    expect(restoredFetch.resilience.alertAvgDurationMs, 1234);
    expect(restoredSearch.resilience.cooldownQuotaSeconds, 302);
  });
}
