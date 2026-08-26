import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../web_engine/kimi_web_search_utils.dart';
import '../web_engine/web_engine_http_utils.dart';
import 'web_fetch_engine.dart';

// 把 URL 当 query 推给搜索引擎，挑最相关 hit 取其 content/snippet 作为 fetch
// 内容。覆盖：kimi / baidu / linkup / bocha / grok / gemini。

class WebFetchKimiEngine extends WebFetchProviderKeyEngine {
  WebFetchKimiEngine({
    required super.config,
    required super.httpClient,
    required super.fallbackKey,
  });

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final response = await sendWebEngineHttpRequest(
      'POST',
      Uri.parse(kimiWebSearchEndpoint),
      headers: {
        kAuthorizationHeaderName: 'Bearer $effectiveApiKey',
        kContentTypeHeaderName: kApplicationJsonMimeType,
      },
      body: buildKimiWebSearchRequestBody(
        '请抓取 ${req.url} 的核心内容并原样返回（保留章节、列表、代码块）。',
      ),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Kimi',
    );
    final references =
        readJsonPath<List>(body, ['choices', 0, 'message', 'references']) ??
        const [];
    final reply =
        readJsonPath<String>(body, ['choices', 0, 'message', 'content']) ?? '';
    final hit = _firstUrlMatchOrFirstMap(references, req.url);
    final content = hit == null
        ? reply
        : (stringOf(hit['content']).isEmpty
              ? stringOf(hit['snippet'])
              : stringOf(hit['content']));
    if (content.isEmpty) return const <WebFetchEngineContent>[];
    return [
      WebFetchEngineContent(
        url: req.url,
        title: hit == null || stringOf(hit['title']).isEmpty
            ? req.url
            : stringOf(hit['title']),
        content: content,
      ),
    ];
  }
}

class WebFetchBaiduEngine extends WebFetchEngine {
  WebFetchBaiduEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final response = await sendWebEngineHttpRequest(
      'POST',
      Uri.parse('https://qianfan.baidubce.com/v2/ai_search'),
      headers: {
        kAuthorizationHeaderName: 'Bearer ${config.apiKey}',
        kContentTypeHeaderName: kApplicationJsonMimeType,
      },
      body: jsonEncode({
        'messages': [
          {'content': req.url, 'role': 'user'},
        ],
        'search_source': 'baidu_search_v2',
        'resource_type_filter': [
          {'type': 'web', 'top_k': 3},
        ],
      }),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Baidu',
    );
    final references = readJsonPath<List>(body, ['references']) ?? const [];
    final hit = _firstUrlMatchOrFirstMap(references, req.url);
    if (hit == null) return const <WebFetchEngineContent>[];
    final content = stringOf(hit['content']);
    if (content.isEmpty) return const <WebFetchEngineContent>[];
    return [
      WebFetchEngineContent(
        url: req.url,
        title: stringOf(hit['title']).isEmpty
            ? req.url
            : stringOf(hit['title']),
        content: content,
        publishedAt: dateTimeFromValue(hit['date']),
      ),
    ];
  }
}

class WebFetchLinkupEngine extends WebFetchEngine {
  WebFetchLinkupEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final response = await sendWebEngineHttpRequest(
      'POST',
      Uri.parse('https://api.linkup.so/v1/search'),
      headers: {
        kAuthorizationHeaderName: 'Bearer ${config.apiKey}',
        kContentTypeHeaderName: kApplicationJsonMimeType,
      },
      body: jsonEncode({
        'q': req.url,
        'depth': 'deep',
        'outputType': 'searchResults',
        'includeImages': false,
      }),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Linkup',
    );
    final results = (body['results'] as List?) ?? const [];
    final hit = _firstUrlMatchOrFirstMap(results, req.url);
    if (hit == null) return const <WebFetchEngineContent>[];
    final content = stringOf(hit['content']);
    if (content.isEmpty) return const <WebFetchEngineContent>[];
    return [
      WebFetchEngineContent(
        url: req.url,
        title: stringOf(hit['name']).isEmpty ? req.url : stringOf(hit['name']),
        content: content,
      ),
    ];
  }
}

