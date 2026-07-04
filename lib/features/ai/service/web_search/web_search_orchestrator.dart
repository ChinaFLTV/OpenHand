import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_web_search_settings.dart';
import '../web_engine/web_engine_concurrency.dart';
import '../web_engine/web_engine_quality.dart';
import 'web_search_api_engines.dart';
import 'web_search_engine.dart';
import 'web_search_html_engines.dart';
import 'web_search_provider_engines.dart';
import 'web_search_telemetry_store.dart';

/// 单个引擎运行进度回调（用于在 BashToolExecutionUpdate 里推送状态）。
typedef WebSearchProgressEmitter =
    void Function(WebSearchEngineProgress progress);

class WebSearchEngineProgress {
  const WebSearchEngineProgress({
    required this.kind,
    required this.stage,
    this.message,
    this.hitCount = 0,
    this.attempt = 0,
    this.elapsedMs = 0,
  });

  final AiWebSearchEngineKind kind;
  final WebSearchProgressStage stage;
  final String? message;
  final int hitCount;
  final int attempt;
  final int elapsedMs;
}

enum WebSearchProgressStage { pending, running, succeeded, failed, fallback }

/// 编排结果：聚合后的最终命中列表 + 各引擎运行 trace。
class WebSearchOrchestrationResult {
  WebSearchOrchestrationResult({
    required this.merged,
    required this.engineRuns,
    required this.fallbackUsed,
  });

  final List<WebSearchAggregatedHit> merged;
  final List<WebSearchEngineResult> engineRuns;
  final bool fallbackUsed;
}

/// 聚合后的命中：合并相同 URL，记录贡献引擎与权重。
class WebSearchAggregatedHit {
  WebSearchAggregatedHit({
    required this.title,
    required this.url,
    required this.snippet,
    required this.contributingEngines,
    required this.totalWeight,
    this.publishedAt,
    this.source,
    this.score,
    this.rawContent,
  });

  final String title;
  final String url;
  final String snippet;
  final List<AiWebSearchEngineKind> contributingEngines;
  final int totalWeight;
  final DateTime? publishedAt;
  final String? source;
  final double? score;
  final String? rawContent;
}

class WebSearchOrchestrator {
  WebSearchOrchestrator({
    required this.settings,
    required this.httpClient,
    required this.availableModels,
  });

  final AiWebSearchSettings settings;
  final http.Client httpClient;
  final List<AiModelConfig> availableModels;

