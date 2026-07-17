import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/serial_task_queue.dart';
import '../../../../shared/util/timer_safety.dart';
import '../chat/ai_protocol_adapter.dart';
import 'ai_tool_runtime_service.dart';

enum AiResourceUsageKind {
  tool('tool'),
  skill('skill'),
  hook('hook'),
  knowledge('knowledge'),
  agent('agent'),
  memory('memory'),
  mcp('mcp');

  const AiResourceUsageKind(this.storageValue);

  final String storageValue;

  static AiResourceUsageKind? fromStorage(Object? value) {
    final normalized = '$value'.trim();
    for (final kind in values) {
      if (kind.storageValue == normalized) return kind;
    }
    return null;
  }
}

enum AiResourceUsagePeriod {
  session('session'),
  day('day'),
  week('week'),
  month('month'),
  quarter('quarter'),
  year('year');

  const AiResourceUsagePeriod(this.storageValue);

  final String storageValue;
}

final class AiResourceUsageTrendPoint {
  const AiResourceUsageTrendPoint({
    required this.bucketKey,
    required this.totalCount,
  });

  final String bucketKey;
  final int totalCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'bucket': bucketKey,
    'total': totalCount,
  };
}

final class AiResourceUsageLevelSnapshot {
  const AiResourceUsageLevelSnapshot({
    required this.period,
    required this.bucketKey,
    required this.counts,
    required this.totalCount,
    required this.trend,
  });

  final AiResourceUsagePeriod period;
  final String bucketKey;
  final Map<String, int> counts;
  final int totalCount;
  final List<AiResourceUsageTrendPoint> trend;

  int get resourceCount => counts.length;

  Map<String, Object?> toJson() => <String, Object?>{
    'level': period.storageValue,
    'bucket': bucketKey,
    'total': totalCount,
    'resource_count': resourceCount,
    'counts': counts,
    'trend': trend.map((item) => item.toJson()).toList(growable: false),
  };
}

final class AiResourceUsageSnapshot {
  const AiResourceUsageSnapshot({
    required this.kind,
    required this.levels,
    required this.generatedAt,
  });

  final AiResourceUsageKind kind;
  final Map<AiResourceUsagePeriod, AiResourceUsageLevelSnapshot> levels;
  final DateTime generatedAt;

  AiResourceUsageLevelSnapshot level(AiResourceUsagePeriod period) {
    return levels[period] ??
        AiResourceUsageLevelSnapshot(
          period: period,
          bucketKey: '',
          counts: const <String, int>{},
          totalCount: 0,
          trend: const <AiResourceUsageTrendPoint>[],
        );
  }

