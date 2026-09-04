import 'dart:async';

import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/exponential_backoff.dart';
import '../../model/ai_web_engine_resilience.dart';

const int kWebEngineRetryBaseMs = 250;
const int kWebEngineRetryCapMs = 4000;

/// WebSearch / WebFetch 引擎共用的请求基类。
///
/// 两个领域的请求 (query / url+prompt) 长得不一样，但都需要可选的
/// `cancelSignal`，所以抽出最小公共面用于在 [WebEngineBase.run] 中协作。
abstract class WebEngineRequest {
  const WebEngineRequest({this.cancelSignal});

  /// 调用方可通过完成该 future 中止当前请求及后续重试。
  final Future<void>? cancelSignal;
}

/// WebSearch / WebFetch 引擎共用的执行壳：
///
/// * 失败重试（最多 `maxRetries+1` 次，受统一执行上限约束）
/// * 指数退避：第 1 次重试等待 [kWebEngineRetryBaseMs]，之后倍增，上限 [kWebEngineRetryCapMs]
/// * 单次 fetch 硬超时 [fetchTimeout]
/// * 每次重试前检查 `cancelSignal`
/// * `Stopwatch` 计时透传给结果
///
/// 子类只需要实现：
/// * [kind] / [isReady] / [fetch]：领域特定的单次抓取
/// * [buildResult]：把 items/error/attempts/elapsed 装进领域 Result
/// * [postProcess]：在成功路径上对 items 做过滤 / 截断 / take
abstract class WebEngineBase<
  TKind,
  TItem,
  TRequest extends WebEngineRequest,
  TResult
> {
  TKind get kind;
  bool get isReady;
  int get maxRetries;
  Duration get fetchTimeout;

  Future<List<TItem>> fetch(TRequest request);

  TResult buildResult({
    required List<TItem> items,
    String? error,
    required int attempts,
    required int elapsedMs,
  });

  List<TItem> postProcess(List<TItem> raw, TRequest request) => raw;

  /// 入口：retry + backoff + cancel + timeout，全部子类共用。
  Future<TResult> run(TRequest request) async {
    if (!isReady) {
      return buildResult(
        items: const [],
        error: 'engine_not_ready',
        attempts: 0,
        elapsedMs: 0,
      );
    }
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    final maxAttempts = (maxRetries + 1).clamp(
      1,
      AiWebEngineExecutionPolicy.maxAttempts,
    );
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (await isCancelSignalCompleted(request.cancelSignal)) {
        return buildResult(
          items: const [],
          error: 'cancelled',
          attempts: attempt - 1,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      }
      try {
        final raw = await _fetchWithCancel(request);
        if (raw == null) {
          return buildResult(
            items: const [],
            error: 'cancelled',
            attempts: attempt - 1,
            elapsedMs: stopwatch.elapsedMilliseconds,
          );
        }
        return buildResult(
          items: postProcess(raw, request),
          attempts: attempt,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      } catch (error) {
        lastError = error;
        if (attempt >= maxAttempts) break;
        final backoff = Duration(
          milliseconds: exponentialBackoffMs(
            attempt: attempt,
            baseMs: kWebEngineRetryBaseMs,
            capMs: kWebEngineRetryCapMs,
          ),
        );
        final cancelled = await delayUntilCancelled(
          backoff,
          cancelSignal: request.cancelSignal,
        );
        if (cancelled) {
          return buildResult(
            items: const [],
            error: 'cancelled',
            attempts: attempt,
            elapsedMs: stopwatch.elapsedMilliseconds,
          );
        }
      }
    }
    return buildResult(
      items: const [],
      error: lastError == null
          ? 'unknown_error'
          : '${lastError.runtimeType}: $lastError',
      attempts: maxAttempts,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  Future<List<TItem>?> _fetchWithCancel(TRequest request) async {
    final fetchFuture = fetch(request).timeout(fetchTimeout);
    return awaitWithCancelSignal(
      fetchFuture,
      cancelSignal: request.cancelSignal,
    );
  }
}
