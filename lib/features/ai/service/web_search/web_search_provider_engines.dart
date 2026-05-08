import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../model/ai_web_search_settings.dart';
import 'web_search_api_engines.dart' show HttpException;
import 'web_search_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Provider 复用型引擎：grok（xAI Live Search）、gemini（Google Grounding）。
// 它们的 web search 能力是协议自带，没有独立的 search endpoint。
// 这里直接打 chat 接口，开启 search_parameters / tools.googleSearch，
// 然后从 citations / groundingChunks 抽取命中结果。
// ─────────────────────────────────────────────────────────────────────────────

class WebSearchGrokEngine extends WebSearchEngine {
  WebSearchGrokEngine({
    required super.config,
    required super.httpClient,
    required this.fallbackKey,
  });

  final String? fallbackKey;

  String? get _key {
    final c = config.apiKey;
    if (c != null && c.isNotEmpty) return c;
    return fallbackKey;
  }

  @override
  bool get isReady => (_key ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await httpClient.post(
      Uri.parse('https://api.x.ai/v1/chat/completions'),
      headers: {
        'authorization': 'Bearer $_key',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': 'grok-4-latest',
        'messages': [
          {
            'role': 'system',
            'content':
                'You are a search engine. Reply ONLY with raw search results citations.',
          },
          {'role': 'user', 'content': req.query},
        ],
        'search_parameters': {
          'mode': 'on',
          'max_search_results': req.maxResults,
          'return_citations': true,
        },
      }),
    );
    if (response.statusCode != 200) {
      throw HttpException('Grok ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final citations = readJsonPath<List>(body, ['citations']) ?? const [];
    final replyText =
        readJsonPath<String>(body, ['choices', 0, 'message', 'content']) ?? '';
    final hits = <WebSearchEngineHit>[];
    for (final c in citations.whereType<String>().take(req.maxResults)) {
      hits.add(
        WebSearchEngineHit(
          title: c,
          url: c,
          snippet: _excerptForCitation(replyText, c),
          source: 'grok',
        ),
      );
    }
    return hits;
  }

  String _excerptForCitation(String reply, String citation) {
    const maxLen = 600;
    if (reply.isEmpty) return '';
    if (reply.length <= maxLen) return reply;
    final idx = reply.indexOf(citation);
    if (idx < 0) return reply.substring(0, maxLen);
    final start = (idx - 200).clamp(0, reply.length);
    final end = (idx + 400).clamp(0, reply.length);
    return reply.substring(start, end);
  }
}

class WebSearchGeminiEngine extends WebSearchEngine {
  WebSearchGeminiEngine({
    required super.config,
    required super.httpClient,
    required this.fallbackKey,
  });

  final String? fallbackKey;

  String? get _key {
    final c = config.apiKey;
    if (c != null && c.isNotEmpty) return c;
    return fallbackKey;
  }

  @override
  bool get isReady => (_key ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/'
      'models/gemini-2.0-flash:generateContent?key=$_key',
    );
    final response = await httpClient.post(
      uri,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': req.query},
            ],
          },
        ],
        'tools': [
          {'googleSearch': {}},
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw HttpException('Gemini ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final chunks =
        readJsonPath<List>(body, [
          'candidates',
          0,
          'groundingMetadata',
          'groundingChunks',
        ]) ??
        const [];
    return chunks
        .whereType<Map>()
        .take(req.maxResults)
        .map((chunk) {
          final web = chunk['web'];
          if (web is! Map) return null;
          final url = stringOf(web['uri']);
          final title = stringOf(web['title']);
          if (url.isEmpty) return null;
          return WebSearchEngineHit(
            title: title.isEmpty ? url : title,
            url: url,
            snippet: stringOf(web['snippet']),
            source: 'gemini',
          );
        })
        .whereType<WebSearchEngineHit>()
        .toList(growable: false);
  }
}

WebSearchEngine? buildProviderEngine({
  required AiWebSearchEngineConfig config,
  required http.Client httpClient,
  required String? Function(String? configId) providerKeyResolver,
}) {
  switch (config.kind) {
    case AiWebSearchEngineKind.grok:
      return WebSearchGrokEngine(
        config: config,
        httpClient: httpClient,
        fallbackKey: providerKeyResolver(config.providerConfigId),
      );
    case AiWebSearchEngineKind.gemini:
      return WebSearchGeminiEngine(
        config: config,
        httpClient: httpClient,
        fallbackKey: providerKeyResolver(config.providerConfigId),
      );
    default:
      return null;
  }
}
