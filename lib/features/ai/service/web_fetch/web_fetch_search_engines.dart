import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../model/ai_web_fetch_settings.dart';
import 'web_fetch_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 把 URL 当 query 推给搜索引擎，挑最相关 hit 取其 content/snippet 作为 fetch
// 内容。覆盖：kimi / baidu / linkup / bocha / grok / gemini。
// ─────────────────────────────────────────────────────────────────────────────

class WebFetchKimiEngine extends WebFetchEngine {
  WebFetchKimiEngine({
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
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final response = await httpClient.post(
      Uri.parse('https://api.moonshot.cn/v1/chat/completions'),
      headers: {
        'authorization': 'Bearer $_key',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': 'kimi-latest',
        'messages': [
          {
            'role': 'user',
            'content': '请抓取 ${req.url} 的核心内容并原样返回（保留章节、列表、代码块）。',
          },
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
      throw WebEngineHttpException(
        'Kimi ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final references =
        readJsonPath<List>(body, ['choices', 0, 'message', 'references']) ??
        const [];
    final reply =
        readJsonPath<String>(body, ['choices', 0, 'message', 'content']) ?? '';
    final hit = references.whereType<Map>().firstWhere(
      (r) => stringOf(r['url']) == req.url,
      orElse: () =>
          references.whereType<Map>().isEmpty ? const {} : references.first,
    );
    final content = hit.isEmpty
        ? reply
        : (stringOf(hit['content']).isEmpty
              ? stringOf(hit['snippet'])
              : stringOf(hit['content']));
    if (content.isEmpty) return const <WebFetchEngineContent>[];
    return [
      WebFetchEngineContent(
        url: req.url,
        title: stringOf(hit['title']).isEmpty
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
    final response = await httpClient.post(
      Uri.parse('https://qianfan.baidubce.com/v2/ai_search'),
      headers: {
        'authorization': 'Bearer ${config.apiKey}',
        'content-type': 'application/json',
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
    );
    if (response.statusCode != 200) {
      throw WebEngineHttpException(
        'Baidu ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final references = readJsonPath<List>(body, ['references']) ?? const [];
    final hit = references.whereType<Map>().firstWhere(
      (r) => stringOf(r['url']) == req.url,
      orElse: () => references.whereType<Map>().isEmpty
          ? const {}
          : references.first as Map,
    );
    if (hit.isEmpty) return const <WebFetchEngineContent>[];
    final content = stringOf(hit['content']);
    if (content.isEmpty) return const <WebFetchEngineContent>[];
    return [
      WebFetchEngineContent(
        url: req.url,
        title: stringOf(hit['title']).isEmpty
            ? req.url
            : stringOf(hit['title']),
        content: content,
        publishedAt: DateTime.tryParse(stringOf(hit['date'])),
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
    final response = await httpClient.post(
      Uri.parse('https://api.linkup.so/v1/search'),
      headers: {
        'authorization': 'Bearer ${config.apiKey}',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'q': req.url,
        'depth': 'deep',
        'outputType': 'searchResults',
        'includeImages': false,
      }),
    );
    if (response.statusCode != 200) {
      throw WebEngineHttpException(
        'Linkup ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final results = (body['results'] as List?) ?? const [];
    final hit = results.whereType<Map>().firstWhere(
      (r) => stringOf(r['url']) == req.url,
      orElse: () =>
          results.whereType<Map>().isEmpty ? const {} : results.first as Map,
    );
    if (hit.isEmpty) return const <WebFetchEngineContent>[];
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
    final response = await httpClient.post(
      Uri.parse('https://api.bochaai.com/v1/web-search'),
      headers: {
        'authorization': 'Bearer ${config.apiKey}',
        'content-type': 'application/json',
      },
      body: jsonEncode({'query': req.url, 'count': 5, 'summary': true}),
    );
    if (response.statusCode != 200) {
      throw WebEngineHttpException(
        'Bocha ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final pages =
        readJsonPath<List>(body, ['data', 'webPages', 'value']) ?? const [];
    final hit = pages.whereType<Map>().firstWhere(
      (r) => stringOf(r['url']) == req.url,
      orElse: () =>
          pages.whereType<Map>().isEmpty ? const {} : pages.first as Map,
    );
    if (hit.isEmpty) return const <WebFetchEngineContent>[];
    final content = stringOf(hit['summary']).isEmpty
        ? stringOf(hit['snippet'])
        : stringOf(hit['summary']);
    if (content.isEmpty) return const <WebFetchEngineContent>[];
    return [
      WebFetchEngineContent(
        url: req.url,
        title: stringOf(hit['name']).isEmpty ? req.url : stringOf(hit['name']),
        content: content,
        publishedAt: DateTime.tryParse(stringOf(hit['datePublished'])),
      ),
    ];
  }
}

class WebFetchGrokEngine extends WebFetchEngine {
  WebFetchGrokEngine({
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
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
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
                'You are a webpage extractor. Reply with the page content.',
          },
          {
            'role': 'user',
            'content': 'Fetch and return the main content of: ${req.url}',
          },
        ],
        'search_parameters': {
          'mode': 'on',
          'max_search_results': 3,
          'return_citations': true,
        },
      }),
    );
    if (response.statusCode != 200) {
      throw WebEngineHttpException(
        'Grok ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final reply =
        readJsonPath<String>(body, ['choices', 0, 'message', 'content']) ?? '';
    if (reply.isEmpty) return const <WebFetchEngineContent>[];
    return [
      WebFetchEngineContent(url: req.url, title: req.url, content: reply),
    ];
  }
}

class WebFetchGeminiEngine extends WebFetchEngine {
  WebFetchGeminiEngine({
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
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
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
              {'text': '抓取并返回该网址的正文内容（保留结构）：${req.url}'},
            ],
          },
        ],
        'tools': [
          {'googleSearch': {}},
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw WebEngineHttpException(
        'Gemini ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
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
