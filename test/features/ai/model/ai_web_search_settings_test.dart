import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_web_search_settings.dart';

void main() {
  group('AiWebSearchEngineConfig', () {
    test('fromJson clamps engine-level numeric settings', () {
      final config = AiWebSearchEngineConfig.fromJson(<String, Object?>{
        'kind': 'tavily',
        'enabled': 'true',
        'weight': -5,
        'max_retries': 99,
        'truncation_chars': 10,
      });

      expect(config, isNotNull);
      expect(config!.enabled, isTrue);
      expect(config.weight, AiWebSearchEngineConfig.minWeight);
      expect(config.maxRetries, AiWebSearchEngineConfig.maxRetriesUpperBound);
      expect(
        config.truncationChars,
        AiWebSearchEngineConfig.minTruncationChars,
      );
    });

    test('fromJson rejects unknown engine kinds', () {
      expect(
        AiWebSearchEngineConfig.fromJson(const <String, Object?>{
          'kind': 'unknown',
        }),
        isNull,
      );
    });
  });

  group('AiWebSearchSettings', () {
    test('fromJson de-duplicates engines and fills missing kinds', () {
      final settings = AiWebSearchSettings.fromJson(<String, Object?>{
        'engines': <Object?>[
          <String, Object?>{'kind': 'tavily', 'enabled': true, 'weight': 80},
          <String, Object?>{'kind': 'tavily', 'enabled': false, 'weight': 1},
          <String, Object?>{'kind': 'unknown'},
        ],
      });

      expect(settings, isNotNull);
      expect(settings!.engines, hasLength(AiWebSearchEngineKind.values.length));
      expect(settings.engines.first.kind, AiWebSearchEngineKind.tavily);
      expect(settings.engines.first.enabled, isTrue);
      expect(settings.engines.first.weight, 80);
      expect(
        settings.engines.where(
          (item) => item.kind == AiWebSearchEngineKind.tavily,
        ),
        hasLength(1),
      );
    });

    test('fromJson clamps settings and normalizes summary bounds', () {
      final settings = AiWebSearchSettings.fromJson(<String, Object?>{
        'result_count': 100,
        'parallel_workers': 0,
        'summary_min_chars': 7000,
        'summary_max_chars': 1200,
        'cache_ttl_seconds': -1,
        'cache_max_bytes': 999999999999,
        'cooldown_tier1_failures': 1,
        'cooldown_tier1_seconds': 1,
        'cooldown_tier2_failures': 99,
        'cooldown_tier2_seconds': 999999,
        'cooldown_tier3_failures': 'bad',
        'cooldown_tier3_seconds': 'bad',
        'cooldown_quota_seconds': 0,
        'alert_success_rate_pct': 150,
        'alert_avg_duration_ms': -2,
        'throttle_per_minute': 800,
      });

      expect(settings, isNotNull);
      expect(settings!.resultCount, AiWebSearchSettings.maxResultCount);
      expect(settings.parallelWorkers, AiWebSearchSettings.minParallelWorkers);
      expect(settings.summaryMaxChars, 1200);
      expect(settings.summaryMinChars, 1200);
      expect(settings.cacheTtlSeconds, AiWebSearchSettings.minCacheTtlSeconds);
      expect(settings.cacheMaxBytes, AiWebSearchSettings.maxCacheMaxBytes);
      expect(
        settings.cooldownTier1Failures,
        AiWebSearchSettings.minCooldownFailures,
      );
      expect(
        settings.cooldownTier1Seconds,
        AiWebSearchSettings.minCooldownSeconds,
      );
      expect(
        settings.cooldownTier2Failures,
        AiWebSearchSettings.maxCooldownFailures,
      );
      expect(
        settings.cooldownTier2Seconds,
        AiWebSearchSettings.maxCooldownSeconds,
      );
      expect(
        settings.cooldownTier3Failures,
        AiWebSearchSettings.defaultCooldownTier3Failures,
      );
      expect(
        settings.cooldownTier3Seconds,
        AiWebSearchSettings.defaultCooldownTier3Seconds,
      );
      expect(
        settings.cooldownQuotaSeconds,
        AiWebSearchSettings.minCooldownSeconds,
      );
      expect(
        settings.alertSuccessRatePct,
        AiWebSearchSettings.maxAlertSuccessRatePct,
      );
      expect(settings.alertAvgDurationMs, 0);
      expect(
        settings.throttlePerMinute,
        AiWebSearchSettings.maxThrottlePerMinute,
      );
    });

    test('fromJson accepts JSON text payloads', () {
      final settings = AiWebSearchSettings.fromJson(
        '{"result_count":4,"parallel":false}',
      );

      expect(settings, isNotNull);
      expect(settings!.resultCount, 4);
      expect(settings.parallel, isFalse);
    });
  });
}
