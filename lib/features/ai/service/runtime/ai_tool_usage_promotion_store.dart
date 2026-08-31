import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/date_time_format.dart';
import '../../../../shared/util/serial_task_queue.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/timer_safety.dart';
import '../../model/ai_session_message.dart';
import '../chat/ai_protocol_adapter.dart';
import 'ai_tool_runtime_service.dart';

enum AiResourceUsageKind {
  tool('tool'),
  skill('skill'),
  hook('hook'),
  knowledge('knowledge'),
  memory('memory'),
  mcp('mcp'),
  workflow('workflow');

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
    required this.successCount,
    required this.failureCount,
  });

  final String bucketKey;
  final int totalCount;
  final int successCount;
  final int failureCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'bucket': bucketKey,
    'total': totalCount,
    'successes': successCount,
    'failures': failureCount,
  };
}

final class AiResourceUsageResourceSnapshot {
  const AiResourceUsageResourceSnapshot({
    required this.resourceId,
    required this.totalCount,
    required this.successCount,
    required this.failureCount,
    required this.totalDurationMs,
    required this.durationSampleCount,
    required this.maxDurationMs,
    required this.sessionCount,
    required this.lastCalledAt,
    required this.subResources,
  });

  final String resourceId;
  final int totalCount;
  final int successCount;
  final int failureCount;
  final int totalDurationMs;
  final int durationSampleCount;
  final int maxDurationMs;
  final int sessionCount;
  final DateTime? lastCalledAt;
  final List<AiResourceUsageResourceSnapshot> subResources;

  int get outcomeCount => successCount + failureCount;
  double? get successRate =>
      outcomeCount == 0 ? null : successCount / outcomeCount;
  double get averageDurationMs =>
      durationSampleCount == 0 ? 0 : totalDurationMs / durationSampleCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'resource_id': resourceId,
    'total': totalCount,
    'successes': successCount,
    'failures': failureCount,
    'success_rate': successRate,
    'average_duration_ms': averageDurationMs,
    'duration_sample_count': durationSampleCount,
    'max_duration_ms': maxDurationMs,
    'session_count': sessionCount,
    'last_called_at': lastCalledAt?.toUtc().toIso8601String(),
    'sub_resources': subResources
        .map((item) => item.toJson())
        .toList(growable: false),
  };
}

final class AiResourceUsageEvent {
  const AiResourceUsageEvent({
    required this.eventId,
    required this.kind,
    required this.resourceId,
    required this.subResourceId,
    required this.sessionId,
    required this.toolCallId,
    required this.toolName,
    required this.occurredAt,
    required this.status,
    required this.durationMs,
    required this.argumentsSummary,
    required this.resultSummary,
    required this.errorSummary,
    required this.source,
    this.metadataJson = '{}',
  });

  final String eventId;
  final AiResourceUsageKind kind;
  final String resourceId;
  final String subResourceId;
  final String sessionId;
  final String toolCallId;
  final String toolName;
  final DateTime occurredAt;
  final String status;
  final int durationMs;
  final String argumentsSummary;
  final String resultSummary;
  final String errorSummary;
  final String source;
  final String metadataJson;

  bool get succeeded => status == 'success';

  Map<String, Object?> toJson() => <String, Object?>{
    'event_id': eventId,
    'kind': kind.storageValue,
    'resource_id': resourceId,
    'sub_resource_id': subResourceId,
    'session_id': sessionId,
    aiSessionMessageToolCallIdMetadataKey: toolCallId,
    'tool_name': toolName,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'status': status,
    'succeeded': succeeded,
    'duration_ms': durationMs,
    'arguments_summary': argumentsSummary,
    'result_summary': resultSummary,
    'error_summary': errorSummary,
    'source': source,
    'metadata_json': metadataJson,
  };
}

final class AiResourceUsageLevelSnapshot {
  const AiResourceUsageLevelSnapshot({
    required this.period,
    required this.bucketKey,
    required this.counts,
    required this.totalCount,
    required this.trend,
    required this.successCount,
    required this.failureCount,
    required this.totalDurationMs,
    required this.durationSampleCount,
    required this.maxDurationMs,
    required this.sessionCount,
    required this.p95DurationMs,
    required this.resources,
    required this.recentEvents,
  });

  final AiResourceUsagePeriod period;
  final String bucketKey;
  final Map<String, int> counts;
  final int totalCount;
  final List<AiResourceUsageTrendPoint> trend;
  final int successCount;
  final int failureCount;
  final int totalDurationMs;
  final int durationSampleCount;
  final int maxDurationMs;
  final int sessionCount;
  final int p95DurationMs;
  final List<AiResourceUsageResourceSnapshot> resources;
  final List<AiResourceUsageEvent> recentEvents;

  int get resourceCount => counts.length;
  int get outcomeCount => successCount + failureCount;
  double? get successRate =>
      outcomeCount == 0 ? null : successCount / outcomeCount;
  double get averageDurationMs =>
      durationSampleCount == 0 ? 0 : totalDurationMs / durationSampleCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'level': period.storageValue,
    'bucket': bucketKey,
    'total': totalCount,
    'resource_count': resourceCount,
    'successes': successCount,
    'failures': failureCount,
    'success_rate': successRate,
    'average_duration_ms': averageDurationMs,
    'duration_sample_count': durationSampleCount,
    'max_duration_ms': maxDurationMs,
    'p95_duration_ms': p95DurationMs,
    'session_count': sessionCount,
    'counts': counts,
    'trend': trend.map((item) => item.toJson()).toList(growable: false),
    'resources': resources.map((item) => item.toJson()).toList(growable: false),
    'recent_events': recentEvents
        .map((item) => item.toJson())
        .toList(growable: false),
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
          successCount: 0,
          failureCount: 0,
          totalDurationMs: 0,
          durationSampleCount: 0,
          maxDurationMs: 0,
          sessionCount: 0,
          p95DurationMs: 0,
          resources: const <AiResourceUsageResourceSnapshot>[],
          recentEvents: const <AiResourceUsageEvent>[],
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

