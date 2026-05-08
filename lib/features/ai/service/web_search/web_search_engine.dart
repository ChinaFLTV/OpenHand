import 'dart:async';

import 'package:http/http.dart' as http;

import '../../model/ai_model_config.dart';
import '../../model/ai_web_search_settings.dart';

export '../web_engine_json_utils.dart'
    show stringOf, readJsonPath, maybeJsonDecode;

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
      title: _cap(title, 240),
      url: url,
      snippet: _cap(snippet, maxChars),
      publishedAt: publishedAt,
      source: source,
      score: score,
      rawContent: rawContent == null ? null : _cap(rawContent!, maxChars),
    );
  }

  static String _cap(String input, int n) =>
      input.length <= n ? input : '${input.substring(0, n)}…';
}

/// 调用引擎所需的请求信息（query + 过滤）。
class WebSearchEngineRequest {
  const WebSearchEngineRequest({
    required this.query,
    required this.maxResults,
    this.allowedDomains = const <String>[],
    this.blockedDomains = const <String>[],
    this.cancelSignal,
  });

  final String query;
  final int maxResults;
  final List<String> allowedDomains;
  final List<String> blockedDomains;
  final Future<void>? cancelSignal;
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

/// 抽象引擎接口。
abstract class WebSearchEngine {
  WebSearchEngine({required this.config, required this.httpClient});

  final AiWebSearchEngineConfig config;
  final http.Client httpClient;

  AiWebSearchEngineKind get kind => config.kind;

  /// 是否准备就绪（有必要的 API key 等）。
  bool get isReady;

  /// 单次执行（不含重试）。
  Future<List<WebSearchEngineHit>> fetch(WebSearchEngineRequest request);

  /// 带重试的对外 API（调用方使用）。指数退避 250ms·2^attempt（上限 4s）。
  Future<WebSearchEngineResult> run(WebSearchEngineRequest request) async {
    if (!isReady) {
      return WebSearchEngineResult(
        kind: kind,
        hits: const [],
        error: 'engine_not_ready',
      );
    }
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    final maxAttempts = (config.maxRetries + 1).clamp(1, 8);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (request.cancelSignal != null) {
        final cancelled = await Future.any([
          Future.value(false),
          request.cancelSignal!.then((_) => true),
        ]);
        if (cancelled) {
          return WebSearchEngineResult(
            kind: kind,
            hits: const [],
            error: 'cancelled',
            attempts: attempt - 1,
            elapsedMs: stopwatch.elapsedMilliseconds,
          );
        }
      }
      try {
        final raw = await fetch(request).timeout(const Duration(seconds: 25));
        final filtered = _applyFilters(
          raw,
          allowed: request.allowedDomains,
          blocked: request.blockedDomains,
        );
        final truncated = filtered
            .map((h) => h.truncated(config.truncationChars))
            .toList(growable: false);
        return WebSearchEngineResult(
          kind: kind,
          hits: truncated.take(request.maxResults).toList(growable: false),
          attempts: attempt,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      } catch (error, _) {
        lastError = error;
        if (attempt >= maxAttempts) break;
        final backoff = Duration(
          milliseconds: (250 * (1 << (attempt - 1))).clamp(250, 4000),
        );
        await Future<void>.delayed(backoff);
      }
    }
    return WebSearchEngineResult(
      kind: kind,
      hits: const [],
      error: lastError == null
          ? 'unknown_error'
          : '${lastError.runtimeType}: $lastError',
      attempts: maxAttempts,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  static List<WebSearchEngineHit> _applyFilters(
    List<WebSearchEngineHit> hits, {
    required List<String> allowed,
    required List<String> blocked,
  }) {
    if (allowed.isEmpty && blocked.isEmpty) return hits;
    return hits.where((hit) {
      final host = Uri.tryParse(hit.url)?.host.toLowerCase() ?? '';
      if (allowed.isNotEmpty &&
          !allowed.any((d) => host == d || host.endsWith('.$d'))) {
        return false;
      }
      if (blocked.any((d) => host == d || host.endsWith('.$d'))) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }
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
  String? resolveProviderApiKey(String? configId) {
    if (configId == null || configId.isEmpty) return null;
    for (final m in availableModels) {
      if (m.id == configId) return m.token.isEmpty ? null : m.token;
    }
    return null;
  }

  /// 解析复用 provider 的 BaseURL（同上）。
  String? resolveProviderBaseUrl(String? configId) {
    if (configId == null || configId.isEmpty) return null;
    for (final m in availableModels) {
      if (m.id == configId) return m.baseUrl.isEmpty ? null : m.baseUrl;
    }
    return null;
  }
}


