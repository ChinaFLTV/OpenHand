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

  /// 单引擎采样历史上限（趋势图用）。
  static const int maxEngineHistorySamples = 200;

  /// 连续失败 N 次后进入 cooldown，以下为分级时长（毫秒）。
  static const int _cooldownStep1Ms = 60 * 1000; // 3 次 → 1 分钟
  static const int _cooldownStep2Ms = 5 * 60 * 1000; // 5 次 → 5 分钟
  static const int _cooldownStep3Ms = 15 * 60 * 1000; // 7+ 次 → 15 分钟

  /// 显式 quota / 429 / rate limit 错误的固定 cooldown。
  static const int _quotaCooldownMs = 5 * 60 * 1000;

  static final RegExp _quotaErrorPattern = RegExp(
    r'\b(429|too many requests|rate[\s_-]?limit|quota|exceeded|throttl)\b',
    caseSensitive: false,
  );

  /// 判断 engine 错误信息是否属于配额/限流类。
  static bool looksLikeQuotaError(String? message) {
    if (message == null || message.isEmpty) return false;
    return _quotaErrorPattern.hasMatch(message);
  }

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

      // 连续失败计数 → 失败自动降级（cooldown）。
      var consecFail = (cur['consecutive_failures'] as num?)?.toInt() ?? 0;
      int? cooldownUntilMs = (cur['cooldown_until_ms'] as num?)?.toInt();
      String? lastQuotaError = cur['last_quota_error'] as String?;
      int? lastQuotaAt = (cur['last_quota_at'] as num?)?.toInt();
      if (per.success) {
        consecFail = 0;
        cooldownUntilMs = null; // 一次成功立即清掉 cooldown
      } else {
        consecFail += 1;
        if (looksLikeQuotaError(per.error)) {
          lastQuotaError = per.error;
          lastQuotaAt = call.timestampMs;
          cooldownUntilMs = call.timestampMs + _quotaCooldownMs;
        } else if (consecFail >= 7) {
          cooldownUntilMs = call.timestampMs + _cooldownStep3Ms;
        } else if (consecFail >= 5) {
          cooldownUntilMs = call.timestampMs + _cooldownStep2Ms;
        } else if (consecFail >= 3) {
          cooldownUntilMs = call.timestampMs + _cooldownStep1Ms;
        }
      }

      final updated = <String, Object?>{
        'total_calls': totalCalls,
        'success_calls': successCalls,
        'total_duration_ms': totalDur,
        'total_hits': totalHits,
        'last_invoked_at': call.timestampMs,
        'consecutive_failures': consecFail,
        if (cooldownUntilMs != null) 'cooldown_until_ms': cooldownUntilMs,
        if (lastQuotaError != null) 'last_quota_error': lastQuotaError,
        if (lastQuotaAt != null) 'last_quota_at': lastQuotaAt,
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

    // 3) 追加 engine_history.json（每引擎 200 个采样，趋势图用）。
    if (call.perEngine.isNotEmpty) {
      final histFile = File(p.join(dir.path, 'engine_history.json'));
      final hist = <String, List<Map<String, Object?>>>{};
      if (await histFile.exists()) {
        try {
          final raw = await histFile.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              if (entry.value is List) {
                hist['${entry.key}'] = (entry.value as List)
                    .whereType<Map>()
                    .map((m) => Map<String, Object?>.from(m))
                    .toList();
              }
            }
          }
        } catch (_) {/* corrupted */}
      }
      for (final per in call.perEngine) {
        final key = per.kind.name;
        final list = hist[key] ?? <Map<String, Object?>>[];
        list.add(<String, Object?>{
          'ts': call.timestampMs,
          'dur': per.elapsedMs,
          'ok': per.success,
          'hits': per.hitCount,
        });
        if (list.length > maxEngineHistorySamples) {
          list.removeRange(0, list.length - maxEngineHistorySamples);
        }
        hist[key] = list;
      }
      await histFile.writeAsString(jsonEncode(hist), flush: true);
    }
  }

  /// 读取 engine_history.json，按引擎返回采样列表（按时间升序）。
  Future<Map<AiWebSearchEngineKind, List<WebSearchEngineSample>>>
      engineHistory() async {
    final f = File(p.join(defaultDirectoryPath(), 'engine_history.json'));
    if (!await f.exists()) return const {};
    try {
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <AiWebSearchEngineKind, List<WebSearchEngineSample>>{};
      for (final entry in decoded.entries) {
        final kind = _parseKind('${entry.key}');
        if (kind == null) continue;
        if (entry.value is! List) continue;
        out[kind] = (entry.value as List)
            .whereType<Map>()
            .map((m) => WebSearchEngineSample(
                  timestampMs: (m['ts'] as num?)?.toInt() ?? 0,
                  durationMs: (m['dur'] as num?)?.toInt() ?? 0,
                  success: m['ok'] == true,
                  hitCount: (m['hits'] as num?)?.toInt() ?? 0,
                ))
            .toList(growable: false);
      }
      return out;
    } catch (error, stack) {
      silentLog('web_search_telemetry', 'engineHistory', error, stack);
      return const {};
    }
  }

  /// orchestrator 用：判断某引擎当前是否处于 cooldown（暂停调用）。
  /// 返回剩余毫秒数；0 表示可调用。
  Future<int> cooldownRemaining(AiWebSearchEngineKind kind) async {
    final stats = await engineStats();
    final s = stats[kind];
    if (s == null) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = s.cooldownUntilMs ?? 0;
    return until > now ? (until - now) : 0;
  }

  /// 手动清掉某引擎的 cooldown（用于设置 UI 上的"重置"动作）。
  Future<void> clearEngineCooldown(AiWebSearchEngineKind kind) async {
    _chain = _chain.then((_) async {
      final f = File(p.join(defaultDirectoryPath(), 'engines.json'));
      if (!await f.exists()) return;
      try {
        final raw = await f.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return;
        final agg = <String, Map<String, Object?>>{};
        for (final entry in decoded.entries) {
          if (entry.value is Map) {
            agg['${entry.key}'] = Map<String, Object?>.from(entry.value as Map);
          }
        }
        final cur = agg[kind.name];
        if (cur == null) return;
        cur.remove('cooldown_until_ms');
        cur['consecutive_failures'] = 0;
        agg[kind.name] = cur;
        await f.writeAsString(jsonEncode(agg), flush: true);
      } catch (error, stack) {
        silentLog('web_search_telemetry', 'clearEngineCooldown', error, stack);
      }
    });
    await _chain;
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
    this.consecutiveFailures = 0,
    this.cooldownUntilMs,
    this.lastQuotaError,
    this.lastQuotaAt,
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
        consecutiveFailures:
            (m['consecutive_failures'] as num?)?.toInt() ?? 0,
        cooldownUntilMs: (m['cooldown_until_ms'] as num?)?.toInt(),
        lastQuotaError: m['last_quota_error'] as String?,
        lastQuotaAt: (m['last_quota_at'] as num?)?.toInt(),
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
