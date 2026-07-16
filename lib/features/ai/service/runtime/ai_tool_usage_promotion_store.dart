import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/serial_task_queue.dart';
import '../chat/ai_protocol_adapter.dart';
import 'ai_tool_runtime_service.dart';

final class AiToolUsageRecord {
  const AiToolUsageRecord({
    required this.toolId,
    required this.sessionCallCount,
    required this.sessionTotalCallCount,
    required this.promotedNow,
    required this.isPromoted,
  });

  const AiToolUsageRecord.ignored()
    : toolId = '',
      sessionCallCount = 0,
      sessionTotalCallCount = 0,
      promotedNow = false,
      isPromoted = false;

  final String toolId;
  final int sessionCallCount;
  final int sessionTotalCallCount;
  final bool promotedNow;
  final bool isPromoted;
}

final class AiToolUsageSessionSnapshot {
  const AiToolUsageSessionSnapshot({
    required this.totalCallCount,
    required this.toolCallCounts,
    required this.promotedToolIds,
  });

  final int totalCallCount;
  final Map<String, int> toolCallCounts;
  final Set<String> promotedToolIds;
}

final class AiToolUsagePromotionStore {
  AiToolUsagePromotionStore({
    String? filePath,
    DateTime Function()? clock,
    Duration persistDebounce = const Duration(milliseconds: 500),
  }) : _file = File(
         filePath ?? OpenHandPaths.defaultToolUsagePromotionFilePath(),
       ),
       _clock = clock ?? DateTime.now,
       _persistDebounce = persistDebounce;

  static final AiToolUsagePromotionStore shared = AiToolUsagePromotionStore();

  static const int _version = 1;
  static const int _maxStoreBytes = 4 * 1024 * 1024;
  static const int _maxSessions = 256;
  static const int _maxToolsPerSession = 256;
  static const int _maxToolsPerPeriod = 1024;
  static const int _maxIdentifierLength = 256;
  static const int _maxCount = 0x3fffffff;

  final File _file;
  final DateTime Function() _clock;
  final Duration _persistDebounce;
  final SerialTaskQueue _operations = SerialTaskQueue();
  final Map<String, _SessionUsage> _sessions = <String, _SessionUsage>{};
  _PeriodUsage _day = _PeriodUsage(period: '', counts: <String, int>{});
  _PeriodUsage _month = _PeriodUsage(period: '', counts: <String, int>{});
  _PeriodUsage _year = _PeriodUsage(period: '', counts: <String, int>{});
  Timer? _persistTimer;
  bool _initialized = false;
  bool _dirty = false;

  Future<void> initialize() => _operations.enqueue(_initializeLocked);

  Future<AiToolUsageRecord> recordToolCall({
    required String sessionId,
    required AiResolvedToolCatalog catalog,
    required AiToolCall toolCall,
    required Map<String, Object?> resultMetadata,
  }) {
    final gatewayToolId = resultMetadata['tool_search_gateway_tool_name'];
    final isGatewayInvocation =
        gatewayToolId is String && gatewayToolId.trim().isNotEmpty;
    final resolvedTool = catalog.find(toolCall.name);
    final logicalToolId = isGatewayInvocation
        ? gatewayToolId.trim()
        : (resolvedTool?.definition.name.trim() ?? toolCall.name.trim());
    return record(
      sessionId: sessionId,
      toolId: logicalToolId,
      promotionEligible: isGatewayInvocation,
    );
  }

