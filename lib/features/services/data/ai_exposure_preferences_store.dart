import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../model/ai_exposure_models.dart';

const int _maxProxyPayloadBytes = 4 * kBytesPerMiB;
const int _maxProxyPayloadTotalBytes = 128 * kBytesPerMiB;
const int _maxProxyRequestSampleBytes = 256 * kBytesPerKiB;
const int _maxProxyRequestBatchCount = 50000;
const int _maxProxyRequestPageBytes = 16 * kBytesPerMiB;
const int _maxProxyTrendBuckets = 10000;
const int _maxExternalAccessTokenCharacters = 64 * kBytesPerKiB;

String _encodeProxyJson(
  Object value, {
  required String field,
  required int maxBytes,
  int maxContainerItems = 4096,
  int maxTotalNodes = 32768,
}) {
  validateCanonicalJsonSubset(
    value,
    value,
    path: field,
    maxDepth: 16,
    maxContainerItems: maxContainerItems,
    maxTotalNodes: maxTotalNodes,
  );
  final encoded = jsonEncode(value);
  if (utf8ByteLength(encoded) > maxBytes) {
    throw FormatException('$field 载荷超过安全上限。');
  }
  return encoded;
}

class AiExposurePreferencesStore {
  static const String _key = 'ai_exposure_preferences_v1';
  static const String _credentialsKey = 'ai_exposure_source_credentials_v1';
  static const String _toolSettingsKey = 'ai_exposure_tool_settings_v2';
  static const String _externalTokenKey = 'ai_exposure_external_token_v1';
  static const String _statisticsTable = 'ai_exposure_proxy_statistics';
  static const String _samplesTable = 'ai_exposure_proxy_samples';
  static const String _requestHistoryTable =
      'ai_exposure_proxy_request_history';

  Database get _database => DatabaseService.instance.database;

