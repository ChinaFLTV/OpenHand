import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_web_fetch_settings.dart';
import 'package:openhand/features/ai/model/ai_web_search_settings.dart';

void main() {
  group('AiWebSearchSettings.fromJson', () {
    test('parses loose JSON text and fills missing engines', () {
      final settings = AiWebSearchSettings.fromJson('''
        {
          "engines": [
            {
              "kind": "bing",
              "enabled": "true",
              "weight": "999",
              "api_key": 123,
              "provider_config_id": " provider ",
              "endpoint_override": " https://search.example.com "
            },
            {"kind": "bing", "enabled": false},
            {"kind": "unknown"}
          ],
          "result_count": "999",
          "model_mode": "fixed",
          "fixed_model_provider_config_id": 99,
          "fixed_model_id": " model ",
          "parallel": "false",
          "parallel_workers": "0",
          "summary_detail": "exhaustive",
          "summary_style": "structured"
        }
      ''');

      expect(settings, isNotNull);
      expect(settings!.engines, hasLength(AiWebSearchEngineKind.values.length));
      final bing = settings.engines.first;
      expect(bing.kind, AiWebSearchEngineKind.bing);
      expect(bing.enabled, isTrue);
      expect(bing.weight, AiWebSearchEngineConfig.maxWeight);
      expect(bing.apiKey, '123');
      expect(bing.providerConfigId, 'provider');
      expect(bing.endpointOverride, 'https://search.example.com');
      expect(settings.resultCount, AiWebSearchSettings.maxResultCount);
      expect(settings.modelMode, AiWebSearchModelMode.fixed);
      expect(settings.fixedModelProviderConfigId, '99');
      expect(settings.fixedModelId, 'model');
      expect(settings.parallel, isFalse);
      expect(settings.parallelWorkers, AiWebSearchSettings.minParallelWorkers);
      expect(settings.summaryDetail, AiWebSearchSummaryDetail.exhaustive);
      expect(settings.summaryStyle, AiWebSearchSummaryStyle.structured);
    });

    test('rejects non-object input', () {
      expect(AiWebSearchSettings.fromJson('[]'), isNull);
      expect(AiWebSearchSettings.fromJson(42), isNull);
    });
  });

  group('AiWebFetchSettings.fromJson', () {
    test('parses loose map values and fills missing engines', () {
      final settings = AiWebFetchSettings.fromJson(<Object?, Object?>{
        'engines': <Object?>[
          <Object?, Object?>{
            'kind': 'firecrawl',
            'enabled': 'yes',
            'weight': '0',
            'max_retries': '99',
            'truncation_chars': '1',
            'connection_timeout_seconds': '0',
            'response_timeout_seconds': '999',
            'api_key': 456,
            'provider_config_id': ' provider ',
            'endpoint_override': ' https://fetch.example.com ',
          },
        ],
        'scrapling': '{"python_executable": 789, "startup_timeout_seconds": 1}',
        'result_count': '999',
        'parallel': 'off',
        'parallel_workers': '99',
      });

      expect(settings, isNotNull);
      expect(settings!.engines, hasLength(AiWebFetchEngineKind.values.length));
      final firecrawl = settings.engines.first;
      expect(firecrawl.kind, AiWebFetchEngineKind.firecrawl);
      expect(firecrawl.enabled, isTrue);
      expect(firecrawl.weight, AiWebFetchEngineConfig.minWeight);
      expect(firecrawl.maxRetries, AiWebFetchEngineConfig.maxRetriesUpperBound);
      expect(
        firecrawl.truncationChars,
        AiWebFetchEngineConfig.minTruncationChars,
      );
      expect(
        firecrawl.connectionTimeoutSeconds,
        AiWebFetchEngineConfig.minConnectionTimeoutSeconds,
      );
      expect(
        firecrawl.responseTimeoutSeconds,
        AiWebFetchEngineConfig.maxResponseTimeoutSeconds,
      );
      expect(firecrawl.apiKey, '456');
      expect(firecrawl.providerConfigId, 'provider');
      expect(firecrawl.endpointOverride, 'https://fetch.example.com');
      expect(settings.scrapling.pythonExecutable, '789');
      expect(
        settings.scrapling.startupTimeoutSeconds,
        AiWebFetchScraplingSettings.minStartupTimeoutSeconds,
      );
      expect(settings.resultCount, AiWebFetchSettings.maxResultCount);
      expect(settings.parallel, isFalse);
      expect(settings.parallelWorkers, AiWebFetchSettings.maxParallelWorkers);
    });

    test('rejects non-object input', () {
      expect(AiWebFetchSettings.fromJson('[]'), isNull);
      expect(AiWebFetchScraplingSettings.fromJson('[]'), isNull);
    });
  });
}
