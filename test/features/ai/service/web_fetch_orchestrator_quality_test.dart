import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_web_fetch_settings.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_engine.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_orchestrator.dart';

void main() {
  late http.Client client;

  setUp(() {
    client = http.Client();
  });

  tearDown(() {
    client.close();
  });

  group('WebFetchOrchestrator result quality', () {
    test(
      'prefers exact native fetch over longer off-target search content',
      () {
        final orchestrator = _orchestrator(client);

        final winner = orchestrator.pickWinnerForTesting(
          requestedUrl: 'https://example.com/docs?id=1',
          results: <WebFetchEngineResult>[
            WebFetchEngineResult(
              kind: AiWebFetchEngineKind.firecrawl,
              contents: <WebFetchEngineContent>[
                WebFetchEngineContent(
                  url: 'https://example.com/docs?id=1',
                  title: 'Exact doc',
                  content: 'Exact page content. ' * 40,
                  statusCode: 200,
                ),
              ],
            ),
            WebFetchEngineResult(
              kind: AiWebFetchEngineKind.linkup,
              contents: <WebFetchEngineContent>[
                WebFetchEngineContent(
                  url: 'https://other.example.net/search-result',
                  title: 'Long off-target result',
                  content: 'Off target content. ' * 3000,
                ),
              ],
            ),
          ],
          configs: const <AiWebFetchEngineKind, AiWebFetchEngineConfig>{
            AiWebFetchEngineKind.firecrawl: AiWebFetchEngineConfig(
              kind: AiWebFetchEngineKind.firecrawl,
              weight: 80,
            ),
            AiWebFetchEngineKind.linkup: AiWebFetchEngineConfig(
              kind: AiWebFetchEngineKind.linkup,
              weight: 100,
            ),
          },
        );

        expect(winner?.kind, AiWebFetchEngineKind.firecrawl);
      },
    );
  });
}

WebFetchOrchestrator _orchestrator(http.Client client) {
  return WebFetchOrchestrator(
    settings: AiWebFetchSettings.defaults(),
    httpClient: client,
    availableModels: const [],
  );
}
