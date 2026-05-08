import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';

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

  /// orchestrator 在每次 run() 之前注入当前 settings 的阈值。
  WebEngineCooldownConfig cooldownConfig = const WebEngineCooldownConfig();

  Future<void> _chain = Future.value();

  static final RegExp _quotaErrorPattern = RegExp(
    r'\b(429|too many requests|rate[\s_-]?limit|quota|exceeded|throttl)\b',
    caseSensitive: false,
  );

  /// 判断 engine 错误信息是否属于配额/限流类。
  static bool looksLikeQuotaError(String? message) {
    if (message == null || message.isEmpty) return false;
    return _quotaErrorPattern.hasMatch(message);
  }

  String defaultDirectoryPath() => p.join(
        OpenHandPaths.defaultCacheDirectoryPath(),
        subdir,
        'telemetry',
      );

  /// 读取 `calls.json` 的原始 entry 数组（按 append 时间升序）。
  /// 调用方负责 reverse + take（旧 API 是返回新→旧）。
  Future<List<Map<String, Object?>>> rawCalls() async {
    final f = File(p.join(defaultDirectoryPath(), 'calls.json'));
    if (!await f.exists()) return const [];
    try {
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, Object?>.from(m))
          .toList(growable: false);
    } catch (error, stack) {
      silentLog(logTag, 'rawCalls', error, stack);
      return const [];
    }
  }

  /// 读取 `engines.json`，返回 `kind.name → entry`。
  Future<Map<String, Map<String, Object?>>> rawEngineStats() async {
    final f = File(p.join(defaultDirectoryPath(), 'engines.json'));
    if (!await f.exists()) return const {};
    try {
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, Map<String, Object?>>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          out['${entry.key}'] = Map<String, Object?>.from(entry.value as Map);
        }
      }
      return out;
    } catch (error, stack) {
      silentLog(logTag, 'rawEngineStats', error, stack);
      return const {};
    }
  }

  /// 读取 `engine_history.json`，返回 `kind.name → 采样数组（map 形式）`。
  Future<Map<String, List<Map<String, Object?>>>> rawEngineHistory() async {
    final f = File(p.join(defaultDirectoryPath(), 'engine_history.json'));
    if (!await f.exists()) return const {};
    try {
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, List<Map<String, Object?>>>{};
      for (final entry in decoded.entries) {
        if (entry.value is List) {
          out['${entry.key}'] = (entry.value as List)
              .whereType<Map>()
              .map((m) => Map<String, Object?>.from(m))
              .toList(growable: false);
        }
      }
      return out;
    } catch (error, stack) {
      silentLog(logTag, 'rawEngineHistory', error, stack);
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
        silentLog(logTag, 'clearAll', error, stack);
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
    final until = (entry['cooldown_until_ms'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return until > now ? (until - now) : 0;
  }

  /// 手动清掉某引擎的 cooldown（用于设置 UI 上的"重置"动作）。
  Future<void> clearEngineCooldown(TKind kind) async {
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
        silentLog(logTag, 'clearEngineCooldown', error, stack);
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
      final ts = (s['ts'] as num?)?.toInt() ?? 0;
      if (ts >= cutoff) count++;
    }
    return count;
  }

  // ---------------------------------------------------------------------------
  // 写入入口（子类的 typed `recordCall(...)` 包装它）
  // ---------------------------------------------------------------------------

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
    int maxRecentCalls = 200,
    int maxHistorySamples = 200,
  }) async {
    _chain = _chain
        .then(
          (_) => _writeCallRaw(
            callJson: callJson,
            timestampMs: timestampMs,
            perEngine: perEngine,
            maxRecentCalls: maxRecentCalls,
            maxHistorySamples: maxHistorySamples,
          ),
        )
        .catchError((Object error, StackTrace stack) {
          silentLog(logTag, 'recordCall', error, stack);
        });
    await _chain;
  }

  Future<void> _writeCallRaw({
    required Map<String, Object?> callJson,
    required int timestampMs,
    required List<WebEngineCallEvent> perEngine,
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
        final raw = await callsFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) calls.add(Map<String, Object?>.from(item));
          }
        }
      } catch (_) {/* corrupted: drop */}
    }
    calls.add(callJson);
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
    final cfg = cooldownConfig;
    for (final per in perEngine) {
      final key = per.kindName;
      final cur = agg[key] ?? <String, Object?>{};
      final totalCalls = ((cur['total_calls'] as num?)?.toInt() ?? 0) + 1;
      final successCalls = ((cur['success_calls'] as num?)?.toInt() ?? 0) +
          (per.success ? 1 : 0);
      final totalDur =
          ((cur['total_duration_ms'] as num?)?.toInt() ?? 0) + per.elapsedMs;

      var consecFail = (cur['consecutive_failures'] as num?)?.toInt() ?? 0;
      int? cooldownUntilMs = (cur['cooldown_until_ms'] as num?)?.toInt();
      String? lastQuotaError = cur['last_quota_error'] as String?;
      int? lastQuotaAt = (cur['last_quota_at'] as num?)?.toInt();
      if (per.success) {
        consecFail = 0;
        cooldownUntilMs = null;
      } else {
        consecFail += 1;
        if (looksLikeQuotaError(per.error)) {
          lastQuotaError = per.error;
          lastQuotaAt = timestampMs;
          cooldownUntilMs = timestampMs + cfg.quotaSeconds * 1000;
        } else if (consecFail >= cfg.tier3Failures) {
          cooldownUntilMs = timestampMs + cfg.tier3Seconds * 1000;
        } else if (consecFail >= cfg.tier2Failures) {
          cooldownUntilMs = timestampMs + cfg.tier2Seconds * 1000;
        } else if (consecFail >= cfg.tier1Failures) {
          cooldownUntilMs = timestampMs + cfg.tier1Seconds * 1000;
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
        final base = (cur[bump.key] as num?)?.toInt() ?? 0;
        updated[bump.key] = base + bump.value.toInt();
      }
      if (!per.success) {
        updated['last_error'] = per.error ?? cur['last_error'];
        updated['last_failure_at'] = timestampMs;
      } else {
        updated['last_error'] = cur['last_error'];
        updated['last_failure_at'] = cur['last_failure_at'];
      }
      agg[key] = updated;
    }
    await enginesFile.writeAsString(jsonEncode(agg), flush: true);

    // 3) engine_history.json
    if (perEngine.isNotEmpty) {
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
      for (final per in perEngine) {
        final key = per.kindName;
        final list = hist[key] ?? <Map<String, Object?>>[];
        list.add(<String, Object?>{
          'ts': timestampMs,
          'dur': per.elapsedMs,
          'ok': per.success,
          ...per.historyExtras,
        });
        if (list.length > maxHistorySamples) {
          list.removeRange(0, list.length - maxHistorySamples);
        }
        hist[key] = list;
      }
      await histFile.writeAsString(jsonEncode(hist), flush: true);
    }
  }
}
