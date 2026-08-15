import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../web_engine/web_engine_http_utils.dart';
import 'web_fetch_engine.dart';
import 'web_fetch_scrapling_bridge.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 真正的「URL → 全文」抓取引擎：firecrawl、tavily-extract、exa-contents。
// 每个引擎只重写 fetch()；运行/重试/超时/截断由基类 [WebFetchEngine.run]
// 统一处理。
// ─────────────────────────────────────────────────────────────────────────────

/// Firecrawl /v1/scrape — https://docs.firecrawl.dev/api-reference/endpoint/scrape
class WebFetchFirecrawlEngine extends WebFetchEngine {
  WebFetchFirecrawlEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => nullIfBlank(config.apiKey) != null;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final base = nullIfBlank(config.endpointOverride);
    final endpoint = base == null
        ? 'https://api.firecrawl.dev/v1/scrape'
        : '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}'
              '/v1/scrape';
    final request = http.Request('POST', Uri.parse(endpoint))
      ..headers.addAll({
        'authorization': 'Bearer ${config.apiKey}',
        kContentTypeHeaderName: kApplicationJsonMimeType,
      })
      ..body = jsonEncode({
        'url': req.url,
        'formats': ['markdown'],
        'onlyMainContent': true,
        'timeout': 25000,
      });
    final response = await sendBoundedWebEngineRequest(
      client: httpClient,
      request: request,
      connectionTimeout: Duration(seconds: config.connectionTimeoutSeconds),
      responseTimeout: Duration(seconds: config.responseTimeoutSeconds),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Firecrawl',
    );
    final data = jsonObjectOf(body['data']);
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
        contentType: kTextMarkdownMimeType,
        statusCode: 200,
      ),
    ];
  }
}

/// Tavily /extract — https://docs.tavily.com/api-reference/endpoint/extract
class WebFetchScraplingEngine extends WebFetchEngine {
  WebFetchScraplingEngine({
    required super.config,
    required super.httpClient,
    required this.scraplingBridge,
    required this.scraplingSettings,
  });

  final WebFetchScraplingBridge scraplingBridge;
  final AiWebFetchScraplingSettings scraplingSettings;

  @override
  bool get isReady => true;

  @override
  Duration get fetchTimeout =>
      Duration(seconds: scraplingSettings.requestTimeoutSeconds + 5);

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final result = await scraplingBridge.fetch(
      url: req.url,
      maxChars: req.maxChars,
      settings: scraplingSettings,
      cancelSignal: req.cancelSignal,
    );
    if (nullIfBlank(result.content) == null) {
      return const <WebFetchEngineContent>[];
    }
    final title = nullIfBlank(result.title) ?? req.url;
    return [
      WebFetchEngineContent(
        url: result.url,
        title: title,
        content: result.content,
        contentType: result.contentType,
        statusCode: result.statusCode,
        responseHeaders: result.responseHeaders,
      ),
    ];
  }
}

class WebFetchJinaReaderEngine extends WebFetchEngine {
  WebFetchJinaReaderEngine({required super.config, required super.httpClient});

  static const String _readerHost = 'r.jina.ai';

  @override
  bool get isReady => true;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final targetUri = _normalizeTargetUri(req.url);
    final readerUri = Uri.parse(
      'https://$_readerHost/${_readerPath(targetUri)}',
    );
    final request = http.Request('GET', readerUri)
      ..headers.addAll(const {
        'accept': 'text/markdown,text/plain,*/*;q=0.8',
        'user-agent': 'OpenHand-WebFetch/1.0',
      });
    final response = await sendBoundedWebEngineRequest(
      client: httpClient,
      request: request,
      connectionTimeout: Duration(seconds: config.connectionTimeoutSeconds),
      responseTimeout: Duration(seconds: config.responseTimeoutSeconds),
      cancelSignal: req.cancelSignal,
    );
    final status = response.statusCode;
    if (status < 200 || status >= 400) {
      throw WebEngineHttpException('Jina Reader HTTP $status');
    }
    final content = response.text().trim();
    if (nullIfBlank(content) == null) {
      return const <WebFetchEngineContent>[];
    }
    return [
      WebFetchEngineContent(
        url: req.url,
        title: _extractReaderTitle(content) ?? targetUri.toString(),
        content: content,
        contentType: response.headers[kContentTypeHeaderName] ?? kTextMarkdownMimeType,
        statusCode: status,
        responseHeaders: Map<String, String>.from(response.headers),
      ),
    ];
  }

  Uri _normalizeTargetUri(String rawUrl) {
    final trimmed = nullIfBlank(rawUrl) ?? '';
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.parse(withScheme);
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') ||
        nullIfBlank(uri.host) == null) {
      throw WebEngineHttpException('Jina Reader invalid URL: $rawUrl');
    }
    return uri;
  }

  String _readerPath(Uri uri) {
    final host = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    final path = uri.path.isEmpty ? '' : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '$host$path$query';
  }

  String? _extractReaderTitle(String content) {
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('Title:')) {
        final title = nullIfBlank(trimmed.substring('Title:'.length));
        if (title != null) return title;
      }
      if (trimmed.startsWith('# ')) {
        final title = nullIfBlank(trimmed.substring(2));
        if (title != null) return title;
      }
      if (nullIfBlank(trimmed) != null) break;
    }
    return null;
  }
}