  Future<AiExposurePreferences> load() async {
    try {
      final rows = await _database.query(
        'app_settings',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object?>[_key],
        limit: 1,
      );
      if (rows.isEmpty) return AiExposurePreferences.defaults();
      final decoded = jsonDecode(rows.first['value'] as String);
      if (decoded is! Map) throw const FormatException('扫描服务设置格式无效。');
      final preferences = AiExposurePreferences.fromJson(
        aiExposureJsonMap(decoded),
      );
      if (preferences.proxyConfiguration.endpoints.isEmpty) return preferences;
      final statisticsRows = await _loadProxyPayloadRows(
        table: _statisticsTable,
        payloadColumn: 'statistics_json',
      );
      final statisticsByUrl = <String, AiExposureProxyUsageStatistics>{};
      for (final row in statisticsRows) {
        final url = row['endpoint_url'] as String?;
        final encoded = row['statistics_json'] as String?;
        if (url == null || encoded == null) {
          throw const FormatException('代理节点使用统计字段无效。');
        }
        final decodedStatistics = jsonDecode(encoded);
        if (decodedStatistics is! Map) {
          throw const FormatException('代理节点使用统计必须为对象。');
        }
        validateCanonicalJsonSubset(
          decodedStatistics,
          decodedStatistics,
          path: 'ai_exposure_proxy_statistics.$url',
          maxDepth: 16,
          maxContainerItems: 4096,
          maxTotalNodes: 32768,
        );
        statisticsByUrl[url] = AiExposureProxyUsageStatistics.fromJson(
          decodedStatistics,
        );
      }
      final sampleRows = await _loadProxyPayloadRows(
        table: _samplesTable,
        payloadColumn: 'samples_json',
      );
      final samplesByUrl = <String, List<AiExposureProxyProbeSample>>{};
      for (final row in sampleRows) {
        final url = row['endpoint_url'] as String?;
        final encoded = row['samples_json'] as String?;
        if (url == null || encoded == null) {
          throw const FormatException('代理节点巡检样本字段无效。');
        }
        final decodedSamples = jsonDecode(encoded);
        if (decodedSamples is! List ||
            decodedSamples.length > kAiExposureProxyLatencySampleLimit ||
            decodedSamples.any((sample) => sample is! Map)) {
          throw const FormatException('代理节点巡检样本格式无效。');
        }
        validateCanonicalJsonSubset(
          decodedSamples,
          decodedSamples,
          path: 'ai_exposure_proxy_samples.$url',
          maxDepth: 16,
          maxContainerItems: 4096,
          maxTotalNodes: 32768,
        );
        final samples = decodedSamples
            .map(AiExposureProxyProbeSample.fromJson)
            .toList(growable: false);
        samplesByUrl[url] = samples;
      }
      final missingStatistics = <AiExposureProxyEndpoint>[];
      final missingSamples = <AiExposureProxyEndpoint>[];
      final endpoints = preferences.proxyConfiguration.endpoints
          .map((endpoint) {
            final stored = statisticsByUrl[endpoint.url];
            final samples = samplesByUrl[endpoint.url];
            if (stored == null &&
                (endpoint.statistics.requests > 0 ||
                    endpoint.statistics.successes > 0 ||
                    endpoint.statistics.failures > 0 ||
                    endpoint.statistics.timeouts > 0 ||
                    endpoint.statistics.recentRequests.isNotEmpty)) {
              missingStatistics.add(endpoint);
            }
            if (samples == null && endpoint.samples.isNotEmpty) {
              missingSamples.add(endpoint);
            }
            return endpoint.copyWith(statistics: stored, samples: samples);
          })
          .toList(growable: false);
      if (missingStatistics.isNotEmpty) {
        await saveProxyStatistics(missingStatistics);
      }
      if (missingSamples.isNotEmpty) {
        await saveProxySamples(missingSamples);
      }
      final merged = AiExposurePreferences(
        enabledSources: preferences.enabledSources,
        defaultConcurrency: preferences.defaultConcurrency,
        defaultValidationMode: preferences.defaultValidationMode,
        forumFetchMode: preferences.forumFetchMode,
        defaultGptAssisted: preferences.defaultGptAssisted,
        useBundledEngine: preferences.useBundledEngine,
        externalAddress: preferences.externalAddress,
        postgresqlEnabled: preferences.postgresqlEnabled,
        redisEnabled: preferences.redisEnabled,
        proxyConfiguration: preferences.proxyConfiguration.copyWith(
          endpoints: endpoints,
        ),
      );
      final legacyHistory = <AiExposureProxyRequestRecord>[
        for (final endpoint in endpoints)
          for (final sample in endpoint.statistics.recentRequests)
            AiExposureProxyRequestRecord(
              endpointUrl: endpoint.url,
              sample: sample,
            ),
      ];
      if (legacyHistory.isNotEmpty) {
        await saveProxyRequestHistory(legacyHistory);
      }
      if (missingSamples.isNotEmpty) await save(merged);
      return merged;
    } on FormatException {
      rethrow;
    } catch (error, stack) {
      silentLog('ai_exposure_preferences_store', '读取扫描服务设置', error, stack);
      return AiExposurePreferences.defaults();
    }
  }