  /// 执行 sub-agent 检索。允许通过 [onProgress] 流式回调每个引擎的状态。
  Future<WebSearchOrchestrationResult> run({
    required String query,
    required List<String> allowedDomains,
    required List<String> blockedDomains,
    required Future<void>? cancelSignal,
    required WebSearchProgressEmitter onProgress,
  }) async {
    final activeConfigs = settings.engines
        .where((c) => c.enabled)
        .toList(growable: false);

    // 失败自动降级：跳过当前 cooldown 中的引擎。一次成功 stat 自动清掉
    // cooldown，所以这里只需要静默过滤 + 汇报 progress.failed("cooldown")。
    // 同时把用户配置的 cooldown 阈值推到 store，确保下一次失败按用户阈值落库。
    WebSearchTelemetryStore.instance.cooldownConfig = WebSearchCooldownConfig(
      tier1Failures: settings.cooldownTier1Failures,
      tier1Seconds: settings.cooldownTier1Seconds,
      tier2Failures: settings.cooldownTier2Failures,
      tier2Seconds: settings.cooldownTier2Seconds,
      tier3Failures: settings.cooldownTier3Failures,
      tier3Seconds: settings.cooldownTier3Seconds,
      quotaSeconds: settings.cooldownQuotaSeconds,
    );
    final outcome =
        await filterByCooldownThrottleWithFallback<
          AiWebSearchEngineConfig,
          AiWebSearchEngineKind
        >(
          primaryConfigs: activeConfigs,
          fallbackConfigs: _fallbackConfigs(),
          kindOf: (c) => c.kind,
          telemetry: WebSearchTelemetryStore.instance,
          throttlePerMinute: settings.throttlePerMinute,
        );
    final effectiveConfigs = outcome.usable;
    final skippedRuns = outcome.skipped
        .map(
          (s) => WebSearchEngineResult(
            kind: s.config.kind,
            hits: const [],
            error: s.reason,
            attempts: 0,
          ),
        )
        .toList(growable: false);
    for (final s in outcome.skipped) {
      onProgress(
        WebSearchEngineProgress(
          kind: s.config.kind,
          stage: WebSearchProgressStage.failed,
          message: s.reason,
        ),
      );
    }

    final ctx = WebSearchEngineContext(
      httpClient: httpClient,
      availableModels: availableModels,
    );

    final engines = effectiveConfigs
        .map((c) => _buildEngine(c, ctx))
        .whereType<WebSearchEngine>()
        .toList(growable: false);

    if (engines.isEmpty) {
      return WebSearchOrchestrationResult(
        merged: const [],
        engineRuns: skippedRuns,
        fallbackUsed: outcome.fallbackUsed,
      );
    }

    for (final e in engines) {
      onProgress(
        WebSearchEngineProgress(
          kind: e.kind,
          stage: WebSearchProgressStage.pending,
        ),
      );
    }

    final request = WebSearchEngineRequest(
      query: query,
      maxResults: settings.resultCount,
      allowedDomains: allowedDomains,
      blockedDomains: blockedDomains,
      cancelSignal: cancelSignal,
    );

    final results = settings.parallel
        ? await _runParallel(engines, request, onProgress)
        : await _runSerial(engines, request, onProgress);

    final merged = _mergeAndRank(
      query: query,
      results: results,
      configs: {for (final c in effectiveConfigs) c.kind: c},
      maxResults: settings.resultCount,
    );

    return WebSearchOrchestrationResult(
      merged: merged,
      engineRuns: [...skippedRuns, ...results],
      fallbackUsed: outcome.fallbackUsed,
    );
  }

  // ── 内部：运行 ─────────────────────────────────────────────────────────────

  Future<List<WebSearchEngineResult>> _runSerial(
    List<WebSearchEngine> engines,
    WebSearchEngineRequest request,
    WebSearchProgressEmitter onProgress,
  ) async {
    final out = <WebSearchEngineResult>[];
    for (final e in engines) {
      onProgress(
        WebSearchEngineProgress(
          kind: e.kind,
          stage: WebSearchProgressStage.running,
        ),
      );
      final r = await e.run(request);
      onProgress(
        WebSearchEngineProgress(
          kind: e.kind,
          stage: r.isSuccess
              ? WebSearchProgressStage.succeeded
              : WebSearchProgressStage.failed,
          hitCount: r.hits.length,
          attempt: r.attempts,
          elapsedMs: r.elapsedMs,
          message: r.error,
        ),
      );
      out.add(r);
    }
    return out;
  }

  Future<List<WebSearchEngineResult>> _runParallel(
    List<WebSearchEngine> engines,
    WebSearchEngineRequest request,
    WebSearchProgressEmitter onProgress,
  ) async {
    final concurrency = settings.parallelWorkers.clamp(1, engines.length);
    final semaphore = WebEngineSemaphore(concurrency);
    final futures = engines.map((e) async {
      return semaphore.withPermit(() async {
        onProgress(
          WebSearchEngineProgress(
            kind: e.kind,
            stage: WebSearchProgressStage.running,
          ),
        );
        final r = await e.run(request);
        onProgress(
          WebSearchEngineProgress(
            kind: e.kind,
            stage: r.isSuccess
                ? WebSearchProgressStage.succeeded
                : WebSearchProgressStage.failed,
            hitCount: r.hits.length,
            attempt: r.attempts,
            elapsedMs: r.elapsedMs,
            message: r.error,
          ),
        );
        return r;
      });
    });
    return Future.wait(futures);
  }

  // ── 内部：合并 & 排序 ─────────────────────────────────────────────────────

