import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../model/ai_model_config.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../web_engine/web_engine_concurrency.dart';
import '../web_engine/web_engine_quality.dart';
import 'web_fetch_direct_engines.dart';
import 'web_fetch_engine.dart';
import 'web_fetch_scrape_engines.dart';
import 'web_fetch_scrapling_bridge.dart';
import 'web_fetch_search_engines.dart';
import 'web_fetch_telemetry_store.dart';

typedef WebFetchProgressEmitter =
    void Function(WebFetchEngineProgress progress);

class WebFetchEngineProgress {
  const WebFetchEngineProgress({
    required this.kind,
    required this.stage,
    this.message,
    this.contentBytes = 0,
    this.attempt = 0,
    this.elapsedMs = 0,
  });

  final AiWebFetchEngineKind kind;
  final WebFetchProgressStage stage;
  final String? message;
  final int contentBytes;
  final int attempt;
  final int elapsedMs;
}

enum WebFetchProgressStage { pending, running, succeeded, failed, fallback }

class WebFetchOrchestrationResult {
  WebFetchOrchestrationResult({
    required this.merged,
    required this.engineRuns,
    required this.fallbackUsed,
    required this.winningKind,
  });

  /// 选定胜出引擎的最终内容（已截断）。
  final WebFetchEngineContent? merged;
  final List<WebFetchEngineResult> engineRuns;
  final bool fallbackUsed;
  final AiWebFetchEngineKind? winningKind;
}

class WebFetchOrchestrator {
  WebFetchOrchestrator({
    required this.settings,
    required this.httpClient,
    required this.availableModels,
    this.scraplingBridge,
  });

  final AiWebFetchSettings settings;
  final http.Client httpClient;
  final List<AiModelConfig> availableModels;
  final WebFetchScraplingBridge? scraplingBridge;

  Future<WebFetchOrchestrationResult> run({
    required String url,
    required String prompt,
    required Future<void>? cancelSignal,
    required WebFetchProgressEmitter onProgress,
  }) async {
    final activeConfigs = settings.engines
        .where((c) => c.enabled)
        .toList(growable: false);

    // 推当前 settings 的 cooldown 阈值到 telemetry store，让 _writeCall 能按
    // 用户调整后的阈值计算 cooldown。
    WebFetchTelemetryStore.instance.cooldownConfig = WebFetchCooldownConfig(
      tier1Failures: settings.cooldownTier1Failures,
      tier1Seconds: settings.cooldownTier1Seconds,
      tier2Failures: settings.cooldownTier2Failures,
      tier2Seconds: settings.cooldownTier2Seconds,
      tier3Failures: settings.cooldownTier3Failures,
      tier3Seconds: settings.cooldownTier3Seconds,
      quotaSeconds: settings.cooldownQuotaSeconds,
    );

    // 处于 cooldown 中或已超 throttle 上限的引擎：跳过。primary 全部被跳时
    // 只尝试未被跳过的无 Key 兜底引擎，不再把 skipped 引擎放回去偷跑。
    final telemetry = WebFetchTelemetryStore.instance;
    final outcome =
        await filterByCooldownThrottleWithFallback<
          AiWebFetchEngineConfig,
          AiWebFetchEngineKind
        >(
          primaryConfigs: activeConfigs,
          fallbackConfigs: _fallbackConfigs(),
          kindOf: (c) => c.kind,
          telemetry: telemetry,
          throttlePerMinute: settings.throttlePerMinute,
        );
    final effectiveConfigs = outcome.usable;
    final skippedRuns = outcome.skipped
        .map(
          (s) => WebFetchEngineResult(
            kind: s.config.kind,
            contents: const [],
            error: s.reason,
            attempts: 0,
          ),
        )
        .toList(growable: false);

    final ctx = WebFetchEngineContext(
      httpClient: httpClient,
      availableModels: availableModels,
      scraplingBridge: scraplingBridge,
    );

    final engines = effectiveConfigs
        .map((c) => _buildEngine(c, ctx))
        .whereType<WebFetchEngine>()
        .toList(growable: false);

    if (engines.isEmpty) {
      return WebFetchOrchestrationResult(
        merged: null,
        engineRuns: skippedRuns,
        fallbackUsed: outcome.fallbackUsed,
        winningKind: null,
      );
    }

    // 对被跳过的引擎也 emit failed 事件，便于 UI 进度看到原因。
    for (final r in skippedRuns) {
      onProgress(
        WebFetchEngineProgress(
          kind: r.kind,
          stage: WebFetchProgressStage.failed,
          message: r.error,
        ),
      );
    }

    for (final e in engines) {
      onProgress(
        WebFetchEngineProgress(
          kind: e.kind,
          stage: WebFetchProgressStage.pending,
        ),
      );
    }

    // maxChars: 选 enabled 引擎里最大的 truncationChars 作为 fetch 上限
    // （单个引擎自己再按 config.truncationChars 二次截断）。
    final maxChars = effectiveConfigs.fold<int>(
      0,
      (acc, c) => c.truncationChars > acc ? c.truncationChars : acc,
    );

    final request = WebFetchEngineRequest(
      url: url,
      prompt: prompt,
      maxChars: maxChars,
      cancelSignal: cancelSignal,
    );

    final results = settings.parallel
        ? await _runParallel(engines, request, onProgress)
        : await _runSerial(engines, request, onProgress);

    final winner = _pickWinner(
      requestedUrl: url,
      prompt: prompt,
      results: results,
      configs: {for (final c in effectiveConfigs) c.kind: c},
    );

    return WebFetchOrchestrationResult(
      merged: winner?.contents.isNotEmpty == true
          ? winner!.contents.first
          : null,
      engineRuns: [...skippedRuns, ...results],
      fallbackUsed: outcome.fallbackUsed,
      winningKind: winner?.kind,
    );
  }

