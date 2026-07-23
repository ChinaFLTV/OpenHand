import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_web_engine_resilience.dart';
import 'package:openhand/features/ai/model/ai_web_fetch_settings.dart';
import 'package:openhand/features/ai/model/ai_web_search_settings.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_cache_store.dart';
import 'package:openhand/features/ai/service/web_search/web_search_cache_store.dart';

void main() {
  test('缓存键区分自定义端点、引擎顺序和摘要模型', () {
    const fetchA = AiWebFetchSettings(
      engines: <AiWebFetchEngineConfig>[
        AiWebFetchEngineConfig(
          kind: AiWebFetchEngineKind.jina,
          enabled: true,
          endpointOverride: 'https://reader-a.example',
        ),
      ],
    );
    const fetchB = AiWebFetchSettings(
      engines: <AiWebFetchEngineConfig>[
        AiWebFetchEngineConfig(
          kind: AiWebFetchEngineKind.jina,
          enabled: true,
          endpointOverride: 'https://reader-b.example',
        ),
      ],
    );
    final fetchKeyA = WebFetchCacheStore.computeKey(
      url: 'https://example.com',
      prompt: '总结',
      settings: fetchA,
      modelProtocol: 'openai',
      modelId: 'model-a',
      modelConfigId: 'provider-a',
    );
    final fetchKeyB = WebFetchCacheStore.computeKey(
      url: 'https://example.com',
      prompt: '总结',
      settings: fetchB,
      modelProtocol: 'openai',
      modelId: 'model-a',
      modelConfigId: 'provider-a',
    );

    expect(fetchKeyA, isNot(fetchKeyB));

    const firstSearch = AiWebSearchSettings(
      engines: <AiWebSearchEngineConfig>[
        AiWebSearchEngineConfig(
          kind: AiWebSearchEngineKind.bing,
          enabled: true,
        ),
        AiWebSearchEngineConfig(
          kind: AiWebSearchEngineKind.duckduckgo,
          enabled: true,
        ),
      ],
    );
    const secondSearch = AiWebSearchSettings(
      engines: <AiWebSearchEngineConfig>[
        AiWebSearchEngineConfig(
          kind: AiWebSearchEngineKind.duckduckgo,
          enabled: true,
        ),
        AiWebSearchEngineConfig(
          kind: AiWebSearchEngineKind.bing,
          enabled: true,
        ),
      ],
    );
    const searchWithEndpoint = AiWebSearchSettings(
      engines: <AiWebSearchEngineConfig>[
        AiWebSearchEngineConfig(
          kind: AiWebSearchEngineKind.bing,
          enabled: true,
          endpointOverride: 'https://search.example',
        ),
        AiWebSearchEngineConfig(
          kind: AiWebSearchEngineKind.duckduckgo,
          enabled: true,
        ),
      ],
    );
    String searchKey(
      AiWebSearchSettings settings, {
      String modelConfigId = 'provider-a',
    }) {
      return WebSearchCacheStore.computeKey(
        query: 'OpenHand',
        settings: settings,
        allowedDomains: const <String>[],
        blockedDomains: const <String>[],
        localeTag: 'zh_CN',
        modelProtocol: 'openai',
        modelId: 'model-a',
        modelConfigId: modelConfigId,
      );
    }

    expect(searchKey(firstSearch), isNot(searchKey(secondSearch)));
    expect(searchKey(firstSearch), isNot(searchKey(searchWithEndpoint)));
    expect(
      searchKey(firstSearch),
      isNot(searchKey(firstSearch, modelConfigId: 'provider-b')),
    );
  });

  test('重试配置上限与公共执行壳一致', () {
    expect(
      AiWebFetchEngineConfig.maxRetriesUpperBound,
      AiWebEngineExecutionPolicy.maxRetries,
    );
    expect(
      AiWebSearchEngineConfig.maxRetriesUpperBound,
      AiWebEngineExecutionPolicy.maxRetries,
    );

    final fetch = AiWebFetchEngineConfig.fromJson(<String, Object?>{
      'kind': AiWebFetchEngineKind.jina.name,
      'max_retries': 99,
    });
    final search = AiWebSearchEngineConfig.fromJson(<String, Object?>{
      'kind': AiWebSearchEngineKind.bing.name,
      'max_retries': 99,
    });

    expect(fetch?.maxRetries, AiWebEngineExecutionPolicy.maxRetries);
    expect(search?.maxRetries, AiWebEngineExecutionPolicy.maxRetries);
  });
}
