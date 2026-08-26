import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../../shared/util/text_clip.dart';
import '../../model/ai_web_search_settings.dart';
import '../web_engine/web_engine_http_utils.dart';
import 'web_search_engine.dart';

// Provider 复用型引擎：grok（xAI Live Search）、gemini（Google Grounding）。
// 它们的 web search 能力是协议自带，没有独立的 search endpoint。
// 这里直接打 chat 接口，开启 search_parameters / tools.googleSearch，
// 然后从 citations / groundingChunks 抽取命中结果。

class WebSearchGrokEngine extends WebSearchProviderKeyEngine {
  WebSearchGrokEngine({
    required super.config,
    required super.httpClient,
    required super.fallbackKey,
  });

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final body = await requestGrokLiveSearch(
      apiKey: effectiveApiKey,
      systemPrompt:
          'You are a search engine. Reply ONLY with raw search results '
          'citations.',
      userPrompt: req.query,
      maxSearchResults: req.maxResults,
      cancelSignal: req.cancelSignal,
    );
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
    if (idx < 0) {
      return clipTextByCodeUnits(reply, maxLen, suffix: '');
    }
    final start = safeUtf16SuffixStart(
      reply,
      (idx - 200).clamp(0, reply.length),
    );
    final end = safeUtf16PrefixCodeUnits(
      reply,
      (idx + 400).clamp(0, reply.length),
    );
    return reply.substring(start, end);
  }
}

class WebSearchGeminiEngine extends WebSearchProviderKeyEngine {
  WebSearchGeminiEngine({
    required super.config,
    required super.httpClient,
    required super.fallbackKey,
  });

  @override
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest req) async {
    final body = await requestGeminiGroundedContent(
      apiKey: effectiveApiKey,
      prompt: req.query,
      cancelSignal: req.cancelSignal,
    );
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
