import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/db/database_service.dart';
import '../model/ai_context_usage.dart';
import '../model/ai_token_usage.dart';
import '../model/ai_usage_analytics.dart';

class AiUsageStorageRecord {
  const AiUsageStorageRecord({
    required this.id,
    required this.traceId,
    required this.startedAt,
    required this.endedAt,
    required this.localDate,
    required this.localHour,
    required this.durationMs,
    required this.status,
    required this.surface,
    required this.source,
    required this.operation,
    required this.providerConfigId,
    required this.providerName,
    required this.protocol,
    required this.modelId,
    required this.apiFamily,
    required this.usage,
    required this.cacheInputTokens,
    required this.usageEstimated,
    this.sessionId,
    this.threadTemplateId,
    this.knowledgeBaseId,
    this.firstTokenMs,
    this.errorType,
    this.errorMessage,
    this.httpStatusCode,
    this.timeoutMs,
    this.timeoutPhase,
    this.inputCostUsd,
    this.outputCostUsd,
    this.cacheReadCostUsd,
    this.cacheWriteCostUsd,
    this.totalCostUsd,
    this.metadataJson = '{}',
  });

  final String id;
  final String traceId;
  final DateTime startedAt;
  final DateTime endedAt;
  final String localDate;
  final String localHour;
  final int durationMs;
  final int? firstTokenMs;
  final String status;
  final String? errorType;
  final String? errorMessage;
  final int? httpStatusCode;
  final int? timeoutMs;
  final String? timeoutPhase;
  final String surface;
  final String source;
  final String operation;
  final String? sessionId;
  final String? threadTemplateId;
  final String? knowledgeBaseId;
  final String providerConfigId;
  final String providerName;
  final String protocol;
  final String modelId;
  final String apiFamily;
  final AiTokenUsage usage;
  final int cacheInputTokens;
  final bool usageEstimated;
  final double? inputCostUsd;
  final double? outputCostUsd;
  final double? cacheReadCostUsd;
  final double? cacheWriteCostUsd;
  final double? totalCostUsd;
  final String metadataJson;

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'trace_id': traceId,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'local_date': localDate,
    'local_hour': localHour,
    'duration_ms': durationMs,
    'first_token_ms': firstTokenMs,
    'status': status,
    'error_type': errorType,
    'error_message': errorMessage,
    'http_status_code': httpStatusCode,
    'timeout_ms': timeoutMs,
    'timeout_phase': timeoutPhase,
    'surface': surface,
    'source': source,
    'operation': operation,
    'session_id': sessionId,
    'thread_template_id': threadTemplateId,
    'knowledge_base_id': knowledgeBaseId,
    'provider_config_id': providerConfigId,
    'provider_name': providerName,
    'protocol': protocol,
    'model_id': modelId,
    'api_family': apiFamily,
    'prompt_tokens': usage.promptTokens ?? 0,
    'completion_tokens': usage.completionTokens ?? 0,
    'cache_creation_tokens': usage.cacheCreationTokens ?? 0,
    'cache_read_tokens': usage.cacheReadTokens ?? 0,
    'cache_input_tokens': cacheInputTokens,
    'reasoning_tokens': usage.reasoningTokens ?? 0,
    'audio_input_tokens': usage.audioInputTokens ?? 0,
    'image_input_tokens': usage.imageInputTokens ?? 0,
    'video_input_tokens': usage.videoInputTokens ?? 0,
    'web_search_tool_usage': usage.webSearchToolUsage ?? 0,
    'web_search_page_usage': usage.webSearchPageUsage ?? 0,
    'total_tokens': usage.resolvedTotalTokens ?? 0,
    'usage_estimated': usageEstimated ? 1 : 0,
    'input_cost_usd': inputCostUsd,
    'output_cost_usd': outputCostUsd,
    'cache_read_cost_usd': cacheReadCostUsd,
    'cache_write_cost_usd': cacheWriteCostUsd,
    'total_cost_usd': totalCostUsd,
    'metadata_json': metadataJson,
  };
}