  bool get isEmpty => levels.values.every((level) => level.totalCount == 0);

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.storageValue,
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'levels': <String, Object?>{
      for (final entry in levels.entries)
        entry.key.storageValue: entry.value.toJson(),
    },
  };
}

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
       _persistDebouncer = OpenHandDebouncer(
         delay: persistDebounce,
         onError: (error, stack) => silentLog(
           'ai_tool_usage_promotion_store',
           '持久化资源调用统计',
           error,
           stack,
         ),
       );

  static final AiToolUsagePromotionStore shared = AiToolUsagePromotionStore();

  static const int _version = 2;
  static const int _legacyVersion = 1;
  static const int _maxStoreBytes = 8 * 1024 * 1024;
  static const int _maxSessions = 256;
  static const int _maxResourcesPerKind = 1024;
  static const int _maxIdentifierLength = 512;
  static const int _maxCount = 0x3fffffff;
  static const int _sessionTrendLimit = 24;
  static const Map<AiResourceUsagePeriod, int> _periodRetention =
      <AiResourceUsagePeriod, int>{
        AiResourceUsagePeriod.day: 90,
        AiResourceUsagePeriod.week: 54,
        AiResourceUsagePeriod.month: 24,
        AiResourceUsagePeriod.quarter: 12,
        AiResourceUsagePeriod.year: 6,
      };

  final File _file;
  final DateTime Function() _clock;
  final OpenHandDebouncer _persistDebouncer;
  final SerialTaskQueue _operations = SerialTaskQueue();
  final Map<String, _SessionUsage> _sessions = <String, _SessionUsage>{};
  final Map<AiResourceUsagePeriod, SplayTreeMap<String, _UsageBucket>>
  _periods = <AiResourceUsagePeriod, SplayTreeMap<String, _UsageBucket>>{
    for (final period in _periodRetention.keys)
      period: SplayTreeMap<String, _UsageBucket>(),
  };
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  bool _initialized = false;
  bool _dirty = false;

  ValueListenable<int> get changes => _revision;

  Future<void> initialize() => _operations.enqueue(_initializeLocked);

  Future<AiToolUsageRecord> recordToolCall({
    required String sessionId,
    required AiResolvedToolCatalog catalog,
    required AiToolCall toolCall,
    required Map<String, Object?> resultMetadata,
  }) {
    final gatewayToolId = _string(
      resultMetadata['tool_search_gateway_tool_name'],
    );
    final isGatewayInvocation = gatewayToolId.isNotEmpty;
    final resolvedTool = catalog.find(toolCall.name);
    final logicalToolId = isGatewayInvocation
        ? gatewayToolId
        : (resolvedTool?.definition.name.trim() ?? toolCall.name.trim());
    final resources = <AiResourceUsageKind, Set<String>>{
      AiResourceUsageKind.tool: <String>{logicalToolId},
    };

    final source = _string(resultMetadata['tool_source']);
    if (source == 'skill' ||
        resolvedTool?.source == AiRuntimeToolSource.skill ||
        _string(resultMetadata['skill_name']).isNotEmpty ||
        _string(resultMetadata['skill_id']).isNotEmpty) {
      _addResource(
        resources,
        AiResourceUsageKind.skill,
        _firstString(<Object?>[
          resultMetadata['skill_id'],
          resolvedTool?.skill?.relativeDirectoryPath,
          resultMetadata['skill_name'],
          resultMetadata['skill_directory_path'],
          resultMetadata['skill_manifest_path'],
          resolvedTool?.skill?.name,
        ]),
      );
    }
    if (source == 'mcp' || resolvedTool?.source == AiRuntimeToolSource.mcp) {
      _addResource(
        resources,
        AiResourceUsageKind.mcp,
        _firstString(<Object?>[
          resultMetadata['mcp_server_name'],
          resolvedTool?.mcpServer?.name,
        ]),
      );
    }

    _addResource(
      resources,
      AiResourceUsageKind.agent,
      _string(resultMetadata['agent_id']),
    );
    final isMemoryTool =
        resolvedTool?.builtinKind == AiBuiltinToolKind.memory ||
        logicalToolId.toLowerCase() == 'memory';
    _addAllResources(
      resources,
      AiResourceUsageKind.memory,
      _resourceIdsFromMetadata(
        resultMetadata,
        directKeys: <String>['memory_id', if (isMemoryTool) 'id'],
        listKeys: const <String>['memory_ids'],
      ),
    );
    _addAllResources(
      resources,
      AiResourceUsageKind.knowledge,
      _knowledgeSourceIds(resultMetadata),
    );
    _mergeExplicitResources(resources, resultMetadata['resource_usage_ids']);

    return _recordBatch(
      sessionId: sessionId,
      resources: resources,
      toolId: logicalToolId,
      promotionEligible: isGatewayInvocation,
    );
  }

  Future<AiToolUsageRecord> record({
    required String sessionId,
    required String toolId,
    bool promotionEligible = false,
  }) {
    return _recordBatch(
      sessionId: sessionId,
      resources: <AiResourceUsageKind, Set<String>>{
        AiResourceUsageKind.tool: <String>{toolId},
      },
      toolId: toolId,
      promotionEligible: promotionEligible,
    );
  }

  Future<void> recordResources({
    required String sessionId,
    required Map<AiResourceUsageKind, Iterable<String>> resources,
  }) async {
    final normalized = <AiResourceUsageKind, Set<String>>{
      for (final entry in resources.entries)
        entry.key: entry.value
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet(),
    }..removeWhere((_, ids) => ids.isEmpty);
    if (normalized.isEmpty) return;
    await _recordBatch(sessionId: sessionId, resources: normalized);
  }

  Future<AiToolUsageRecord> _recordBatch({
    required String sessionId,
    required Map<AiResourceUsageKind, Set<String>> resources,
    String toolId = '',
    bool promotionEligible = false,
  }) {
    return _operations.enqueue(() async {
      await _initializeLocked();
      final normalizedSessionId = _validIdentifier(sessionId);
      if (normalizedSessionId == null) {
        return const AiToolUsageRecord.ignored();
      }
      final normalizedResources = <AiResourceUsageKind, Set<String>>{};
      for (final entry in resources.entries) {
        final ids = <String>{};
        for (final id in entry.value) {
          final normalized = _validIdentifier(id);
          if (normalized != null) ids.add(normalized);
        }
        if (ids.isNotEmpty) normalizedResources[entry.key] = ids;
      }
      if (normalizedResources.isEmpty) {
        return const AiToolUsageRecord.ignored();
      }

      final now = _clock();
      var session = _sessions[normalizedSessionId];
      if (session == null) {
        _evictOldestSessionIfNeeded();
        session = _SessionUsage(updatedAt: now.toUtc());
        _sessions[normalizedSessionId] = session;
      }
      final periodBuckets = <_UsageBucket>[
        for (final period in _periodRetention.keys) _periodBucket(period, now),
      ];
      for (final entry in normalizedResources.entries) {
        for (final resourceId in entry.value) {
          session.increment(entry.key, resourceId);
          for (final bucket in periodBuckets) {
            bucket.increment(entry.key, resourceId);
          }
        }
      }
      session.updatedAt = now.toUtc();

      final normalizedToolId = _validIdentifier(toolId) ?? '';
      final toolCount = session.countFor(
        AiResourceUsageKind.tool,
        normalizedToolId,
      );
      final toolTotal = session.totalFor(AiResourceUsageKind.tool);
      final promotedNow =
          promotionEligible &&
          normalizedToolId.isNotEmpty &&
          !session.promotedToolIds.contains(normalizedToolId) &&
          toolCount * 2 > toolTotal;
      if (promotedNow) session.promotedToolIds.add(normalizedToolId);

      _dirty = true;
      _revision.value += 1;
      _schedulePersist();
      return AiToolUsageRecord(
        toolId: normalizedToolId,
        sessionCallCount: toolCount,
        sessionTotalCallCount: toolTotal,
        promotedNow: promotedNow,
        isPromoted: session.promotedToolIds.contains(normalizedToolId),
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
      totalCallCount: usage.totalFor(AiResourceUsageKind.tool),
      toolCallCounts: Map<String, int>.unmodifiable(
        usage.countsFor(AiResourceUsageKind.tool),
      ),
      promotedToolIds: Set<String>.unmodifiable(usage.promotedToolIds),
    );
  }

  Map<String, int> get dayCounts =>
      _latestCounts(AiResourceUsagePeriod.day, AiResourceUsageKind.tool);

  Map<String, int> get monthCounts =>
      _latestCounts(AiResourceUsagePeriod.month, AiResourceUsageKind.tool);

  Map<String, int> get yearCounts =>
      _latestCounts(AiResourceUsagePeriod.year, AiResourceUsageKind.tool);

  AiResourceUsageSnapshot snapshot({
    required AiResourceUsageKind kind,
    String? preferredSessionId,
  }) {
    final sessionEntries = _sessions.entries.toList(growable: false)
      ..sort(
        (left, right) => left.value.updatedAt.compareTo(right.value.updatedAt),
      );
    MapEntry<String, _SessionUsage>? activeSession;
    final preferred = preferredSessionId?.trim() ?? '';
    if (preferred.isNotEmpty) {
      final usage = _sessions[preferred];
      if (usage != null) {
        activeSession = MapEntry<String, _SessionUsage>(preferred, usage);
      }
    }
    if (activeSession == null && sessionEntries.isNotEmpty) {
      activeSession = sessionEntries.last;
    }
    final sessionTrendEntries = sessionEntries.length <= _sessionTrendLimit
        ? sessionEntries
        : sessionEntries.sublist(sessionEntries.length - _sessionTrendLimit);
    final levels = <AiResourceUsagePeriod, AiResourceUsageLevelSnapshot>{
      AiResourceUsagePeriod.session: AiResourceUsageLevelSnapshot(
        period: AiResourceUsagePeriod.session,
        bucketKey: activeSession?.key ?? '',
        counts: _sortedCounts(
          activeSession?.value.countsFor(kind) ?? const <String, int>{},
        ),
        totalCount: activeSession?.value.totalFor(kind) ?? 0,
        trend: <AiResourceUsageTrendPoint>[
          for (final entry in sessionTrendEntries)
            AiResourceUsageTrendPoint(
              bucketKey: entry.key,
              totalCount: entry.value.totalFor(kind),
            ),
        ],
      ),
    };
    for (final period in _periodRetention.keys) {
      final buckets = _periods[period]!;
      final currentKey = _periodKey(period, _clock());
      final current = buckets[currentKey];
      levels[period] = AiResourceUsageLevelSnapshot(
        period: period,
        bucketKey: currentKey,
        counts: _sortedCounts(
          current?.countsFor(kind) ?? const <String, int>{},
        ),
        totalCount: current?.totalFor(kind) ?? 0,
        trend: <AiResourceUsageTrendPoint>[
          for (final entry in buckets.entries)
            AiResourceUsageTrendPoint(
              bucketKey: entry.key,
              totalCount: entry.value.totalFor(kind),
            ),
        ],
      );
    }
    return AiResourceUsageSnapshot(
      kind: kind,
      levels:
          Map<AiResourceUsagePeriod, AiResourceUsageLevelSnapshot>.unmodifiable(
            levels,
          ),
      generatedAt: _clock().toUtc(),
    );
  }

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
      for (final buckets in _periods.values) {
        buckets.clear();
      }
      silentLog('ai_tool_usage_promotion_store', '初始化资源调用统计失败', error, stack);
    }
    _pruneAll();
  }

  void _restore(Object? raw) {
    if (raw is! Map) return;
    final version = raw['version'];
    if (version == _legacyVersion) {
      _restoreLegacy(raw);
      _dirty = true;
      _schedulePersist();
      return;
    }
    if (version != _version) return;
    _restoreSessions(raw['sessions']);
    final rawPeriods = raw['periods'];
    if (rawPeriods is! Map) return;
    for (final period in _periodRetention.keys) {
      final rawBuckets = rawPeriods[period.storageValue];
      if (rawBuckets is! Map) continue;
      final buckets = _periods[period]!;
      for (final entry in rawBuckets.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final key = _validPeriodKey(entry.key as String);
        if (key == null) continue;
        buckets[key] = _UsageBucket.fromJson(
          entry.value,
          validIdentifier: _validIdentifier,
          validCount: _validCount,
        );
      }
    }
  }

  void _restoreSessions(Object? rawSessions) {
    if (rawSessions is! Map) return;
    for (final entry in rawSessions.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      final sessionId = _validIdentifier(entry.key as String);
      if (sessionId == null) continue;
      _sessions[sessionId] = _SessionUsage.fromJson(
        entry.value,
        validIdentifier: _validIdentifier,
        validCount: _validCount,
      );
    }
  }

  void _restoreLegacy(Map raw) {
    final rawSessions = raw['sessions'];
    if (rawSessions is Map) {
      for (final entry in rawSessions.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final sessionId = _validIdentifier(entry.key as String);
        if (sessionId == null) continue;
        final value = entry.value as Map;
        final counts = _restoreLegacyCounts(value['counts']);
        final promoted = <String>{};
        final rawPromoted = value['promoted_tools'];
        if (rawPromoted is List) {
          for (final item in rawPromoted) {
            final id = item is String ? _validIdentifier(item) : null;
            if (id != null) promoted.add(id);
          }
        }
        _sessions[sessionId] = _SessionUsage(
          updatedAt:
              DateTime.tryParse('${value['updated_at'] ?? ''}')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          counts: <AiResourceUsageKind, Map<String, int>>{
            AiResourceUsageKind.tool: counts,
          },
          totals: <AiResourceUsageKind, int>{
            AiResourceUsageKind.tool: _validCount(value['total']).clamp(
              counts.values.fold<int>(
                0,
                (sum, count) => (sum + count).clamp(0, _maxCount),
              ),
              _maxCount,
            ),
          },
          promotedToolIds: promoted,
        );
      }
    }
    for (final legacy in <(String, AiResourceUsagePeriod)>[
      ('day', AiResourceUsagePeriod.day),
      ('month', AiResourceUsagePeriod.month),
      ('year', AiResourceUsagePeriod.year),
    ]) {
      final value = raw[legacy.$1];
      if (value is! Map) continue;
      final key = _validPeriodKey('${value['period'] ?? ''}');
      if (key == null) continue;
      final counts = _restoreLegacyCounts(value['counts']);
      _periods[legacy.$2]![key] = _UsageBucket(
        counts: <AiResourceUsageKind, Map<String, int>>{
          AiResourceUsageKind.tool: counts,
        },
        totals: <AiResourceUsageKind, int>{
          AiResourceUsageKind.tool: counts.values.fold<int>(
            0,
            (sum, count) => (sum + count).clamp(0, _maxCount),
          ),
        },
      );
    }
  }

  Map<String, int> _restoreLegacyCounts(Object? raw) {
    final counts = <String, int>{};
    if (raw is! Map) return counts;
    for (final entry in raw.entries) {
      if (counts.length >= _maxResourcesPerKind || entry.key is! String) break;
      final id = _validIdentifier(entry.key as String);
      final count = _validCount(entry.value);
      if (id != null && count > 0) counts[id] = count;
    }
    return counts;
  }

  _UsageBucket _periodBucket(AiResourceUsagePeriod period, DateTime now) {
    final buckets = _periods[period]!;
    final key = _periodKey(period, now);
    final bucket = buckets.putIfAbsent(key, _UsageBucket.new);
    _prunePeriod(period);
    return bucket;
  }

  String _periodKey(AiResourceUsagePeriod period, DateTime now) {
    final local = now.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return switch (period) {
      AiResourceUsagePeriod.day => '$year-$month-$day',
      AiResourceUsagePeriod.week => _isoWeekKey(local),
      AiResourceUsagePeriod.month => '$year-$month',
      AiResourceUsagePeriod.quarter => '$year-Q${((local.month - 1) ~/ 3) + 1}',
      AiResourceUsagePeriod.year => year,
      AiResourceUsagePeriod.session => '',
    };
  }

  String _isoWeekKey(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstThursdayBase = DateTime(thursday.year, 1, 4);
    final firstThursday = firstThursdayBase.add(
      Duration(days: 4 - firstThursdayBase.weekday),
    );
    final week = 1 + thursday.difference(firstThursday).inDays ~/ 7;
    return '${thursday.year.toString().padLeft(4, '0')}-W${week.toString().padLeft(2, '0')}';
  }

  Map<String, int> _latestCounts(
    AiResourceUsagePeriod period,
    AiResourceUsageKind kind,
  ) {
    final buckets = _periods[period]!;
    if (buckets.isEmpty) return const <String, int>{};
    return Map<String, int>.unmodifiable(buckets.values.last.countsFor(kind));
  }

  int _validCount(Object? value) {
    if (value is! num || !value.isFinite) return 0;
    return value.toInt().clamp(0, _maxCount);
  }

  String? _validIdentifier(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > _maxIdentifierLength) {
      return null;
    }
    return normalized;
  }

  String? _validPeriodKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 24) return null;
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

  void _pruneAll() {
    while (_sessions.length > _maxSessions) {
      _removeOldestSession();
    }
    for (final period in _periodRetention.keys) {
      _prunePeriod(period);
    }
  }

  void _prunePeriod(AiResourceUsagePeriod period) {
    final buckets = _periods[period]!;
    final limit = _periodRetention[period]!;
    while (buckets.length > limit) {
      buckets.remove(buckets.firstKey());
    }
  }

  void _schedulePersist() {
    _persistDebouncer.schedule(flush);
  }

  Future<void> _flushLocked() async {
    _persistDebouncer.cancel();
    if (!_dirty) return;
    var content = _encodeState();
    while (utf8.encode(content).length > _maxStoreBytes &&
        _sessions.length > 1) {
      _removeOldestSession();
      content = _encodeState();
    }
    while (utf8.encode(content).length > _maxStoreBytes &&
        _trimOldestPeriodBucket()) {
      content = _encodeState();
    }
    if (utf8.encode(content).length > _maxStoreBytes) {
      throw const FileSystemException('资源调用统计文件超过大小上限');
    }
    await writeFileAtomically(_file, content);
    _dirty = false;
  }

  bool _trimOldestPeriodBucket() {
    for (final period in const <AiResourceUsagePeriod>[
      AiResourceUsagePeriod.day,
      AiResourceUsagePeriod.week,
      AiResourceUsagePeriod.month,
      AiResourceUsagePeriod.quarter,
      AiResourceUsagePeriod.year,
    ]) {
      final buckets = _periods[period]!;
      if (buckets.length > 1) {
        buckets.remove(buckets.firstKey());
        return true;
      }
    }
    return false;
  }

  String _encodeState() {
    final sessions = _sessions.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return jsonEncode(<String, Object?>{
      'version': _version,
      'periods': <String, Object?>{
        for (final period in _periodRetention.keys)
          period.storageValue: <String, Object?>{
            for (final entry in _periods[period]!.entries)
              entry.key: entry.value.toJson(),
          },
      },
      'sessions': <String, Object?>{
        for (final entry in sessions) entry.key: entry.value.toJson(),
      },
    });
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static String _firstString(Iterable<Object?> values) {
    for (final value in values) {
      final text = _string(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static void _addResource(
    Map<AiResourceUsageKind, Set<String>> resources,
    AiResourceUsageKind kind,
    String id,
  ) {
    final normalized = id.trim();
    if (normalized.isEmpty) return;
    resources.putIfAbsent(kind, () => <String>{}).add(normalized);
  }

  static void _addAllResources(
    Map<AiResourceUsageKind, Set<String>> resources,
    AiResourceUsageKind kind,
    Iterable<String> ids,
  ) {
    for (final id in ids) {
      _addResource(resources, kind, id);
    }
  }

  static Set<String> _resourceIdsFromMetadata(
    Map<String, Object?> metadata, {
    required List<String> directKeys,
    required List<String> listKeys,
  }) {
    final ids = <String>{};
    for (final key in directKeys) {
      final value = _string(metadata[key]);
      if (value.isNotEmpty) ids.add(value);
    }
    for (final key in listKeys) {
      final value = metadata[key];
      if (value is! Iterable) continue;
      for (final item in value) {
        final id = _string(item);
        if (id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  static Set<String> _knowledgeSourceIds(Map<String, Object?> metadata) {
    final ids = <String>{};
    void absorbResults(Object? raw) {
      if (raw is! Iterable) return;
      for (final item in raw) {
        if (item is! Map) continue;
        final id = _string(item['source_id']);
        if (id.isNotEmpty) ids.add(id);
      }
    }

    absorbResults(metadata['results']);
    final nested = metadata['knowledge_base'];
    if (nested is Map) absorbResults(nested['results']);
    final direct = _string(metadata['knowledge_source_id']);
    if (direct.isNotEmpty) ids.add(direct);
    return ids;
  }

  static void _mergeExplicitResources(
    Map<AiResourceUsageKind, Set<String>> resources,
    Object? raw,
  ) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final kind = AiResourceUsageKind.fromStorage(entry.key);
      if (kind == null) continue;
      final value = entry.value;
      if (value is Iterable) {
        for (final item in value) {
          _addResource(resources, kind, _string(item));
        }
      } else {
        _addResource(resources, kind, _string(value));
      }
    }
  }
}

class _UsageBucket {
  _UsageBucket({
    Map<AiResourceUsageKind, Map<String, int>>? counts,
    Map<AiResourceUsageKind, int>? totals,
  }) : counts = counts ?? <AiResourceUsageKind, Map<String, int>>{},
       totals = totals ?? <AiResourceUsageKind, int>{};

  factory _UsageBucket.fromJson(
    Object? raw, {
    required String? Function(String value) validIdentifier,
    required int Function(Object? value) validCount,
  }) {
    final bucket = _UsageBucket();
    if (raw is! Map) return bucket;
    final rawCounts = raw['counts'];
    if (rawCounts is Map) {
      for (final kindEntry in rawCounts.entries) {
        final kind = AiResourceUsageKind.fromStorage(kindEntry.key);
        if (kind == null || kindEntry.value is! Map) continue;
        final kindCounts = <String, int>{};
        for (final entry in (kindEntry.value as Map).entries) {
          if (kindCounts.length >=
                  AiToolUsagePromotionStore._maxResourcesPerKind ||
              entry.key is! String) {
            break;
          }
          final id = validIdentifier(entry.key as String);
          final count = validCount(entry.value);
          if (id != null && count > 0) kindCounts[id] = count;
        }
        if (kindCounts.isNotEmpty) bucket.counts[kind] = kindCounts;
      }
    }
    final rawTotals = raw['totals'];
    if (rawTotals is Map) {
      for (final entry in rawTotals.entries) {
        final kind = AiResourceUsageKind.fromStorage(entry.key);
        final total = validCount(entry.value);
        if (kind != null && total > 0) bucket.totals[kind] = total;
      }
    }
    for (final entry in bucket.counts.entries) {
      final sum = entry.value.values.fold<int>(
        0,
        (total, count) =>
            (total + count).clamp(0, AiToolUsagePromotionStore._maxCount),
      );
      if ((bucket.totals[entry.key] ?? 0) < sum) bucket.totals[entry.key] = sum;
    }
    return bucket;
  }

  final Map<AiResourceUsageKind, Map<String, int>> counts;
  final Map<AiResourceUsageKind, int> totals;

  void increment(AiResourceUsageKind kind, String resourceId) {
    totals[kind] = _incrementCount(totals[kind] ?? 0);
    final kindCounts = counts.putIfAbsent(kind, () => <String, int>{});
    if (!kindCounts.containsKey(resourceId) &&
        kindCounts.length >= AiToolUsagePromotionStore._maxResourcesPerKind) {
      return;
    }
    kindCounts[resourceId] = _incrementCount(kindCounts[resourceId] ?? 0);
  }

  Map<String, int> countsFor(AiResourceUsageKind kind) =>
      counts[kind] ?? const <String, int>{};

  int countFor(AiResourceUsageKind kind, String id) => counts[kind]?[id] ?? 0;

  int totalFor(AiResourceUsageKind kind) => totals[kind] ?? 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'counts': <String, Object?>{
      for (final kind in AiResourceUsageKind.values)
        if (counts[kind]?.isNotEmpty ?? false)
          kind.storageValue: _sortedCounts(counts[kind]!),
    },
    'totals': <String, int>{
      for (final kind in AiResourceUsageKind.values)
        if ((totals[kind] ?? 0) > 0) kind.storageValue: totals[kind]!,
    },
  };
}

final class _SessionUsage extends _UsageBucket {
  _SessionUsage({
    required this.updatedAt,
    super.counts,
    super.totals,
    Set<String>? promotedToolIds,
  }) : promotedToolIds = promotedToolIds ?? <String>{};

  factory _SessionUsage.fromJson(
    Object? raw, {
    required String? Function(String value) validIdentifier,
    required int Function(Object? value) validCount,
  }) {
    final bucket = _UsageBucket.fromJson(
      raw,
      validIdentifier: validIdentifier,
      validCount: validCount,
    );
    final promoted = <String>{};
    if (raw is Map && raw['promoted_tools'] is List) {
      for (final item in raw['promoted_tools'] as List) {
        if (item is! String) continue;
        final id = validIdentifier(item);
        if (id != null) promoted.add(id);
      }
    }
    return _SessionUsage(
      updatedAt: raw is Map
          ? DateTime.tryParse('${raw['updated_at'] ?? ''}')?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      counts: bucket.counts,
      totals: bucket.totals,
      promotedToolIds: promoted,
    );
  }

  final Set<String> promotedToolIds;
  DateTime updatedAt;

  @override
  Map<String, Object?> toJson() {
    final promoted = promotedToolIds.toList(growable: false)..sort();
    return <String, Object?>{
      ...super.toJson(),
      'promoted_tools': promoted,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

int _incrementCount(int value) {
  return value >= AiToolUsagePromotionStore._maxCount
      ? AiToolUsagePromotionStore._maxCount
      : value + 1;
}

Map<String, int> _sortedCounts(Map<String, int> source) {
  final entries = source.entries.toList(growable: false)
    ..sort((left, right) {
      final countCompare = right.value.compareTo(left.value);
      return countCompare != 0 ? countCompare : left.key.compareTo(right.key);
    });
  return Map<String, int>.unmodifiable(Map<String, int>.fromEntries(entries));
}
