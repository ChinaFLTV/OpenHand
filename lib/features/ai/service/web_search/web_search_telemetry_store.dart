import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_web_search_settings.dart';
import '../web_engine/web_engine_telemetry_store_base.dart';
import '../web_engine/web_engine_value_parsing.dart';

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

  @override
  String get subdir => 'web_search';

  @override
  String get logTag => 'web_search_telemetry';

  @override
  AiWebSearchEngineKind? parseKind(String name) {
    return enumByName(AiWebSearchEngineKind.values, name);
  }

  /// 记录一次完整调用：把 call log 追加到 calls.json，并把 perEngine 增量
  /// 折叠到 engines.json。永不抛异常。
  Future<void> recordCall(
    WebSearchCallLog call, {
    required WebEngineCooldownConfig cooldownConfig,
  }) {
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
      cooldownConfig: cooldownConfig,
    );
  }

  Future<List<WebSearchCallLog>> recentCalls({int limit = 50}) async {
    return (await recentRawCalls(
      limit: limit,
    )).map((m) => WebSearchCallLog.fromJson(m)).toList(growable: false);
  }

  Future<Map<AiWebSearchEngineKind, WebSearchEngineStat>> engineStats() async {
    return typedEngineStats(WebSearchEngineStat.fromJson);
  }

  /// 读取 engine_history.json，按引擎返回采样列表（按时间升序）。
  Future<Map<AiWebSearchEngineKind, List<WebSearchEngineSample>>>
  engineHistory() async {
    return typedEngineHistory(
      (m) => WebSearchEngineSample(
        timestampMs: webEngineNonNegativeIntFromValue(m['ts']),
        durationMs: webEngineNonNegativeIntFromValue(m['dur']),
        success: m['ok'] == true,
        hitCount: webEngineNonNegativeIntFromValue(m['hits']),
      ),
    );
  }
}

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
    final perEngine = stringKeyedMapListFromValue(
      m['per_engine'],
    ).map(WebSearchPerEngineLog.fromJson).toList(growable: false);
    return WebSearchCallLog(
      timestampMs: webEngineNonNegativeIntFromValue(m['timestamp_ms']),
      query: '${m['query'] ?? ''}',
      cacheStatus: '${m['cache_status'] ?? ''}',
      success: m['success'] == true,
      totalDurationMs: webEngineNonNegativeIntFromValue(m['total_duration_ms']),
      mergedHitCount: webEngineNonNegativeIntFromValue(m['merged_hit_count']),
      fallbackUsed: m['fallback_used'] == true,
      summaryChars: webEngineNonNegativeIntFromValue(m['summary_chars']),
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
    final kind = enumByNameOr(
      AiWebSearchEngineKind.values,
      m['kind'],
      fallback: AiWebSearchEngineKind.values.first,
    );
    return WebSearchPerEngineLog(
      kind: kind,
      success: m['success'] == true,
      hitCount: webEngineNonNegativeIntFromValue(m['hit_count']),
      elapsedMs: webEngineNonNegativeIntFromValue(m['elapsed_ms']),
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

class WebSearchEngineStat extends WebEngineStatBase {
  const WebSearchEngineStat({
    required super.totalCalls,
    required super.successCalls,
    required super.totalDurationMs,
    required this.totalHits,
    super.lastError,
    super.lastFailureAt,
    super.lastInvokedAt,
    super.consecutiveFailures,
    super.cooldownUntilMs,
    super.lastQuotaError,
    super.lastQuotaAt,
  });

  factory WebSearchEngineStat.fromJson(Map<String, Object?> m) =>
      WebSearchEngineStat._fromJson(m);

  WebSearchEngineStat._fromJson(super.json)
    : totalHits = webEngineNonNegativeIntFromValue(json['total_hits']),
      super.fromJson();

  final int totalHits;
}

class WebSearchEngineSample extends WebEngineSampleBase {
  const WebSearchEngineSample({
    required super.timestampMs,
    required super.durationMs,
    required super.success,
    required this.hitCount,
  });

  final int hitCount;
}
