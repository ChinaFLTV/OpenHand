import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('default WebFetch settings include Jina Reader', () {
    final settings = AiWebFetchSettings.defaults();

    expect(
      settings.engines.any(
        (config) => config.kind == AiWebFetchEngineKind.jina,
      ),
      isTrue,
    );
    expect(AiWebFetchEngineKind.jina.requiresApiKey, isFalse);
    expect(AiWebFetchEngineKind.jina.isFallback, isTrue);
  });

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
