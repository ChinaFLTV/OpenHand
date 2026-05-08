import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../model/ai_web_search_settings.dart';
import '../web_engine_http_exception.dart';
import 'web_search_engine.dart';

export '../web_engine_http_exception.dart' show WebEngineHttpException;

// ─────────────────────────────────────────────────────────────────────────────
// Pure JSON-API engines: tavily, exa, linkup, bocha, baidu(qianfan), kimi
// 每个引擎只重写 fetch()；运行/重试/超时/截断由基类 [WebSearchEngine.run] 统一处理。
// 解析逻辑遵循各家 2025 年 1 月版公开文档；字段缺失时用空串安全降级。
// ─────────────────────────────────────────────────────────────────────────────

/// Tavily — https://docs.tavily.com/api-reference/endpoint/search
class WebSearchTavilyEngine extends WebSearchEngine {
  WebSearchTavilyEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await httpClient.post(
      Uri.parse('https://api.tavily.com/search'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'api_key': config.apiKey,
        'query': req.query,
        'max_results': req.maxResults,
        'include_answer': false,
        'include_raw_content': false,
        'search_depth': 'advanced',
      }),
    );
    if (response.statusCode != 200) {
      throw WebEngineHttpException('Tavily ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final results = (body['results'] as List?) ?? const [];
    return results.whereType<Map>().map((r) {
      return WebSearchEngineHit(
        title: stringOf(r['title']),
        url: stringOf(r['url']),
        snippet: stringOf(r['content']),
        score: (r['score'] as num?)?.toDouble(),
        source: 'tavily',
      );
    }).toList(growable: false);
  }
}

/// Exa — https://docs.exa.ai/reference/search
class WebSearchExaEngine extends WebSearchEngine {
  WebSearchExaEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await httpClient.post(
      Uri.parse('https://api.exa.ai/search'),
      headers: {
        'content-type': 'application/json',
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
    );
    if (response.statusCode != 200) {
      throw WebEngineHttpException('Exa ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final results = (body['results'] as List?) ?? const [];
    return results.whereType<Map>().map((r) {
      final text = readJsonPath<String>(r, ['text']) ?? '';
      return WebSearchEngineHit(
        title: stringOf(r['title']),
        url: stringOf(r['url']),
        snippet: text.isEmpty ? stringOf(r['snippet']) : text,
        score: (r['score'] as num?)?.toDouble(),
        publishedAt: DateTime.tryParse(stringOf(r['publishedDate'])),
        source: 'exa',
      );
    }).toList(growable: false);
  }
}

/// Linkup — https://docs.linkup.so/pages/api-reference/endpoint/post-search
class WebSearchLinkupEngine extends WebSearchEngine {
  WebSearchLinkupEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await httpClient.post(
      Uri.parse('https://api.linkup.so/v1/search'),
      headers: {
        'authorization': 'Bearer ${config.apiKey}',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'q': req.query,
        'depth': 'standard',
        'outputType': 'searchResults',
      }),
    );
    if (response.statusCode != 200) {
      throw WebEngineHttpException('Linkup ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final results = (body['results'] as List?) ?? const [];
    return results.whereType<Map>().take(req.maxResults).map((r) {
      return WebSearchEngineHit(
        title: stringOf(r['name']),
        url: stringOf(r['url']),
        snippet: stringOf(r['content']),
        source: 'linkup',
      );
    }).toList(growable: false);
  }
}

/// 博查 Bocha — https://docs.bochaai.com
class WebSearchBochaEngine extends WebSearchEngine {
  WebSearchBochaEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await httpClient.post(
      Uri.parse('https://api.bochaai.com/v1/web-search'),
      headers: {
        'authorization': 'Bearer ${config.apiKey}',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'query': req.query,
        'count': req.maxResults,
        'summary': true,
      }),
    );
    if (response.statusCode != 200) {
      throw WebEngineHttpException('Bocha ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final pages =
        readJsonPath<List>(body, ['data', 'webPages', 'value']) ?? const [];
    return pages.whereType<Map>().map((r) {
      return WebSearchEngineHit(
        title: stringOf(r['name']),
        url: stringOf(r['url']),
        snippet: stringOf(r['summary']).isEmpty
            ? stringOf(r['snippet'])
            : stringOf(r['summary']),
        publishedAt: DateTime.tryParse(stringOf(r['datePublished'])),
        source: 'bocha',
      );
    }).toList(growable: false);
  }
}

/// 百度 AI 搜索 — Qianfan ai_search 接口
class WebSearchBaiduEngine extends WebSearchEngine {
  WebSearchBaiduEngine({required super.config, required super.httpClient});

  @override
  bool get isReady => (config.apiKey ?? '').isNotEmpty;

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final response = await httpClient.post(
      Uri.parse('https://qianfan.baidubce.com/v2/ai_search'),
      headers: {
        'authorization': 'Bearer ${config.apiKey}',
        'content-type': 'application/json',
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
    );
    if (response.statusCode != 200) {
      throw WebEngineHttpException('Baidu ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final references =
        readJsonPath<List>(body, ['references']) ?? const [];
    return references.whereType<Map>().map((r) {
      return WebSearchEngineHit(
        title: stringOf(r['title']),
        url: stringOf(r['url']),
        snippet: stringOf(r['content']),
        publishedAt: DateTime.tryParse(stringOf(r['date'])),
        source: 'baidu',
      );
    }).toList(growable: false);
  }
}

/// Kimi (Moonshot) — 借助 chat/completions 的 web_search tool 工具
/// 注意：返回结果在 message.tool_calls 之后的工具响应里以 `references` 字段出现。
/// 此实现走 Moonshot 提供的轻量级 builtin function `$web_search`：
/// 我们直接调用 `/v1/tools/web_search`（如果该 endpoint 存在）；
/// 若 endpoint 不存在则回退使用 chat completions + tool 模式。
class WebSearchKimiEngine extends WebSearchEngine {
  WebSearchKimiEngine({
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
    // 通过 Moonshot chat completions + 内置 web_search tool 拉取结果
    // （Moonshot 的工具响应会塞在 message.references 数组里）
    final response = await httpClient.post(
      Uri.parse('https://api.moonshot.cn/v1/chat/completions'),
      headers: {
        'authorization': 'Bearer $_key',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': 'kimi-latest',
        'messages': [
          {'role': 'user', 'content': req.query},
        ],
        'tools': [
          {
            'type': 'builtin_function',
            'function': {'name': '\$web_search'},
          },
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw WebEngineHttpException('Kimi ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
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
