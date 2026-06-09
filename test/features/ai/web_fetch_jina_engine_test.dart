import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test(
    'WebFetch settings expose Jina Reader after Scrapling but not as fallback',
    () {
      final settings = AiWebFetchSettings.defaults();
      final kinds = settings.engines.map((config) => config.kind).toList();

      expect(kinds, contains(AiWebFetchEngineKind.jina));
      expect(
        kinds.indexOf(AiWebFetchEngineKind.jina),
        kinds.indexOf(AiWebFetchEngineKind.scrapling) + 1,
      );
      expect(
        settings.engines[kinds.indexOf(AiWebFetchEngineKind.jina)].enabled,
        isFalse,
      );
      expect(AiWebFetchEngineKind.jina.requiresApiKey, isFalse);
      expect(AiWebFetchEngineKind.jina.isFallback, isFalse);
    },
  );

  test('Jina Reader fetches markdown through r.jina.ai path form', () async {
    late Uri requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        'Title: Example Docs\n\nMarkdown Content',
        200,
        headers: const {'content-type': 'text/plain; charset=utf-8'},
        request: request,
      );
    });
    final engine = buildScrapeEngine(
      config: const AiWebFetchEngineConfig(
        kind: AiWebFetchEngineKind.jina,
        enabled: true,
      ),
      httpClient: client,
      scraplingSettings: const AiWebFetchScraplingSettings(),
    );

    expect(engine, isA<WebFetchJinaReaderEngine>());

    final result = await engine!.run(
      const WebFetchEngineRequest(
        url: 'https://example.com/docs?q=hello',
        prompt: 'summarize',
        maxChars: 10000,
      ),
    );

    expect(
      requestedUri.toString(),
      'https://r.jina.ai/example.com/docs?q=hello',
    );
    expect(result.isSuccess, isTrue);
    expect(result.contents.single.title, 'Example Docs');
    expect(result.contents.single.content, contains('Markdown Content'));
  });
}