  Future<AiToolUsageRecord> record({
    required String sessionId,
    required String toolId,
    bool promotionEligible = false,
  }) {
    return _operations.enqueue(() async {
      await _initializeLocked();
      final normalizedSessionId = _validIdentifier(sessionId);
      final normalizedToolId = _validIdentifier(toolId);
      if (normalizedSessionId == null || normalizedToolId == null) {
        return const AiToolUsageRecord.ignored();
      }

      final now = _clock();
      _rollPeriods(now);
      var usage = _sessions[normalizedSessionId];
      if (usage == null) {
        _evictOldestSessionIfNeeded();
        usage = _SessionUsage(updatedAt: now.toUtc());
        _sessions[normalizedSessionId] = usage;
      }
      if (!usage.counts.containsKey(normalizedToolId) &&
          usage.counts.length >= _maxToolsPerSession) {
        usage.total = _increment(usage.total);
        usage.updatedAt = now.toUtc();
        _incrementPeriod(_day.counts, normalizedToolId);
        _incrementPeriod(_month.counts, normalizedToolId);
        _incrementPeriod(_year.counts, normalizedToolId);
        _dirty = true;
        _schedulePersist();
        return AiToolUsageRecord(
          toolId: normalizedToolId,
          sessionCallCount: 0,
          sessionTotalCallCount: usage.total,
          promotedNow: false,
          isPromoted: false,
        );
      }

      usage.total = _increment(usage.total);
      usage.counts[normalizedToolId] = _increment(
        usage.counts[normalizedToolId] ?? 0,
      );
      usage.updatedAt = now.toUtc();
      _incrementPeriod(_day.counts, normalizedToolId);
      _incrementPeriod(_month.counts, normalizedToolId);
      _incrementPeriod(_year.counts, normalizedToolId);

      final toolCount = usage.counts[normalizedToolId]!;
      final promotedNow =
          promotionEligible &&
          !usage.promotedToolIds.contains(normalizedToolId) &&
          toolCount * 2 > usage.total;
      if (promotedNow) {
        usage.promotedToolIds.add(normalizedToolId);
      }
      _dirty = true;
      _schedulePersist();
      return AiToolUsageRecord(
        toolId: normalizedToolId,
        sessionCallCount: toolCount,
        sessionTotalCallCount: usage.total,
        promotedNow: promotedNow,
        isPromoted: usage.promotedToolIds.contains(normalizedToolId),
      );
    });
  }

  Set<String> promotedToolIdsForSession(String sessionId) {
    final usage = _sessions[sessionId.trim()];
    return Set<String>.unmodifiable(usage?.promotedToolIds ?? const <String>{});
  }

  AiToolUsageSessionSnapshot? sessionSnapshot(String sessionId) {
    final usage = _sessions[sessionId.trim()];
    if (usage == null) return null;
    return AiToolUsageSessionSnapshot(
      totalCallCount: usage.total,
      toolCallCounts: Map<String, int>.unmodifiable(usage.counts),
      promotedToolIds: Set<String>.unmodifiable(usage.promotedToolIds),
    );
  }

  Map<String, int> get dayCounts => Map<String, int>.unmodifiable(_day.counts);
  Map<String, int> get monthCounts =>
      Map<String, int>.unmodifiable(_month.counts);
  Map<String, int> get yearCounts =>
      Map<String, int>.unmodifiable(_year.counts);

  Future<void> flush() {
    return _operations.enqueue(() async {
      await _initializeLocked();
      await _flushLocked();
    });
  }

