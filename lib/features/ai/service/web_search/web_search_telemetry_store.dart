import 'dart:async';

import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_web_search_settings.dart';
import '../web_engine/web_engine_telemetry_store_base.dart';

/// WebSearch 调用日志 + 引擎健康度的本地持久化存储。
///
/// 公共骨架（写盘 / cooldown / FIFO / engine history）由
/// [WebEngineTelemetryStoreBase] 接管；本类只负责：
///   * 维护领域 typed 包装（[WebSearchCallLog] / [WebSearchPerEngineLog] /
///     [WebSearchEngineStat] / [WebSearchEngineSample]）；
///   * 在 typed `recordCall` 里把 perEngine 拍平成 [WebEngineCallEvent]，
///     并把 `total_hits` / `hits` 走"领域累加器"通道。
class WebSearchTelemetryStore
    extends WebEngineTelemetryStoreBase<AiWebSearchEngineKind> {
  WebSearchTelemetryStore._();

  static final WebSearchTelemetryStore instance = WebSearchTelemetryStore._();

  static const int maxRecentCalls = 200;
  static const int maxEngineHistorySamples = 200;

  @override
  String get subdir => 'web_search';

  @override
  String get logTag => 'web_search_telemetry';

  @override
  List<AiWebSearchEngineKind> get kindValues => AiWebSearchEngineKind.values;

  @override
  AiWebSearchEngineKind? parseKind(String name) {
    for (final k in AiWebSearchEngineKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  /// 记录一次完整调用：把 call log 追加到 calls.json，并把 perEngine 增量
  /// 折叠到 engines.json。永不抛异常。
  Future<void> recordCall(WebSearchCallLog call) {
    return recordCallRaw(
      callJson: call.toJson(),
      timestampMs: call.timestampMs,
      perEngine: call.perEngine
          .map(
            (per) => WebEngineCallEvent(
              kindName: per.kind.name,
              success: per.success,
              elapsedMs: per.elapsedMs,
              error: per.error,
              aggregateBumps: <String, num>{'total_hits': per.hitCount},
              historyExtras: <String, Object?>{'hits': per.hitCount},
            ),
          )
          .toList(growable: false),
    );
  }

  Future<List<WebSearchCallLog>> recentCalls({int limit = 50}) async {
    final list = await rawCalls();
    final reversed = list.reversed
        .map((m) => WebSearchCallLog.fromJson(m))
        .toList(growable: false);
    if (reversed.length <= limit) return reversed;
    return reversed.sublist(0, limit);
  }

  Future<Map<AiWebSearchEngineKind, WebSearchEngineStat>> engineStats() async {
    final raw = await rawEngineStats();
    final out = <AiWebSearchEngineKind, WebSearchEngineStat>{};
    for (final entry in raw.entries) {
      final kind = parseKind(entry.key);
      if (kind == null) continue;
      out[kind] = WebSearchEngineStat.fromJson(entry.value);
    }
    return out;
  }

  /// 读取 engine_history.json，按引擎返回采样列表（按时间升序）。
  Future<Map<AiWebSearchEngineKind, List<WebSearchEngineSample>>>
  engineHistory() async {
    final raw = await rawEngineHistory();
    final out = <AiWebSearchEngineKind, List<WebSearchEngineSample>>{};
    for (final entry in raw.entries) {
      final kind = parseKind(entry.key);
      if (kind == null) continue;
      out[kind] = entry.value
          .map(
            (m) => WebSearchEngineSample(
              timestampMs: _readTelemetryInt(m['ts']),
              durationMs: _readTelemetryInt(m['dur']),
              success: m['ok'] == true,
              hitCount: _readTelemetryInt(m['hits']),
            ),
          )
          .toList(growable: false);
    }
    return out;
  }
}

/// WebSearch 共享 [WebEngineCooldownConfig]：保留旧名做无破坏切换。
typedef WebSearchCooldownConfig = WebEngineCooldownConfig;

/// 单次 WebSearch 调用日志。
class WebSearchCallLog {
  const WebSearchCallLog({
    required this.timestampMs,
    required this.query,
    required this.cacheStatus,
    required this.success,
    required this.totalDurationMs,
    required this.mergedHitCount,
    required this.fallbackUsed,
    required this.summaryChars,
    required this.perEngine,
    this.errorMessage,
    this.modelProtocol,
    this.modelId,
  });

  factory WebSearchCallLog.fromJson(Map<String, Object?> m) {
    final perEngineRaw = m['per_engine'];
    final perEngine = perEngineRaw is List
        ? perEngineRaw
              .whereType<Map>()
              .map(
                (e) => WebSearchPerEngineLog.fromJson(
                  Map<String, Object?>.from(e),
                ),
              )
              .toList(growable: false)
        : const <WebSearchPerEngineLog>[];
    return WebSearchCallLog(
      timestampMs: _readTelemetryInt(m['timestamp_ms']),
      query: '${m['query'] ?? ''}',
      cacheStatus: '${m['cache_status'] ?? ''}',
      success: m['success'] == true,
      totalDurationMs: _readTelemetryInt(m['total_duration_ms']),
      mergedHitCount: _readTelemetryInt(m['merged_hit_count']),
      fallbackUsed: m['fallback_used'] == true,
      summaryChars: _readTelemetryInt(m['summary_chars']),
      errorMessage: m['error_message'] as String?,
      modelProtocol: m['model_protocol'] as String?,
      modelId: m['model_id'] as String?,
      perEngine: perEngine,
    );
  }

  final int timestampMs;
  final String query;

  /// 取值同 metadata.websearch_cache：`hit` / `miss-stored` / `disabled` / `bypass`
  final String cacheStatus;
  final bool success;
  final int totalDurationMs;
  final int mergedHitCount;
  final bool fallbackUsed;
  final int summaryChars;
  final String? errorMessage;
  final String? modelProtocol;
  final String? modelId;
  final List<WebSearchPerEngineLog> perEngine;

  Map<String, Object?> toJson() => {
    'timestamp_ms': timestampMs,
    'query': query,
    'cache_status': cacheStatus,
    'success': success,
    'total_duration_ms': totalDurationMs,
    'merged_hit_count': mergedHitCount,
    'fallback_used': fallbackUsed,
    'summary_chars': summaryChars,
    if (errorMessage != null) 'error_message': errorMessage,
    if (modelProtocol != null) 'model_protocol': modelProtocol,
    if (modelId != null) 'model_id': modelId,
    'per_engine': perEngine.map((e) => e.toJson()).toList(growable: false),
  };
}

class WebSearchPerEngineLog {
  const WebSearchPerEngineLog({
    required this.kind,
    required this.success,
    required this.hitCount,
    required this.elapsedMs,
    this.error,
  });

  factory WebSearchPerEngineLog.fromJson(Map<String, Object?> m) {
    final kind = AiWebSearchEngineKind.values.firstWhere(
      (k) => k.name == '${m['kind'] ?? ''}',
      orElse: () => AiWebSearchEngineKind.values.first,
    );
    return WebSearchPerEngineLog(
      kind: kind,
      success: m['success'] == true,
      hitCount: _readTelemetryInt(m['hit_count']),
      elapsedMs: _readTelemetryInt(m['elapsed_ms']),
      error: m['error'] as String?,
    );
  }

  final AiWebSearchEngineKind kind;
  final bool success;
  final int hitCount;
  final int elapsedMs;
  final String? error;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'success': success,
    'hit_count': hitCount,
    'elapsed_ms': elapsedMs,
    if (error != null) 'error': error,
  };
}

class WebSearchEngineStat {
  const WebSearchEngineStat({
    required this.totalCalls,
    required this.successCalls,
    required this.totalDurationMs,
    required this.totalHits,
    this.lastError,
    this.lastFailureAt,
    this.lastInvokedAt,
    this.consecutiveFailures = 0,
    this.cooldownUntilMs,
    this.lastQuotaError,
    this.lastQuotaAt,
  });

  factory WebSearchEngineStat.fromJson(Map<String, Object?> m) =>
      WebSearchEngineStat(
        totalCalls: _readTelemetryInt(m['total_calls']),
        successCalls: _readTelemetryInt(m['success_calls']),
        totalDurationMs: _readTelemetryInt(m['total_duration_ms']),
        totalHits: _readTelemetryInt(m['total_hits']),
        lastError: m['last_error'] as String?,
        lastFailureAt: _readOptionalTelemetryInt(m['last_failure_at']),
        lastInvokedAt: _readOptionalTelemetryInt(m['last_invoked_at']),
        consecutiveFailures: _readTelemetryInt(m['consecutive_failures']),
        cooldownUntilMs: _readOptionalTelemetryInt(m['cooldown_until_ms']),
        lastQuotaError: m['last_quota_error'] as String?,
        lastQuotaAt: _readOptionalTelemetryInt(m['last_quota_at']),
      );

  final int totalCalls;
  final int successCalls;
  final int totalDurationMs;
  final int totalHits;
  final String? lastError;
  final int? lastFailureAt;
  final int? lastInvokedAt;
  final int consecutiveFailures;
  final int? cooldownUntilMs;
  final String? lastQuotaError;
  final int? lastQuotaAt;

  double get successRate => totalCalls == 0 ? 0 : successCalls / totalCalls;
  double get avgDurationMs =>
      totalCalls == 0 ? 0 : totalDurationMs / totalCalls;

  bool isInCooldown([int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return cooldownUntilMs != null && cooldownUntilMs! > now;
  }
}

/// 单次引擎调用采样（趋势图用）。
class WebSearchEngineSample {
  const WebSearchEngineSample({
    required this.timestampMs,
    required this.durationMs,
    required this.success,
    required this.hitCount,
  });

  final int timestampMs;
  final int durationMs;
  final bool success;
  final int hitCount;
}

int _readTelemetryInt(Object? value) {
  return nonNegativeIntFromValue(value, fallback: 0);
}

int? _readOptionalTelemetryInt(Object? value) {
  return optionalNonNegativeIntFromValue(value);
}
