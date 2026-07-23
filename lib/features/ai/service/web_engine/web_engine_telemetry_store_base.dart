import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/input_value_parsing.dart';
import 'web_engine_persistence_io.dart';
import 'web_engine_value_parsing.dart';

/// WebSearch / WebFetch 调用日志的共用 cooldown 阈值配置。
///
/// 两个领域的策略完全一致（Tier1/2/3 + Quota），统一成同一个类，以 typedef
/// 暴露给原有名字 `WebSearchCooldownConfig` / `WebFetchCooldownConfig`。
class WebEngineCooldownConfig {
  const WebEngineCooldownConfig({
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

/// 一次 per-engine 调用事件（写日志 + 折叠到 engines.json + 补一条 history 采样）。
///
/// 由各领域的 `recordCall` 在 telemetry 写入前组装：把领域 `WebXPerEngineLog`
/// 拍平成 [kindName] / [success] / [error] / [elapsedMs] + 两个 metadata bag：
///   * [aggregateBumps]  —— 折叠到 engines.json 时把对应 key 累加（如 `total_hits` / `total_bytes`）。
///   * [historyExtras]   —— 写入 engine_history.json 时一并保存（如 `hits` / `bytes`）。
class WebEngineCallEvent {
  const WebEngineCallEvent({
    required this.kindName,
    required this.success,
    required this.elapsedMs,
    this.error,
    this.aggregateBumps = const <String, num>{},
    this.historyExtras = const <String, Object?>{},
  });

  final String kindName;
  final bool success;
  final int elapsedMs;
  final String? error;
  final Map<String, num> aggregateBumps;
  final Map<String, Object?> historyExtras;
}

abstract class WebEngineStatBase {
  const WebEngineStatBase({
    required this.totalCalls,
    required this.successCalls,
    required this.totalDurationMs,
    this.lastError,
    this.lastFailureAt,
    this.lastInvokedAt,
    this.consecutiveFailures = 0,
    this.cooldownUntilMs,
    this.lastQuotaError,
    this.lastQuotaAt,
  });

  WebEngineStatBase.fromJson(Map<String, Object?> json)
    : totalCalls = webEngineNonNegativeIntFromValue(json['total_calls']),
      successCalls = webEngineNonNegativeIntFromValue(json['success_calls']),
      totalDurationMs = webEngineNonNegativeIntFromValue(
        json['total_duration_ms'],
      ),
      lastError = json['last_error'] as String?,
      lastFailureAt = webEngineOptionalNonNegativeIntFromValue(
        json['last_failure_at'],
      ),
      lastInvokedAt = webEngineOptionalNonNegativeIntFromValue(
        json['last_invoked_at'],
      ),
      consecutiveFailures = webEngineNonNegativeIntFromValue(
        json['consecutive_failures'],
      ),
      cooldownUntilMs = webEngineOptionalNonNegativeIntFromValue(
        json['cooldown_until_ms'],
      ),
      lastQuotaError = json['last_quota_error'] as String?,
      lastQuotaAt = webEngineOptionalNonNegativeIntFromValue(
        json['last_quota_at'],
      );

  final int totalCalls;
  final int successCalls;
  final int totalDurationMs;
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

abstract class WebEngineSampleBase {
  const WebEngineSampleBase({
    required this.timestampMs,
    required this.durationMs,
    required this.success,
  });

  final int timestampMs;
  final int durationMs;
  final bool success;
}

/// WebSearch / WebFetch telemetry 持久化的公共骨架：
///
/// * 目录：`<openhand_cache>/<subdir>/telemetry/`
/// * 三份文件：`calls.json` (FIFO log) / `engines.json` (累计 + cooldown) /
///   `engine_history.json` (每引擎 ring buffer，趋势图用)。
/// * `_chain` 串联所有写盘动作；外部 `recordCall` 永不抛异常。
///
/// 子类需要实现：
///   * [subdir] / [logTag] / [kindValues]：领域元信息
///   * [parseKind]：name → TKind?
///
/// 同时维护各自的 typed `CallLog/PerEngineLog/EngineStat/EngineSample` 包装；
/// 写日志统一走 [recordCallRaw]，读日志拿到 raw map 后再做 fromJson。
abstract class WebEngineTelemetryStoreBase<TKind extends Enum> {
  WebEngineTelemetryStoreBase();

  String get subdir;
  String get logTag;
  List<TKind> get kindValues;
  TKind? parseKind(String name);

  Future<void> _chain = Future.value();
  static const int _maxPersistedCalls = 2000;
  static const int _maxPersistedHistorySamples = 2000;

  static final RegExp _quotaErrorPattern = RegExp(
    r'\b(429|too many requests|rate[\s_-]?limit|quota|exceeded|throttl)\b',
    caseSensitive: false,
  );

  /// 判断 engine 错误信息是否属于配额/限流类。
  static bool looksLikeQuotaError(String? message) {
    if (message == null || message.isEmpty) return false;
    return _quotaErrorPattern.hasMatch(message);
  }

  String defaultDirectoryPath() =>
      p.join(OpenHandPaths.defaultCacheDirectoryPath(), subdir, 'telemetry');

  /// 读取 `calls.json` 的原始 entry 数组（按 append 时间升序）。
  /// 调用方负责 reverse + take（旧 API 是返回新→旧）。
  Future<List<Map<String, Object?>>> rawCalls() async {
    final f = File(p.join(defaultDirectoryPath(), 'calls.json'));
    if (!await f.exists()) return const [];
    try {
      final decoded = await readWebEngineJsonFile(f);
      if (decoded is! List) return const [];
      return stringKeyedMapListFromValue(decoded);
    } catch (error, stack) {
      silentLog(logTag, '读取原始调用记录', error, stack);
      return const [];
    }
  }

  /// 读取最近调用，按新 → 旧排序，并统一处理非正 limit。
  Future<List<Map<String, Object?>>> recentRawCalls({int limit = 50}) async {
    if (limit <= 0) return const <Map<String, Object?>>[];
    final reversed = (await rawCalls()).reversed.toList(growable: false);
    if (reversed.length <= limit) return reversed;
    return reversed.sublist(0, limit);
  }

  /// 读取 `engines.json`，返回 `kind.name → entry`。
  Future<Map<String, Map<String, Object?>>> rawEngineStats() async {
    final f = File(p.join(defaultDirectoryPath(), 'engines.json'));
    if (!await f.exists()) return const {};
    try {
      final decoded = await readWebEngineJsonFile(f);
      if (decoded is! Map) return const {};
      final out = <String, Map<String, Object?>>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          out['${entry.key}'] = stringKeyedMapFromValue(entry.value);
        }
      }
      return out;
    } catch (error, stack) {
      silentLog(logTag, '读取原始引擎统计', error, stack);
      return const {};
    }
  }

  /// 读取 `engine_history.json`，返回 `kind.name → 采样数组（map 形式）`。
  Future<Map<String, List<Map<String, Object?>>>> rawEngineHistory() async {
    final f = File(p.join(defaultDirectoryPath(), 'engine_history.json'));
    if (!await f.exists()) return const {};
    try {
      final decoded = await readWebEngineJsonFile(f);
      if (decoded is! Map) return const {};
      final out = <String, List<Map<String, Object?>>>{};
      for (final entry in decoded.entries) {
        if (entry.value is List) {
          out['${entry.key}'] = stringKeyedMapListFromValue(entry.value);
        }
      }
      return out;
    } catch (error, stack) {
      silentLog(logTag, '读取原始引擎历史', error, stack);
      return const {};
    }
  }

  Future<Map<TKind, TStat>> typedEngineStats<TStat>(
    TStat Function(Map<String, Object?> json) decode,
  ) async {
    final result = <TKind, TStat>{};
    for (final entry in (await rawEngineStats()).entries) {
      final kind = parseKind(entry.key);
      if (kind != null) result[kind] = decode(entry.value);
    }
    return result;
  }

  Future<Map<TKind, List<TSample>>> typedEngineHistory<TSample>(
    TSample Function(Map<String, Object?> json) decode,
  ) async {
    final result = <TKind, List<TSample>>{};
    for (final entry in (await rawEngineHistory()).entries) {
      final kind = parseKind(entry.key);
      if (kind == null) continue;
      result[kind] = entry.value.map(decode).toList(growable: false);
    }
    return result;
  }

  Future<void> clearAll() async {
    _chain = _chain.then((_) async {
      final dir = Directory(defaultDirectoryPath());
      if (!await dir.exists()) return;
      try {
        final complete = await clearWebEngineDirectoryBounded(dir);
        if (!complete) {
          throw StateError('Web 引擎遥测清理已达到安全上限。');
        }
      } catch (error, stack) {
        silentLog(logTag, '清理全部遥测记录', error, stack);
      }
    });
    await _chain;
  }

  /// orchestrator 用：判断某引擎当前是否处于 cooldown（暂停调用）。
  /// 返回剩余毫秒数；0 表示可调用。
  Future<int> cooldownRemaining(TKind kind) async {
    final stats = await rawEngineStats();
    final entry = stats[kind.name];
    if (entry == null) return 0;
    final until = webEngineNonNegativeIntFromValue(entry['cooldown_until_ms']);
    final now = DateTime.now().millisecondsSinceEpoch;
    return until > now ? (until - now) : 0;
  }

  /// 手动清掉某引擎的 cooldown（用于设置 UI 上的"重置"动作）。
  Future<void> clearEngineCooldown(TKind kind) async {
    _chain = _chain.then((_) async {
      final f = File(p.join(defaultDirectoryPath(), 'engines.json'));
      if (!await f.exists()) return;
      try {
        final decoded = await readWebEngineJsonFile(f);
        if (decoded is! Map) return;
        final agg = <String, Map<String, Object?>>{};
        for (final entry in decoded.entries) {
          if (entry.value is Map) {
            agg['${entry.key}'] = stringKeyedMapFromValue(entry.value);
          }
        }
        final cur = agg[kind.name];
        if (cur == null) return;
        cur.remove('cooldown_until_ms');
        cur['consecutive_failures'] = 0;
        agg[kind.name] = cur;
        await writeWebEngineJsonFile(f, agg);
      } catch (error, stack) {
        silentLog(logTag, '清理引擎冷却状态', error, stack);
      }
    });
    await _chain;
  }

  /// 返回 [kind] 在最近 60 秒内的调用次数（基于 engine_history.json 时间戳）。
  Future<int> callsInLastMinute(TKind kind) async {
    final hist = await rawEngineHistory();
    final samples = hist[kind.name];
    if (samples == null || samples.isEmpty) return 0;
    final cutoff = DateTime.now().millisecondsSinceEpoch - 60 * 1000;
    var count = 0;
    for (final s in samples) {
      final ts = webEngineNonNegativeIntFromValue(s['ts']);
      if (ts >= cutoff) count++;
    }
    return count;
  }

  // 写入入口（子类的 typed `recordCall(...)` 包装它）
  /// 把一条调用日志（[callJson]）+ per-engine 事件批量写盘：
  /// 1) 追加到 calls.json（FIFO 上限 [maxRecentCalls]）。
  /// 2) 把每个 [perEngine] 折叠到 engines.json：累加 `total_calls/success_calls/
  ///    total_duration_ms` + [WebEngineCallEvent.aggregateBumps]，根据
  ///    [WebEngineCooldownConfig] 决定 cooldown_until_ms。
  /// 3) 追加到 engine_history.json（每引擎 ring buffer 上限 [maxHistorySamples]）。
  ///
  /// 失败完全 silentLog，不抛异常。
  Future<void> recordCallRaw({
    required Map<String, Object?> callJson,
    required int timestampMs,
    required List<WebEngineCallEvent> perEngine,
    required WebEngineCooldownConfig cooldownConfig,
    int maxRecentCalls = 200,
    int maxHistorySamples = 200,
  }) async {
    final retainedCalls = maxRecentCalls.clamp(0, _maxPersistedCalls);
    final retainedHistory = maxHistorySamples.clamp(
      0,
      _maxPersistedHistorySamples,
    );
    _chain = _chain
        .then(
          (_) => _writeCallRaw(
            callJson: callJson,
            timestampMs: timestampMs,
            perEngine: perEngine,
            cooldownConfig: cooldownConfig,
            maxRecentCalls: retainedCalls,
            maxHistorySamples: retainedHistory,
          ),
        )
        .catchError((Object error, StackTrace stack) {
          silentLog(logTag, '记录原始调用', error, stack);
        });
    await _chain;
  }

  Future<void> _writeCallRaw({
    required Map<String, Object?> callJson,
    required int timestampMs,
    required List<WebEngineCallEvent> perEngine,
    required WebEngineCooldownConfig cooldownConfig,
    required int maxRecentCalls,
    required int maxHistorySamples,
  }) async {
    final dir = Directory(defaultDirectoryPath());
    if (!await dir.exists()) await dir.create(recursive: true);

    // 1) calls.json
    final callsFile = File(p.join(dir.path, 'calls.json'));
    final calls = <Map<String, Object?>>[];
    if (await callsFile.exists()) {
      try {
        final decoded = await readWebEngineJsonFile(callsFile);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) calls.add(stringKeyedMapFromValue(item));
          }
        }
      } catch (_) {
        /* corrupted: drop */
      }
    }
    calls.add(_jsonSafeTelemetryMap(callJson));
    _keepNewestEntries(calls, maxRecentCalls);
    await writeWebEngineJsonFile(callsFile, calls);

