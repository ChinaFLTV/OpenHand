import 'dart:async';
import 'dart:collection';

import 'web_engine_telemetry_store_base.dart';

/// 简单计数信号量，用于 orchestrator 并行 fan-out 限流。
///
/// 之前 [WebSearchOrchestrator] / [WebFetchOrchestrator] 各自有一份等价实现，
/// 这里做唯一来源。
class WebEngineSemaphore {
  WebEngineSemaphore(this.maxCount) : _available = maxCount;

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

/// 单个被跳过的引擎条目（cooldown / throttle）。
class WebEngineSkippedItem<TConfig> {
  const WebEngineSkippedItem({required this.config, required this.reason});

  /// 用户配置（保留原 typed 形态，调用方按需映射成领域 result）。
  final TConfig config;

  /// 一类原因短语，已和老实现保持兼容：
  ///   * `'skipped: cooldown active'`
  ///   * `'skipped: throttle limit reached'`
  final String reason;
}

class WebEngineFilterOutcome<TConfig> {
  const WebEngineFilterOutcome({required this.usable, required this.skipped});

  final List<TConfig> usable;
  final List<WebEngineSkippedItem<TConfig>> skipped;
}

class WebEngineFallbackFilterOutcome<TConfig> {
  const WebEngineFallbackFilterOutcome({
    required this.usable,
    required this.skipped,
    required this.fallbackUsed,
  });

  final List<TConfig> usable;
  final List<WebEngineSkippedItem<TConfig>> skipped;
  final bool fallbackUsed;
}

/// 把 cooldown / throttle 过滤逻辑收敛成单一入口，供 WebSearch /
/// WebFetch orchestrator 复用。返回值同时给出可用列表与被跳过项（含原因），
/// 调用方按各自的 progress / result 模型再做映射。
///
/// * [kindOf]：从 config 取到 telemetry 用的 kind 枚举。
/// * [telemetry]：领域专属 store，由 base 类提供 cooldown/throttle 查询。
/// * [throttlePerMinute]：0 表示不限。
///
/// 注意：[telemetry] 的 `cooldownRemaining` / `callsInLastMinute` 都是 async，
/// 所以这里也是 async；语义和老实现 1:1 对齐（一次成功 stat 自动清掉
/// cooldown 由 base 侧负责，这里不重复处理）。
Future<WebEngineFilterOutcome<TConfig>>
filterByCooldownAndThrottle<TConfig, TKind extends Enum>({
  required List<TConfig> configs,
  required TKind Function(TConfig) kindOf,
  required WebEngineTelemetryStoreBase<TKind> telemetry,
  required int throttlePerMinute,
}) async {
  final usable = <TConfig>[];
  final skipped = <WebEngineSkippedItem<TConfig>>[];
  for (final c in configs) {
    final kind = kindOf(c);
    final remaining = await telemetry.cooldownRemaining(kind);
    if (remaining > 0) {
      skipped.add(
        WebEngineSkippedItem(config: c, reason: 'skipped: cooldown active'),
      );
      continue;
    }
    if (throttlePerMinute > 0) {
      final used = await telemetry.callsInLastMinute(kind);
      if (used >= throttlePerMinute) {
        skipped.add(
          WebEngineSkippedItem(
            config: c,
            reason: 'skipped: throttle limit reached',
          ),
        );
        continue;
      }
    }
    usable.add(c);
  }
  return WebEngineFilterOutcome(usable: usable, skipped: skipped);
}

/// 在 primary 全部被 cooldown/throttle 跳过时尝试 fallback configs。
///
/// 关键语义：被跳过的 primary 不会被偷偷放回执行队列；fallback 只尝试尚未被
/// primary 过滤命中过的 kind，避免同一引擎先显示 skipped 又继续真实调用。
Future<WebEngineFallbackFilterOutcome<TConfig>>
filterByCooldownThrottleWithFallback<TConfig, TKind extends Enum>({
  required List<TConfig> primaryConfigs,
  required List<TConfig> fallbackConfigs,
  required TKind Function(TConfig) kindOf,
  required WebEngineTelemetryStoreBase<TKind> telemetry,
  required int throttlePerMinute,
}) async {
  final initialConfigs = primaryConfigs.isNotEmpty
      ? primaryConfigs
      : fallbackConfigs;
  final initial = await filterByCooldownAndThrottle<TConfig, TKind>(
    configs: initialConfigs,
    kindOf: kindOf,
    telemetry: telemetry,
    throttlePerMinute: throttlePerMinute,
  );
  if (initial.usable.isNotEmpty || primaryConfigs.isEmpty) {
    return WebEngineFallbackFilterOutcome(
      usable: initial.usable,
      skipped: initial.skipped,
      fallbackUsed: primaryConfigs.isEmpty,
    );
  }

  final skippedKinds = initial.skipped
      .map((skipped) => kindOf(skipped.config))
      .toSet();
  final fallbackCandidates = fallbackConfigs
      .where((config) => !skippedKinds.contains(kindOf(config)))
      .toList(growable: false);
  if (fallbackCandidates.isEmpty) {
    return WebEngineFallbackFilterOutcome(
      usable: const [],
      skipped: initial.skipped,
      fallbackUsed: false,
    );
  }

  final fallback = await filterByCooldownAndThrottle<TConfig, TKind>(
    configs: fallbackCandidates,
    kindOf: kindOf,
    telemetry: telemetry,
    throttlePerMinute: throttlePerMinute,
  );
  return WebEngineFallbackFilterOutcome(
    usable: fallback.usable,
    skipped: [...initial.skipped, ...fallback.skipped],
    fallbackUsed: true,
  );
}