  @visibleForTesting
  List<WebSearchAggregatedHit> mergeAndRankForTesting({
    String query = '',
    required List<WebSearchEngineResult> results,
    required Map<AiWebSearchEngineKind, AiWebSearchEngineConfig> configs,
    required int maxResults,
  }) {
    return _mergeAndRank(
      query: query,
      results: results,
      configs: configs,
      maxResults: maxResults,
    );
  }

  List<WebSearchAggregatedHit> _mergeAndRank({
    required String query,
    required List<WebSearchEngineResult> results,
    required Map<AiWebSearchEngineKind, AiWebSearchEngineConfig> configs,
    required int maxResults,
  }) {
    final byUrl = <String, _MergeBucket>{};
    for (final result in results) {
      if (!result.isSuccess) continue;
      final weight = configs[result.kind]?.weight ?? 50;
      for (var index = 0; index < result.hits.length; index += 1) {
        final hit = result.hits[index];
        if (!webHasInformativeSearchText(
          title: hit.title,
          url: hit.url,
          snippet: hit.snippet,
          rawContent: hit.rawContent,
        )) {
          continue;
        }
        final key = _normalizeUrl(hit.url);
        if (key.isEmpty) continue;
        final bucket = byUrl.putIfAbsent(
          key,
          () => _MergeBucket(
            title: hit.title,
            url: hit.url,
            snippet: hit.snippet,
            publishedAt: hit.publishedAt,
            source: hit.source,
            score: hit.score,
            rawContent: hit.rawContent,
          ),
        );
        bucket.recordEngineContribution(
          result.kind,
          weight: weight,
          score: _engineContributionScore(
            query: query,
            hit: hit,
            weight: weight,
            hitIndex: index,
            hitScore: hit.score,
          ),
        );
        if (bucket.snippet.length < hit.snippet.length) {
          bucket.snippet = hit.snippet;
        }
        if (bucket.title.length < hit.title.length) {
          bucket.title = hit.title;
        }
        if (hit.publishedAt != null &&
            (bucket.publishedAt == null ||
                hit.publishedAt!.isAfter(bucket.publishedAt!))) {
          bucket.publishedAt = hit.publishedAt;
        }
        if ((bucket.source ?? '').isEmpty && (hit.source ?? '').isNotEmpty) {
          bucket.source = hit.source;
        }
        if (hit.score != null &&
            (bucket.score == null || hit.score! > bucket.score!)) {
          bucket.score = hit.score;
        }
        if (_textQualityScore(hit.rawContent) >
            _textQualityScore(bucket.rawContent)) {
          bucket.rawContent = hit.rawContent;
        }
      }
    }
    final sorted = byUrl.values.toList()
      ..sort((a, b) {
        final byScore = b.rankingScore.compareTo(a.rankingScore);
        if (byScore != 0) return byScore;
        final byWeight = b.totalWeight.compareTo(a.totalWeight);
        if (byWeight != 0) return byWeight;
        final aDate = a.publishedAt;
        final bDate = b.publishedAt;
        if (aDate != null && bDate != null) {
          final byDate = bDate.compareTo(aDate);
          if (byDate != 0) return byDate;
        }
        return a.url.compareTo(b.url);
      });
    return sorted
        .take(maxResults)
        .map(
          (b) => WebSearchAggregatedHit(
            title: b.title,
            url: b.url,
            snippet: b.snippet,
            contributingEngines: b.engines.toList(growable: false),
            totalWeight: b.totalWeight,
            publishedAt: b.publishedAt,
            source: b.source,
            score: b.score,
            rawContent: b.rawContent,
          ),
        )
        .toList(growable: false);
  }

  int _textQualityScore(String? value) {
    final text = nullIfBlank(value);
    if (text == null) return 0;
    return text.length.clamp(0, 4000);
  }

