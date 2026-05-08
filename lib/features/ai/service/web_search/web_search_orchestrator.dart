import 'dart:async';
import 'dart:collection';

import 'package:http/http.dart' as http;

import '../../model/ai_model_config.dart';
import '../../model/ai_web_search_settings.dart';
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

enum WebSearchProgressStage {
  pending,
  running,
  succeeded,
  failed,
  fallback,
}

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
  });

  final String title;
  final String url;
  final String snippet;
  final List<AiWebSearchEngineKind> contributingEngines;
  final int totalWeight;
  final DateTime? publishedAt;
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
    final orderedConfigs = activeConfigs.isNotEmpty
        ? activeConfigs
        : _fallbackConfigs();
    final fallbackUsed = activeConfigs.isEmpty;

    // 失败自动降级：跳过当前 cooldown 中的引擎。一次成功 stat 自动清掉
    // cooldown，所以这里只需要静默过滤 + 汇报 progress.failed("cooldown")。
    final stats = await WebSearchTelemetryStore.instance.engineStats();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final usableConfigs = <AiWebSearchEngineConfig>[];
    final skippedKinds = <AiWebSearchEngineKind>[];
    for (final c in orderedConfigs) {
      final s = stats[c.kind];
      if (s != null && s.isInCooldown(nowMs)) {
        skippedKinds.add(c.kind);
      } else {
        usableConfigs.add(c);
      }
    }
    for (final k in skippedKinds) {
      onProgress(
        WebSearchEngineProgress(
          kind: k,
          stage: WebSearchProgressStage.failed,
          message: 'skipped: cooldown active',
        ),
      );
    }
    final effectiveConfigs =
        usableConfigs.isNotEmpty ? usableConfigs : orderedConfigs;

    final ctx = WebSearchEngineContext(
      httpClient: httpClient,
      availableModels: availableModels,
    );

    final engines = effectiveConfigs
        .map(
          (c) => _buildEngine(c, ctx),
        )
        .whereType<WebSearchEngine>()
        .toList(growable: false);

    if (engines.isEmpty) {
      return WebSearchOrchestrationResult(
        merged: const [],
        engineRuns: const [],
        fallbackUsed: fallbackUsed,
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
      results: results,
      configs: { for (final c in effectiveConfigs) c.kind: c },
      maxResults: settings.resultCount,
    );

    return WebSearchOrchestrationResult(
      merged: merged,
      engineRuns: results,
      fallbackUsed: fallbackUsed,
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
    final semaphore = _Semaphore(concurrency);
    final futures = engines.map((e) async {
      await semaphore.acquire();
      try {
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
      } finally {
        semaphore.release();
      }
    });
    return Future.wait(futures);
  }

  // ── 内部：合并 & 排序 ─────────────────────────────────────────────────────

  List<WebSearchAggregatedHit> _mergeAndRank({
    required List<WebSearchEngineResult> results,
    required Map<AiWebSearchEngineKind, AiWebSearchEngineConfig> configs,
    required int maxResults,
  }) {
    final byUrl = <String, _MergeBucket>{};
    for (final result in results) {
      if (!result.isSuccess) continue;
      final weight = configs[result.kind]?.weight ?? 50;
      for (final hit in result.hits) {
        final key = _normalizeUrl(hit.url);
        if (key.isEmpty) continue;
        final bucket = byUrl.putIfAbsent(
          key,
          () => _MergeBucket(
            title: hit.title,
            url: hit.url,
            snippet: hit.snippet,
            publishedAt: hit.publishedAt,
          ),
        );
        bucket.totalWeight += weight;
        bucket.engines.add(result.kind);
        if (bucket.snippet.length < hit.snippet.length) {
          bucket.snippet = hit.snippet;
        }
        if (bucket.title.length < hit.title.length) {
          bucket.title = hit.title;
        }
        bucket.publishedAt ??= hit.publishedAt;
      }
    }
    final sorted = byUrl.values.toList()
      ..sort((a, b) => b.totalWeight.compareTo(a.totalWeight));
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
          ),
        )
        .toList(growable: false);
  }

  String _normalizeUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw.trim().toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return '$host$path';
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
  });

  String title;
  final String url;
  String snippet;
  DateTime? publishedAt;
  int totalWeight = 0;
  final Set<AiWebSearchEngineKind> engines = <AiWebSearchEngineKind>{};
}

/// 简单计数信号量，用于并行 fan-out 限流。
class _Semaphore {
  _Semaphore(this.maxCount) : _available = maxCount;

  final int maxCount;
  int _available;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_available > 0) {
      _available -= 1;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _available = (_available + 1).clamp(0, maxCount);
    }
  }
}
