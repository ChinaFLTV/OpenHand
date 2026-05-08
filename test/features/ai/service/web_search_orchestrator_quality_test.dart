import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_web_search_settings.dart';
import 'package:openhand/features/ai/service/web_search/web_search_engine.dart';
import 'package:openhand/features/ai/service/web_search/web_search_orchestrator.dart';

void main() {
  late http.Client client;

  setUp(() {
    client = http.Client();
  });

  tearDown(() {
    client.close();
  });

  group('WebSearchOrchestrator result quality', () {
    test('does not inflate weight for duplicate URLs from the same engine', () {
      final orchestrator = _orchestrator(client);

      final merged = orchestrator.mergeAndRankForTesting(
        results: <WebSearchEngineResult>[
          WebSearchEngineResult(
            kind: AiWebSearchEngineKind.bing,
            hits: <WebSearchEngineHit>[
              WebSearchEngineHit(
                title: 'Short title',
                url: 'https://example.com/docs?id=1&utm_source=newsletter',
                snippet: 'Short.',
              ),
              WebSearchEngineHit(
                title: 'A much more descriptive title',
                url: 'https://www.example.com/docs?utm_campaign=x&id=1',
                snippet: 'A longer snippet with the useful context.',
                source: 'provider-docs',
                score: 0.82,
                rawContent: 'Full provider text with extra evidence.',
              ),
            ],
          ),
        ],
        configs: const <AiWebSearchEngineKind, AiWebSearchEngineConfig>{
          AiWebSearchEngineKind.bing: AiWebSearchEngineConfig(
            kind: AiWebSearchEngineKind.bing,
            weight: 70,
          ),
        },
        maxResults: 10,
      );

      expect(merged, hasLength(1));
      expect(merged.single.totalWeight, 70);
      expect(merged.single.contributingEngines, <AiWebSearchEngineKind>[
        AiWebSearchEngineKind.bing,
      ]);
      expect(merged.single.title, 'A much more descriptive title');
      expect(
        merged.single.snippet,
        'A longer snippet with the useful context.',
      );
      expect(merged.single.source, 'provider-docs');
      expect(merged.single.score, 0.82);
      expect(
        merged.single.rawContent,
        'Full provider text with extra evidence.',
      );
    });

    test('preserves meaningful query parameters while stripping trackers', () {
      final orchestrator = _orchestrator(client);

      final merged = orchestrator.mergeAndRankForTesting(
        results: <WebSearchEngineResult>[
          WebSearchEngineResult(
            kind: AiWebSearchEngineKind.duckduckgo,
            hits: <WebSearchEngineHit>[
              WebSearchEngineHit(
                title: 'Issue 1',
                url: 'https://example.com/issues?id=1&utm_medium=social',
                snippet: 'First issue.',
              ),
              WebSearchEngineHit(
                title: 'Issue 2',
                url: 'https://example.com/issues?id=2&utm_medium=social',
                snippet: 'Second issue.',
              ),
            ],
          ),
        ],
        configs: const <AiWebSearchEngineKind, AiWebSearchEngineConfig>{
          AiWebSearchEngineKind.duckduckgo: AiWebSearchEngineConfig(
            kind: AiWebSearchEngineKind.duckduckgo,
          ),
        },
        maxResults: 10,
      );

      expect(merged, hasLength(2));
      expect(
        merged.map((hit) => hit.url),
        contains('https://example.com/issues?id=1&utm_medium=social'),
      );
      expect(
        merged.map((hit) => hit.url),
        contains('https://example.com/issues?id=2&utm_medium=social'),
      );
    });

    test('boosts query-relevant hits and skips URL-only noise', () {
      final orchestrator = _orchestrator(client);

      final merged = orchestrator.mergeAndRankForTesting(
        query: 'WebFetch cache key settings',
        results: <WebSearchEngineResult>[
          WebSearchEngineResult(
            kind: AiWebSearchEngineKind.bing,
            hits: <WebSearchEngineHit>[
              WebSearchEngineHit(
                title: 'Generic homepage',
                url: 'https://example.com/',
                snippet: 'Welcome to the example website.',
              ),
              WebSearchEngineHit(
                title: 'https://example.com/empty',
                url: 'https://example.com/empty',
                snippet: '',
              ),
              WebSearchEngineHit(
                title: 'WebFetch cache key settings',
                url: 'https://example.com/webfetch-cache-key',
                snippet:
                    'Explains how WebFetch cache keys include settings and model identity.',
              ),
            ],
          ),
        ],
        configs: const <AiWebSearchEngineKind, AiWebSearchEngineConfig>{
          AiWebSearchEngineKind.bing: AiWebSearchEngineConfig(
            kind: AiWebSearchEngineKind.bing,
          ),
        },
        maxResults: 10,
      );

      expect(
        merged.map((hit) => hit.url),
        isNot(contains('https://example.com/empty')),
      );
      expect(merged.first.url, 'https://example.com/webfetch-cache-key');
    });
  });
}

WebSearchOrchestrator _orchestrator(http.Client client) {
  return WebSearchOrchestrator(
    settings: AiWebSearchSettings.defaults(),
    httpClient: client,
    availableModels: const [],
  );
}
