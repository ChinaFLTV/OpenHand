import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_web_search_settings.dart';
import '../web_engine/kimi_web_search_utils.dart';
import 'web_search_engine.dart';

export '../web_engine/web_engine_http_exception.dart'
    show WebEngineHttpException;

// 纯 JSON API 引擎，重试、超时和截断由基类统一处理。

/// Tavily — https://docs.tavily.com/api-reference/endpoint/search
class WebSearchTavilyEngine extends WebSearchEngine {
  WebSearchTavilyEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await sendWebEngineHttpRequest(
      'POST',
      Uri.parse('https://api.tavily.com/search'),
      headers: const {kContentTypeHeaderName: kApplicationJsonMimeType},
      body: jsonEncode({
        'api_key': config.apiKey,
        'query': req.query,
        'max_results': req.maxResults,
        'include_answer': false,
        'include_raw_content': false,
        'search_depth': 'advanced',
      }),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Tavily',
    );
    final results = (body['results'] as List?) ?? const [];
    return results
        .whereType<Map>()
        .map((r) {
          return WebSearchEngineHit(
            title: stringOf(r['title']),
            url: stringOf(r['url']),
            snippet: stringOf(r['content']),
            score: webSearchScoreFromValue(r['score']),
            source: 'tavily',
          );
        })
        .toList(growable: false);
  }
}

/// Exa — https://docs.exa.ai/reference/search
class WebSearchExaEngine extends WebSearchEngine {
  WebSearchExaEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await sendWebEngineHttpRequest(
      'POST',
      Uri.parse('https://api.exa.ai/search'),
      headers: {
        kContentTypeHeaderName: kApplicationJsonMimeType,
        'x-api-key': config.apiKey ?? '',
      },
      body: jsonEncode({
        'query': req.query,
        'numResults': req.maxResults,
        'type': 'auto',
        'contents': {
          'text': {'maxCharacters': 1500},
        },
      }),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Exa',
    );
    final results = (body['results'] as List?) ?? const [];
    return results
        .whereType<Map>()
        .map((r) {
          final text = readJsonPath<String>(r, ['text']) ?? '';
          return WebSearchEngineHit(
            title: stringOf(r['title']),
            url: stringOf(r['url']),
            snippet: text.isEmpty ? stringOf(r['snippet']) : text,
            score: webSearchScoreFromValue(r['score']),
            publishedAt: dateTimeFromValue(r['publishedDate']),
            source: 'exa',
          );
        })
        .toList(growable: false);
  }
}

/// Linkup — https://docs.linkup.so/pages/api-reference/endpoint/post-search
class WebSearchLinkupEngine extends WebSearchEngine {
  WebSearchLinkupEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await sendWebEngineHttpRequest(
      'POST',
      Uri.parse('https://api.linkup.so/v1/search'),
      headers: {
        kAuthorizationHeaderName: 'Bearer ${config.apiKey}',
        kContentTypeHeaderName: kApplicationJsonMimeType,
      },
      body: jsonEncode({
        'q': req.query,
        'depth': 'standard',
        'outputType': 'searchResults',
      }),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Linkup',
    );
    final results = (body['results'] as List?) ?? const [];
    return results
        .whereType<Map>()
        .take(req.maxResults)
        .map((r) {
          return WebSearchEngineHit(
            title: stringOf(r['name']),
            url: stringOf(r['url']),
            snippet: stringOf(r['content']),
            source: 'linkup',
          );
        })
        .toList(growable: false);
  }
}

/// 博查 Bocha — https://docs.bochaai.com
class WebSearchBochaEngine extends WebSearchEngine {
  WebSearchBochaEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await sendWebEngineHttpRequest(
      'POST',
      Uri.parse('https://api.bochaai.com/v1/web-search'),
      headers: {
        kAuthorizationHeaderName: 'Bearer ${config.apiKey}',
        kContentTypeHeaderName: kApplicationJsonMimeType,
      },
      body: jsonEncode({
        'query': req.query,
        'count': req.maxResults,
        'summary': true,
      }),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Bocha',
    );
    final pages =
        readJsonPath<List>(body, ['data', 'webPages', 'value']) ?? const [];
    return pages
        .whereType<Map>()
        .map((r) {
          return WebSearchEngineHit(
            title: stringOf(r['name']),
            url: stringOf(r['url']),
            snippet: stringOf(r['summary']).isEmpty
                ? stringOf(r['snippet'])
                : stringOf(r['summary']),
            publishedAt: dateTimeFromValue(r['datePublished']),
            source: 'bocha',
          );
        })
        .toList(growable: false);
  }
}

