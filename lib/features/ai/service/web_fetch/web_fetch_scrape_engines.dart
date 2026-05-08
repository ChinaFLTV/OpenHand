import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../model/ai_web_fetch_settings.dart';
import 'web_fetch_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 真正的「URL → 全文」抓取引擎：firecrawl、tavily-extract、exa-contents。
// 每个引擎只重写 fetch()；运行/重试/超时/截断由基类 [WebFetchEngine.run]
// 统一处理。
// ─────────────────────────────────────────────────────────────────────────────

/// Firecrawl /v1/scrape — https://docs.firecrawl.dev/api-reference/endpoint/scrape
class WebFetchFirecrawlEngine extends WebFetchEngine {
  WebFetchFirecrawlEngine({
    required super.config,
    required super.httpClient,
  });

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final base = (config.endpointOverride ?? '').trim();
    final endpoint = base.isEmpty
        ? 'https://api.firecrawl.dev/v1/scrape'
        : '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}'
              '/v1/scrape';
    final response = await httpClient.post(
      Uri.parse(endpoint),
      headers: {
        'authorization': 'Bearer ${config.apiKey}',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'url': req.url,
        'formats': ['markdown'],
        'onlyMainContent': true,
        'timeout': 25000,
      }),
    );
    if (response.statusCode != 200) {
      throw WebFetchHttpException(
        'Firecrawl ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final data = body['data'] is Map
        ? Map<String, Object?>.from(body['data'] as Map)
        : <String, Object?>{};
    final markdown = stringOf(data['markdown']);
    final title = stringOf(readJsonPath<String>(data, ['metadata', 'title']));
    final source = stringOf(
      readJsonPath<String>(data, ['metadata', 'sourceURL']),
    );
    if (markdown.isEmpty) {
      return const <WebFetchEngineContent>[];
    }
    return [
      WebFetchEngineContent(
        url: source.isNotEmpty ? source : req.url,
        title: title.isEmpty ? req.url : title,
        content: markdown,
        contentType: 'text/markdown',
        statusCode: 200,
      ),
    ];
  }
}

/// Tavily /extract — https://docs.tavily.com/api-reference/endpoint/extract
class WebFetchTavilyEngine extends WebFetchEngine {
  WebFetchTavilyEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final response = await httpClient.post(
      Uri.parse('https://api.tavily.com/extract'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'api_key': config.apiKey,
        'urls': [req.url],
        'extract_depth': 'advanced',
      }),
    );
    if (response.statusCode != 200) {
      throw WebFetchHttpException(
        'Tavily-extract ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final results = (body['results'] as List?) ?? const [];
    return results.whereType<Map>().map((r) {
      final raw = stringOf(r['raw_content']);
      return WebFetchEngineContent(
        url: stringOf(r['url']).isEmpty ? req.url : stringOf(r['url']),
        title: req.url,
        content: raw,
      );
    }).where((c) => c.content.isNotEmpty).toList(growable: false);
  }
}

/// Exa /contents — https://docs.exa.ai/reference/get-contents
class WebFetchExaEngine extends WebFetchEngine {
  WebFetchExaEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final response = await httpClient.post(
      Uri.parse('https://api.exa.ai/contents'),
      headers: {
        'content-type': 'application/json',
        'x-api-key': config.apiKey ?? '',
      },
      body: jsonEncode({
        'urls': [req.url],
        'text': {'maxCharacters': req.maxChars, 'includeHtmlTags': false},
        'livecrawl': 'always',
      }),
    );
    if (response.statusCode != 200) {
      throw WebFetchHttpException(
        'Exa-contents ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final results = (body['results'] as List?) ?? const [];
    return results.whereType<Map>().map((r) {
      final text = stringOf(r['text']);
      return WebFetchEngineContent(
        url: stringOf(r['url']).isEmpty ? req.url : stringOf(r['url']),
        title: stringOf(r['title']),
        content: text,
        publishedAt: DateTime.tryParse(stringOf(r['publishedDate'])),
      );
    }).where((c) => c.content.isNotEmpty).toList(growable: false);
  }
}

WebFetchEngine? buildScrapeEngine({
  required AiWebFetchEngineConfig config,
  required http.Client httpClient,
}) {
  switch (config.kind) {
    case AiWebFetchEngineKind.firecrawl:
      return WebFetchFirecrawlEngine(config: config, httpClient: httpClient);
    case AiWebFetchEngineKind.tavily:
      return WebFetchTavilyEngine(config: config, httpClient: httpClient);
    case AiWebFetchEngineKind.exa:
      return WebFetchExaEngine(config: config, httpClient: httpClient);
    default:
      return null;
  }
}