  static const int _version = 3;
  static const int _aggregateVersion = 2;
  static const int _legacyVersion = 1;
  static const Duration runtimeCleanupTimeout =
      kOpenHandServiceRuntimeCleanupTimeout;
  static const int _maxStoreBytes = 8 * kBytesPerMiB;
  static const int _maxSessions = 256;
  static const int _maxResourcesPerKind = 1024;
  static const int _maxIdentifierLength = 512;
  static const int _maxCount = 0x3fffffff;
  static const int _sessionTrendLimit = 24;
  static const int _maxRecentEvents = 384;
  static const int _maxRecentEventsPerLevel = _maxRecentEvents;
  static const int _maxSubResourcesPerResource = 256;
  static const int _maxSummaryLength = 4096;
  static const int _maxErrorSummaryLength = 480;
  static const int _maxMetadataLength = 4096;
  static const int _periodTrimBatchSize = 8;
  static const List<String> _nestedSessionMarkers = <String>[
    '::parallel-',
    '/task/',
  ];
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
  final OpenHandAsyncOnce _shutdownOnce = OpenHandAsyncOnce();
  final Map<String, _SessionUsage> _sessions = <String, _SessionUsage>{};
  final Map<AiResourceUsagePeriod, SplayTreeMap<String, _UsageBucket>>
  _periods = <AiResourceUsagePeriod, SplayTreeMap<String, _UsageBucket>>{
    for (final period in _periodRetention.keys)
      period: SplayTreeMap<String, _UsageBucket>(),
  };
  final List<AiResourceUsageEvent> _recentEvents = <AiResourceUsageEvent>[];
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  int _eventSequence = 0;
  bool _initialized = false;
  bool _dirty = false;
  bool _shuttingDown = false;

  ValueListenable<int> get changes => _revision;

  /// 返回指定资源最近的调用记录，结果按发生时间倒序排列。
  List<AiResourceUsageEvent> recentEventsFor({
    required AiResourceUsageKind kind,
    String? resourceId,
    int limit = 20,
  }) {
    final normalizedResourceId = resourceId?.trim();
    if (limit <= 0) return const <AiResourceUsageEvent>[];
    final boundedLimit = limit > _maxRecentEvents ? _maxRecentEvents : limit;
    final events =
        _recentEvents
            .where(
              (event) =>
                  event.kind == kind &&
                  (normalizedResourceId == null ||
                      normalizedResourceId.isEmpty ||
                      event.resourceId == normalizedResourceId),
            )
            .toList(growable: false)
          ..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    if (events.length <= boundedLimit) {
      return List<AiResourceUsageEvent>.unmodifiable(events);
    }
    return List<AiResourceUsageEvent>.unmodifiable(events.take(boundedLimit));
  }

  Future<void> initialize() {
    if (_shuttingDown) return Future<void>.value();
    return _operations.enqueue(_initializeLocked);
  }

  Future<AiToolUsageRecord> recordToolCall({
    required String sessionId,
    required AiResolvedToolCatalog catalog,
    required AiToolCall toolCall,
    required AiToolExecutionResult result,
  }) {
    final resultMetadata = result.metadata;
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
    final workflowId = _firstString(<Object?>[
      resultMetadata['workflow_id'],
      resultMetadata['workflow_name'],
      if (source == 'workflow') logicalToolId,
    ]);
    final isWorkflowInvocation = source == 'workflow' || workflowId.isNotEmpty;
    if (isWorkflowInvocation) {
      _addResource(resources, AiResourceUsageKind.workflow, workflowId);
    }
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

    final mcpToolId = _firstString(<Object?>[
      resultMetadata['mcp_tool_name'],
      resultMetadata['mcp_tool_id'],
      if (source == 'mcp' || resolvedTool?.source == AiRuntimeToolSource.mcp)
        logicalToolId,
    ]);
    final defaultSubResourceId = _firstString(<Object?>[
      if (isWorkflowInvocation) resultMetadata['execution_id'],
      if (source == 'mcp' || resolvedTool?.source == AiRuntimeToolSource.mcp)
        mcpToolId,
      logicalToolId,
    ]);
    final usageSource = isWorkflowInvocation
        ? _firstString(<Object?>[resultMetadata['workflow_source'], source])
        : source;
    final workflowStatus = _string(resultMetadata['workflow_status']);
    final usageStatus =
        isWorkflowInvocation &&
            (workflowStatus == 'failed' || workflowStatus == 'error')
        ? workflowStatus
        : result.status.storageValue;

    return _recordBatch(
      sessionId: sessionId,
      resources: resources,
      toolId: logicalToolId,
      promotionEligible: isGatewayInvocation,
      subResourceId: defaultSubResourceId,
      toolCallId: toolCall.id,
      toolName: logicalToolId,
      status: usageStatus,
      durationMs: result.durationMs,
      argumentsSummary: _summarizeArguments(toolCall.arguments),
      resultSummary: _boundedSummary(result.resultText, _maxSummaryLength),
      errorSummary: _boundedSummary(result.stderr, _maxErrorSummaryLength),
      source: usageSource.isEmpty
          ? (resolvedTool?.source.name ?? 'unknown')
          : usageSource,
      metadataJson: isWorkflowInvocation
          ? _encodeMetadata(resultMetadata)
          : '{}',
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
      subResourceId: toolId,
      toolName: toolId,
      source: 'direct',
    );
  }

  Future<void> recordResources({
    required String sessionId,
    required Map<AiResourceUsageKind, Iterable<String>> resources,
    String subResourceId = '',
    String toolCallId = '',
    String toolName = '',
    String status = 'success',
    int durationMs = 0,
    String argumentsSummary = '',
    String resultSummary = '',
    String errorSummary = '',
    String source = 'runtime',
    String metadataJson = '{}',
  }) async {
    final normalized = <AiResourceUsageKind, Set<String>>{};
    for (final entry in resources.entries) {
      final ids = <String>{};
      for (final item in entry.value.take(_maxResourcesPerKind)) {
        final id = item.trim();
        if (id.isNotEmpty) ids.add(id);
      }
      if (ids.isNotEmpty) normalized[entry.key] = ids;
    }
    if (normalized.isEmpty) return;
    await _recordBatch(
      sessionId: sessionId,
      resources: normalized,
      subResourceId: subResourceId,
      toolCallId: toolCallId,
      toolName: toolName,
      status: status,
      durationMs: durationMs,
      argumentsSummary: argumentsSummary,
      resultSummary: resultSummary,
      errorSummary: errorSummary,
      source: source,
      metadataJson: metadataJson,
    );
  }