  Future<List<WebFetchEngineResult>> _runSerial(
    List<WebFetchEngine> engines,
    WebFetchEngineRequest request,
    WebFetchProgressEmitter onProgress,
  ) async {
    final out = <WebFetchEngineResult>[];
    for (final e in engines) {
      onProgress(
        WebFetchEngineProgress(
          kind: e.kind,
          stage: WebFetchProgressStage.running,
        ),
      );
      final r = await e.run(request);
      onProgress(
        WebFetchEngineProgress(
          kind: e.kind,
          stage: r.isSuccess
              ? WebFetchProgressStage.succeeded
              : WebFetchProgressStage.failed,
          contentBytes: r.contents.isEmpty
              ? 0
              : r.contents.first.content.length,
          attempt: r.attempts,
          elapsedMs: r.elapsedMs,
          message: r.error,
        ),
      );
      out.add(r);
      // 串行模式下首次成功立即短路
      if (r.isSuccess) break;
    }
    return out;
  }

  Future<List<WebFetchEngineResult>> _runParallel(
    List<WebFetchEngine> engines,
    WebFetchEngineRequest request,
    WebFetchProgressEmitter onProgress,
  ) async {
    final concurrency = settings.parallelWorkers.clamp(1, engines.length);
    final semaphore = WebEngineSemaphore(concurrency);
    final futures = engines.map((e) async {
      await semaphore.acquire();
      try {
        onProgress(
          WebFetchEngineProgress(
            kind: e.kind,
            stage: WebFetchProgressStage.running,
          ),
        );
        final r = await e.run(request);
        onProgress(
          WebFetchEngineProgress(
            kind: e.kind,
            stage: r.isSuccess
                ? WebFetchProgressStage.succeeded
                : WebFetchProgressStage.failed,
            contentBytes: r.contents.isEmpty
                ? 0
                : r.contents.first.content.length,
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

  /// 选胜：成功结果中综合权重、URL 命中、抓取类型、HTTP 状态与长度信号。
  @visibleForTesting
  WebFetchEngineResult? pickWinnerForTesting({
    required String requestedUrl,
    String prompt = '',
    required List<WebFetchEngineResult> results,
    required Map<AiWebFetchEngineKind, AiWebFetchEngineConfig> configs,
  }) {
    return _pickWinner(
      requestedUrl: requestedUrl,
      prompt: prompt,
      results: results,
      configs: configs,
    );
  }

  WebFetchEngineResult? _pickWinner({
    required String requestedUrl,
    required String prompt,
    required List<WebFetchEngineResult> results,
    required Map<AiWebFetchEngineKind, AiWebFetchEngineConfig> configs,
  }) {
    WebFetchEngineResult? best;
    double bestScore = double.negativeInfinity;
    for (final r in results) {
      if (!r.isSuccess) continue;
      final cfg = configs[r.kind];
      final score = _winnerScore(
        requestedUrl: requestedUrl,
        prompt: prompt,
        result: r,
        weight: cfg?.weight ?? 50,
      );
      if (score > bestScore) {
        bestScore = score;
        best = r;
      }
    }
    return best;
  }

  double _winnerScore({
    required String requestedUrl,
    required String prompt,
    required WebFetchEngineResult result,
    required int weight,
  }) {
    final content = result.contents.first;
    final lengthScore = math.log(content.content.length + 1) / math.ln10 * 50;
    final urlScore = _urlMatchScore(requestedUrl, content.url);
    final relevanceScore = webTextRelevanceScore(prompt, content.content) * 160;
    final qualityScore = webContentQualityScore(content.content);
    final nativeFetchScore = _isNativeUrlFetchKind(result.kind) ? 100.0 : 0.0;
    final statusScore = content.statusCode == null
        ? 0.0
        : (content.statusCode! >= 200 && content.statusCode! < 300
              ? 50.0
              : 0.0);
    final providerScore = (content.score ?? 0).clamp(0.0, 1.0).toDouble() * 50;
    return weight * 10 +
        lengthScore +
        urlScore +
        relevanceScore +
        qualityScore +
        nativeFetchScore +
        statusScore +
        providerScore;
  }

  double _urlMatchScore(String requestedUrl, String resultUrl) {
    final requested = _normalizedUriForScore(requestedUrl);
    final result = _normalizedUriForScore(resultUrl);
    if (requested == null || result == null) return 0;
    if (requested.host == result.host && requested.path == result.path) {
      return requested.query == result.query ? 300.0 : 240.0;
    }
    if (requested.host == result.host) return 80.0;
    return -180.0;
  }

  Uri? _normalizedUriForScore(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.trim().isEmpty) return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final path = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return Uri(host: host, path: path, query: uri.query);
  }

  bool _isNativeUrlFetchKind(AiWebFetchEngineKind kind) {
    return switch (kind) {
      AiWebFetchEngineKind.firecrawl ||
      AiWebFetchEngineKind.scrapling ||
      AiWebFetchEngineKind.tavily ||
      AiWebFetchEngineKind.exa ||
      AiWebFetchEngineKind.duckduckgo ||
      AiWebFetchEngineKind.bing => true,
      AiWebFetchEngineKind.kimi ||
      AiWebFetchEngineKind.baidu ||
      AiWebFetchEngineKind.linkup ||
      AiWebFetchEngineKind.bocha ||
      AiWebFetchEngineKind.grok ||
      AiWebFetchEngineKind.gemini => false,
    };
  }

  List<AiWebFetchEngineConfig> _fallbackConfigs() {
    return const [
      AiWebFetchEngineConfig(kind: AiWebFetchEngineKind.bing, enabled: true),
      AiWebFetchEngineConfig(
        kind: AiWebFetchEngineKind.duckduckgo,
        enabled: true,
      ),
    ];
  }

  WebFetchEngine? _buildEngine(
    AiWebFetchEngineConfig config,
    WebFetchEngineContext ctx,
  ) {
    return buildScrapeEngine(
          config: config,
          httpClient: httpClient,
          scraplingBridge: ctx.scraplingBridge,
          scraplingSettings: settings.scrapling,
        ) ??
        buildSearchAsFetchEngine(
          config: config,
          httpClient: httpClient,
          providerKeyResolver: ctx.resolveProviderApiKey,
        ) ??
        buildDirectEngine(config: config, httpClient: httpClient);
  }
}