  double _engineContributionScore({
    required String query,
    required WebSearchEngineHit hit,
    required int weight,
    required int hitIndex,
    required double? hitScore,
  }) {
    final rankScore = weight / (hitIndex + 1);
    final normalizedHitScore = hitScore == null
        ? 0.0
        : hitScore.clamp(0.0, 1.0).toDouble();
    final relevanceScore = webTextRelevanceScore(
      query,
      '${hit.title}\n${hit.snippet}\n${hit.rawContent ?? ''}',
    );
    return rankScore +
        normalizedHitScore * weight * 0.25 +
        relevanceScore * weight * 0.9;
  }

  String _normalizeUrl(String raw) {
    final trimmed = nullIfBlank(raw) ?? '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null || nullIfBlank(uri.host) == null) {
      return trimmed.toLowerCase();
    }
    final host = _normalizeHost(uri.host);
    final path = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    final query = _normalizeQuery(uri.queryParametersAll);
    return query.isEmpty ? '$host$path' : '$host$path?$query';
  }

  String _normalizeHost(String host) {
    final lower = host.toLowerCase();
    return lower.startsWith('www.') ? lower.substring(4) : lower;
  }

  String _normalizeQuery(Map<String, List<String>> queryParameters) {
    if (queryParameters.isEmpty) return '';
    final pairs = <String>[];
    final keys =
        queryParameters.keys
            .where((key) => !_isTrackingQueryKey(key))
            .toList(growable: false)
          ..sort();
    for (final key in keys) {
      final values = [...?queryParameters[key]]..sort();
      for (final value in values) {
        pairs.add(
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
        );
      }
    }
    return pairs.join('&');
  }

  bool _isTrackingQueryKey(String key) {
    final lower = key.toLowerCase();
    return lower.startsWith('utm_') ||
        lower == 'fbclid' ||
        lower == 'gclid' ||
        lower == 'dclid' ||
        lower == 'mc_cid' ||
        lower == 'mc_eid' ||
        lower == 'igshid' ||
        lower == 'ref' ||
        lower == 'ref_src' ||
        lower == 'spm';
  }

  // ── 内部：兜底配置 ────────────────────────────────────────────────────────

  List<AiWebSearchEngineConfig> _fallbackConfigs() {
    return [
      const AiWebSearchEngineConfig(
        kind: AiWebSearchEngineKind.bing,
        enabled: true,
      ),
      const AiWebSearchEngineConfig(
        kind: AiWebSearchEngineKind.duckduckgo,
        enabled: true,
      ),
    ];
  }

  // ── 内部：构造引擎实例 ────────────────────────────────────────────────────

  WebSearchEngine? _buildEngine(
    AiWebSearchEngineConfig config,
    WebSearchEngineContext ctx,
  ) {
    return buildApiEngine(
          config: config,
          httpClient: httpClient,
          providerKeyResolver: ctx.resolveProviderApiKey,
        ) ??
        buildHtmlEngine(config: config, httpClient: httpClient) ??
        buildProviderEngine(
          config: config,
          httpClient: httpClient,
          providerKeyResolver: ctx.resolveProviderApiKey,
        );
  }
}

class _MergeBucket {
  _MergeBucket({
    required this.title,
    required this.url,
    required this.snippet,
    this.publishedAt,
    this.source,
    this.score,
    this.rawContent,
  });

  String title;
  final String url;
  String snippet;
  DateTime? publishedAt;
  String? source;
  double? score;
  String? rawContent;
  int totalWeight = 0;
  double rankingScore = 0;
  final Set<AiWebSearchEngineKind> engines = <AiWebSearchEngineKind>{};
  final Map<AiWebSearchEngineKind, double> _engineScores =
      <AiWebSearchEngineKind, double>{};

  void recordEngineContribution(
    AiWebSearchEngineKind kind, {
    required int weight,
    required double score,
  }) {
    final previous = _engineScores[kind];
    if (previous == null) {
      engines.add(kind);
      totalWeight += weight;
      _engineScores[kind] = score;
      rankingScore += score;
      return;
    }
    if (score > previous) {
      _engineScores[kind] = score;
      rankingScore += score - previous;
    }
  }
}