  Future<void> save(AiExposurePreferences preferences) async {
    _validateEndpoints(
      preferences.proxyConfiguration.endpoints,
      includeStatistics: false,
      includeSamples: false,
    );
    final preferencesPayload = preferences.toJson(
      includeProxyStatistics: false,
      includeProxySamples: false,
    );
    final preferencesJson = _encodeProxyJson(
      preferencesPayload,
      field: '扫描服务设置',
      maxBytes: _maxProxyPayloadTotalBytes,
      maxContainerItems: kAiExposureMaxProxyEndpoints,
      maxTotalNodes: 500000,
    );
    await _database.transaction((transaction) async {
      await transaction.insert('app_settings', <String, Object?>{
        'key': _key,
        'value': preferencesJson,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final activeUrls = preferences.proxyConfiguration.endpoints
          .map((endpoint) => endpoint.url)
          .toSet();
      if (activeUrls.isEmpty) {
        await transaction.delete(_statisticsTable);
        await transaction.delete(_samplesTable);
        return;
      }
      final storedUrls = await _loadStoredProxyUrls(
        transaction,
        _statisticsTable,
      );
      final storedSampleUrls = await _loadStoredProxyUrls(
        transaction,
        _samplesTable,
      );
      final batch = transaction.batch();
      final updatedAt = DateTime.now().toUtc().toIso8601String();
      for (final endpoint in preferences.proxyConfiguration.endpoints) {
        if (storedUrls.contains(endpoint.url)) continue;
        batch.insert(
          _statisticsTable,
          _statisticsValues(endpoint, updatedAt),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final endpoint in preferences.proxyConfiguration.endpoints) {
        if (storedSampleUrls.contains(endpoint.url) ||
            endpoint.samples.isEmpty) {
          continue;
        }
        batch.insert(
          _samplesTable,
          _sampleValues(endpoint, updatedAt),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final url in storedUrls.where((url) => !activeUrls.contains(url))) {
        batch.delete(
          _statisticsTable,
          where: 'endpoint_url = ?',
          whereArgs: <Object?>[url],
        );
      }
      for (final url in storedSampleUrls.where(
        (url) => !activeUrls.contains(url),
      )) {
        batch.delete(
          _samplesTable,
          where: 'endpoint_url = ?',
          whereArgs: <Object?>[url],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> saveProxyStatistics(
    List<AiExposureProxyEndpoint> endpoints,
  ) async {
    if (endpoints.isEmpty) return;
    _validateEndpoints(
      endpoints,
      includeStatistics: true,
      includeSamples: false,
    );
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((transaction) async {
      final batch = transaction.batch();
      for (final endpoint in endpoints) {
        batch.insert(
          _statisticsTable,
          _statisticsValues(endpoint, updatedAt),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> saveProxySamples(List<AiExposureProxyEndpoint> endpoints) async {
    if (endpoints.isEmpty) return;
    _validateEndpoints(
      endpoints,
      includeStatistics: false,
      includeSamples: true,
    );
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((transaction) async {
      final batch = transaction.batch();
      for (final endpoint in endpoints) {
        batch.insert(
          _samplesTable,
          _sampleValues(endpoint, updatedAt),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> saveProxyRequestHistory(
    List<AiExposureProxyRequestRecord> records,
  ) async {
    if (records.isEmpty) return;
    if (records.length > _maxProxyRequestBatchCount) {
      throw const FormatException('代理请求明细批量写入数量超过安全上限。');
    }
    final rows = <Map<String, Object?>>[];
    final recordIds = <String>{};
    final createdAt = DateTime.now().toUtc().toIso8601String();
    for (final record in records) {
      if (!record.sample.atReported) continue;
      final endpointUrl = _validateEndpointUrl(record.endpointUrl);
      final recordId = record.recordId;
      if (recordId.isEmpty || !recordIds.add(recordId)) continue;
      if (!const <String>{
            'success',
            'failure',
            'timeout',
          }.contains(record.sample.result) ||
          record.sample.responseTimeMs < 0 ||
          record.sample.at.millisecondsSinceEpoch < 0) {
        throw const FormatException('代理请求明细字段无效。');
      }
      final sampleJson = _encodeProxyJson(
        record.sample.toJson(),
        field: '代理请求明细',
        maxBytes: _maxProxyRequestSampleBytes - utf8ByteLength(endpointUrl),
      );
      rows.add(<String, Object?>{
        'record_id': recordId,
        'endpoint_url': endpointUrl,
        'at_ms': record.sample.at.millisecondsSinceEpoch,
        'result': record.sample.result,
        'response_time_ms': record.sample.responseTimeMs,
        'sample_json': sampleJson,
        'created_at': createdAt,
      });
    }
    if (rows.isEmpty) return;
    await _database.transaction((transaction) async {
      final batch = transaction.batch();
      for (final row in rows) {
        batch.insert(
          _requestHistoryTable,
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
      final countRows = await transaction.rawQuery(
        'SELECT COUNT(*) AS count FROM $_requestHistoryTable',
      );
      final count = optionalIntegralIntFromValue(
        countRows.firstOrNull?['count'],
      );
      if (count == null) {
        throw const FormatException('代理请求明细数量统计无效。');
      }
      final excess = count - kAiExposureProxyRequestHistoryLimit;
      if (excess <= 0) return;
      await transaction.rawDelete(
        'DELETE FROM $_requestHistoryTable WHERE record_id IN ('
        'SELECT record_id FROM $_requestHistoryTable '
        'ORDER BY at_ms ASC, record_id ASC LIMIT ?)',
        <Object?>[excess],
      );
    });
  }

  static Map<String, Object?> _statisticsValues(
    AiExposureProxyEndpoint endpoint,
    String updatedAt,
  ) {
    final statisticsJson = _encodeProxyJson(
      endpoint.statistics.toJson(),
      field: '代理节点使用统计',
      maxBytes: _maxProxyPayloadBytes,
    );
    return <String, Object?>{
      'endpoint_url': endpoint.url,
      'statistics_json': statisticsJson,
      'updated_at': updatedAt,
    };
  }

  static Map<String, Object?> _sampleValues(
    AiExposureProxyEndpoint endpoint,
    String updatedAt,
  ) {
    if (endpoint.samples.length > kAiExposureProxyLatencySampleLimit) {
      throw const FormatException('代理节点巡检样本数量超过安全上限。');
    }
    final samplesJson = _encodeProxyJson(
      endpoint.samples.map((sample) => sample.toJson()).toList(growable: false),
      field: '代理节点巡检样本',
      maxBytes: _maxProxyPayloadBytes,
    );
    return <String, Object?>{
      'endpoint_url': endpoint.url,
      'samples_json': samplesJson,
      'updated_at': updatedAt,
    };
  }

  Future<int> countProxyRequestHistory() async {
    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM $_requestHistoryTable',
    );
    final count = optionalIntegralIntFromValue(rows.firstOrNull?['count']);
    if (count == null || count > kAiExposureProxyRequestHistoryLimit) {
      throw const FormatException('代理请求明细数量无效。');
    }
    return count;
  }

  Future<List<AiExposureProxyRequestRecord>> loadProxyRequestHistory({
    required int offset,
    required int limit,
  }) async {
    final safeOffset = offset.clamp(0, kAiExposureProxyRequestHistoryLimit);
    final safeLimit = limit.clamp(1, kAiExposureProxyRequestHistoryPageMax);
    await _validateRequestHistoryPage(offset: safeOffset, limit: safeLimit);
    final rows = await _database.query(
      _requestHistoryTable,
      columns: const <String>['endpoint_url', 'sample_json'],
      orderBy: 'at_ms DESC, record_id DESC',
      offset: safeOffset,
      limit: safeLimit,
    );
    final records = <AiExposureProxyRequestRecord>[];
    for (final row in rows) {
      final endpointUrl = row['endpoint_url'] as String?;
      final encoded = row['sample_json'] as String?;
      if (endpointUrl == null || encoded == null) {
        throw const FormatException('代理请求明细字段无效。');
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('代理请求明细必须为对象。');
      }
      validateCanonicalJsonSubset(
        decoded,
        decoded,
        path: 'ai_exposure_proxy_request_history',
        maxDepth: 16,
        maxContainerItems: 4096,
        maxTotalNodes: 32768,
      );
      records.add(
        AiExposureProxyRequestRecord(
          endpointUrl: _validateEndpointUrl(endpointUrl),
          sample: AiExposureProxyRequestSample.fromJson(decoded),
        ),
      );
    }
    return List<AiExposureProxyRequestRecord>.unmodifiable(records);
  }

  Future<List<AiExposureProxyRequestTrendBucket>> loadProxyRequestTrend({
    required DateTime startAt,
    required Duration interval,
  }) async {
    final intervalMs = interval.inMilliseconds.clamp(
      Duration.millisecondsPerMinute,
      Duration.millisecondsPerDay,
    );
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final endBucket = (nowMs ~/ intervalMs) * intervalMs;
    final requestedStartBucket =
        (startAt.millisecondsSinceEpoch ~/ intervalMs) * intervalMs;
    final earliestBucket = endBucket - intervalMs * (_maxProxyTrendBuckets - 1);
    final startBucket = requestedStartBucket < earliestBucket
        ? earliestBucket
        : requestedStartBucket;
    final rows = await _database.rawQuery(
      'SELECT (at_ms / ?) * ? AS bucket_ms, COUNT(*) AS total, '
      'SUM(response_time_ms) AS total_response_time_ms, '
      "SUM(CASE WHEN result = 'success' THEN 1 ELSE 0 END) AS successes, "
      "SUM(CASE WHEN result = 'failure' THEN 1 ELSE 0 END) AS failures, "
      "SUM(CASE WHEN result = 'timeout' THEN 1 ELSE 0 END) AS timeouts "
      'FROM $_requestHistoryTable WHERE at_ms >= ? '
      'GROUP BY bucket_ms ORDER BY bucket_ms ASC',
      <Object?>[intervalMs, intervalMs, startBucket],
    );
    final buckets = <int, AiExposureProxyRequestTrendBucket>{};
    for (final row in rows) {
      int value(String key) => (row[key] as num?)?.toInt() ?? 0;
      final bucketMs = value('bucket_ms');
      buckets[bucketMs] = AiExposureProxyRequestTrendBucket(
        at: DateTime.fromMillisecondsSinceEpoch(bucketMs),
        total: value('total'),
        successes: value('successes'),
        failures: value('failures'),
        timeouts: value('timeouts'),
        totalResponseTimeMs: value('total_response_time_ms'),
      );
    }
    return List<AiExposureProxyRequestTrendBucket>.unmodifiable(
      <AiExposureProxyRequestTrendBucket>[
        for (
          var bucketMs = startBucket;
          bucketMs <= endBucket;
          bucketMs += intervalMs
        )
          buckets[bucketMs] ??
              AiExposureProxyRequestTrendBucket(
                at: DateTime.fromMillisecondsSinceEpoch(bucketMs),
                total: 0,
                successes: 0,
                failures: 0,
                timeouts: 0,
              ),
      ],
    );
  }

  // ── 扫描工具设置持久化 ────────────────────────────────────────────

  Future<AiExposureToolSettings> loadToolSettings() async {
    try {
      final rows = await _database.query(
        'app_settings',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object?>[_toolSettingsKey],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return AiExposureToolSettings.fromJson(
          jsonDecode(rows.first['value'] as String),
        );
      }
      final legacy = await _loadLegacySourceCredentials();
      final migrated = legacy.isEmpty
          ? AiExposureToolSettings.defaults()
          : AiExposureToolSettings.fromLegacy(legacy);
      if (legacy.isNotEmpty) await saveToolSettings(migrated);
      return migrated;
    } catch (error, stack) {
      silentLog('ai_exposure_preferences_store', '读取扫描工具设置', error, stack);
      return AiExposureToolSettings.defaults();
    }
  }

  Future<void> saveToolSettings(AiExposureToolSettings settings) async {
    await _database.transaction((transaction) async {
      await transaction.insert('app_settings', <String, Object?>{
        'key': _toolSettingsKey,
        'value': jsonEncode(settings.normalized().toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: const <Object?>[_credentialsKey],
      );
    });
  }

  Future<Map<String, String>> _loadLegacySourceCredentials() async {
    final rows = await _database.query(
      'app_settings',
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>[_credentialsKey],
      limit: 1,
    );
    if (rows.isEmpty) return const <String, String>{};
    final decoded = jsonDecode(rows.first['value'] as String);
    if (decoded is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in decoded.entries)
        if (entry.key is String &&
            entry.value is String &&
            (entry.value as String).trim().isNotEmpty)
          entry.key as String: (entry.value as String).trim(),
    };
  }

  // ── 外部服务令牌持久化 ────────────────────────────────────────────

  Future<String?> loadExternalAccessToken() async {
    try {
      final rows = await _database.query(
        'app_settings',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object?>[_externalTokenKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final value = rows.first['value'] as String?;
      final normalized = value?.trim() ?? '';
      if (normalized.length > _maxExternalAccessTokenCharacters) {
        throw const FormatException('外部服务令牌超过安全上限。');
      }
      return normalized.isEmpty ? null : normalized;
    } catch (error, stack) {
      silentLog('ai_exposure_preferences_store', '读取外部服务令牌', error, stack);
      return null;
    }
  }

  Future<void> saveExternalAccessToken(String? token) async {
    final normalized = token?.trim() ?? '';
    if (normalized.isEmpty) {
      await _database.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: const <Object?>[_externalTokenKey],
      );
      return;
    }
    if (normalized.length > _maxExternalAccessTokenCharacters) {
      throw const FormatException('外部服务令牌超过安全上限。');
    }
    await _database.insert('app_settings', <String, Object?>{
      'key': _externalTokenKey,
      'value': normalized,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> _loadProxyPayloadRows({
    required String table,
    required String payloadColumn,
  }) async {
    final usageRows = await _database.rawQuery('''
      SELECT COUNT(*) AS entry_count,
             COALESCE(MAX(LENGTH(CAST(endpoint_url AS BLOB)) +
                          LENGTH(CAST($payloadColumn AS BLOB))), 0)
               AS max_entry_bytes,
             COALESCE(SUM(LENGTH(CAST(endpoint_url AS BLOB)) +
                          LENGTH(CAST($payloadColumn AS BLOB))), 0)
               AS total_bytes
      FROM $table
      ''');
    final usage = usageRows.firstOrNull;
    final entryCount = optionalIntegralIntFromValue(usage?['entry_count']);
    final maxEntryBytes = optionalIntegralIntFromValue(
      usage?['max_entry_bytes'],
    );
    final totalBytes = optionalIntegralIntFromValue(usage?['total_bytes']);
    if (entryCount == null || maxEntryBytes == null || totalBytes == null) {
      throw const FormatException('代理节点存储统计无效。');
    }
    if (entryCount > kAiExposureMaxProxyEndpoints ||
        maxEntryBytes > _maxProxyPayloadBytes ||
        totalBytes > _maxProxyPayloadTotalBytes) {
      throw const FormatException('代理节点存储规模超过安全上限。');
    }
    final rows = await _database.query(
      table,
      columns: <String>['endpoint_url', payloadColumn],
      limit: kAiExposureMaxProxyEndpoints + 1,
    );
    if (rows.length > kAiExposureMaxProxyEndpoints) {
      throw const FormatException('代理节点数量超过安全上限。');
    }
    return rows;
  }

  Future<Set<String>> _loadStoredProxyUrls(
    DatabaseExecutor database,
    String table,
  ) async {
    final rows = await database.query(
      table,
      columns: const <String>['endpoint_url'],
      limit: kAiExposureMaxProxyEndpoints + 1,
    );
    if (rows.length > kAiExposureMaxProxyEndpoints) {
      throw const FormatException('代理节点数量超过安全上限。');
    }
    final urls = <String>{};
    for (final row in rows) {
      final url = row['endpoint_url'];
      if (url is! String || !urls.add(_validateEndpointUrl(url))) {
        throw const FormatException('代理节点存储地址无效或重复。');
      }
    }
    return urls;
  }

  Future<void> _validateRequestHistoryPage({
    required int offset,
    required int limit,
  }) async {
    final rows = await _database.rawQuery(
      '''
      SELECT COUNT(*) AS entry_count,
             COALESCE(MAX(payload_bytes), 0) AS max_entry_bytes,
             COALESCE(SUM(payload_bytes), 0) AS total_bytes
      FROM (
        SELECT LENGTH(CAST(endpoint_url AS BLOB)) +
               LENGTH(CAST(sample_json AS BLOB)) AS payload_bytes
        FROM $_requestHistoryTable
        ORDER BY at_ms DESC, record_id DESC
        LIMIT ? OFFSET ?
      )
      ''',
      <Object?>[limit, offset],
    );
    final row = rows.firstOrNull;
    final entryCount = optionalIntegralIntFromValue(row?['entry_count']);
    final maxEntryBytes = optionalIntegralIntFromValue(row?['max_entry_bytes']);
    final totalBytes = optionalIntegralIntFromValue(row?['total_bytes']);
    if (entryCount == null || maxEntryBytes == null || totalBytes == null) {
      throw const FormatException('代理请求明细载荷统计无效。');
    }
    if (entryCount > limit ||
        maxEntryBytes > _maxProxyRequestSampleBytes ||
        totalBytes > _maxProxyRequestPageBytes) {
      throw const FormatException('代理请求明细载荷超过安全上限。');
    }
  }

  void _validateEndpoints(
    List<AiExposureProxyEndpoint> endpoints, {
    required bool includeStatistics,
    required bool includeSamples,
  }) {
    if (endpoints.length > kAiExposureMaxProxyEndpoints) {
      throw const FormatException('代理节点数量超过安全上限。');
    }
    final urls = <String>{};
    var totalBytes = 0;
    for (final endpoint in endpoints) {
      final url = _validateEndpointUrl(endpoint.url);
      if (!urls.add(url)) throw const FormatException('代理节点地址重复。');
      totalBytes += utf8ByteLength(url);
      if (includeStatistics) {
        final statistics = _statisticsValues(endpoint, '');
        totalBytes += utf8ByteLength('${statistics['statistics_json']}');
      }
      if (includeSamples) {
        final samples = _sampleValues(endpoint, '');
        totalBytes += utf8ByteLength('${samples['samples_json']}');
      }
      if (totalBytes > _maxProxyPayloadTotalBytes) {
        throw const FormatException('代理节点总载荷超过安全上限。');
      }
    }
  }

  String _validateEndpointUrl(String value) {
    if (value.isEmpty || value.trim() != value || value.length > 2048) {
      throw const FormatException('代理节点地址无效。');
    }
    return value;
  }
}
