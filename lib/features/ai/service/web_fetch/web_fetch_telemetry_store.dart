import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../model/ai_web_fetch_settings.dart';

/// WebFetch 调用日志 + 引擎健康度的本地持久化存储。
///
/// 目录：`~/.openhand/cache/web_fetch/telemetry/`
///   * `calls.json`           — 最近 N 条调用日志（FIFO）。
///   * `engines.json`         — 每引擎累计统计与 cooldown 状态。
///   * `engine_history.json`  — 每引擎采样列表（趋势图用）。
///
/// 与 [WebFetchCacheStore] 共用 `~/.openhand/cache/web_fetch/` 根，但写入互不冲突
/// （子目录隔离 + 内部 `_chain` 串行）。
class WebFetchTelemetryStore {
  WebFetchTelemetryStore._();

  static final WebFetchTelemetryStore instance = WebFetchTelemetryStore._();

  static const int maxRecentCalls = 200;
  static const int maxEngineHistorySamples = 200;

  /// orchestrator 在每次 run() 之前用 [setCooldownConfig] 推一份当前 settings
  /// 的阈值进来；默认值与 WebSearch 一致。
  WebFetchCooldownConfig cooldownConfig = const WebFetchCooldownConfig();

  static final RegExp _quotaErrorPattern = RegExp(
    r'\b(429|too many requests|rate[\s_-]?limit|quota|exceeded|throttl)\b',
    caseSensitive: false,
  );

  static bool looksLikeQuotaError(String? message) {
    if (message == null || message.isEmpty) return false;
    return _quotaErrorPattern.hasMatch(message);
  }

  Future<void> _chain = Future.value();

  static String defaultDirectoryPath() => p.join(
        OpenHandPaths.defaultCacheDirectoryPath(),
        'web_fetch',
        'telemetry',
      );

  Future<void> recordCall(WebFetchCallLog call) async {
    _chain = _chain.then((_) => _writeCall(call)).catchError((
      Object error,
      StackTrace stack,
    ) {
      silentLog('web_fetch_telemetry', 'recordCall', error, stack);
    });
    await _chain;
  }

  Future<List<WebFetchCallLog>> recentCalls({int limit = 50}) async {
    final f = File(p.join(defaultDirectoryPath(), 'calls.json'));
    if (!await f.exists()) return const [];
    try {
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final list = decoded
          .whereType<Map>()
          .map((m) => WebFetchCallLog.fromJson(Map<String, Object?>.from(m)))
          .toList(growable: false);
      final reversed = list.reversed.toList(growable: false);
      if (reversed.length <= limit) return reversed;
      return reversed.sublist(0, limit);
    } catch (error, stack) {
      silentLog('web_fetch_telemetry', 'recentCalls', error, stack);
      return const [];
    }
  }

