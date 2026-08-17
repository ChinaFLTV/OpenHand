import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../model/ai_exposure_models.dart';

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
      final statisticsRows = await _database.query(
        _statisticsTable,
        columns: const <String>['endpoint_url', 'statistics_json'],
      );
      final statisticsByUrl = <String, AiExposureProxyUsageStatistics>{};
      for (final row in statisticsRows) {
        final url = row['endpoint_url'] as String?;
        final encoded = row['statistics_json'] as String?;
        if (url == null || encoded == null) continue;
        try {
          statisticsByUrl[url] = AiExposureProxyUsageStatistics.fromJson(
            jsonDecode(encoded),
          );
        } catch (error, stack) {
          silentLog(
            'ai_exposure_preferences_store',
            '读取代理节点使用统计',
            error,
            stack,
          );
        }
      }
      final sampleRows = await _database.query(
        _samplesTable,
        columns: const <String>['endpoint_url', 'samples_json'],
      );
      final samplesByUrl = <String, List<AiExposureProxyProbeSample>>{};
      for (final row in sampleRows) {
        final url = row['endpoint_url'] as String?;
        final encoded = row['samples_json'] as String?;
        if (url == null || encoded == null) continue;
        try {
          final decodedSamples = jsonDecode(encoded);
          if (decodedSamples is! List) continue;
          final samples = decodedSamples
              .map(AiExposureProxyProbeSample.fromJson)
              .toList(growable: false);
          samplesByUrl[url] =
              samples.length <= kAiExposureProxyLatencySampleLimit
              ? samples
              : samples.sublist(
                  samples.length - kAiExposureProxyLatencySampleLimit,
                );
        } catch (error, stack) {
          silentLog(
            'ai_exposure_preferences_store',
            '读取代理节点巡检样本',
            error,
            stack,
          );
        }
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
    } catch (error, stack) {
      silentLog('ai_exposure_preferences_store', '读取扫描服务设置', error, stack);
      return AiExposurePreferences.defaults();
    }
  }

  Future<void> save(AiExposurePreferences preferences) async {
    await _database.transaction((transaction) async {
      await transaction.insert('app_settings', <String, Object?>{
        'key': _key,
        'value': jsonEncode(
          preferences.toJson(
            includeProxyStatistics: false,
            includeProxySamples: false,
          ),
        ),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final activeUrls = preferences.proxyConfiguration.endpoints
          .map((endpoint) => endpoint.url)
          .toSet();
      if (activeUrls.isEmpty) {
        await transaction.delete(_statisticsTable);
        await transaction.delete(_samplesTable);
        return;
      }
      final rows = await transaction.query(
        _statisticsTable,
        columns: const <String>['endpoint_url'],
      );
      final storedUrls = rows
          .map((row) => row['endpoint_url'] as String?)
          .whereType<String>()
          .toSet();
      final sampleRows = await transaction.query(
        _samplesTable,
        columns: const <String>['endpoint_url'],
      );
      final storedSampleUrls = sampleRows
          .map((row) => row['endpoint_url'] as String?)
          .whereType<String>()
          .toSet();
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
    await _database.transaction((transaction) async {
      final batch = transaction.batch();
      final createdAt = DateTime.now().toUtc().toIso8601String();
      for (final record in records) {
        if (!record.sample.atReported) continue;
        batch.insert(_requestHistoryTable, <String, Object?>{
          'record_id': record.recordId,
          'endpoint_url': record.endpointUrl,
          'at_ms': record.sample.at.millisecondsSinceEpoch,
          'result': record.sample.result,
          'response_time_ms': record.sample.responseTimeMs,
          'sample_json': jsonEncode(record.sample.toJson()),
          'created_at': createdAt,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
      final countRows = await transaction.rawQuery(
        'SELECT COUNT(*) AS count FROM $_requestHistoryTable',
      );
      final count = (countRows.firstOrNull?['count'] as num?)?.toInt() ?? 0;
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
    return <String, Object?>{
      'endpoint_url': endpoint.url,
      'statistics_json': jsonEncode(endpoint.statistics.toJson()),
      'updated_at': updatedAt,
    };
  }

  static Map<String, Object?> _sampleValues(
    AiExposureProxyEndpoint endpoint,
    String updatedAt,
  ) {
    return <String, Object?>{
      'endpoint_url': endpoint.url,
      'samples_json': jsonEncode(
        endpoint.samples
            .map((sample) => sample.toJson())
            .toList(growable: false),
      ),
      'updated_at': updatedAt,
    };
  }

  Future<int> countProxyRequestHistory() async {
    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM $_requestHistoryTable',
    );
    return (rows.firstOrNull?['count'] as num?)?.toInt() ?? 0;
  }

  Future<List<AiExposureProxyRequestRecord>> loadProxyRequestHistory({
    required int offset,
    required int limit,
  }) async {
    final rows = await _database.query(
      _requestHistoryTable,
      columns: const <String>['endpoint_url', 'sample_json'],
      orderBy: 'at_ms DESC, record_id DESC',
      offset: offset.clamp(0, kAiExposureProxyRequestHistoryLimit),
      limit: limit.clamp(1, 100),
    );
    final records = <AiExposureProxyRequestRecord>[];
    for (final row in rows) {
      final endpointUrl = row['endpoint_url'] as String?;
      final encoded = row['sample_json'] as String?;
      if (endpointUrl == null || encoded == null) continue;
      try {
        records.add(
          AiExposureProxyRequestRecord(
            endpointUrl: endpointUrl,
            sample: AiExposureProxyRequestSample.fromJson(jsonDecode(encoded)),
          ),
        );
      } catch (error, stack) {
        silentLog('ai_exposure_preferences_store', '读取代理请求明细', error, stack);
      }
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
    final rows = await _database.rawQuery(
      'SELECT (at_ms / ?) * ? AS bucket_ms, COUNT(*) AS total, '
      'SUM(response_time_ms) AS total_response_time_ms, '
      "SUM(CASE WHEN result = 'success' THEN 1 ELSE 0 END) AS successes, "
      "SUM(CASE WHEN result = 'failure' THEN 1 ELSE 0 END) AS failures, "
      "SUM(CASE WHEN result = 'timeout' THEN 1 ELSE 0 END) AS timeouts "
      'FROM $_requestHistoryTable WHERE at_ms >= ? '
      'GROUP BY bucket_ms ORDER BY bucket_ms ASC',
      <Object?>[intervalMs, intervalMs, startAt.millisecondsSinceEpoch],
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
    final startBucket =
        (startAt.millisecondsSinceEpoch ~/ intervalMs) * intervalMs;
    final endBucket =
        (DateTime.now().millisecondsSinceEpoch ~/ intervalMs) * intervalMs;
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
      return (value != null && value.trim().isNotEmpty) ? value.trim() : null;
    } catch (error, stack) {
      silentLog('ai_exposure_preferences_store', '读取外部服务令牌', error, stack);
      return null;
    }
  }

  Future<void> saveExternalAccessToken(String? token) async {
    if (token == null || token.trim().isEmpty) {
      await _database.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: const <Object?>[_externalTokenKey],
      );
      return;
    }
    await _database.insert('app_settings', <String, Object?>{
      'key': _externalTokenKey,
      'value': token.trim(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
