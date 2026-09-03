import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../web_engine/web_engine_telemetry_store_base.dart';
import '../web_engine/web_engine_value_parsing.dart';

/// WebFetch 调用日志 + 引擎健康度的本地持久化存储。
///
/// 公共骨架由 [WebEngineTelemetryStoreBase] 接管；本类只负责领域 typed 包装
/// 和 perEngine 拍平（`total_bytes` / `bytes` 走"领域累加器"通道）。
class WebFetchTelemetryStore
    extends WebEngineTelemetryStoreBase<AiWebFetchEngineKind> {
  WebFetchTelemetryStore._();

  static final WebFetchTelemetryStore instance = WebFetchTelemetryStore._();

  @override
  String get subdir => 'web_fetch';

  @override
  String get logTag => 'web_fetch_telemetry';

  @override
  AiWebFetchEngineKind? parseKind(String name) {
    return enumByName(AiWebFetchEngineKind.values, name);
  }

  Future<void> recordCall(
    WebFetchCallLog call, {
    required WebEngineCooldownConfig cooldownConfig,
  }) {
    return recordMetricCall(
      callJson: call.toJson(),
      timestampMs: call.timestampMs,
      perEngine: call.perEngine,
      aggregateMetricKey: 'total_bytes',
      historyMetricKey: 'bytes',
      cooldownConfig: cooldownConfig,
    );
  }

  Future<List<WebFetchCallLog>> recentCalls({int limit = 50}) async {
    return (await recentRawCalls(
      limit: limit,
    )).map((m) => WebFetchCallLog.fromJson(m)).toList(growable: false);
  }

  Future<Map<AiWebFetchEngineKind, WebFetchEngineStat>> engineStats() async {
    return typedEngineStats(WebFetchEngineStat.fromJson);
  }

  Future<Map<AiWebFetchEngineKind, List<WebFetchEngineSample>>>
  engineHistory() async {
    return typedEngineHistory(
      (m) => WebFetchEngineSample(
        timestampMs: webEngineNonNegativeIntFromValue(m['ts']),
        durationMs: webEngineNonNegativeIntFromValue(m['dur']),
        success: m['ok'] == true,
        contentBytes: webEngineNonNegativeIntFromValue(m['bytes']),
      ),
    );
  }
}

class WebFetchCallLog {
  const WebFetchCallLog({
    required this.timestampMs,
    required this.url,
    required this.cacheStatus,
    required this.success,
    required this.totalDurationMs,
    required this.contentChars,
    required this.fallbackUsed,
    required this.perEngine,
    this.errorMessage,
    this.winningEngine,
  });

  factory WebFetchCallLog.fromJson(Map<String, Object?> m) {
    final perEngine = stringKeyedMapListFromValue(
      m['per_engine'],
    ).map(WebFetchPerEngineLog.fromJson).toList(growable: false);
    final winning = enumByName(
      AiWebFetchEngineKind.values,
      m['winning_engine'],
    );
    return WebFetchCallLog(
      timestampMs: webEngineNonNegativeIntFromValue(m['timestamp_ms']),
      url: '${m['url'] ?? ''}',
      cacheStatus: '${m['cache_status'] ?? ''}',
      success: m['success'] == true,
      totalDurationMs: webEngineNonNegativeIntFromValue(m['total_duration_ms']),
      contentChars: webEngineNonNegativeIntFromValue(m['content_chars']),
      fallbackUsed: m['fallback_used'] == true,
      errorMessage: optionalStringFromValue(m['error_message']),
      winningEngine: winning,
      perEngine: perEngine,
    );
  }

  final int timestampMs;
  final String url;

  /// 取值同 metadata.webfetch_cache：`hit` / `miss-stored` / `disabled` / `bypass`
  final String cacheStatus;
  final bool success;
  final int totalDurationMs;
  final int contentChars;
  final bool fallbackUsed;
  final String? errorMessage;
  final AiWebFetchEngineKind? winningEngine;
  final List<WebFetchPerEngineLog> perEngine;

  Map<String, Object?> toJson() => {
    'timestamp_ms': timestampMs,
    'url': url,
    'cache_status': cacheStatus,
    'success': success,
    'total_duration_ms': totalDurationMs,
    'content_chars': contentChars,
    'fallback_used': fallbackUsed,
    if (errorMessage != null) 'error_message': errorMessage,
    if (winningEngine != null) 'winning_engine': winningEngine!.name,
    'per_engine': perEngine.map((e) => e.toJson()).toList(growable: false),
  };
}

class WebFetchPerEngineLog implements WebEngineMetricCall {
  const WebFetchPerEngineLog({
    required this.kind,
    required this.success,
    required this.contentBytes,
    required this.elapsedMs,
    this.error,
  });

  factory WebFetchPerEngineLog.fromJson(Map<String, Object?> m) {
    final kind = enumByNameOr(
      AiWebFetchEngineKind.values,
      m['kind'],
      fallback: AiWebFetchEngineKind.values.first,
    );
    return WebFetchPerEngineLog(
      kind: kind,
      success: m['success'] == true,
      contentBytes: webEngineNonNegativeIntFromValue(m['content_bytes']),
      elapsedMs: webEngineNonNegativeIntFromValue(m['elapsed_ms']),
      error: optionalStringFromValue(m['error']),
    );
  }

  final AiWebFetchEngineKind kind;
  @override
  final bool success;
  final int contentBytes;
  @override
  final int elapsedMs;
  @override
  final String? error;

  @override
  String get kindName => kind.name;

  @override
  int get metricValue => contentBytes;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'success': success,
    'content_bytes': contentBytes,
    'elapsed_ms': elapsedMs,
    if (error != null) 'error': error,
  };
}

class WebFetchEngineStat extends WebEngineStatBase {
  const WebFetchEngineStat({
    required super.totalCalls,
    required super.successCalls,
    required super.totalDurationMs,
    required this.totalBytes,
    super.lastError,
    super.lastFailureAt,
    super.lastInvokedAt,
    super.consecutiveFailures,
    super.cooldownUntilMs,
    super.lastQuotaError,
    super.lastQuotaAt,
  });

  factory WebFetchEngineStat.fromJson(Map<String, Object?> m) =>
      WebFetchEngineStat._fromJson(m);

  WebFetchEngineStat._fromJson(super.json)
    : totalBytes = webEngineNonNegativeIntFromValue(json['total_bytes']),
      super.fromJson();

  final int totalBytes;
}

class WebFetchEngineSample extends WebEngineSampleBase {
  const WebFetchEngineSample({
    required super.timestampMs,
    required super.durationMs,
    required super.success,
    required this.contentBytes,
  });

  final int contentBytes;
}