class AiUsageStore {
  const AiUsageStore();

  static const String tableName = 'ai_usage_records';
  static const int maxRetainedRecords = 500000;
  static const Duration maxRetention = Duration(days: 3650);

  Database get _db => DatabaseService.instance.database;

  Future<void> insert(AiUsageStorageRecord record) {
    return _db.insert(
      tableName,
      record.toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<AiUsageSnapshot> loadSnapshot(AiUsageFilter filter) async {
    final now = DateTime.now();
    final where = _buildWhere(filter, now: now);
    final heatmapWhere = _buildWhere(
      filter.copyWith(range: AiUsageRange.year),
      now: now,
    );
    final facetWhere = _buildWhere(
      filter.copyWith(clearProvider: true, clearModel: true, clearSource: true),
      now: now,
    );
    final results = await Future.wait<Object>(<Future<Object>>[
      _loadSummary(where),
      _loadTrend(where, filter.range),
      _loadBuckets(heatmapWhere, 'local_date'),
      _loadBreakdown(where, 'provider_config_id', 'provider_name'),
      _loadBreakdown(where, 'model_id', 'model_id'),
      _loadBreakdown(where, 'source', 'source'),
      _loadBreakdown(where, 'surface', 'surface'),
      _loadBreakdown(where, 'operation', 'operation'),
      _loadBreakdown(
        where,
        'thread_template_id',
        'thread_template_id',
        omitBlank: true,
      ),
      _loadRecent(where),
      _loadFacets(facetWhere, 'provider_config_id', 'provider_name'),
      _loadFacets(facetWhere, 'model_id', 'model_id'),
      _loadFacets(facetWhere, 'source', 'source'),
      _loadBreakdown(
        _sourceWhere(where, AiUsageDataScope.proxySource),
        r"CASE WHEN json_valid(metadata_json) THEN COALESCE(json_extract(metadata_json, '$.proxy_mode'), 'direct') ELSE 'direct' END",
        r"CASE WHEN json_valid(metadata_json) THEN COALESCE(json_extract(metadata_json, '$.proxy_mode'), '直连') ELSE '直连' END",
      ),
      _loadBreakdown(where, 'provider_config_id', 'provider_name', limit: 100),
    ]);
    return AiUsageSnapshot(
      generatedAt: now,
      filter: filter,
      summary: results[0] as AiUsageSummary,
      trend: results[1] as List<AiUsageBucket>,
      heatmap: results[2] as List<AiUsageBucket>,
      providers: results[3] as List<AiUsageBreakdown>,
      models: results[4] as List<AiUsageBreakdown>,
      sources: results[5] as List<AiUsageBreakdown>,
      surfaces: results[6] as List<AiUsageBreakdown>,
      operations: results[7] as List<AiUsageBreakdown>,
      templates: results[8] as List<AiUsageBreakdown>,
      recentRequests: results[9] as List<AiUsageRequestRecord>,
      providerFacets: results[10] as List<AiUsageFacet>,
      modelFacets: results[11] as List<AiUsageFacet>,
      sourceFacets: results[12] as List<AiUsageFacet>,
      proxyRoutes: results[13] as List<AiUsageBreakdown>,
      healthProviders: results[14] as List<AiUsageBreakdown>,
    );
  }

  Future<AiUsageSummary> loadSessionSummary({
    required String sessionId,
    required String source,
    DateTime? legacyStartAt,
    DateTime? legacyEndAt,
  }) {
    final normalizedSessionId = sessionId.trim();
    final normalizedSource = source.trim();
    if (normalizedSessionId.isEmpty || normalizedSource.isEmpty) {
      return Future<AiUsageSummary>.value(const AiUsageSummary());
    }
    final clauses = <String>['source = ?'];
    final arguments = <Object?>[normalizedSource];
    if (legacyStartAt == null) {
      clauses.add('session_id = ?');
      arguments.add(normalizedSessionId);
    } else {
      final legacyClauses = <String>[
        "(session_id IS NULL OR session_id = '')",
        'started_at >= ?',
      ];
      final legacyArguments = <Object?>[
        legacyStartAt.toUtc().toIso8601String(),
      ];
      if (legacyEndAt != null) {
        legacyClauses.add('started_at <= ?');
        legacyArguments.add(legacyEndAt.toUtc().toIso8601String());
      }
      clauses.add('(session_id = ? OR (${legacyClauses.join(' AND ')}))');
      arguments
        ..add(normalizedSessionId)
        ..addAll(legacyArguments);
    }
    return _loadSummary(
      _UsageWhere(sql: 'WHERE ${clauses.join(' AND ')}', arguments: arguments),
    );
  }

  Future<void> clear() => _db.delete(tableName);

  Future<void> prune() async {
    final cutoff = DateTime.now().toUtc().subtract(maxRetention);
    await _db.transaction((transaction) async {
      await transaction.delete(
        tableName,
        where: 'started_at < ?',
        whereArgs: <Object?>[cutoff.toIso8601String()],
      );
      await transaction.rawDelete(
        '''
        DELETE FROM $tableName
        WHERE id IN (
          SELECT id FROM $tableName
          ORDER BY started_at DESC
          LIMIT -1 OFFSET ?
        )
        ''',
        <Object?>[maxRetainedRecords],
      );
    });
  }

  Future<AiUsageSummary> _loadSummary(_UsageWhere where) async {
    final rows = await _db.rawQuery('''
      WITH filtered_usage AS (
        SELECT * FROM $tableName ${where.sql}
      )
      SELECT
        COUNT(*) AS request_count,
        SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success_count,
        SUM(CASE WHEN status != 'success' THEN 1 ELSE 0 END) AS failure_count,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_count,
        SUM(CASE WHEN status = 'timeout' THEN 1 ELSE 0 END) AS timeout_count,
        SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END) AS error_count,
        SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_count,
        SUM(usage_estimated) AS estimated_count,
        SUM(CASE WHEN total_cost_usd IS NOT NULL THEN 1 ELSE 0 END) AS priced_count,
        SUM(prompt_tokens) AS prompt_tokens,
        SUM(completion_tokens) AS completion_tokens,
        SUM(cache_creation_tokens) AS cache_creation_tokens,
        SUM(cache_read_tokens) AS cache_read_tokens,
        SUM(cache_input_tokens) AS cache_input_tokens,
        SUM(reasoning_tokens) AS reasoning_tokens,
        SUM(audio_input_tokens) AS audio_input_tokens,
        SUM(image_input_tokens) AS image_input_tokens,
        SUM(video_input_tokens) AS video_input_tokens,
        SUM(total_tokens) AS total_tokens,
        SUM(COALESCE(total_cost_usd, 0)) AS total_cost_usd,
        SUM(duration_ms) AS total_duration_ms,
        SUM(CASE WHEN first_token_ms IS NOT NULL THEN first_token_ms ELSE 0 END) AS first_token_ms,
        SUM(CASE WHEN first_token_ms IS NOT NULL THEN 1 ELSE 0 END) AS first_token_count,
        (
          SELECT metadata_json
          FROM filtered_usage
          WHERE status = 'success'
          ORDER BY started_at DESC
          LIMIT 1
        ) AS latest_metadata_json
      FROM filtered_usage
      ''', where.arguments);
    final row = rows.firstOrNull ?? const <String, Object?>{};
    final latestContext = _contextUsageFromMetadata(
      row['latest_metadata_json'],
    );
    return AiUsageSummary(
      requestCount: _int(row['request_count']),
      successCount: _int(row['success_count']),
      failureCount: _int(row['failure_count']),
      failedCount: _int(row['failed_count']),
      timeoutCount: _int(row['timeout_count']),
      errorCount: _int(row['error_count']),
      cancelledCount: _int(row['cancelled_count']),
      estimatedCount: _int(row['estimated_count']),
      pricedRequestCount: _int(row['priced_count']),
      promptTokens: _int(row['prompt_tokens']),
      completionTokens: _int(row['completion_tokens']),
      cacheCreationTokens: _int(row['cache_creation_tokens']),
      cacheReadTokens: _int(row['cache_read_tokens']),
      cacheInputTokens: _int(row['cache_input_tokens']),
      reasoningTokens: _int(row['reasoning_tokens']),
      audioInputTokens: _int(row['audio_input_tokens']),
      imageInputTokens: _int(row['image_input_tokens']),
      videoInputTokens: _int(row['video_input_tokens']),
      totalTokens: _int(row['total_tokens']),
      totalCostUsd: _double(row['total_cost_usd']),
      totalDurationMs: _int(row['total_duration_ms']),
      firstTokenDurationMs: _int(row['first_token_ms']),
      firstTokenSampleCount: _int(row['first_token_count']),
      latestContextUsedTokens: latestContext.usedTokens,
      latestContextWindowTokens: latestContext.windowTokens,
    );
  }

  Future<List<AiUsageBucket>> _loadTrend(
    _UsageWhere where,
    AiUsageRange range,
  ) {
    final keyExpression = switch (range) {
      AiUsageRange.today => 'local_hour',
      AiUsageRange.all => 'substr(local_date, 1, 7)',
      _ => 'local_date',
    };
    return _loadBuckets(where, keyExpression);
  }

  Future<List<AiUsageBucket>> _loadBuckets(
    _UsageWhere where,
    String keyExpression,
  ) async {
    final rows = await _db.rawQuery('''
      SELECT $keyExpression AS bucket_key,
        COUNT(*) AS request_count,
        SUM(prompt_tokens) AS prompt_tokens,
        SUM(completion_tokens) AS completion_tokens,
        SUM(cache_creation_tokens) AS cache_creation_tokens,
        SUM(cache_read_tokens) AS cache_read_tokens,
        SUM(total_tokens) AS total_tokens,
        SUM(CASE WHEN total_cost_usd IS NOT NULL THEN 1 ELSE 0 END) AS priced_count,
        SUM(COALESCE(total_cost_usd, 0)) AS total_cost_usd,
        SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success_count,
        SUM(CASE WHEN status IN ('failed', 'error') THEN 1 ELSE 0 END) AS failed_count,
        SUM(CASE WHEN status != 'success' THEN 1 ELSE 0 END) AS failure_count,
        SUM(CASE WHEN status = 'timeout' THEN 1 ELSE 0 END) AS timeout_count,
        SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END) AS error_count,
        SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_count
      FROM $tableName ${where.sql}
      GROUP BY bucket_key
      ORDER BY bucket_key ASC
      ''', where.arguments);
    return rows
        .map(
          (row) => AiUsageBucket(
            key: '${row['bucket_key'] ?? ''}',
            requestCount: _int(row['request_count']),
            promptTokens: _int(row['prompt_tokens']),
            completionTokens: _int(row['completion_tokens']),
            cacheCreationTokens: _int(row['cache_creation_tokens']),
            cacheReadTokens: _int(row['cache_read_tokens']),
            totalTokens: _int(row['total_tokens']),
            totalCostUsd: _double(row['total_cost_usd']),
            pricedRequestCount: _int(row['priced_count']),
            successCount: _int(row['success_count']),
            failedCount: _int(row['failed_count']),
            failureCount: _int(row['failure_count']),
            timeoutCount: _int(row['timeout_count']),
            errorCount: _int(row['error_count']),
            cancelledCount: _int(row['cancelled_count']),
          ),
        )
        .where((item) => item.key.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<AiUsageBreakdown>> _loadBreakdown(
    _UsageWhere where,
    String keyColumn,
    String labelColumn, {
    bool omitBlank = false,
    int limit = 12,
  }) async {
    final effectiveWhere = !omitBlank
        ? where.sql
        : where.sql.isEmpty
        ? "WHERE $keyColumn != ''"
        : "${where.sql} AND $keyColumn != ''";
    final rows = await _db.rawQuery('''
      SELECT $keyColumn AS item_key, $labelColumn AS item_label,
        COUNT(*) AS request_count,
        SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success_count,
        SUM(total_tokens) AS total_tokens,
        SUM(CASE WHEN total_cost_usd IS NOT NULL THEN 1 ELSE 0 END) AS priced_count,
        SUM(COALESCE(total_cost_usd, 0)) AS total_cost_usd,
        AVG(duration_ms) AS average_duration_ms,
        SUM(CASE WHEN status != 'success' THEN 1 ELSE 0 END) AS failure_count,
        SUM(CASE WHEN status = 'timeout' THEN 1 ELSE 0 END) AS timeout_count,
        SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END) AS error_count,
        SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_count
      FROM $tableName $effectiveWhere
      GROUP BY item_key, item_label
      ORDER BY total_tokens DESC, request_count DESC
      LIMIT $limit
      ''', where.arguments);
    return rows
        .map(
          (row) => AiUsageBreakdown(
            key: '${row['item_key'] ?? ''}',
            label: '${row['item_label'] ?? row['item_key'] ?? ''}',
            requestCount: _int(row['request_count']),
            successCount: _int(row['success_count']),
            totalTokens: _int(row['total_tokens']),
            totalCostUsd: _double(row['total_cost_usd']),
            pricedRequestCount: _int(row['priced_count']),
            averageDurationMs: _double(row['average_duration_ms']),
            failureCount: _int(row['failure_count']),
            timeoutCount: _int(row['timeout_count']),
            errorCount: _int(row['error_count']),
            cancelledCount: _int(row['cancelled_count']),
          ),
        )
        .where((item) => item.key.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<AiUsageRequestRecord>> _loadRecent(_UsageWhere where) async {
    final rows = await _db.rawQuery('''
      SELECT * FROM $tableName ${where.sql}
      ORDER BY started_at DESC
      LIMIT 40
      ''', where.arguments);
    return rows.map(_requestFromRow).toList(growable: false);
  }

  Future<List<AiUsageFacet>> _loadFacets(
    _UsageWhere where,
    String valueColumn,
    String labelColumn,
  ) async {
    final rows = await _db.rawQuery('''
      SELECT $valueColumn AS facet_value, $labelColumn AS facet_label,
        SUM(total_tokens) AS total_tokens
      FROM $tableName ${where.sql.isEmpty ? 'WHERE' : '${where.sql} AND'} $valueColumn != ''
      GROUP BY facet_value, facet_label
      ORDER BY total_tokens DESC
      LIMIT 100
    ''', where.arguments);
    return rows
        .map(
          (row) => AiUsageFacet(
            value: '${row['facet_value'] ?? ''}',
            label: '${row['facet_label'] ?? row['facet_value'] ?? ''}',
          ),
        )
        .where((item) => item.value.isNotEmpty)
        .toList(growable: false);
  }

  _UsageWhere _buildWhere(AiUsageFilter filter, {required DateTime now}) {
    final clauses = <String>[];
    final arguments = <Object?>[];
    final start = filter.range.startAt(now);
    if (start != null) {
      clauses.add('started_at >= ?');
      arguments.add(start.toUtc().toIso8601String());
    }
    final provider = filter.providerConfigId?.trim();
    if (provider != null && provider.isNotEmpty) {
      clauses.add('provider_config_id = ?');
      arguments.add(provider);
    }
    final model = filter.modelId?.trim();
    if (model != null && model.isNotEmpty) {
      clauses.add('model_id = ?');
      arguments.add(model);
    }
    final source = filter.source?.trim();
    if (source != null && source.isNotEmpty) {
      clauses.add('source = ?');
      arguments.add(source);
    }
    switch (filter.scope) {
      case AiUsageDataScope.proxyOnly:
        clauses.add('source = ?');
        arguments.add(AiUsageDataScope.proxySource);
      case AiUsageDataScope.nonProxy:
        clauses.add('source != ?');
        arguments.add(AiUsageDataScope.proxySource);
      case AiUsageDataScope.all:
        break;
    }
    return _UsageWhere(
      sql: clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}',
      arguments: arguments,
    );
  }

  _UsageWhere _sourceWhere(_UsageWhere where, String source) {
    final sql = where.sql.isEmpty
        ? 'WHERE source = ?'
        : '${where.sql} AND source = ?';
    return _UsageWhere(
      sql: sql,
      arguments: <Object?>[...where.arguments, source],
    );
  }

  AiUsageRequestRecord _requestFromRow(Map<String, Object?> row) {
    final startedAt = DateTime.tryParse(
      '${row['started_at'] ?? ''}',
    )?.toLocal();
    return AiUsageRequestRecord(
      id: '${row['id'] ?? ''}',
      traceId: '${row['trace_id'] ?? ''}',
      startedAt: startedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      durationMs: _int(row['duration_ms']),
      firstTokenMs: _nullableInt(row['first_token_ms']),
      status: '${row['status'] ?? ''}',
      errorType: _nullableString(row['error_type']),
      errorMessage: _nullableString(row['error_message']),
      httpStatusCode: _nullableInt(row['http_status_code']),
      timeoutMs: _nullableInt(row['timeout_ms']),
      timeoutPhase: _nullableString(row['timeout_phase']),
      surface: '${row['surface'] ?? ''}',
      source: '${row['source'] ?? ''}',
      operation: '${row['operation'] ?? ''}',
      sessionId: _nullableString(row['session_id']),
      threadTemplateId: _nullableString(row['thread_template_id']),
      providerName: '${row['provider_name'] ?? ''}',
      modelId: '${row['model_id'] ?? ''}',
      apiFamily: '${row['api_family'] ?? ''}',
      usage: AiTokenUsage(
        promptTokens: _int(row['prompt_tokens']),
        completionTokens: _int(row['completion_tokens']),
        cacheCreationTokens: _int(row['cache_creation_tokens']),
        cacheReadTokens: _int(row['cache_read_tokens']),
        reasoningTokens: _int(row['reasoning_tokens']),
        audioInputTokens: _int(row['audio_input_tokens']),
        imageInputTokens: _int(row['image_input_tokens']),
        videoInputTokens: _int(row['video_input_tokens']),
        webSearchToolUsage: _int(row['web_search_tool_usage']),
        webSearchPageUsage: _int(row['web_search_page_usage']),
        totalTokens: _int(row['total_tokens']),
      ),
      totalCostUsd: _nullableDouble(row['total_cost_usd']),
      usageEstimated: _int(row['usage_estimated']) == 1,
    );
  }
}

({int usedTokens, int windowTokens}) _contextUsageFromMetadata(Object? value) {
  if (value is! String || value.isEmpty) {
    return (usedTokens: 0, windowTokens: 0);
  }
  try {
    final metadata = jsonDecode(value);
    if (metadata is! Map) return (usedTokens: 0, windowTokens: 0);
    return (
      usedTokens: _int(metadata[aiContextUsedTokensMetadataKey]),
      windowTokens: _int(metadata[aiContextWindowTokensMetadataKey]),
    );
  } on FormatException {
    return (usedTokens: 0, windowTokens: 0);
  }
}

class _UsageWhere {
  const _UsageWhere({required this.sql, required this.arguments});

  final String sql;
  final List<Object?> arguments;
}

int _int(Object? value) => switch (value) {
  int number => number,
  num number when number.isFinite => number.round(),
  _ => int.tryParse('$value') ?? 0,
};

int? _nullableInt(Object? value) => value == null ? null : _int(value);

double _double(Object? value) => switch (value) {
  num number when number.isFinite => number.toDouble(),
  String text => _finiteUsageDouble(text),
  _ => _finiteUsageDouble('$value'),
};

double _finiteUsageDouble(String value) {
  final parsed = double.tryParse(value.trim());
  return parsed != null && parsed.isFinite ? parsed : 0;
}

double? _nullableDouble(Object? value) => value == null ? null : _double(value);

String? _nullableString(Object? value) {
  final text = '$value'.trim();
  return value == null || text.isEmpty ? null : text;
}
