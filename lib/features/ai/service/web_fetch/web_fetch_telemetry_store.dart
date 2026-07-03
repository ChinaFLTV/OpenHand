import 'dart:async';

import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../web_engine/web_engine_telemetry_store_base.dart';

/// WebFetch 调用日志 + 引擎健康度的本地持久化存储。
///
/// 公共骨架由 [WebEngineTelemetryStoreBase] 接管；本类只负责领域 typed 包装
/// 和 perEngine 拍平（`total_bytes` / `bytes` 走"领域累加器"通道）。
class WebFetchTelemetryStore
    extends WebEngineTelemetryStoreBase<AiWebFetchEngineKind> {
  WebFetchTelemetryStore._();

  static final WebFetchTelemetryStore instance = WebFetchTelemetryStore._();

  static const int maxRecentCalls = 200;
  static const int maxEngineHistorySamples = 200;

  @override
  String get subdir => 'web_fetch';

  @override
  String get logTag => 'web_fetch_telemetry';

  @override
  List<AiWebFetchEngineKind> get kindValues => AiWebFetchEngineKind.values;

  @override
  AiWebFetchEngineKind? parseKind(String name) {
    for (final k in AiWebFetchEngineKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  Future<void> recordCall(WebFetchCallLog call) {
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
              aggregateBumps: <String, num>{'total_bytes': per.contentBytes},
              historyExtras: <String, Object?>{'bytes': per.contentBytes},
            ),
          )
          .toList(growable: false),
    );
  }

  Future<List<WebFetchCallLog>> recentCalls({int limit = 50}) async {
    return (await recentRawCalls(
      limit: limit,
    )).map((m) => WebFetchCallLog.fromJson(m)).toList(growable: false);
  }

  Future<Map<AiWebFetchEngineKind, WebFetchEngineStat>> engineStats() async {
    final raw = await rawEngineStats();
    final out = <AiWebFetchEngineKind, WebFetchEngineStat>{};
    for (final entry in raw.entries) {
      final kind = parseKind(entry.key);
      if (kind == null) continue;
      out[kind] = WebFetchEngineStat.fromJson(entry.value);
    }
    return out;
  }

  Future<Map<AiWebFetchEngineKind, List<WebFetchEngineSample>>>
  engineHistory() async {
    final raw = await rawEngineHistory();
    final out = <AiWebFetchEngineKind, List<WebFetchEngineSample>>{};
    for (final entry in raw.entries) {
      final kind = parseKind(entry.key);
      if (kind == null) continue;
      out[kind] = entry.value
          .map(
            (m) => WebFetchEngineSample(
              timestampMs: _readTelemetryInt(m['ts']),
              durationMs: _readTelemetryInt(m['dur']),
              success: m['ok'] == true,
              contentBytes: _readTelemetryInt(m['bytes']),
            ),
          )
          .toList(growable: false);
    }
    return out;
  }
}

typedef WebFetchCooldownConfig = WebEngineCooldownConfig;

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
    final perEngineRaw = m['per_engine'];
    final perEngine = perEngineRaw is List
        ? perEngineRaw
              .whereType<Map>()
              .map(
                (e) =>
                    WebFetchPerEngineLog.fromJson(stringKeyedMapFromValue(e)),
              )
              .toList(growable: false)
        : const <WebFetchPerEngineLog>[];
    final winningRaw = '${m['winning_engine'] ?? ''}'.trim();
    final winning = winningRaw.isEmpty
        ? null
        : AiWebFetchEngineKind.values
              .where((k) => k.name == winningRaw)
              .firstOrNull;
    return WebFetchCallLog(
      timestampMs: _readTelemetryInt(m['timestamp_ms']),
      url: '${m['url'] ?? ''}',
      cacheStatus: '${m['cache_status'] ?? ''}',
      success: m['success'] == true,
      totalDurationMs: _readTelemetryInt(m['total_duration_ms']),
      contentChars: _readTelemetryInt(m['content_chars']),
      fallbackUsed: m['fallback_used'] == true,
      errorMessage: m['error_message'] as String?,
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

class WebFetchPerEngineLog {
  const WebFetchPerEngineLog({
    required this.kind,
    required this.success,
    required this.contentBytes,
    required this.elapsedMs,
    this.error,
  });

  factory WebFetchPerEngineLog.fromJson(Map<String, Object?> m) {
    final kind = AiWebFetchEngineKind.values.firstWhere(
      (k) => k.name == '${m['kind'] ?? ''}',
      orElse: () => AiWebFetchEngineKind.values.first,
    );
    return WebFetchPerEngineLog(
      kind: kind,
      success: m['success'] == true,
      contentBytes: _readTelemetryInt(m['content_bytes']),
      elapsedMs: _readTelemetryInt(m['elapsed_ms']),
      error: m['error'] as String?,
    );
  }

  final AiWebFetchEngineKind kind;
  final bool success;
  final int contentBytes;
  final int elapsedMs;
  final String? error;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'success': success,
    'content_bytes': contentBytes,
    'elapsed_ms': elapsedMs,
    if (error != null) 'error': error,
  };
}

class WebFetchEngineStat {
  const WebFetchEngineStat({
    required this.totalCalls,
    required this.successCalls,
    required this.totalDurationMs,
    required this.totalBytes,
    this.lastError,
    this.lastFailureAt,
    this.lastInvokedAt,
    this.consecutiveFailures = 0,
    this.cooldownUntilMs,
    this.lastQuotaError,
    this.lastQuotaAt,
  });

  factory WebFetchEngineStat.fromJson(Map<String, Object?> m) =>
      WebFetchEngineStat(
        totalCalls: _readTelemetryInt(m['total_calls']),
        successCalls: _readTelemetryInt(m['success_calls']),
        totalDurationMs: _readTelemetryInt(m['total_duration_ms']),
        totalBytes: _readTelemetryInt(m['total_bytes']),
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
  final int totalBytes;
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

class WebFetchEngineSample {
  const WebFetchEngineSample({
    required this.timestampMs,
    required this.durationMs,
    required this.success,
    required this.contentBytes,
  });

  final int timestampMs;
  final int durationMs;
  final bool success;
  final int contentBytes;
}

int _readTelemetryInt(Object? value) {
  return nonNegativeIntFromValue(value, fallback: 0);
}

int? _readOptionalTelemetryInt(Object? value) {
  return optionalNonNegativeIntFromValue(value);
}
