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
  const WebEngineFilterOutcome({
    required this.usable,
    required this.skipped,
  });

  final List<TConfig> usable;
  final List<WebEngineSkippedItem<TConfig>> skipped;
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
        WebEngineSkippedItem(
          config: c,
          reason: 'skipped: cooldown active',
        ),
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