class WebFetchBochaEngine extends WebFetchEngine {
  WebFetchBochaEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final response = await sendWebEngineHttpRequest(
      'POST',
      Uri.parse('https://api.bochaai.com/v1/web-search'),
      headers: {
        kAuthorizationHeaderName: 'Bearer ${config.apiKey}',
        kContentTypeHeaderName: kApplicationJsonMimeType,
      },
      body: jsonEncode({'query': req.url, 'count': 5, 'summary': true}),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Bocha',
    );
    final pages =
        readJsonPath<List>(body, ['data', 'webPages', 'value']) ?? const [];
    final hit = _firstUrlMatchOrFirstMap(pages, req.url);
    if (hit == null) return const <WebFetchEngineContent>[];
    final content = stringOf(hit['summary']).isEmpty
        ? stringOf(hit['snippet'])
        : stringOf(hit['summary']);
    if (content.isEmpty) return const <WebFetchEngineContent>[];
    return [
      WebFetchEngineContent(
        url: req.url,
        title: stringOf(hit['name']).isEmpty ? req.url : stringOf(hit['name']),
        content: content,
        publishedAt: dateTimeFromValue(hit['datePublished']),
      ),
    ];
  }
}

/// 以 URL 为查询走 Grok 时保留的候选结果条数：只需要命中目标页，多取无益。
const int _kGrokFetchSearchResults = 3;

class WebFetchGrokEngine extends WebFetchProviderKeyEngine {
  WebFetchGrokEngine({
    required super.config,
    required super.httpClient,
    required super.fallbackKey,
  });

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final body = await requestGrokLiveSearch(
      apiKey: effectiveApiKey,
      systemPrompt: 'You are a webpage extractor. Reply with the page content.',
      userPrompt: 'Fetch and return the main content of: ${req.url}',
      maxSearchResults: _kGrokFetchSearchResults,
      cancelSignal: req.cancelSignal,
    );
    final reply =
        readJsonPath<String>(body, ['choices', 0, 'message', 'content']) ?? '';
    if (reply.isEmpty) return const <WebFetchEngineContent>[];
    return [
      WebFetchEngineContent(url: req.url, title: req.url, content: reply),
    ];
  }
}

class WebFetchGeminiEngine extends WebFetchProviderKeyEngine {
  WebFetchGeminiEngine({
    required super.config,
    required super.httpClient,
    required super.fallbackKey,
  });

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final body = await requestGeminiGroundedContent(
      apiKey: effectiveApiKey,
      prompt: '抓取并返回该网址的正文内容（保留结构）：${req.url}',
      cancelSignal: req.cancelSignal,
    );
    final parts =
        readJsonPath<List>(body, ['candidates', 0, 'content', 'parts']) ??
        const [];
    final buf = StringBuffer();
    for (final p in parts.whereType<Map>()) {
      final t = stringOf(p['text']);
      if (t.isNotEmpty) {
        if (buf.isNotEmpty) buf.write('\n\n');
        buf.write(t);
      }
    }
    final content = buf.toString();
    if (content.isEmpty) return const <WebFetchEngineContent>[];
    return [
      WebFetchEngineContent(url: req.url, title: req.url, content: content),
    ];
  }
}

Map<Object?, Object?>? _firstUrlMatchOrFirstMap(
  List<Object?> values,
  String url,
) {
  Map<Object?, Object?>? first;
  for (final value in values) {
    if (value is! Map) continue;
    first ??= value;
    if (stringOf(value['url']) == url) return value;
  }
  return first;
}

WebFetchEngine? buildSearchAsFetchEngine({
  required AiWebFetchEngineConfig config,
  required http.Client httpClient,
  required String? Function(String? configId) providerKeyResolver,
}) {
  switch (config.kind) {
    case AiWebFetchEngineKind.kimi:
      return WebFetchKimiEngine(
        config: config,
        httpClient: httpClient,
        fallbackKey: providerKeyResolver(config.providerConfigId),
      );
    case AiWebFetchEngineKind.baidu:
      return WebFetchBaiduEngine(config: config, httpClient: httpClient);
    case AiWebFetchEngineKind.linkup:
      return WebFetchLinkupEngine(config: config, httpClient: httpClient);
    case AiWebFetchEngineKind.bocha:
      return WebFetchBochaEngine(config: config, httpClient: httpClient);
    case AiWebFetchEngineKind.grok:
      return WebFetchGrokEngine(
        config: config,
        httpClient: httpClient,
        fallbackKey: providerKeyResolver(config.providerConfigId),
      );
    case AiWebFetchEngineKind.gemini:
      return WebFetchGeminiEngine(
        config: config,
        httpClient: httpClient,
        fallbackKey: providerKeyResolver(config.providerConfigId),
      );
    default:
      return null;
  }
}