  Future<AiToolUsageRecord> _recordBatch({
    required String sessionId,
    required Map<AiResourceUsageKind, Set<String>> resources,
    String toolId = '',
    bool promotionEligible = false,
    String subResourceId = '',
    String toolCallId = '',
    String toolName = '',
    String status = 'success',
    int durationMs = 0,
    String argumentsSummary = '',
    String resultSummary = '',
    String errorSummary = '',
    String source = 'runtime',
    String metadataJson = '{}',
  }) {
    if (_shuttingDown) {
      return Future<AiToolUsageRecord>.value(const AiToolUsageRecord.ignored());
    }
    return _operations.enqueue(() async {
      await _initializeLocked();
      final normalizedSessionId = _validSessionId(sessionId);
      if (normalizedSessionId == null) {
        return const AiToolUsageRecord.ignored();
      }
      final normalizedResources = <AiResourceUsageKind, Set<String>>{};
      for (final entry in resources.entries) {
        final ids = <String>{};
        for (final id in entry.value.take(_maxResourcesPerKind)) {
          final normalized = _validIdentifier(id);
          if (normalized != null) ids.add(normalized);
        }
        if (ids.isNotEmpty) normalizedResources[entry.key] = ids;
      }
      if (normalizedResources.isEmpty) {
        return const AiToolUsageRecord.ignored();
      }

      final now = _clock();
      final normalizedStatus = _normalizeStatus(status);
      final normalizedDurationMs = durationMs.clamp(0, _maxCount);
      final normalizedSubResourceId = _validIdentifier(subResourceId) ?? '';
      final normalizedToolCallId = _validIdentifier(toolCallId) ?? '';
      final normalizedToolName = _validIdentifier(toolName) ?? '';
      final normalizedSource = _validIdentifier(source) ?? 'runtime';
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
          final effectiveSubResourceId = entry.key == AiResourceUsageKind.tool
              ? normalizedSource
              : normalizedSubResourceId;
          session.increment(
            entry.key,
            resourceId,
            sessionId: normalizedSessionId,
            subResourceId: effectiveSubResourceId,
            status: normalizedStatus,
            durationMs: normalizedDurationMs,
            occurredAt: now,
          );
          for (final bucket in periodBuckets) {
            bucket.increment(
              entry.key,
              resourceId,
              sessionId: normalizedSessionId,
              subResourceId: effectiveSubResourceId,
              status: normalizedStatus,
              durationMs: normalizedDurationMs,
              occurredAt: now,
            );
          }
          _appendEvent(
            AiResourceUsageEvent(
              eventId:
                  '${now.toUtc().microsecondsSinceEpoch}-${_eventSequence++}',
              kind: entry.key,
              resourceId: resourceId,
              subResourceId: effectiveSubResourceId,
              sessionId: normalizedSessionId,
              toolCallId: normalizedToolCallId,
              toolName: normalizedToolName,
              occurredAt: now.toUtc(),
              status: normalizedStatus,
              durationMs: normalizedDurationMs,
              argumentsSummary: _boundedSummary(
                argumentsSummary,
                _maxSummaryLength,
              ),
              resultSummary: _boundedSummary(resultSummary, _maxSummaryLength),
              errorSummary: _boundedSummary(
                errorSummary,
                _maxErrorSummaryLength,
              ),
              source: normalizedSource,
              metadataJson: _boundedSummary(metadataJson, _maxMetadataLength),
            ),
          );
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
      if (!_shuttingDown) _revision.value += 1;
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
    final normalizedSessionId = _validSessionId(sessionId);
    final usage = normalizedSessionId == null
        ? null
        : _sessions[normalizedSessionId];
    return Set<String>.unmodifiable(usage?.promotedToolIds ?? const <String>{});
  }

  AiResourceUsageSnapshot snapshot({
    required AiResourceUsageKind kind,
    String? preferredSessionId,
  }) {
    final sessionEntries = _sessions.entries.toList(growable: false)
      ..sort(
        (left, right) => left.value.updatedAt.compareTo(right.value.updatedAt),
      );
    MapEntry<String, _SessionUsage>? activeSession;
    final preferred = _validSessionId(preferredSessionId ?? '') ?? '';
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
      AiResourceUsagePeriod.session: _buildLevelSnapshot(
        period: AiResourceUsagePeriod.session,
        bucketKey: activeSession?.key ?? '',
        bucket: activeSession?.value,
        kind: kind,
        trend: <AiResourceUsageTrendPoint>[
          for (final entry in sessionTrendEntries)
            AiResourceUsageTrendPoint(
              bucketKey: entry.key,
              totalCount: entry.value.totalFor(kind),
              successCount: entry.value.successesFor(kind),
              failureCount: entry.value.failuresFor(kind),
            ),
        ],
      ),
    };
    for (final period in _periodRetention.keys) {
      final buckets = _periods[period]!;
      final currentKey = _periodKey(period, _clock());
      final current = buckets[currentKey];
      levels[period] = _buildLevelSnapshot(
        period: period,
        bucketKey: currentKey,
        bucket: current,
        kind: kind,
        trend: <AiResourceUsageTrendPoint>[
          for (final entry in buckets.entries)
            AiResourceUsageTrendPoint(
              bucketKey: entry.key,
              totalCount: entry.value.totalFor(kind),
              successCount: entry.value.successesFor(kind),
              failureCount: entry.value.failuresFor(kind),
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

  AiResourceUsageLevelSnapshot _buildLevelSnapshot({
    required AiResourceUsagePeriod period,
    required String bucketKey,
    required _UsageBucket? bucket,
    required AiResourceUsageKind kind,
    required List<AiResourceUsageTrendPoint> trend,
  }) {
    final events = _recentEvents
        .where((event) {
          if (event.kind != kind) return false;
          return period == AiResourceUsagePeriod.session
              ? event.sessionId == bucketKey
              : _periodKey(period, event.occurredAt) == bucketKey;
        })
        .toList(growable: false);
    final visibleEvents = events.length <= _maxRecentEventsPerLevel
        ? events.reversed.toList(growable: false)
        : events
              .sublist(events.length - _maxRecentEventsPerLevel)
              .reversed
              .toList(growable: false);
    final durations =
        events
            .map((event) => event.durationMs)
            .where((duration) => duration >= 0)
            .toList(growable: false)
          ..sort();
    final p95Index = durations.isEmpty
        ? -1
        : ((durations.length * 0.95).ceil() - 1).clamp(0, durations.length - 1);
    return AiResourceUsageLevelSnapshot(
      period: period,
      bucketKey: bucketKey,
      counts: _sortedCounts(bucket?.countsFor(kind) ?? const <String, int>{}),
      totalCount: bucket?.totalFor(kind) ?? 0,
      trend: List<AiResourceUsageTrendPoint>.unmodifiable(trend),
      successCount: bucket?.successesFor(kind) ?? 0,
      failureCount: bucket?.failuresFor(kind) ?? 0,
      totalDurationMs: bucket?.durationFor(kind) ?? 0,
      durationSampleCount: bucket?.durationSampleCountFor(kind) ?? 0,
      maxDurationMs: bucket?.maxDurationFor(kind) ?? 0,
      sessionCount: bucket?.sessionCountFor(kind) ?? 0,
      p95DurationMs: p95Index < 0 ? 0 : durations[p95Index],
      resources:
          bucket?.resourceSnapshotsFor(kind) ??
          const <AiResourceUsageResourceSnapshot>[],
      recentEvents: visibleEvents,
    );
  }

  Future<void> flush() {
    if (_shuttingDown) return shutdown();
    return _operations.enqueue(() async {
      await _initializeLocked();
      await _flushLocked();
    });
  }

  Future<void> shutdown() {
    _shuttingDown = true;
    _persistDebouncer.dispose();
    return _shutdownOnce.run(() async {
      try {
        await _finishShutdown().timeout(runtimeCleanupTimeout);
      } finally {
        _revision.dispose();
      }
    });
  }

  Future<void> _finishShutdown() async {
    await _operations.idle;
    await _initializeLocked();
    await _flushLocked();
  }

  Future<void> _initializeLocked() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await recoverAtomicWriteBackupIfNeeded(_file);
      if (await regularFileExistsBounded(_file)) {
        final raw = await readBoundedFileString(
          _file,
          maxBytes: _maxStoreBytes,
        );
        _restore(jsonDecode(raw));
      }
    } catch (error, stack) {
      _sessions.clear();
      _recentEvents.clear();
      for (final buckets in _periods.values) {
        buckets.clear();
      }
      _dirty = true;
      _schedulePersist();
      silentLog('ai_tool_usage_promotion_store', '初始化资源调用统计失败', error, stack);
    }
    _pruneAll();
  }

  void _restore(Object? raw) {
    if (raw is! Map) {
      _dirty = true;
      _schedulePersist();
      return;
    }
    final version = raw['version'];
    if (version == _legacyVersion) {
      _restoreLegacy(raw);
      _dirty = true;
      _schedulePersist();
      return;
    }
    if (version != _version && version != _aggregateVersion) return;
    _restoreSessions(raw['sessions']);
    final rawPeriods = raw['periods'];
    if (rawPeriods is Map) {
      for (final period in _periodRetention.keys) {
        final rawBuckets = rawPeriods[period.storageValue];
        if (rawBuckets is! Map) continue;
        final buckets = _periods[period]!;
        final currentKey = _periodKey(period, _clock());
        for (final entry in rawBuckets.entries) {
          if (entry.key is! String || entry.value is! Map) {
            _dirty = true;
            continue;
          }
          final key = _validPeriodKey(period, entry.key as String);
          if (key == null || key.compareTo(currentKey) > 0) {
            _dirty = true;
            continue;
          }
          buckets[key] = _UsageBucket.fromJson(
            entry.value,
            validIdentifier: _validIdentifier,
            validSessionIdentifier: _validSessionId,
            validCount: _validCount,
          );
          while (buckets.length > _periodRetention[period]!) {
            buckets.remove(buckets.firstKey());
            _dirty = true;
          }
        }
      }
    } else {
      _dirty = true;
    }
    if (version == _version) {
      _restoreEvents(raw['recent_events']);
    } else {
      _dirty = true;
    }
    if (_dirty) _schedulePersist();
  }

  void _restoreEvents(Object? rawEvents) {
    if (rawEvents is! List) {
      _dirty = true;
      return;
    }
    final start = rawEvents.length > _maxRecentEvents
        ? rawEvents.length - _maxRecentEvents
        : 0;
    if (start > 0) _dirty = true;
    for (var index = start; index < rawEvents.length; index++) {
      final raw = rawEvents[index];
      if (raw is! Map) {
        _dirty = true;
        continue;
      }
      final kind = AiResourceUsageKind.fromStorage(raw['kind']);
      final resourceId = _validIdentifier('${raw['resource_id'] ?? ''}');
      final rawSessionId = '${raw['session_id'] ?? ''}';
      final sessionId = _validSessionId(rawSessionId);
      final occurredAt = DateTime.tryParse(
        '${raw['occurred_at'] ?? ''}',
      )?.toUtc();
      if (kind == null ||
          resourceId == null ||
          sessionId == null ||
          occurredAt == null) {
        _dirty = true;
        continue;
      }
      if (sessionId != rawSessionId.trim()) _dirty = true;
      final restoredEventId = _validIdentifier('${raw['event_id'] ?? ''}');
      if (restoredEventId != null) {
        final separator = restoredEventId.lastIndexOf('-');
        final sequence = separator < 0
            ? null
            : int.tryParse(restoredEventId.substring(separator + 1));
        if (sequence != null && sequence >= _eventSequence) {
          _eventSequence = sequence + 1;
        }
      }
      _recentEvents.add(
        AiResourceUsageEvent(
          eventId:
              restoredEventId ??
              '${occurredAt.microsecondsSinceEpoch}-${_eventSequence++}',
          kind: kind,
          resourceId: resourceId,
          subResourceId:
              _validIdentifier('${raw['sub_resource_id'] ?? ''}') ?? '',
          sessionId: sessionId,
          toolCallId:
              _validIdentifier(
                '${raw[aiSessionMessageToolCallIdMetadataKey] ?? ''}',
              ) ??
              '',
          toolName: _validIdentifier('${raw['tool_name'] ?? ''}') ?? '',
          occurredAt: occurredAt,
          status: _normalizeStatus('${raw['status'] ?? ''}'),
          durationMs: _validCount(raw['duration_ms']),
          argumentsSummary: _boundedSummary(
            '${raw['arguments_summary'] ?? ''}',
            _maxSummaryLength,
          ),
          resultSummary: _boundedSummary(
            '${raw['result_summary'] ?? ''}',
            _maxSummaryLength,
          ),
          errorSummary: _boundedSummary(
            '${raw['error_summary'] ?? ''}',
            _maxErrorSummaryLength,
          ),
          source: _validIdentifier('${raw['source'] ?? ''}') ?? 'runtime',
          metadataJson: _boundedSummary(
            '${raw['metadata_json'] ?? '{}'}',
            _maxMetadataLength,
          ),
        ),
      );
    }
  }

  void _restoreSessions(Object? rawSessions) {
    if (rawSessions is! Map) {
      _dirty = true;
      return;
    }
    for (final entry in rawSessions.entries) {
      if (entry.key is! String || entry.value is! Map) {
        _dirty = true;
        continue;
      }
      final sessionId = _validSessionId(entry.key as String);
      if (sessionId == null) {
        _dirty = true;
        continue;
      }
      final restored = _SessionUsage.fromJson(
        entry.value,
        validIdentifier: _validIdentifier,
        validSessionIdentifier: _validSessionId,
        validCount: _validCount,
      );
      final existing = _sessions[sessionId];
      if (existing == null) {
        _sessions[sessionId] = restored;
      } else {
        existing.absorb(restored);
      }
      if (sessionId != (entry.key as String).trim()) _dirty = true;
      while (_sessions.length > _maxSessions) {
        _removeOldestSession();
        _dirty = true;
      }
    }
  }

  void _restoreLegacy(Map raw) {
    final rawSessions = raw['sessions'];
    if (rawSessions is Map) {
      for (final entry in rawSessions.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final sessionId = _validSessionId(entry.key as String);
        if (sessionId == null) continue;
        final value = entry.value as Map;
        final counts = _restoreLegacyCounts(value['counts']);
        final promoted = <String>{};
        final rawPromoted = value['promoted_tools'];
        if (rawPromoted is List) {
          for (final item in rawPromoted) {
            if (promoted.length >= _maxResourcesPerKind) break;
            final id = item is String ? _validIdentifier(item) : null;
            if (id != null) promoted.add(id);
          }
        }
        final restored = _SessionUsage(
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
        final existing = _sessions[sessionId];
        if (existing == null) {
          _sessions[sessionId] = restored;
        } else {
          existing.absorb(restored);
        }
        while (_sessions.length > _maxSessions) {
          _removeOldestSession();
        }
      }
    }
    for (final legacy in <(String, AiResourceUsagePeriod)>[
      ('day', AiResourceUsagePeriod.day),
      ('month', AiResourceUsagePeriod.month),
      ('year', AiResourceUsagePeriod.year),
    ]) {
      final value = raw[legacy.$1];
      if (value is! Map) continue;
      final key = _validPeriodKey(legacy.$2, '${value['period'] ?? ''}');
      if (key == null || key.compareTo(_periodKey(legacy.$2, _clock())) > 0) {
        continue;
      }
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
      if (counts.length >= _maxResourcesPerKind) break;
      if (entry.key is! String) continue;
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
    final year = fourDigit(local.year);
    final month = twoDigit(local.month);
    return switch (period) {
      AiResourceUsagePeriod.day => formatYearMonthDay(local),
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
    return '${fourDigit(thursday.year)}-W${twoDigit(week)}';
  }

  int _validCount(Object? value) {
    if (value is! num || !value.isFinite) return 0;
    return value.toInt().clamp(0, _maxCount);
  }

  String? _validIdentifier(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > _maxIdentifierLength ||
        _identifierControlCharacterPattern.hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  String? _validSessionId(String value) {
    var normalized = value.trim();
    var end = normalized.length;
    for (final marker in _nestedSessionMarkers) {
      final index = normalized.indexOf(marker);
      if (index >= 0 && index < end) end = index;
    }
    if (end < normalized.length) normalized = normalized.substring(0, end);
    return _validIdentifier(normalized);
  }

  String? _validPeriodKey(AiResourceUsagePeriod period, String value) {
    final normalized = value.trim();
    final valid = switch (period) {
      AiResourceUsagePeriod.day => _isValidDayPeriodKey(normalized),
      AiResourceUsagePeriod.week =>
        _weekPeriodKeyPattern.hasMatch(normalized) &&
            _isInRange(normalized.substring(6), 1, 53),
      AiResourceUsagePeriod.month =>
        _monthPeriodKeyPattern.hasMatch(normalized) &&
            _isInRange(normalized.substring(5), 1, 12),
      AiResourceUsagePeriod.quarter =>
        _quarterPeriodKeyPattern.hasMatch(normalized) &&
            _isInRange(normalized.substring(6), 1, 4),
      AiResourceUsagePeriod.year =>
        _yearPeriodKeyPattern.hasMatch(normalized) &&
            _isInRange(normalized, 1, 9999),
      AiResourceUsagePeriod.session => false,
    };
    return valid ? normalized : null;
  }

  static bool _isValidDayPeriodKey(String value) {
    if (!_dayPeriodKeyPattern.hasMatch(value)) return false;
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
      return false;
    }
    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }

  static bool _isInRange(String value, int min, int max) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed >= min && parsed <= max;
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
    while (_recentEvents.length > _maxRecentEvents) {
      _recentEvents.removeAt(0);
    }
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
    var pruned = false;
    try {
      var content = _encodeState();
      var contentBytes = utf8.encode(content).length;
      while (contentBytes > _maxStoreBytes && _recentEvents.isNotEmpty) {
        final removeCount = (_recentEvents.length ~/ 4).clamp(
          1,
          _recentEvents.length,
        );
        _recentEvents.removeRange(0, removeCount);
        pruned = true;
        content = _encodeState();
        contentBytes = utf8.encode(content).length;
      }
      while (contentBytes > _maxStoreBytes && _sessions.length > 1) {
        final removeCount = (_sessions.length ~/ 8).clamp(
          1,
          _sessions.length - 1,
        );
        for (var index = 0; index < removeCount; index++) {
          _removeOldestSession();
        }
        pruned = true;
        content = _encodeState();
        contentBytes = utf8.encode(content).length;
      }
      while (contentBytes > _maxStoreBytes && _trimOldestPeriodBuckets()) {
        pruned = true;
        content = _encodeState();
        contentBytes = utf8.encode(content).length;
      }
      if (contentBytes > _maxStoreBytes) {
        throw const FileSystemException('资源调用统计文件超过大小上限');
      }
      await writeFileAtomically(_file, content);
      _dirty = false;
    } finally {
      if (pruned && !_shuttingDown) _revision.value += 1;
    }
  }

  bool _trimOldestPeriodBuckets() {
    var removed = 0;
    for (final period in const <AiResourceUsagePeriod>[
      AiResourceUsagePeriod.day,
      AiResourceUsagePeriod.week,
      AiResourceUsagePeriod.month,
      AiResourceUsagePeriod.quarter,
      AiResourceUsagePeriod.year,
    ]) {
      final buckets = _periods[period]!;
      while (buckets.length > 1 && removed < _periodTrimBatchSize) {
        buckets.remove(buckets.firstKey());
        removed += 1;
      }
      if (removed >= _periodTrimBatchSize) break;
    }
    return removed > 0;
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
      'recent_events': _recentEvents
          .map((event) => event.toJson())
          .toList(growable: false),
    });
  }

  void _appendEvent(AiResourceUsageEvent event) {
    if (_recentEvents.length >= _maxRecentEvents) {
      _recentEvents.removeAt(0);
    }
    _recentEvents.add(event);
  }

  static String _normalizeStatus(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? 'success' : normalized;
  }

  static String _summarizeArguments(String arguments) {
    final normalized = arguments.trim();
    if (normalized.isEmpty) return '';
    try {
      return _boundedSummary(
        jsonEncode(_redactSummaryValue(jsonDecode(normalized))),
        _maxSummaryLength,
      );
    } catch (_) {
      return _boundedSummary(normalized, _maxSummaryLength);
    }
  }

  static String _encodeMetadata(Map<String, Object?> metadata) {
    try {
      return _boundedSummary(
        jsonEncode(_redactSummaryValue(metadata)),
        _maxMetadataLength,
      );
    } catch (_) {
      return '{}';
    }
  }

  static Object? _redactSummaryValue(Object? value, [int depth = 0]) {
    if (depth >= 4) return '…';
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries.take(32)) {
        final key = '${entry.key}';
        result[key] = _sensitiveKeyPattern.hasMatch(key)
            ? '[已脱敏]'
            : _redactSummaryValue(entry.value, depth + 1);
      }
      return result;
    }
    if (value is Iterable) {
      return value
          .take(24)
          .map((item) => _redactSummaryValue(item, depth + 1))
          .toList(growable: false);
    }
    return value;
  }

  static String _boundedSummary(String value, int limit) {
    final normalized = value
        .replaceAllMapped(
          _sensitiveValuePattern,
          (match) => '${match.group(1) ?? ''}[已脱敏]',
        )
        .replaceAllMapped(
          _bearerTokenPattern,
          (match) => '${match.group(1) ?? ''}[已脱敏]',
        )
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
    return clipTextByCodeUnits(normalized, limit, suffix: '…');
  }

  static final RegExp _sensitiveKeyPattern = RegExp(
    r'(password|passwd|token|secret|api[_-]?key|authorization|cookie|credential)',
    caseSensitive: false,
  );
  static final RegExp _sensitiveValuePattern = RegExp(
    r'''((?:"|'|\b)[a-z0-9_-]*(?:password|passwd|token|secret|api[_-]?key|authorization|cookie|credential)[a-z0-9_-]*(?:"|'|\b)\s*[:=]\s*)(?:"[^"]*"|'[^']*'|\S+)''',
    caseSensitive: false,
  );
  static final RegExp _bearerTokenPattern = RegExp(
    r'(bearer\s+)[a-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _identifierControlCharacterPattern = RegExp(
    r'[\x00-\x1f\x7f]',
  );
  static final RegExp _dayPeriodKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _weekPeriodKeyPattern = RegExp(r'^\d{4}-W\d{2}$');
  static final RegExp _monthPeriodKeyPattern = RegExp(r'^\d{4}-\d{2}$');
  static final RegExp _quarterPeriodKeyPattern = RegExp(r'^\d{4}-Q\d$');
  static final RegExp _yearPeriodKeyPattern = RegExp(r'^\d{4}$');

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
    final target = resources.putIfAbsent(kind, () => <String>{});
    if (target.length >= _maxResourcesPerKind && !target.contains(normalized)) {
      return;
    }
    target.add(normalized);
  }

  static void _addAllResources(
    Map<AiResourceUsageKind, Set<String>> resources,
    AiResourceUsageKind kind,
    Iterable<String> ids,
  ) {
    for (final id in ids.take(_maxResourcesPerKind)) {
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
      for (final item in value.take(_maxResourcesPerKind)) {
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
      for (final item in raw.take(_maxResourcesPerKind)) {
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
        for (final item in value.take(_maxResourcesPerKind)) {
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
    Map<AiResourceUsageKind, Map<String, _ResourceMetric>>? metrics,
  }) : counts = counts ?? <AiResourceUsageKind, Map<String, int>>{},
       totals = totals ?? <AiResourceUsageKind, int>{},
       metrics =
           metrics ?? <AiResourceUsageKind, Map<String, _ResourceMetric>>{};

  factory _UsageBucket.fromJson(
    Object? raw, {
    required String? Function(String value) validIdentifier,
    required String? Function(String value) validSessionIdentifier,
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
              AiToolUsagePromotionStore._maxResourcesPerKind) {
            break;
          }
          if (entry.key is! String) continue;
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
    final rawMetrics = raw['metrics'];
    if (rawMetrics is Map) {
      for (final kindEntry in rawMetrics.entries) {
        final kind = AiResourceUsageKind.fromStorage(kindEntry.key);
        if (kind == null || kindEntry.value is! Map) continue;
        final kindMetrics = <String, _ResourceMetric>{};
        for (final entry in (kindEntry.value as Map).entries) {
          if (kindMetrics.length >=
              AiToolUsagePromotionStore._maxResourcesPerKind) {
            break;
          }
          if (entry.key is! String) continue;
          final id = validIdentifier(entry.key as String);
          if (id == null || entry.value is! Map) continue;
          kindMetrics[id] = _ResourceMetric.fromJson(
            entry.value,
            validIdentifier: validIdentifier,
            validSessionIdentifier: validSessionIdentifier,
            validCount: validCount,
          );
        }
        if (kindMetrics.isNotEmpty) bucket.metrics[kind] = kindMetrics;
      }
    }
    for (final entry in bucket.counts.entries) {
      final sum = entry.value.values.fold<int>(
        0,
        (total, count) =>
            (total + count).clamp(0, AiToolUsagePromotionStore._maxCount),
      );
      if ((bucket.totals[entry.key] ?? 0) < sum) bucket.totals[entry.key] = sum;
      final kindMetrics = bucket.metrics.putIfAbsent(
        entry.key,
        () => <String, _ResourceMetric>{},
      );
      for (final countEntry in entry.value.entries) {
        kindMetrics.putIfAbsent(
          countEntry.key,
          () => _ResourceMetric(callCount: countEntry.value),
        );
      }
    }
    return bucket;
  }

  final Map<AiResourceUsageKind, Map<String, int>> counts;
  final Map<AiResourceUsageKind, int> totals;
  final Map<AiResourceUsageKind, Map<String, _ResourceMetric>> metrics;

  void absorb(_UsageBucket other) {
    for (final entry in other.totals.entries) {
      totals[entry.key] = _boundedAdd(totals[entry.key] ?? 0, entry.value);
    }
    for (final kindEntry in other.counts.entries) {
      final target = counts.putIfAbsent(kindEntry.key, () => <String, int>{});
      for (final entry in kindEntry.value.entries) {
        if (!target.containsKey(entry.key) &&
            target.length >= AiToolUsagePromotionStore._maxResourcesPerKind) {
          continue;
        }
        target[entry.key] = _boundedAdd(target[entry.key] ?? 0, entry.value);
      }
    }
    for (final kindEntry in other.metrics.entries) {
      final target = metrics.putIfAbsent(
        kindEntry.key,
        () => <String, _ResourceMetric>{},
      );
      for (final entry in kindEntry.value.entries) {
        final existing = target[entry.key];
        if (existing != null) {
          existing.absorb(entry.value);
        } else if (target.length <
            AiToolUsagePromotionStore._maxResourcesPerKind) {
          target[entry.key] = entry.value;
        }
      }
    }
  }

  void increment(
    AiResourceUsageKind kind,
    String resourceId, {
    required String sessionId,
    required String subResourceId,
    required String status,
    required int durationMs,
    required DateTime occurredAt,
  }) {
    totals[kind] = _incrementCount(totals[kind] ?? 0);
    final kindCounts = counts.putIfAbsent(kind, () => <String, int>{});
    if (!kindCounts.containsKey(resourceId) &&
        kindCounts.length >= AiToolUsagePromotionStore._maxResourcesPerKind) {
      return;
    }
    kindCounts[resourceId] = _incrementCount(kindCounts[resourceId] ?? 0);
    final kindMetrics = metrics.putIfAbsent(
      kind,
      () => <String, _ResourceMetric>{},
    );
    kindMetrics
        .putIfAbsent(resourceId, _ResourceMetric.new)
        .increment(
          sessionId: sessionId,
          subResourceId: subResourceId,
          status: status,
          durationMs: durationMs,
          occurredAt: occurredAt,
        );
  }

  Map<String, int> countsFor(AiResourceUsageKind kind) =>
      counts[kind] ?? const <String, int>{};

  int countFor(AiResourceUsageKind kind, String id) => counts[kind]?[id] ?? 0;

  int totalFor(AiResourceUsageKind kind) => totals[kind] ?? 0;

  int successesFor(AiResourceUsageKind kind) =>
      metrics[kind]?.values.fold<int>(
        0,
        (total, metric) => _boundedAdd(total, metric.successCount),
      ) ??
      0;

  int failuresFor(AiResourceUsageKind kind) =>
      metrics[kind]?.values.fold<int>(
        0,
        (total, metric) => _boundedAdd(total, metric.failureCount),
      ) ??
      0;

  int durationFor(AiResourceUsageKind kind) =>
      metrics[kind]?.values.fold<int>(
        0,
        (total, metric) => _boundedAdd(total, metric.totalDurationMs),
      ) ??
      0;

  int durationSampleCountFor(AiResourceUsageKind kind) =>
      metrics[kind]?.values.fold<int>(
        0,
        (total, metric) => _boundedAdd(total, metric.durationSampleCount),
      ) ??
      0;

  int maxDurationFor(AiResourceUsageKind kind) =>
      metrics[kind]?.values.fold<int>(
        0,
        (maximum, metric) =>
            metric.maxDurationMs > maximum ? metric.maxDurationMs : maximum,
      ) ??
      0;

  int sessionCountFor(AiResourceUsageKind kind) {
    final sessions = <String>{};
    for (final metric in metrics[kind]?.values ?? const <_ResourceMetric>[]) {
      sessions.addAll(metric.sessionIds);
    }
    return sessions.length;
  }

  List<AiResourceUsageResourceSnapshot> resourceSnapshotsFor(
    AiResourceUsageKind kind,
  ) {
    final snapshots =
        <AiResourceUsageResourceSnapshot>[
          for (final entry
              in metrics[kind]?.entries ??
                  const <MapEntry<String, _ResourceMetric>>[])
            entry.value.snapshot(entry.key),
        ]..sort((left, right) {
          final countCompare = right.totalCount.compareTo(left.totalCount);
          return countCompare != 0
              ? countCompare
              : left.resourceId.compareTo(right.resourceId);
        });
    return List<AiResourceUsageResourceSnapshot>.unmodifiable(snapshots);
  }

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
    'metrics': <String, Object?>{
      for (final kind in AiResourceUsageKind.values)
        if (metrics[kind]?.isNotEmpty ?? false)
          kind.storageValue: <String, Object?>{
            for (final entry in metrics[kind]!.entries)
              entry.key: entry.value.toJson(),
          },
    },
  };
}

class _ResourceMetric {
  _ResourceMetric({
    this.callCount = 0,
    this.successCount = 0,
    this.failureCount = 0,
    this.totalDurationMs = 0,
    this.durationSampleCount = 0,
    this.maxDurationMs = 0,
    this.lastCalledAt,
    Set<String>? sessionIds,
    Map<String, _ResourceMetric>? subResources,
  }) : sessionIds = sessionIds ?? <String>{},
       subResources = subResources ?? <String, _ResourceMetric>{};

  factory _ResourceMetric.fromJson(
    Object? raw, {
    required String? Function(String value) validIdentifier,
    required String? Function(String value) validSessionIdentifier,
    required int Function(Object? value) validCount,
    int depth = 0,
  }) {
    if (raw is! Map) return _ResourceMetric();
    final sessionIds = <String>{};
    final rawSessions = raw['session_ids'];
    if (rawSessions is List) {
      for (final value in rawSessions) {
        if (sessionIds.length >= AiToolUsagePromotionStore._maxSessions) break;
        final id = validSessionIdentifier('$value');
        if (id != null) sessionIds.add(id);
      }
    }
    final subResources = <String, _ResourceMetric>{};
    final rawSubResources = raw['sub_resources'];
    if (depth == 0 && rawSubResources is Map) {
      for (final entry in rawSubResources.entries) {
        if (subResources.length >=
            AiToolUsagePromotionStore._maxSubResourcesPerResource) {
          break;
        }
        if (entry.key is! String || entry.value is! Map) continue;
        final id = validIdentifier(entry.key as String);
        if (id != null) {
          subResources[id] = _ResourceMetric.fromJson(
            entry.value,
            validIdentifier: validIdentifier,
            validSessionIdentifier: validSessionIdentifier,
            validCount: validCount,
            depth: depth + 1,
          );
        }
      }
    }
    return _ResourceMetric(
      callCount: validCount(raw['calls']),
      successCount: validCount(raw['successes']),
      failureCount: validCount(raw['failures']),
      totalDurationMs: validCount(raw['duration_ms']),
      durationSampleCount: validCount(raw['duration_sample_count']),
      maxDurationMs: validCount(raw['max_duration_ms']),
      lastCalledAt: DateTime.tryParse(
        '${raw['last_called_at'] ?? ''}',
      )?.toUtc(),
      sessionIds: sessionIds,
      subResources: subResources,
    );
  }

  int callCount;
  int successCount;
  int failureCount;
  int totalDurationMs;
  int durationSampleCount;
  int maxDurationMs;
  DateTime? lastCalledAt;
  final Set<String> sessionIds;
  final Map<String, _ResourceMetric> subResources;

  void absorb(_ResourceMetric other) {
    callCount = _boundedAdd(callCount, other.callCount);
    successCount = _boundedAdd(successCount, other.successCount);
    failureCount = _boundedAdd(failureCount, other.failureCount);
    totalDurationMs = _boundedAdd(totalDurationMs, other.totalDurationMs);
    durationSampleCount = _boundedAdd(
      durationSampleCount,
      other.durationSampleCount,
    );
    if (other.maxDurationMs > maxDurationMs) {
      maxDurationMs = other.maxDurationMs;
    }
    final otherLastCalledAt = other.lastCalledAt;
    if (otherLastCalledAt != null &&
        (lastCalledAt == null || otherLastCalledAt.isAfter(lastCalledAt!))) {
      lastCalledAt = otherLastCalledAt;
    }
    for (final sessionId in other.sessionIds) {
      if (sessionIds.length >= AiToolUsagePromotionStore._maxSessions) break;
      sessionIds.add(sessionId);
    }
    for (final entry in other.subResources.entries) {
      final existing = subResources[entry.key];
      if (existing != null) {
        existing.absorb(entry.value);
      } else if (subResources.length <
          AiToolUsagePromotionStore._maxSubResourcesPerResource) {
        subResources[entry.key] = entry.value;
      }
    }
  }

  void increment({
    required String sessionId,
    required String subResourceId,
    required String status,
    required int durationMs,
    required DateTime occurredAt,
    bool includeSubResource = true,
  }) {
    callCount = _incrementCount(callCount);
    if (status == 'success') {
      successCount = _incrementCount(successCount);
    } else {
      failureCount = _incrementCount(failureCount);
    }
    totalDurationMs = _boundedAdd(totalDurationMs, durationMs);
    durationSampleCount = _incrementCount(durationSampleCount);
    if (durationMs > maxDurationMs) maxDurationMs = durationMs;
    lastCalledAt = occurredAt.toUtc();
    if (sessionIds.length < AiToolUsagePromotionStore._maxSessions ||
        sessionIds.contains(sessionId)) {
      sessionIds.add(sessionId);
    }
    if (!includeSubResource || subResourceId.isEmpty) return;
    if (!subResources.containsKey(subResourceId) &&
        subResources.length >=
            AiToolUsagePromotionStore._maxSubResourcesPerResource) {
      return;
    }
    subResources
        .putIfAbsent(subResourceId, _ResourceMetric.new)
        .increment(
          sessionId: sessionId,
          subResourceId: '',
          status: status,
          durationMs: durationMs,
          occurredAt: occurredAt,
          includeSubResource: false,
        );
  }

  AiResourceUsageResourceSnapshot snapshot(String resourceId) {
    final children =
        <AiResourceUsageResourceSnapshot>[
          for (final entry in subResources.entries)
            entry.value.snapshot(entry.key),
        ]..sort((left, right) {
          final countCompare = right.totalCount.compareTo(left.totalCount);
          return countCompare != 0
              ? countCompare
              : left.resourceId.compareTo(right.resourceId);
        });
    return AiResourceUsageResourceSnapshot(
      resourceId: resourceId,
      totalCount: callCount,
      successCount: successCount,
      failureCount: failureCount,
      totalDurationMs: totalDurationMs,
      durationSampleCount: durationSampleCount,
      maxDurationMs: maxDurationMs,
      sessionCount: sessionIds.length,
      lastCalledAt: lastCalledAt,
      subResources: List<AiResourceUsageResourceSnapshot>.unmodifiable(
        children,
      ),
    );
  }

  Map<String, Object?> toJson() {
    final sessions = sessionIds.toList(growable: false)..sort();
    return <String, Object?>{
      'calls': callCount,
      'successes': successCount,
      'failures': failureCount,
      'duration_ms': totalDurationMs,
      'duration_sample_count': durationSampleCount,
      'max_duration_ms': maxDurationMs,
      'last_called_at': lastCalledAt?.toUtc().toIso8601String(),
      'session_ids': sessions,
      'sub_resources': <String, Object?>{
        for (final entry in subResources.entries)
          entry.key: entry.value.toJson(),
      },
    };
  }
}

final class _SessionUsage extends _UsageBucket {
  _SessionUsage({
    required this.updatedAt,
    super.counts,
    super.totals,
    super.metrics,
    Set<String>? promotedToolIds,
  }) : promotedToolIds = promotedToolIds ?? <String>{};

  factory _SessionUsage.fromJson(
    Object? raw, {
    required String? Function(String value) validIdentifier,
    required String? Function(String value) validSessionIdentifier,
    required int Function(Object? value) validCount,
  }) {
    final bucket = _UsageBucket.fromJson(
      raw,
      validIdentifier: validIdentifier,
      validSessionIdentifier: validSessionIdentifier,
      validCount: validCount,
    );
    final promoted = <String>{};
    if (raw is Map && raw['promoted_tools'] is List) {
      for (final item in raw['promoted_tools'] as List) {
        if (promoted.length >= AiToolUsagePromotionStore._maxResourcesPerKind) {
          break;
        }
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
      metrics: bucket.metrics,
      promotedToolIds: promoted,
    );
  }

  final Set<String> promotedToolIds;
  DateTime updatedAt;

  @override
  void absorb(_UsageBucket other) {
    super.absorb(other);
    if (other is! _SessionUsage) return;
    for (final id in other.promotedToolIds) {
      if (promotedToolIds.length >=
          AiToolUsagePromotionStore._maxResourcesPerKind) {
        break;
      }
      promotedToolIds.add(id);
    }
    if (other.updatedAt.isAfter(updatedAt)) updatedAt = other.updatedAt;
  }

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

int _boundedAdd(int left, int right) {
  return (left + right).clamp(0, AiToolUsagePromotionStore._maxCount);
}

Map<String, int> _sortedCounts(Map<String, int> source) {
  final entries = source.entries.toList(growable: false)
    ..sort((left, right) {
      final countCompare = right.value.compareTo(left.value);
      return countCompare != 0 ? countCompare : left.key.compareTo(right.key);
    });
  return Map<String, int>.unmodifiable(Map<String, int>.fromEntries(entries));
}
