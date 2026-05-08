import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../model/ai_web_search_settings.dart';

/// WebSearch 调用日志 + 引擎健康度的本地持久化存储。
///
/// 目录：`~/.openhand/cache/web_search/telemetry/`
///   * `calls.json`   —— 最近 N 条调用日志（FIFO，[maxRecentCalls] 上限）。
///   * `engines.json` —— 每引擎累计统计 { totalCalls, successCalls,
///                        totalDurationMs, lastError, lastFailureAt }。
///
/// 读写经过同一 `_chain` 串行，保证不会与 [WebSearchCacheStore] 互踩。
class WebSearchTelemetryStore {
  WebSearchTelemetryStore._();

  static final WebSearchTelemetryStore instance = WebSearchTelemetryStore._();

  /// 调用日志 ring buffer 上限。超过后裁掉最旧的若干条。
  static const int maxRecentCalls = 200;

  Future<void> _chain = Future.value();

  static String defaultDirectoryPath() => p.join(
        OpenHandPaths.defaultCacheDirectoryPath(),
        'web_search',
        'telemetry',
      );

  /// 记录一次完整调用：把 call log 追加到 calls.json，并把 perEngine 增量
  /// 折叠到 engines.json。永不抛异常，全部失败 silentLog。
  Future<void> recordCall(WebSearchCallLog call) async {
    _chain = _chain.then((_) => _writeCall(call)).catchError((
      Object error,
      StackTrace stack,
    ) {
      silentLog('web_search_telemetry', 'recordCall', error, stack);
    });
    await _chain;
  }

  Future<List<WebSearchCallLog>> recentCalls({int limit = 50}) async {
    final f = File(p.join(defaultDirectoryPath(), 'calls.json'));
    if (!await f.exists()) return const [];
    try {
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final list = decoded
          .whereType<Map>()
          .map((m) => WebSearchCallLog.fromJson(Map<String, Object?>.from(m)))
          .toList(growable: false);
      // 文件存的是 append 顺序（最旧→最新），UI 多半要按新→旧展示。
      final reversed = list.reversed.toList(growable: false);
      if (reversed.length <= limit) return reversed;
      return reversed.sublist(0, limit);
    } catch (error, stack) {
      silentLog('web_search_telemetry', 'recentCalls', error, stack);
      return const [];
    }
  }

  Future<Map<AiWebSearchEngineKind, WebSearchEngineStat>> engineStats() async {
    final f = File(p.join(defaultDirectoryPath(), 'engines.json'));
    if (!await f.exists()) return const {};
    try {
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <AiWebSearchEngineKind, WebSearchEngineStat>{};
      for (final entry in decoded.entries) {
        final kind = _parseKind('${entry.key}');
        if (kind == null) continue;
        if (entry.value is! Map) continue;
        out[kind] = WebSearchEngineStat.fromJson(
          Map<String, Object?>.from(entry.value as Map),
        );
      }
      return out;
    } catch (error, stack) {
      silentLog('web_search_telemetry', 'engineStats', error, stack);
      return const {};
    }
  }