  Future<Map<AiWebFetchEngineKind, WebFetchEngineStat>> engineStats() async {
    final f = File(p.join(defaultDirectoryPath(), 'engines.json'));
    if (!await f.exists()) return const {};
    try {
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <AiWebFetchEngineKind, WebFetchEngineStat>{};
      for (final entry in decoded.entries) {
        final kind = _parseKind('${entry.key}');
        if (kind == null) continue;
        if (entry.value is! Map) continue;
        out[kind] = WebFetchEngineStat.fromJson(
          Map<String, Object?>.from(entry.value as Map),
        );
      }
      return out;
    } catch (error, stack) {
      silentLog('web_fetch_telemetry', 'engineStats', error, stack);
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
        silentLog('web_fetch_telemetry', 'clearAll', error, stack);
      }
    });
    await _chain;
  }

  Future<void> _writeCall(WebFetchCallLog call) async {
    final dir = Directory(defaultDirectoryPath());
    if (!await dir.exists()) await dir.create(recursive: true);

    // 1) calls.json
    final callsFile = File(p.join(dir.path, 'calls.json'));
    final calls = <Map<String, Object?>>[];
    if (await callsFile.exists()) {
      try {
        final raw = await callsFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) calls.add(Map<String, Object?>.from(item));
          }
        }
      } catch (_) {/* corrupted: drop */}
    }
    calls.add(call.toJson());
    if (calls.length > maxRecentCalls) {
      calls.removeRange(0, calls.length - maxRecentCalls);
    }
    await callsFile.writeAsString(jsonEncode(calls), flush: true);

    // 2) engines.json
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
      } catch (_) {/* corrupted: rebuild */}
    }
    for (final per in call.perEngine) {
      final key = per.kind.name;
      final cur = agg[key] ?? <String, Object?>{};
      final totalCalls = ((cur['total_calls'] as num?)?.toInt() ?? 0) + 1;
      final successCalls =
          ((cur['success_calls'] as num?)?.toInt() ?? 0) +
              (per.success ? 1 : 0);
      final totalDur =
          ((cur['total_duration_ms'] as num?)?.toInt() ?? 0) + per.elapsedMs;
      final totalBytes =
          ((cur['total_bytes'] as num?)?.toInt() ?? 0) + per.contentBytes;

      var consecFail = (cur['consecutive_failures'] as num?)?.toInt() ?? 0;
      int? cooldownUntilMs = (cur['cooldown_until_ms'] as num?)?.toInt();
      String? lastQuotaError = cur['last_quota_error'] as String?;
      int? lastQuotaAt = (cur['last_quota_at'] as num?)?.toInt();
      if (per.success) {
        consecFail = 0;
        cooldownUntilMs = null;
      } else {
        consecFail += 1;
        final cfg = cooldownConfig;
        if (looksLikeQuotaError(per.error)) {
          lastQuotaError = per.error;
          lastQuotaAt = call.timestampMs;
          cooldownUntilMs = call.timestampMs + cfg.quotaSeconds * 1000;
        } else if (consecFail >= cfg.tier3Failures) {
          cooldownUntilMs = call.timestampMs + cfg.tier3Seconds * 1000;
        } else if (consecFail >= cfg.tier2Failures) {
          cooldownUntilMs = call.timestampMs + cfg.tier2Seconds * 1000;
        } else if (consecFail >= cfg.tier1Failures) {
          cooldownUntilMs = call.timestampMs + cfg.tier1Seconds * 1000;
        }
      }

      final updated = <String, Object?>{
        'total_calls': totalCalls,
        'success_calls': successCalls,
        'total_duration_ms': totalDur,
        'total_bytes': totalBytes,
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

    // 3) engine_history.json
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
          'bytes': per.contentBytes,
        });
        if (list.length > maxEngineHistorySamples) {
          list.removeRange(0, list.length - maxEngineHistorySamples);
        }
        hist[key] = list;
      }
      await histFile.writeAsString(jsonEncode(hist), flush: true);
    }
  }

  Future<Map<AiWebFetchEngineKind, List<WebFetchEngineSample>>>
      engineHistory() async {
    final f = File(p.join(defaultDirectoryPath(), 'engine_history.json'));
    if (!await f.exists()) return const {};
    try {
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <AiWebFetchEngineKind, List<WebFetchEngineSample>>{};
      for (final entry in decoded.entries) {
        final kind = _parseKind('${entry.key}');
        if (kind == null) continue;
        if (entry.value is! List) continue;
        out[kind] = (entry.value as List)
            .whereType<Map>()
            .map((m) => WebFetchEngineSample(
                  timestampMs: (m['ts'] as num?)?.toInt() ?? 0,
                  durationMs: (m['dur'] as num?)?.toInt() ?? 0,
                  success: m['ok'] == true,
                  contentBytes: (m['bytes'] as num?)?.toInt() ?? 0,
                ))
            .toList(growable: false);
      }
      return out;
    } catch (error, stack) {
      silentLog('web_fetch_telemetry', 'engineHistory', error, stack);
      return const {};
    }
  }

  Future<int> cooldownRemaining(AiWebFetchEngineKind kind) async {
    final stats = await engineStats();
    final s = stats[kind];
    if (s == null) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = s.cooldownUntilMs ?? 0;
    return until > now ? (until - now) : 0;
  }

  Future<void> clearEngineCooldown(AiWebFetchEngineKind kind) async {
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
            agg['${entry.key}'] =
                Map<String, Object?>.from(entry.value as Map);
          }
        }
        final cur = agg[kind.name];
        if (cur == null) return;
        cur.remove('cooldown_until_ms');
        cur['consecutive_failures'] = 0;
        agg[kind.name] = cur;
        await f.writeAsString(jsonEncode(agg), flush: true);
      } catch (error, stack) {
        silentLog('web_fetch_telemetry', 'clearEngineCooldown', error, stack);
      }
    });
    await _chain;
  }

  AiWebFetchEngineKind? _parseKind(String name) {
    for (final k in AiWebFetchEngineKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  Future<int> callsInLastMinute(AiWebFetchEngineKind kind) async {
    final hist = await engineHistory();
    final samples = hist[kind];
    if (samples == null || samples.isEmpty) return 0;
    final cutoff = DateTime.now().millisecondsSinceEpoch - 60 * 1000;
    var count = 0;
    for (final s in samples) {
      if (s.timestampMs >= cutoff) count++;
    }
    return count;
  }
}

class WebFetchCooldownConfig {
  const WebFetchCooldownConfig({
    this.tier1Failures = 3,
    this.tier1Seconds = 60,
    this.tier2Failures = 5,
    this.tier2Seconds = 300,
    this.tier3Failures = 7,
    this.tier3Seconds = 900,
    this.quotaSeconds = 300,
  });

  final int tier1Failures;
  final int tier1Seconds;
  final int tier2Failures;
  final int tier2Seconds;
  final int tier3Failures;
  final int tier3Seconds;
  final int quotaSeconds;
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
    final perEngineRaw = m['per_engine'];
    final perEngine = perEngineRaw is List
        ? perEngineRaw
            .whereType<Map>()
            .map((e) =>
                WebFetchPerEngineLog.fromJson(Map<String, Object?>.from(e)))
            .toList(growable: false)
        : const <WebFetchPerEngineLog>[];
    final winningRaw = '${m['winning_engine'] ?? ''}'.trim();
    final winning = winningRaw.isEmpty
        ? null
        : AiWebFetchEngineKind.values
            .where((k) => k.name == winningRaw)
            .firstOrNull;
    return WebFetchCallLog(
      timestampMs: (m['timestamp_ms'] as num?)?.toInt() ?? 0,
      url: '${m['url'] ?? ''}',
      cacheStatus: '${m['cache_status'] ?? ''}',
      success: m['success'] == true,
      totalDurationMs: (m['total_duration_ms'] as num?)?.toInt() ?? 0,
      contentChars: (m['content_chars'] as num?)?.toInt() ?? 0,
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
      contentBytes: (m['content_bytes'] as num?)?.toInt() ?? 0,
      elapsedMs: (m['elapsed_ms'] as num?)?.toInt() ?? 0,
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
        totalCalls: (m['total_calls'] as num?)?.toInt() ?? 0,
        successCalls: (m['success_calls'] as num?)?.toInt() ?? 0,
        totalDurationMs: (m['total_duration_ms'] as num?)?.toInt() ?? 0,
        totalBytes: (m['total_bytes'] as num?)?.toInt() ?? 0,
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
