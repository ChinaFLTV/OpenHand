import 'dart:async';
import 'dart:collection';

import 'package:http/http.dart' as http;

import '../../model/ai_model_config.dart';
import '../../model/ai_web_fetch_settings.dart';
import 'web_fetch_direct_engines.dart';
import 'web_fetch_engine.dart';
import 'web_fetch_scrape_engines.dart';
import 'web_fetch_search_engines.dart';

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

    final ctx = WebFetchEngineContext(
      httpClient: httpClient,
      availableModels: availableModels,
    );

    final engines = orderedConfigs
        .map((c) => _buildEngine(c, ctx))
        .whereType<WebFetchEngine>()
        .toList(growable: false);

    if (engines.isEmpty) {
      return WebFetchOrchestrationResult(
        merged: null,
        engineRuns: const [],
        fallbackUsed: fallbackUsed,
        winningKind: null,
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
    final maxChars = orderedConfigs.fold<int>(
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
      configs: {for (final c in orderedConfigs) c.kind: c},
    );

    return WebFetchOrchestrationResult(
      merged: winner?.contents.isNotEmpty == true ? winner!.contents.first : null,
      engineRuns: results,
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
    final semaphore = _Semaphore(concurrency);
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