  Future<void> clearAll() async {
    _chain = _chain.then((_) async {
      final dir = Directory(defaultDirectoryPath());
      if (!await dir.exists()) return;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          await entity.delete(recursive: true);
        }
      } catch (error, stack) {
        silentLog('web_search_telemetry', 'clearAll', error, stack);
      }
    });
    await _chain;
  }

  // ---------------------------------------------------------------------------

  Future<void> _writeCall(WebSearchCallLog call) async {
    final dir = Directory(defaultDirectoryPath());
    if (!await dir.exists()) await dir.create(recursive: true);

    // 1) 追加 calls.json
    final callsFile = File(p.join(dir.path, 'calls.json'));
    final calls = <Map<String, Object?>>[];
    if (await callsFile.exists()) {
      try {
        final raw = await callsFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              calls.add(Map<String, Object?>.from(item));
            }
          }
        }
      } catch (_) {/* corrupted: 抛弃 */}
    }
    calls.add(call.toJson());
    if (calls.length > maxRecentCalls) {
      calls.removeRange(0, calls.length - maxRecentCalls);
    }
    await callsFile.writeAsString(jsonEncode(calls), flush: true);

    // 2) 折叠 engines.json
    final enginesFile = File(p.join(dir.path, 'engines.json'));
    final agg = <String, Map<String, Object?>>{};
    if (await enginesFile.exists()) {
      try {
        final raw = await enginesFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is Map) {
              agg['${entry.key}'] =
                  Map<String, Object?>.from(entry.value as Map);
            }
          }
        }
      } catch (_) {/* corrupted: 重建 */}
    }
    for (final per in call.perEngine) {
      final key = per.kind.name;
      final cur = agg[key] ?? <String, Object?>{};
      final totalCalls = ((cur['total_calls'] as num?)?.toInt() ?? 0) + 1;
      final successCalls =
          ((cur['success_calls'] as num?)?.toInt() ?? 0) + (per.success ? 1 : 0);
      final totalDur =
          ((cur['total_duration_ms'] as num?)?.toInt() ?? 0) + per.elapsedMs;
      final totalHits =
          ((cur['total_hits'] as num?)?.toInt() ?? 0) + per.hitCount;
      final updated = <String, Object?>{
        'total_calls': totalCalls,
        'success_calls': successCalls,
        'total_duration_ms': totalDur,
        'total_hits': totalHits,
        'last_invoked_at': call.timestampMs,
      };
      if (!per.success) {
        updated['last_error'] = per.error ?? cur['last_error'];
        updated['last_failure_at'] = call.timestampMs;
      } else {
        updated['last_error'] = cur['last_error'];
        updated['last_failure_at'] = cur['last_failure_at'];
      }
      agg[key] = updated;
    }
    await enginesFile.writeAsString(jsonEncode(agg), flush: true);
  }

  AiWebSearchEngineKind? _parseKind(String name) {
    for (final k in AiWebSearchEngineKind.values) {
      if (k.name == name) return k;
    }
    return null;
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
    final perEngineRaw = m['per_engine'];
    final perEngine = perEngineRaw is List
        ? perEngineRaw
            .whereType<Map>()
            .map((e) =>
                WebSearchPerEngineLog.fromJson(Map<String, Object?>.from(e)))
            .toList(growable: false)
        : const <WebSearchPerEngineLog>[];
    return WebSearchCallLog(
      timestampMs: (m['timestamp_ms'] as num?)?.toInt() ?? 0,
      query: '${m['query'] ?? ''}',
      cacheStatus: '${m['cache_status'] ?? ''}',
      success: m['success'] == true,
      totalDurationMs: (m['total_duration_ms'] as num?)?.toInt() ?? 0,
      mergedHitCount: (m['merged_hit_count'] as num?)?.toInt() ?? 0,
      fallbackUsed: m['fallback_used'] == true,
      summaryChars: (m['summary_chars'] as num?)?.toInt() ?? 0,
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
      hitCount: (m['hit_count'] as num?)?.toInt() ?? 0,
      elapsedMs: (m['elapsed_ms'] as num?)?.toInt() ?? 0,
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
  });

  factory WebSearchEngineStat.fromJson(Map<String, Object?> m) =>
      WebSearchEngineStat(
        totalCalls: (m['total_calls'] as num?)?.toInt() ?? 0,
        successCalls: (m['success_calls'] as num?)?.toInt() ?? 0,
        totalDurationMs: (m['total_duration_ms'] as num?)?.toInt() ?? 0,
        totalHits: (m['total_hits'] as num?)?.toInt() ?? 0,
        lastError: m['last_error'] as String?,
        lastFailureAt: (m['last_failure_at'] as num?)?.toInt(),
        lastInvokedAt: (m['last_invoked_at'] as num?)?.toInt(),
      );

  final int totalCalls;
  final int successCalls;
  final int totalDurationMs;
  final int totalHits;
  final String? lastError;
  final int? lastFailureAt;
  final int? lastInvokedAt;

  double get successRate => totalCalls == 0 ? 0 : successCalls / totalCalls;
  double get avgDurationMs =>
      totalCalls == 0 ? 0 : totalDurationMs / totalCalls;
}