  Future<void> _initializeLocked() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await recoverAtomicWriteBackupIfNeeded(_file);
      if (await _file.exists()) {
        final raw = await readBoundedFileString(
          _file,
          maxBytes: _maxStoreBytes,
        );
        _restore(jsonDecode(raw));
      }
    } catch (error, stack) {
      _sessions.clear();
      silentLog('ai_tool_usage_promotion_store', '初始化工具调用统计失败', error, stack);
    }
    if (_rollPeriods(_clock())) {
      _dirty = true;
      _schedulePersist();
    }
    _pruneSessions();
  }

  void _restore(Object? raw) {
    if (raw is! Map || raw['version'] != _version) return;
    _day = _restorePeriod(raw['day']);
    _month = _restorePeriod(raw['month']);
    _year = _restorePeriod(raw['year']);
    final rawSessions = raw['sessions'];
    if (rawSessions is! Map) return;
    for (final entry in rawSessions.entries) {
      final sessionId = entry.key;
      final value = entry.value;
      if (sessionId is! String || value is! Map) continue;
      final validSessionId = _validIdentifier(sessionId);
      if (validSessionId == null) continue;
      final counts = _restoreCounts(value['counts'], _maxToolsPerSession);
      final promoted = <String>{};
      final rawPromoted = value['promoted_tools'];
      if (rawPromoted is List) {
        for (final item in rawPromoted) {
          if (promoted.length >= _maxToolsPerSession) break;
          if (item is! String) continue;
          final toolId = _validIdentifier(item);
          if (toolId != null) promoted.add(toolId);
        }
      }
      final countSum = counts.values.fold<int>(
        0,
        (total, count) => (total + count).clamp(0, _maxCount),
      );
      final parsedTotal = _validCount(value['total']);
      final updatedAt =
          DateTime.tryParse('${value['updated_at'] ?? ''}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      _sessions[validSessionId] = _SessionUsage(
        total: parsedTotal < countSum ? countSum : parsedTotal,
        counts: counts,
        promotedToolIds: promoted,
        updatedAt: updatedAt,
      );
    }
  }

  _PeriodUsage _restorePeriod(Object? raw) {
    if (raw is! Map) {
      return _PeriodUsage(period: '', counts: <String, int>{});
    }
    final period = raw['period'] is String ? '${raw['period']}' : '';
    return _PeriodUsage(
      period: period,
      counts: _restoreCounts(raw['counts'], _maxToolsPerPeriod),
    );
  }

  Map<String, int> _restoreCounts(Object? raw, int limit) {
    final counts = <String, int>{};
    if (raw is! Map) return counts;
    for (final entry in raw.entries) {
      if (counts.length >= limit) break;
      if (entry.key is! String) continue;
      final toolId = _validIdentifier(entry.key as String);
      final count = _validCount(entry.value);
      if (toolId != null && count > 0) counts[toolId] = count;
    }
    return counts;
  }

  int _validCount(Object? value) {
    if (value is! num || !value.isFinite) return 0;
    return value.toInt().clamp(0, _maxCount);
  }

  bool _rollPeriods(DateTime now) {
    final local = now.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    var changed = false;
    if (_day.period != '$year-$month-$day') {
      _day = _PeriodUsage(period: '$year-$month-$day');
      changed = true;
    }
    if (_month.period != '$year-$month') {
      _month = _PeriodUsage(period: '$year-$month');
      changed = true;
    }
    if (_year.period != year) {
      _year = _PeriodUsage(period: year);
      changed = true;
    }
    return changed;
  }

  void _incrementPeriod(Map<String, int> counts, String toolId) {
    if (!counts.containsKey(toolId) && counts.length >= _maxToolsPerPeriod) {
      return;
    }
    counts[toolId] = _increment(counts[toolId] ?? 0);
  }

  int _increment(int value) => value >= _maxCount ? _maxCount : value + 1;

  String? _validIdentifier(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > _maxIdentifierLength) {
      return null;
    }
    return normalized;
  }

  void _evictOldestSessionIfNeeded() {
    if (_sessions.length < _maxSessions) return;
    _removeOldestSession();
  }

  void _removeOldestSession() {
    String? oldestId;
    DateTime? oldestAt;
    for (final entry in _sessions.entries) {
      if (oldestAt == null || entry.value.updatedAt.isBefore(oldestAt)) {
        oldestId = entry.key;
        oldestAt = entry.value.updatedAt;
      }
    }
    if (oldestId != null) _sessions.remove(oldestId);
  }

  void _pruneSessions() {
    while (_sessions.length > _maxSessions) {
      _removeOldestSession();
    }
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      _persistTimer = null;
      unawaited(
        flush().catchError((Object error, StackTrace stack) {
          silentLog(
            'ai_tool_usage_promotion_store',
            '持久化工具调用统计失败',
            error,
            stack,
          );
        }),
      );
    });
  }

  Future<void> _flushLocked() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    if (!_dirty) return;
    var content = _encodeState();
    while (utf8.encode(content).length > _maxStoreBytes &&
        _sessions.length > 1) {
      _removeOldestSession();
      content = _encodeState();
    }
    if (utf8.encode(content).length > _maxStoreBytes) {
      throw const FileSystemException('工具调用统计文件超过大小上限');
    }
    await writeFileAtomically(_file, content);
    _dirty = false;
  }

  String _encodeState() {
    final sessions = _sessions.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return jsonEncode(<String, Object?>{
      'version': _version,
      'day': _day.toJson(),
      'month': _month.toJson(),
      'year': _year.toJson(),
      'sessions': <String, Object?>{
        for (final entry in sessions) entry.key: entry.value.toJson(),
      },
    });
  }
}

final class _PeriodUsage {
  _PeriodUsage({required this.period, Map<String, int>? counts})
    : counts = counts ?? <String, int>{};

  final String period;
  final Map<String, int> counts;

  Map<String, Object?> toJson() => <String, Object?>{
    'period': period,
    'counts': _sortedCounts(counts),
  };
}

final class _SessionUsage {
  _SessionUsage({
    this.total = 0,
    Map<String, int>? counts,
    Set<String>? promotedToolIds,
    required this.updatedAt,
  }) : counts = counts ?? <String, int>{},
       promotedToolIds = promotedToolIds ?? <String>{};

  int total;
  final Map<String, int> counts;
  final Set<String> promotedToolIds;
  DateTime updatedAt;

  Map<String, Object?> toJson() {
    final promoted = promotedToolIds.toList(growable: false)..sort();
    return <String, Object?>{
      'total': total,
      'counts': _sortedCounts(counts),
      'promoted_tools': promoted,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

Map<String, int> _sortedCounts(Map<String, int> source) {
  final entries = source.entries.toList(growable: false)
    ..sort((left, right) => left.key.compareTo(right.key));
  return Map<String, int>.fromEntries(entries);
}
