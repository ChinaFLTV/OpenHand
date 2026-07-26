import 'package:http/http.dart' as http;

import '../../../../shared/util/text_clip.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_web_search_settings.dart';
import '../web_engine/web_engine_base.dart';
import '../web_engine/web_engine_http_utils.dart';
import '../web_engine/web_engine_value_parsing.dart';

export '../web_engine/web_engine_base.dart' show WebEngineRequest;
export '../web_engine/web_engine_http_utils.dart'
    show decodeSuccessfulWebEngineJsonResponse;
export '../web_engine/web_engine_json_utils.dart'
    show decodeJsonObjectBytes, jsonObjectOf, readJsonPath, stringOf;
export '../web_engine/web_engine_value_parsing.dart'
    show resolveWebEngineApiKey;

/// 单条搜索命中结果（统一抽象）。
class WebSearchEngineHit {
  WebSearchEngineHit({
    required this.title,
    required this.url,
    required this.snippet,
    this.publishedAt,
    this.source,
    this.score,
    this.rawContent,
  });

  final String title;
  final String url;
  final String snippet;
  final DateTime? publishedAt;
  final String? source;
  final double? score;
  final String? rawContent;

  WebSearchEngineHit truncated(int maxChars) {
    if (maxChars <= 0) return this;
    return WebSearchEngineHit(
      title: clipTextWithEllipsis(title, 240),
      url: url,
      snippet: clipTextWithEllipsis(snippet, maxChars),
      publishedAt: publishedAt,
      source: source,
      score: score,
      rawContent: rawContent == null
          ? null
          : clipTextWithEllipsis(rawContent!, maxChars),
    );
  }
}

double? webSearchScoreFromValue(Object? value) {
  return webEngineScoreFromValue(value);
}

/// 调用引擎所需的请求信息（query + 过滤）。
class WebSearchEngineRequest extends WebEngineRequest {
  const WebSearchEngineRequest({
    required this.query,
    required this.maxResults,
    this.allowedDomains = const <String>[],
    this.blockedDomains = const <String>[],
    super.cancelSignal,
  });

  final String query;
  final int maxResults;
  final List<String> allowedDomains;
  final List<String> blockedDomains;
}

/// 引擎执行结果包装：含命中数组 + 错误信息（若有）。
class WebSearchEngineResult {
  const WebSearchEngineResult({
    required this.kind,
    required this.hits,
    this.error,
    this.attempts = 1,
    this.elapsedMs = 0,
  });

  final AiWebSearchEngineKind kind;
  final List<WebSearchEngineHit> hits;
  final String? error;
  final int attempts;
  final int elapsedMs;

  bool get isSuccess => error == null && hits.isNotEmpty;
  bool get isEmpty => hits.isEmpty;
}

/// 抽象引擎：retry/backoff/cancel/timeout 委托给 [WebEngineBase]，子类只需实现
/// [fetch] + [isReady]，并通过 [postProcess] 统一做 allow/block 过滤、截断、take。
abstract class WebSearchEngine
    extends
        WebEngineBase<
          AiWebSearchEngineKind,
          WebSearchEngineHit,
          WebSearchEngineRequest,
          WebSearchEngineResult
        >
    with BoundedWebEngineHttpClient {
  WebSearchEngine({required this.config, required this.httpClient});

  final AiWebSearchEngineConfig config;
  @override
  final http.Client httpClient;

  @override
  AiWebSearchEngineKind get kind => config.kind;

  @override
  int get maxRetries => config.maxRetries;

  @override
  Duration get fetchTimeout => const Duration(seconds: 25);

  @override
  WebSearchEngineResult buildResult({
    required List<WebSearchEngineHit> items,
    String? error,
    required int attempts,
    required int elapsedMs,
  }) {
    return WebSearchEngineResult(
      kind: kind,
      hits: items,
      error: error,
      attempts: attempts,
      elapsedMs: elapsedMs,
    );
  }

  @override
  List<WebSearchEngineHit> postProcess(
    List<WebSearchEngineHit> raw,
    WebSearchEngineRequest request,
  ) {
    final filtered = _applyFilters(
      raw,
      allowed: request.allowedDomains,
      blocked: request.blockedDomains,
    );
    return filtered
        .map((h) => h.truncated(config.truncationChars))
        .take(request.maxResults)
        .toList(growable: false);
  }

  static List<WebSearchEngineHit> _applyFilters(
    List<WebSearchEngineHit> hits, {
    required List<String> allowed,
    required List<String> blocked,
  }) {
    if (allowed.isEmpty && blocked.isEmpty) return hits;
    return hits
        .where((hit) {
          final host = Uri.tryParse(hit.url)?.host.toLowerCase() ?? '';
          if (allowed.isNotEmpty &&
              !allowed.any((d) => host == d || host.endsWith('.$d'))) {
            return false;
          }
          if (blocked.any((d) => host == d || host.endsWith('.$d'))) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }
}

abstract class WebSearchProviderKeyEngine extends WebSearchEngine {
  WebSearchProviderKeyEngine({
    required super.config,
    required super.httpClient,
    required this.fallbackKey,
  });

  final String? fallbackKey;

  String? get effectiveApiKey =>
      resolveWebEngineApiKey(config.apiKey, fallbackKey);

  @override
  bool get isReady => (effectiveApiKey ?? '').isNotEmpty;
}

/// 引擎构造上下文：提供共享 http、provider 列表（用于复用 key）。
class WebSearchEngineContext {
  WebSearchEngineContext({
    required this.httpClient,
    required this.availableModels,
  });

  final http.Client httpClient;
  final List<AiModelConfig> availableModels;

  /// 解析复用 provider 的 API key（仅 kimi/grok/gemini）。
  String? resolveProviderApiKey(String? configId) =>
      resolveWebEngineProviderApiKey(availableModels, configId);
}