class WebFetchTavilyEngine extends WebFetchEngine {
  WebFetchTavilyEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final request =
        http.Request('POST', Uri.parse('https://api.tavily.com/extract'))
          ..headers[kContentTypeHeaderName] = kApplicationJsonMimeType
          ..body = jsonEncode({
            'api_key': config.apiKey,
            'urls': [req.url],
            'extract_depth': 'advanced',
          });
    final response = await sendBoundedWebEngineRequest(
      client: httpClient,
      request: request,
      connectionTimeout: Duration(seconds: config.connectionTimeoutSeconds),
      responseTimeout: Duration(seconds: config.responseTimeoutSeconds),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Tavily-extract',
      source: 'Tavily extract response',
    );
    final results = (body['results'] as List?) ?? const [];
    return results
        .whereType<Map>()
        .map((r) {
          final raw = stringOf(r['raw_content']);
          return WebFetchEngineContent(
            url: stringOf(r['url']).isEmpty ? req.url : stringOf(r['url']),
            title: req.url,
            content: raw,
          );
        })
        .where((c) => c.content.isNotEmpty)
        .toList(growable: false);
  }
}

/// Exa /contents — https://docs.exa.ai/reference/get-contents
class WebFetchExaEngine extends WebFetchEngine {
  WebFetchExaEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final request =
        http.Request('POST', Uri.parse('https://api.exa.ai/contents'))
          ..headers.addAll({
            kContentTypeHeaderName: kApplicationJsonMimeType,
            'x-api-key': config.apiKey ?? '',
          })
          ..body = jsonEncode({
            'urls': [req.url],
            'text': {'maxCharacters': req.maxChars, 'includeHtmlTags': false},
            'livecrawl': 'always',
          });
    final response = await sendBoundedWebEngineRequest(
      client: httpClient,
      request: request,
      connectionTimeout: Duration(seconds: config.connectionTimeoutSeconds),
      responseTimeout: Duration(seconds: config.responseTimeoutSeconds),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Exa-contents',
      source: 'Exa contents response',
    );
    final results = (body['results'] as List?) ?? const [];
    return results
        .whereType<Map>()
        .map((r) {
          final text = stringOf(r['text']);
          return WebFetchEngineContent(
            url: stringOf(r['url']).isEmpty ? req.url : stringOf(r['url']),
            title: stringOf(r['title']),
            content: text,
            publishedAt: dateTimeFromValue(r['publishedDate']),
          );
        })
        .where((c) => c.content.isNotEmpty)
        .toList(growable: false);
  }
}

WebFetchEngine? buildScrapeEngine({
  required AiWebFetchEngineConfig config,
  required http.Client httpClient,
  required AiWebFetchScraplingSettings scraplingSettings,
  WebFetchScraplingBridge? scraplingBridge,
}) {
  switch (config.kind) {
    case AiWebFetchEngineKind.firecrawl:
      return WebFetchFirecrawlEngine(config: config, httpClient: httpClient);
    case AiWebFetchEngineKind.scrapling:
      if (scraplingBridge == null) return null;
      return WebFetchScraplingEngine(
        config: config,
        httpClient: httpClient,
        scraplingBridge: scraplingBridge,
        scraplingSettings: scraplingSettings,
      );
    case AiWebFetchEngineKind.jina:
      return WebFetchJinaReaderEngine(config: config, httpClient: httpClient);
    case AiWebFetchEngineKind.tavily:
      return WebFetchTavilyEngine(config: config, httpClient: httpClient);
    case AiWebFetchEngineKind.exa:
      return WebFetchExaEngine(config: config, httpClient: httpClient);
    default:
      return null;
  }
}