    // 2) engines.json
    final enginesFile = File(p.join(dir.path, 'engines.json'));
    final agg = <String, Map<String, Object?>>{};
    if (await enginesFile.exists()) {
      try {
        final decoded = await readWebEngineJsonFile(enginesFile);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is Map) {
              agg['${entry.key}'] = stringKeyedMapFromValue(entry.value);
            }
          }
        }
      } catch (_) {
        /* corrupted: rebuild */
      }
    }
    for (final per in perEngine) {
      final key = per.kindName;
      final cur = agg[key] ?? <String, Object?>{};
      final totalCalls =
          webEngineNonNegativeIntFromValue(cur['total_calls']) + 1;
      final successCalls =
          webEngineNonNegativeIntFromValue(cur['success_calls']) +
          (per.success ? 1 : 0);
      final safeElapsedMs = webEngineNonNegativeIntFromValue(per.elapsedMs);
      final totalDur =
          webEngineNonNegativeIntFromValue(cur['total_duration_ms']) +
          safeElapsedMs;

      var consecFail = webEngineNonNegativeIntFromValue(
        cur['consecutive_failures'],
      );
      int? cooldownUntilMs = webEngineOptionalNonNegativeIntFromValue(
        cur['cooldown_until_ms'],
      );
      String? lastQuotaError = cur['last_quota_error'] as String?;
      int? lastQuotaAt = webEngineOptionalNonNegativeIntFromValue(
        cur['last_quota_at'],
      );
      if (per.success) {
        consecFail = 0;
        cooldownUntilMs = null;
      } else {
        consecFail += 1;
        if (looksLikeQuotaError(per.error)) {
          lastQuotaError = per.error;
          lastQuotaAt = timestampMs;
          cooldownUntilMs = timestampMs + cooldownConfig.quotaSeconds * 1000;
        } else if (consecFail >= cooldownConfig.tier3Failures) {
          cooldownUntilMs = timestampMs + cooldownConfig.tier3Seconds * 1000;
        } else if (consecFail >= cooldownConfig.tier2Failures) {
          cooldownUntilMs = timestampMs + cooldownConfig.tier2Seconds * 1000;
        } else if (consecFail >= cooldownConfig.tier1Failures) {
          cooldownUntilMs = timestampMs + cooldownConfig.tier1Seconds * 1000;
        }
      }

      final updated = <String, Object?>{
        'total_calls': totalCalls,
        'success_calls': successCalls,
        'total_duration_ms': totalDur,
        'last_invoked_at': timestampMs,
        'consecutive_failures': consecFail,
        if (cooldownUntilMs != null) 'cooldown_until_ms': cooldownUntilMs,
        if (lastQuotaError != null) 'last_quota_error': lastQuotaError,
        if (lastQuotaAt != null) 'last_quota_at': lastQuotaAt,
      };
      // 累加领域专属计数（total_hits / total_bytes 等）
      for (final bump in per.aggregateBumps.entries) {
        final base = webEngineNonNegativeIntFromValue(cur[bump.key]);
        updated[bump.key] = base + webEngineNonNegativeIntFromValue(bump.value);
      }
      if (!per.success) {
        updated['last_error'] = per.error ?? cur['last_error'];
        updated['last_failure_at'] = timestampMs;
      } else {
        updated['last_error'] = cur['last_error'];
        final lastFailureAt = webEngineOptionalNonNegativeIntFromValue(
          cur['last_failure_at'],
        );
        if (lastFailureAt != null) updated['last_failure_at'] = lastFailureAt;
      }
      agg[key] = updated;
    }
    await writeWebEngineJsonFile(enginesFile, agg);

    // 3) engine_history.json
    if (perEngine.isNotEmpty) {
      final histFile = File(p.join(dir.path, 'engine_history.json'));
      final hist = <String, List<Map<String, Object?>>>{};
      if (await histFile.exists()) {
        try {
          final decoded = await readWebEngineJsonFile(histFile);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              if (entry.value is List) {
                hist['${entry.key}'] = (entry.value as List)
                    .whereType<Map>()
                    .map(
                      (m) => _jsonSafeTelemetryMap(stringKeyedMapFromValue(m)),
                    )
                    .toList();
              }
            }
          }
        } catch (_) {
          /* corrupted */
        }
      }
      for (final per in perEngine) {
        final key = per.kindName;
        final list = hist[key] ?? <Map<String, Object?>>[];
        list.add(
          _jsonSafeTelemetryMap(<String, Object?>{
            'ts': timestampMs,
            'dur': webEngineNonNegativeIntFromValue(per.elapsedMs),
            'ok': per.success,
            ...per.historyExtras,
          }),
        );
        _keepNewestEntries(list, maxHistorySamples);
        hist[key] = list;
      }
      await writeWebEngineJsonFile(histFile, hist);
    }
  }
}

void _keepNewestEntries<T>(List<T> entries, int maxEntries) {
  if (maxEntries <= 0) {
    entries.clear();
    return;
  }
  if (entries.length > maxEntries) {
    entries.removeRange(0, entries.length - maxEntries);
  }
}

Map<String, Object?> _jsonSafeTelemetryMap(Map<Object?, Object?> value) {
  return <String, Object?>{
    for (final entry in value.entries)
      '${entry.key}': _jsonSafeTelemetryValue(entry.value),
  };
}

Object? _jsonSafeTelemetryValue(Object? value) {
  if (value is num && !value.isFinite) return 0;
  if (value is Map) return _jsonSafeTelemetryMap(value);
  if (value is List) {
    return value.map(_jsonSafeTelemetryValue).toList(growable: false);
  }
  return value;
}