/// 百度 AI 搜索 — Qianfan ai_search 接口
class WebSearchBaiduEngine extends WebSearchEngine {
  WebSearchBaiduEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await sendWebEngineHttpRequest(
      'POST',
      Uri.parse('https://qianfan.baidubce.com/v2/ai_search'),
      headers: {
        kAuthorizationHeaderName: 'Bearer ${config.apiKey}',
        kContentTypeHeaderName: kApplicationJsonMimeType,
      },
      body: jsonEncode({
        'messages': [
          {'content': req.query, 'role': 'user'},
        ],
        'search_source': 'baidu_search_v2',
        'resource_type_filter': [
          {'type': 'web', 'top_k': req.maxResults},
        ],
      }),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Baidu',
    );
    final references = readJsonPath<List>(body, ['references']) ?? const [];
    return references
        .whereType<Map>()
        .map((r) {
          return WebSearchEngineHit(
            title: stringOf(r['title']),
            url: stringOf(r['url']),
            snippet: stringOf(r['content']),
            publishedAt: dateTimeFromValue(r['date']),
            source: 'baidu',
          );
        })
        .toList(growable: false);
  }
}

/// Kimi 通过 Chat Completions 的内置网页搜索工具返回引用列表。
class WebSearchKimiEngine extends WebSearchProviderKeyEngine {
  WebSearchKimiEngine({
    required super.config,
    required super.httpClient,
    required super.fallbackKey,
  });

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await sendWebEngineHttpRequest(
      'POST',
      Uri.parse(kimiWebSearchEndpoint),
      headers: {
        kAuthorizationHeaderName: 'Bearer $effectiveApiKey',
        kContentTypeHeaderName: kApplicationJsonMimeType,
      },
      body: buildKimiWebSearchRequestBody(req.query),
      cancelSignal: req.cancelSignal,
    );
    final body = decodeSuccessfulWebEngineJsonResponse(
      response,
      engineLabel: 'Kimi',
    );
    final references =
        readJsonPath<List>(body, ['choices', 0, 'message', 'references']) ??
        const [];
    return references
        .whereType<Map>()
        .take(req.maxResults)
        .map(
          (r) => WebSearchEngineHit(
            title: stringOf(r['title']),
            url: stringOf(r['url']),
            snippet: stringOf(r['content']).isEmpty
                ? stringOf(r['snippet'])
                : stringOf(r['content']),
            source: 'kimi',
          ),
        )
        .toList(growable: false);
  }
}

/// 工厂：根据 [AiWebSearchEngineKind] 构造对应的 WebSearchEngine。
WebSearchEngine? buildApiEngine({
  required AiWebSearchEngineConfig config,
  required http.Client httpClient,
  required String? Function(String? configId) providerKeyResolver,
}) {
  switch (config.kind) {
    case AiWebSearchEngineKind.tavily:
      return WebSearchTavilyEngine(config: config, httpClient: httpClient);
    case AiWebSearchEngineKind.exa:
      return WebSearchExaEngine(config: config, httpClient: httpClient);
    case AiWebSearchEngineKind.linkup:
      return WebSearchLinkupEngine(config: config, httpClient: httpClient);
    case AiWebSearchEngineKind.bocha:
      return WebSearchBochaEngine(config: config, httpClient: httpClient);
    case AiWebSearchEngineKind.baidu:
      return WebSearchBaiduEngine(config: config, httpClient: httpClient);
    case AiWebSearchEngineKind.kimi:
      return WebSearchKimiEngine(
        config: config,
        httpClient: httpClient,
        fallbackKey: providerKeyResolver(config.providerConfigId),
      );
    default:
      return null;
  }
}
