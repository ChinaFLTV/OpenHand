import 'dart:async';

import 'package:http/http.dart' as http;

import '../../model/ai_model_config.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../web_engine_concurrency.dart';
import 'web_fetch_direct_engines.dart';
import 'web_fetch_engine.dart';
import 'web_fetch_scrape_engines.dart';
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
  });

  final AiWebFetchSettings settings;
  final http.Client httpClient;
  final List<AiModelConfig> availableModels;

  Future<WebFetchOrchestrationResult> run({
    required String url,
    required String prompt,
    required Future<void>? cancelSignal,
    required WebFetchProgressEmitter onProgress,
  }) async {
    final activeConfigs = settings.engines
        .where((c) => c.enabled)
        .toList(growable: false);
    final orderedConfigs = activeConfigs.isNotEmpty
        ? activeConfigs
        : _fallbackConfigs();
    final fallbackUsed = activeConfigs.isEmpty;

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

    // 处于 cooldown 中或已超 throttle 上限的引擎：跳过。全部被跳时回退原序。
    final telemetry = WebFetchTelemetryStore.instance;
    final outcome = await filterByCooldownAndThrottle<
        AiWebFetchEngineConfig,
        AiWebFetchEngineKind>(
      configs: orderedConfigs,
      kindOf: (c) => c.kind,
      telemetry: telemetry,
      throttlePerMinute: settings.throttlePerMinute,
    );
    final filteredConfigs = outcome.usable;
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
    // 全部被跳时回退原序，否则 cooldown 会让全部引擎同时静默。
    final effectiveConfigs =
        filteredConfigs.isNotEmpty ? filteredConfigs : orderedConfigs;

    final ctx = WebFetchEngineContext(
      httpClient: httpClient,
      availableModels: availableModels,
    );

    final engines = effectiveConfigs
        .map((c) => _buildEngine(c, ctx))
        .whereType<WebFetchEngine>()
        .toList(growable: false);

    if (engines.isEmpty) {
      return WebFetchOrchestrationResult(
        merged: null,
        engineRuns: skippedRuns,
        fallbackUsed: fallbackUsed,
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
      results: results,
      configs: {for (final c in effectiveConfigs) c.kind: c},
    );

    return WebFetchOrchestrationResult(
      merged: winner?.contents.isNotEmpty == true ? winner!.contents.first : null,
      engineRuns: [...skippedRuns, ...results],
      fallbackUsed: fallbackUsed,
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
          contentBytes: r.contents.isEmpty ? 0 : r.contents.first.content.length,
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
            contentBytes:
                r.contents.isEmpty ? 0 : r.contents.first.content.length,
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

  /// 选胜：成功的结果中按 (weight × 内容长度) 选最大值。
  WebFetchEngineResult? _pickWinner({
    required List<WebFetchEngineResult> results,
    required Map<AiWebFetchEngineKind, AiWebFetchEngineConfig> configs,
  }) {
    WebFetchEngineResult? best;
    int bestScore = -1;
    for (final r in results) {
      if (!r.isSuccess) continue;
      final cfg = configs[r.kind];
      final w = cfg?.weight ?? 50;
      final len = r.contents.first.content.length;
      final score = w * len;
      if (score > bestScore) {
        bestScore = score;
        best = r;
      }
    }
    return best;
  }

  List<AiWebFetchEngineConfig> _fallbackConfigs() {
    return const [
      AiWebFetchEngineConfig(
        kind: AiWebFetchEngineKind.bing,
        enabled: true,
      ),
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
    return buildScrapeEngine(config: config, httpClient: httpClient) ??
        buildSearchAsFetchEngine(
          config: config,
          httpClient: httpClient,
          providerKeyResolver: ctx.resolveProviderApiKey,
        ) ??
        buildDirectEngine(config: config, httpClient: httpClient);
  }
}
