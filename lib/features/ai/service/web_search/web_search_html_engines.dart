import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_web_search_settings.dart';
import '../../tools/ai_tool_utils.dart';
import '../web_engine/web_engine_http_exception.dart';
import '../web_engine/web_engine_http_utils.dart';
import 'web_search_engine.dart';

List<WebSearchEngineHit> _parseHtmlSearchHits({
  required String html,
  required RegExp pattern,
  required int maxResults,
  required String source,
  String Function(String url)? normalizeUrl,
}) {
  if (maxResults <= 0) return const <WebSearchEngineHit>[];
  final hits = <WebSearchEngineHit>[];
  for (final match in pattern.allMatches(html)) {
    final rawUrl = AiToolUtils.htmlToText(match.group(1) ?? '');
    final url = normalizeUrl?.call(rawUrl) ?? rawUrl;
    final title = AiToolUtils.htmlToText(match.group(2) ?? '');
    final snippet = AiToolUtils.htmlToText(match.group(3) ?? '');
    if (url.isEmpty || title.isEmpty) continue;
    hits.add(
      WebSearchEngineHit(
        title: title,
        url: url,
        snippet: snippet,
        source: source,
      ),
    );
    if (hits.length >= maxResults) break;
  }
  return hits;
}

// 无 / 弱认证的 HTML / JSON 引擎：DuckDuckGo HTML、Bing HTML、SearXNG JSON。
// 使用与既有 ai_web_search_tool.dart 兼容的 DDG HTML 抓取逻辑。

class WebSearchDuckDuckGoEngine extends WebSearchEngine {
  WebSearchDuckDuckGoEngine({required super.config, required super.httpClient});

  static final RegExp _resultPattern = RegExp(
    r'<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>'
    r'[\s\S]*?<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>',
    caseSensitive: false,
  );

  @override
  bool get isReady => true;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final uri = Uri.https('duckduckgo.com', '/html/', {'q': req.query});
    final response = await sendWebEngineHttpRequest(
      'GET',
      uri,
      headers: const {kUserAgentHeaderName: kWebEngineSafariUserAgent},
      cancelSignal: req.cancelSignal,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw WebEngineHttpException('DuckDuckGo ${response.statusCode}');
    }
    final html = response.body;
    if (_isChallenge(html)) {
      throw WebEngineHttpException('DuckDuckGo anti-bot challenge');
    }
    return _parseHtmlSearchHits(
      html: html,
      pattern: _resultPattern,
      maxResults: req.maxResults,
      source: 'duckduckgo',
      normalizeUrl: _resolveUrl,
    );
  }

  bool _isChallenge(String html) {
    final l = html.toLowerCase();
    return l.contains('challenge-form') ||
        l.contains('anomaly.js') ||
        l.contains('bot challenge') ||
        l.contains('unusual traffic');
  }

  String _resolveUrl(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return '';
    final resolved = clean.startsWith('//') ? 'https:$clean' : clean;
    final uri = Uri.tryParse(resolved);
    if (uri == null) return resolved;
    final isDdgRedirect =
        (uri.host == 'duckduckgo.com' || uri.host == 'www.duckduckgo.com') &&
        uri.path.startsWith('/l/');
    if (!isDdgRedirect) return uri.toString();
    final target = nullIfBlank(uri.queryParameters['uddg']) ?? '';
    if (target.isEmpty) return uri.toString();
    final t = target.startsWith('//') ? 'https:$target' : target;
    return Uri.tryParse(t)?.toString() ?? t;
  }
}

class WebSearchBingEngine extends WebSearchEngine {
  WebSearchBingEngine({required super.config, required super.httpClient});

  static final RegExp _resultPattern = RegExp(
    r'<li class="b_algo">[\s\S]*?<h2><a[^>]*href="([^"]+)"[^>]*>(.*?)</a></h2>'
    r'[\s\S]*?<p[^>]*>(.*?)</p>',
    caseSensitive: false,
  );

  @override
  bool get isReady => true;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final uri = Uri.https('www.bing.com', '/search', {
      'q': req.query,
      'form': 'QBLH',
    });
    final response = await sendWebEngineHttpRequest(
      'GET',
      uri,
      headers: const {kUserAgentHeaderName: kWebEngineChromeUserAgent},
      cancelSignal: req.cancelSignal,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw WebEngineHttpException('Bing ${response.statusCode}');
    }
    final html = response.body;
    return _parseHtmlSearchHits(
      html: html,
      pattern: _resultPattern,
      maxResults: req.maxResults,
      source: 'bing',
    );
  }
}

class WebSearchSearxngEngine extends WebSearchEngine {
  WebSearchSearxngEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => nullIfBlank(config.endpointOverride) != null;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final base = nullIfBlank(config.endpointOverride);
    if (base == null) {
      throw WebEngineHttpException('SearXNG endpoint not configured');
    }
    final cleaned = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final uri = Uri.parse('$cleaned/search').replace(
      queryParameters: {'q': req.query, 'format': 'json', 'language': 'auto'},
    );
    final response = await sendWebEngineHttpRequest(
      'GET',
      uri,
      headers: const {kUserAgentHeaderName: 'OpenHand/1.0 (+websearch)'},
      cancelSignal: req.cancelSignal,
    );
    if (isHttpFailureStatus(response.statusCode)) {
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
