import 'dart:async';

import 'package:http/http.dart' as http;

import '../../model/ai_web_search_settings.dart';
import '../../tools/ai_tool_utils.dart';
import '../web_engine/web_engine_http_exception.dart';
import 'web_search_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 无 / 弱认证的 HTML / JSON 引擎：DuckDuckGo HTML、Bing HTML、SearXNG JSON。
// 使用与既有 ai_web_search_tool.dart 兼容的 DDG HTML 抓取逻辑。
// ─────────────────────────────────────────────────────────────────────────────

class WebSearchDuckDuckGoEngine extends WebSearchEngine {
  WebSearchDuckDuckGoEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => true;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final uri = Uri.https('duckduckgo.com', '/html/', {'q': req.query});
    final response = await httpClient.get(
      uri,
      headers: const {
        'user-agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) '
            'Version/17.0 Safari/605.1.15',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebEngineHttpException('DuckDuckGo ${response.statusCode}');
    }
    final html = response.body;
    if (_isChallenge(html)) {
      throw WebEngineHttpException('DuckDuckGo anti-bot challenge');
    }
    final pattern = RegExp(
      r'<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>'
      r'[\s\S]*?<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>',
      caseSensitive: false,
    );
    final hits = <WebSearchEngineHit>[];
    for (final m in pattern.allMatches(html)) {
      final url = _resolveUrl(m.group(1) ?? '');
      final title = AiToolUtils.htmlToText(m.group(2) ?? '');
      final snippet = AiToolUtils.htmlToText(m.group(3) ?? '');
      if (url.isEmpty || title.isEmpty) continue;
      hits.add(
        WebSearchEngineHit(
          title: title,
          url: url,
          snippet: snippet,
          source: 'duckduckgo',
        ),
      );
      if (hits.length >= req.maxResults) break;
    }
    return hits;
  }

  bool _isChallenge(String html) {
    final l = html.toLowerCase();
    return l.contains('challenge-form') ||
        l.contains('anomaly.js') ||
        l.contains('bot challenge') ||
        l.contains('unusual traffic');
  }

  String _resolveUrl(String raw) {
    final clean = AiToolUtils.htmlToText(raw).trim();
    if (clean.isEmpty) return '';
    final resolved = clean.startsWith('//') ? 'https:$clean' : clean;
    final uri = Uri.tryParse(resolved);
    if (uri == null) return resolved;
    final isDdgRedirect =
        (uri.host == 'duckduckgo.com' || uri.host == 'www.duckduckgo.com') &&
        uri.path.startsWith('/l/');
    if (!isDdgRedirect) return uri.toString();
    final target = uri.queryParameters['uddg']?.trim() ?? '';
    if (target.isEmpty) return uri.toString();
    final t = target.startsWith('//') ? 'https:$target' : target;
    return Uri.tryParse(t)?.toString() ?? t;
  }
}

class WebSearchBingEngine extends WebSearchEngine {
  WebSearchBingEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => true;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final uri = Uri.https('www.bing.com', '/search', {
      'q': req.query,
      'form': 'QBLH',
    });
    final response = await httpClient.get(
      uri,
      headers: const {
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/121.0 Safari/537.36',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebEngineHttpException('Bing ${response.statusCode}');
    }
    final html = response.body;
    final hits = <WebSearchEngineHit>[];
    final pattern = RegExp(
      r'<li class="b_algo">[\s\S]*?<h2><a[^>]*href="([^"]+)"[^>]*>(.*?)</a></h2>'
      r'[\s\S]*?<p[^>]*>(.*?)</p>',
      caseSensitive: false,
    );
    for (final m in pattern.allMatches(html)) {
      final url = AiToolUtils.htmlToText(m.group(1) ?? '');
      final title = AiToolUtils.htmlToText(m.group(2) ?? '');
      final snippet = AiToolUtils.htmlToText(m.group(3) ?? '');
      if (url.isEmpty || title.isEmpty) continue;
      hits.add(
        WebSearchEngineHit(
          title: title,
          url: url,
          snippet: snippet,
          source: 'bing',
        ),
      );
      if (hits.length >= req.maxResults) break;
    }
    return hits;
  }
}

class WebSearchSearxngEngine extends WebSearchEngine {
  WebSearchSearxngEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.endpointOverride ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final base = (config.endpointOverride ?? '').trim();
    if (base.isEmpty) {
      throw WebEngineHttpException('SearXNG endpoint not configured');
    }
    final cleaned = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final uri = Uri.parse('$cleaned/search').replace(
      queryParameters: {'q': req.query, 'format': 'json', 'language': 'auto'},
    );
    final response = await httpClient.get(
      uri,
      headers: const {'user-agent': 'OpenHand/1.0 (+websearch)'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebEngineHttpException('SearXNG ${response.statusCode}');
    }
    final body = decodeJsonObjectBytes(
      response.bodyBytes,
      source: 'SearXNG response',
    );
    final results = (body['results'] as List?) ?? const [];
    return results
        .whereType<Map>()
        .take(req.maxResults)
        .map(
          (r) => WebSearchEngineHit(
            title: stringOf(r['title']),
            url: stringOf(r['url']),
            snippet: stringOf(r['content']),
            score: webSearchScoreFromValue(r['score']),
            source: 'searxng',
          ),
        )
        .toList(growable: false);
  }
}

WebSearchEngine? buildHtmlEngine({
  required AiWebSearchEngineConfig config,
  required http.Client httpClient,
}) {
  switch (config.kind) {
    case AiWebSearchEngineKind.duckduckgo:
      return WebSearchDuckDuckGoEngine(config: config, httpClient: httpClient);
    case AiWebSearchEngineKind.bing:
      return WebSearchBingEngine(config: config, httpClient: httpClient);
    case AiWebSearchEngineKind.searxng:
      return WebSearchSearxngEngine(config: config, httpClient: httpClient);
    default:
      return null;
  }
}
