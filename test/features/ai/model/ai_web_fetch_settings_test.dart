import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_web_fetch_settings.dart';

void main() {
  group('AiWebFetchEngineConfig', () {
    test('fromJson clamps engine-level numeric settings', () {
      final config = AiWebFetchEngineConfig.fromJson(<String, Object?>{
        'kind': 'firecrawl',
        'enabled': 'true',
        'weight': 120,
        'max_retries': -2,
        'truncation_chars': 10,
        'connection_timeout_seconds': 0,
        'response_timeout_seconds': 999,
      });

      expect(config, isNotNull);
      expect(config!.enabled, isTrue);
      expect(config.weight, AiWebFetchEngineConfig.maxWeight);
      expect(config.maxRetries, 0);
      expect(config.truncationChars, AiWebFetchEngineConfig.minTruncationChars);
      expect(
        config.connectionTimeoutSeconds,
        AiWebFetchEngineConfig.minConnectionTimeoutSeconds,
      );
      expect(
        config.responseTimeoutSeconds,
        AiWebFetchEngineConfig.maxResponseTimeoutSeconds,
      );
    });

    test('fromJson rejects unknown engine kinds', () {
      expect(
        AiWebFetchEngineConfig.fromJson(const <String, Object?>{
          'kind': 'unknown',
        }),
        isNull,
      );
    });
  });

  group('AiWebFetchScraplingSettings', () {
    test('fromJson clamps timeout settings and trims executable', () {
      final settings = AiWebFetchScraplingSettings.fromJson(
        '{"python_executable":" /usr/bin/python3 ",'
        '"startup_timeout_seconds":1,'
        '"request_timeout_seconds":999,'
        '"install_timeout_seconds":"bad"}',
      );

      expect(settings, isNotNull);
      expect(settings!.pythonExecutable, '/usr/bin/python3');
      expect(
        settings.startupTimeoutSeconds,
        AiWebFetchScraplingSettings.minStartupTimeoutSeconds,
      );
      expect(
        settings.requestTimeoutSeconds,
        AiWebFetchScraplingSettings.maxRequestTimeoutSeconds,
      );
      expect(
        settings.installTimeoutSeconds,
        AiWebFetchScraplingSettings.defaultInstallTimeoutSeconds,
      );
    });
  });

  group('AiWebFetchSettings', () {
    test('fromJson de-duplicates engines and fills missing kinds', () {
      final settings = AiWebFetchSettings.fromJson(<String, Object?>{
        'engines': <Object?>[
          <String, Object?>{'kind': 'firecrawl', 'enabled': true, 'weight': 80},
          <String, Object?>{'kind': 'firecrawl', 'enabled': false, 'weight': 1},
          <String, Object?>{'kind': 'unknown'},
        ],
      });

      expect(settings, isNotNull);
      expect(settings!.engines, hasLength(AiWebFetchEngineKind.values.length));
      expect(settings.engines.first.kind, AiWebFetchEngineKind.firecrawl);
      expect(settings.engines.first.enabled, isTrue);
      expect(settings.engines.first.weight, 80);
      expect(
        settings.engines.where(
          (item) => item.kind == AiWebFetchEngineKind.firecrawl,
        ),
        hasLength(1),
      );
    });

    test('fromJson clamps settings-level numeric values', () {
      final settings = AiWebFetchSettings.fromJson(<String, Object?>{
        'result_count': 100,
        'parallel_workers': 0,
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
      expect(settings!.resultCount, AiWebFetchSettings.maxResultCount);
      expect(settings.parallelWorkers, AiWebFetchSettings.minParallelWorkers);
      expect(settings.cacheTtlSeconds, AiWebFetchSettings.minCacheTtlSeconds);
      expect(settings.cacheMaxBytes, AiWebFetchSettings.maxCacheMaxBytes);
      expect(
        settings.cooldownTier1Failures,
        AiWebFetchSettings.minCooldownFailures,
      );
      expect(
        settings.cooldownTier1Seconds,
        AiWebFetchSettings.minCooldownSeconds,
      );
      expect(
        settings.cooldownTier2Failures,
        AiWebFetchSettings.maxCooldownFailures,
      );
      expect(
        settings.cooldownTier2Seconds,
        AiWebFetchSettings.maxCooldownSeconds,
      );
      expect(
        settings.cooldownTier3Failures,
        AiWebFetchSettings.defaultCooldownTier3Failures,
      );
      expect(
        settings.cooldownTier3Seconds,
        AiWebFetchSettings.defaultCooldownTier3Seconds,
      );
      expect(
        settings.cooldownQuotaSeconds,
        AiWebFetchSettings.minCooldownSeconds,
      );
      expect(
        settings.alertSuccessRatePct,
        AiWebFetchSettings.maxAlertSuccessRatePct,
      );
      expect(settings.alertAvgDurationMs, 0);
      expect(
        settings.throttlePerMinute,
        AiWebFetchSettings.maxThrottlePerMinute,
      );
    });

    test('fromJson accepts JSON text payloads', () {
      final settings = AiWebFetchSettings.fromJson(
        '{"result_count":4,"parallel":false}',
      );

      expect(settings, isNotNull);
      expect(settings!.resultCount, 4);
      expect(settings.parallel, isFalse);
    });
  });
}
