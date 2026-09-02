import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../model/ai_model_proxy_models.dart';

const int _maxSettingsBytes = 8 * kBytesPerMiB;
const int _maxSettingsRoutes = 512;
const int _maxBackendsPerRoute = 512;
const int _maxTotalBackends = 4096;
const int _maxSettingsIdentifierCharacters = 8 * kBytesPerKiB;
const int _maxApiKeyCharacters = 64 * kBytesPerKiB;
const int _maxTelemetryBatchCount = 10000;
const int _maxTelemetryJsonBytes = 512 * kBytesPerKiB;
const int _maxTelemetryRowBytes = kBytesPerMiB;
const int _maxTelemetryPageBytes = 64 * kBytesPerMiB;
const int _maxTelemetryValue = 1 << 52;
const int _telemetryScalarBytes = 15 * 8;

class AiModelProxyStore {
  static const String _key = 'ai_model_proxy_settings_v1';
  static const String _telemetryTable = 'ai_model_proxy_telemetry';

  int? _lastTelemetryPruneDay;

  Database get _database => DatabaseService.instance.database;

  Future<AiModelProxySettings> load() async {
    try {
      final rows = await _database.query(
        'app_settings',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object?>[_key],
        limit: 1,
      );
      if (rows.isEmpty) return const AiModelProxySettings();
      final encoded = rows.first['value'];
      if (encoded is! String || encoded.trim().isEmpty) {
        throw const FormatException('模型中转站设置为空或类型无效。');
      }
      if (utf8ByteLength(encoded) > _maxSettingsBytes) {
        throw const FormatException('模型中转站设置超过安全上限。');
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('模型中转站设置必须为对象。');
      }
      final payload = stringKeyedMapFromValue(decoded);
      _validateSettingsPayload(payload);
      validateCanonicalJsonSubset(
        payload,
        payload,
        path: 'ai_model_proxy_settings',
        maxDepth: 16,
        maxContainerItems: 4096,
        maxTotalNodes: 100000,
      );
      final settings = AiModelProxySettings.fromJson(payload);
      _validateSettings(settings);
      return settings;
    } catch (error, stack) {
      silentLog('ai_model_proxy_store', '读取模型服务设置', error, stack);
      return const AiModelProxySettings();
    }
  }

  Future<void> save(AiModelProxySettings settings) async {
    final encoded = _encodeSettings(settings);
    await _database.insert('app_settings', <String, Object?>{
      'key': _key,
      'value': encoded,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AiModelProxyTelemetryBucket>> loadTelemetry({
    List<AiModelProxyRequestRecord> legacyRecords =
        const <AiModelProxyRequestRecord>[],
    int limit = aiModelProxyTelemetryLoadLimit,
  }) async {
    try {
      await _pruneTelemetryIfNeeded(force: true);
      final safeLimit = limit.clamp(12, 10000);
      Future<List<AiModelProxyTelemetryBucket>> read() async {
        await _validateTelemetryPage(safeLimit);
        final rows = await _database.query(
          _telemetryTable,
          orderBy: 'bucket_at_ms DESC',
          limit: safeLimit,
        );
        return <AiModelProxyTelemetryBucket>[
          for (final row in rows.reversed) _telemetryFromRow(row),
        ];
      }

      var buckets = await read();
      if (legacyRecords.isNotEmpty &&
          buckets.every((bucket) => bucket.recordedRequestCount <= 0)) {
        final extras = _requestTelemetryFromRecords(legacyRecords);
        if (extras.isNotEmpty) {
          await mergeTelemetry(extras);
          buckets = await read();
        }
      }
      return buckets;
    } on FormatException {
      rethrow;
    } catch (error, stack) {
      silentLog('ai_model_proxy_store', '读取中转站遥测', error, stack);
      return const <AiModelProxyTelemetryBucket>[];
    }
  }

  Future<void> mergeTelemetry(
    Iterable<AiModelProxyTelemetryBucket> buckets,
  ) async {
    final mergedBuckets = <int, AiModelProxyTelemetryBucket>{};
    var inputCount = 0;
    for (final bucket in buckets) {
      inputCount += 1;
      if (inputCount > _maxTelemetryBatchCount) {
        throw const FormatException('中转站遥测批量写入数量超过安全上限。');
      }
      _validateTelemetryBucket(bucket);
      final current = mergedBuckets[bucket.bucketAtMs];
      final merged = current?.merge(bucket) ?? bucket;
      _validateTelemetryBucket(merged);
      mergedBuckets[bucket.bucketAtMs] = merged;
    }
    if (mergedBuckets.isEmpty) return;
    final rows =
        <
          ({
            AiModelProxyTelemetryBucket bucket,
            String metadata,
            String environment,
          })
        >[];
    var totalPayloadBytes = 0;
    for (final bucket in mergedBuckets.values) {
      final metadata = _encodeTelemetryMap(bucket.metadata, '中转站遥测元数据');
      final environment = _encodeTelemetryMap(bucket.environment, '中转站遥测环境');
      final payloadBytes =
          utf8ByteLength(metadata) +
          utf8ByteLength(environment) +
          _telemetryScalarBytes;
      if (payloadBytes > _maxTelemetryRowBytes) {
        throw const FormatException('中转站遥测单项载荷超过安全上限。');
      }
      totalPayloadBytes += payloadBytes;
      if (totalPayloadBytes > _maxTelemetryPageBytes) {
        throw const FormatException('中转站遥测批量载荷超过安全上限。');
      }
      rows.add((bucket: bucket, metadata: metadata, environment: environment));
    }
    await _pruneTelemetryIfNeeded();
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((txn) async {
      for (final row in rows) {
        final bucket = row.bucket;
        await txn.rawInsert(
          '''
          INSERT INTO $_telemetryTable (
            bucket_at_ms,
            ingress_count,
            success_count,
            failure_count,
            ingress_error_count,
            inbound_bytes,
            outbound_bytes,
            connection_sample_count,
            connection_total,
            last_connections,
            peak_connections,
            peak_active_requests,
            duration_total_ms,
            token_count,
            metadata_json,
            environment_json,
            updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(bucket_at_ms) DO UPDATE SET
            ingress_count = MIN($_maxTelemetryValue, ingress_count + excluded.ingress_count),
            success_count = MIN($_maxTelemetryValue, success_count + excluded.success_count),
            failure_count = MIN($_maxTelemetryValue, failure_count + excluded.failure_count),
            ingress_error_count = MIN($_maxTelemetryValue, ingress_error_count + excluded.ingress_error_count),
            inbound_bytes = MIN($_maxTelemetryValue, inbound_bytes + excluded.inbound_bytes),
            outbound_bytes = MIN($_maxTelemetryValue, outbound_bytes + excluded.outbound_bytes),
            connection_sample_count = MIN($_maxTelemetryValue, connection_sample_count + excluded.connection_sample_count),
            connection_total = MIN($_maxTelemetryValue, connection_total + excluded.connection_total),
            last_connections = CASE
              WHEN excluded.connection_sample_count > 0
              THEN excluded.last_connections
              ELSE last_connections
            END,
            peak_connections = MAX(peak_connections, excluded.peak_connections),
            peak_active_requests = MAX(peak_active_requests, excluded.peak_active_requests),
            duration_total_ms = MIN($_maxTelemetryValue, duration_total_ms + excluded.duration_total_ms),
            token_count = MIN($_maxTelemetryValue, token_count + excluded.token_count),
            metadata_json = CASE
              WHEN excluded.metadata_json <> '{}'
              THEN excluded.metadata_json
              ELSE metadata_json
            END,
            environment_json = CASE
              WHEN excluded.environment_json <> '{}'
              THEN excluded.environment_json
              ELSE environment_json
            END,
            updated_at = excluded.updated_at
          ''',
          <Object?>[
            bucket.bucketAtMs,
            bucket.ingressCount,
            bucket.successCount,
            bucket.failureCount,
            bucket.ingressErrorCount,
            bucket.inboundBytes,
            bucket.outboundBytes,
            bucket.connectionSampleCount,
            bucket.connectionTotal,
            bucket.lastConnections,
            bucket.peakConnections,
            bucket.peakActiveRequests,
            bucket.durationTotalMs,
            bucket.tokenCount,
            row.metadata,
            row.environment,
            updatedAt,
          ],
        );
      }
    });
  }

  List<AiModelProxyTelemetryBucket> _requestTelemetryFromRecords(
    Iterable<AiModelProxyRequestRecord> records,
  ) {
    final buckets = <int, AiModelProxyTelemetryBucket>{};
    final cutoff = DateTime.now().subtract(
      const Duration(days: aiModelProxyTelemetryRetentionDays),
    );
    for (final record in records) {
      if (record.startedAt.isBefore(cutoff)) continue;
      final key = aiModelProxyTelemetryBucketKey(record.startedAt);
      final delta = AiModelProxyTelemetryBucket(
        bucketAtMs: key,
        ingressCount: 1,
        successCount: record.success ? 1 : 0,
        failureCount: record.success ? 0 : 1,
        inboundBytes: record.inboundBytes,
        outboundBytes: record.outboundBytes,
        durationTotalMs: record.durationMs,
        tokenCount: record.tokens,
      );
      buckets[key] = buckets[key]?.merge(delta) ?? delta;
    }
    return buckets.values.toList(growable: false);
  }

  Future<void> _pruneTelemetryIfNeeded({bool force = false}) async {
    final now = DateTime.now().toUtc();
    final day = now.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    if (!force && _lastTelemetryPruneDay == day) return;
    final cutoff = now
        .subtract(const Duration(days: aiModelProxyTelemetryRetentionDays))
        .millisecondsSinceEpoch;
    await _database.delete(
      _telemetryTable,
      where: 'bucket_at_ms < ?',
      whereArgs: <Object?>[cutoff],
    );
    _lastTelemetryPruneDay = day;
  }

  AiModelProxyTelemetryBucket _telemetryFromRow(Map<String, Object?> row) {
    final bucketAtMs = _readTelemetryInt(row, 'bucket_at_ms');
    if (bucketAtMs.remainder(aiModelProxyTelemetryBucketMs) != 0) {
      throw const FormatException('中转站遥测时间桶未按分钟对齐。');
    }
    final updatedAt = row['updated_at'];
    final parsedUpdatedAt = updatedAt is String && updatedAt.length <= 64
        ? DateTime.tryParse(updatedAt)
        : null;
    if (parsedUpdatedAt == null || !parsedUpdatedAt.isUtc) {
      throw const FormatException('中转站遥测更新时间无效。');
    }
    return AiModelProxyTelemetryBucket(
      bucketAtMs: bucketAtMs,
      ingressCount: _readTelemetryInt(row, 'ingress_count'),
      successCount: _readTelemetryInt(row, 'success_count'),
      failureCount: _readTelemetryInt(row, 'failure_count'),
      ingressErrorCount: _readTelemetryInt(row, 'ingress_error_count'),
      inboundBytes: _readTelemetryInt(row, 'inbound_bytes'),
      outboundBytes: _readTelemetryInt(row, 'outbound_bytes'),
      connectionSampleCount: _readTelemetryInt(row, 'connection_sample_count'),
      connectionTotal: _readTelemetryInt(row, 'connection_total'),
      lastConnections: _readTelemetryInt(row, 'last_connections'),
      peakConnections: _readTelemetryInt(row, 'peak_connections'),
      peakActiveRequests: _readTelemetryInt(row, 'peak_active_requests'),
      durationTotalMs: _readTelemetryInt(row, 'duration_total_ms'),
      tokenCount: _readTelemetryInt(row, 'token_count'),
      metadata: _decodeTelemetryMap(row['metadata_json'], '中转站遥测元数据'),
      environment: _decodeTelemetryMap(row['environment_json'], '中转站遥测环境'),
    );
  }

  static int _readTelemetryInt(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! int || value < 0 || value > _maxTelemetryValue) {
      throw FormatException('中转站遥测字段 $key 无效。');
    }
    return value;
  }

  static Map<String, Object?> _decodeTelemetryMap(Object? value, String field) {
    if (value is! String ||
        value.isEmpty ||
        utf8ByteLength(value) > _maxTelemetryJsonBytes) {
      throw FormatException('$field 载荷无效。');
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw FormatException('$field 必须为对象。');
    final map = stringKeyedMapFromValue(decoded);
    validateCanonicalJsonSubset(
      map,
      map,
      path: field,
      maxDepth: 16,
      maxContainerItems: 4096,
      maxTotalNodes: 32768,
    );
    return Map<String, Object?>.unmodifiable(map);
  }

  static String _encodeTelemetryMap(Map<String, Object?> value, String field) {
    validateCanonicalJsonSubset(
      value,
      value,
      path: field,
      maxDepth: 16,
      maxContainerItems: 4096,
      maxTotalNodes: 32768,
    );
    final encoded = jsonEncode(value);
    if (utf8ByteLength(encoded) > _maxTelemetryJsonBytes) {
      throw FormatException('$field 超过安全上限。');
    }
    return encoded;
  }

  static void _validateTelemetryBucket(AiModelProxyTelemetryBucket bucket) {
    if (bucket.bucketAtMs < 0 ||
        bucket.bucketAtMs > _maxTelemetryValue ||
        bucket.bucketAtMs.remainder(aiModelProxyTelemetryBucketMs) != 0) {
      throw const FormatException('中转站遥测时间桶无效。');
    }
    for (final value in <int>[
      bucket.ingressCount,
      bucket.successCount,
      bucket.failureCount,
      bucket.ingressErrorCount,
      bucket.inboundBytes,
      bucket.outboundBytes,
      bucket.connectionSampleCount,
      bucket.connectionTotal,
      bucket.lastConnections,
      bucket.peakConnections,
      bucket.peakActiveRequests,
      bucket.durationTotalMs,
      bucket.tokenCount,
    ]) {
      if (value < 0 || value > _maxTelemetryValue) {
        throw const FormatException('中转站遥测数值超过安全范围。');
      }
    }
  }

  Future<void> _validateTelemetryPage(int limit) async {
    final usageRows = await _database.rawQuery(
      '''
      SELECT COUNT(*) AS entry_count,
             COALESCE(MAX(payload_bytes), 0) AS max_entry_bytes,
             COALESCE(SUM(payload_bytes), 0) AS total_bytes
      FROM (
        SELECT COALESCE(LENGTH(CAST(metadata_json AS BLOB)), 0) +
               COALESCE(LENGTH(CAST(environment_json AS BLOB)), 0) +
               COALESCE(LENGTH(CAST(updated_at AS BLOB)), 0) +
               $_telemetryScalarBytes AS payload_bytes
        FROM $_telemetryTable
        ORDER BY bucket_at_ms DESC
        LIMIT ?
      )
      ''',
      <Object?>[limit],
    );
    final usage = usageRows.firstOrNull;
    final entryCount = optionalIntegralIntFromValue(usage?['entry_count']);
    final maxEntryBytes = optionalIntegralIntFromValue(
      usage?['max_entry_bytes'],
    );
    final totalBytes = optionalIntegralIntFromValue(usage?['total_bytes']);
    if (entryCount == null || maxEntryBytes == null || totalBytes == null) {
      throw const FormatException('中转站遥测存储统计无效。');
    }
    if (entryCount > limit ||
        maxEntryBytes > _maxTelemetryRowBytes ||
        totalBytes > _maxTelemetryPageBytes) {
      throw const FormatException('中转站遥测存储规模超过安全上限。');
    }
  }

  static String _encodeSettings(AiModelProxySettings settings) {
    _validateSettings(settings);
    final payload = settings.toJson();
    validateCanonicalJsonSubset(
      payload,
      payload,
      path: 'ai_model_proxy_settings',
      maxDepth: 16,
      maxContainerItems: 4096,
      maxTotalNodes: 100000,
    );
    final encoded = jsonEncode(payload);
    if (utf8ByteLength(encoded) > _maxSettingsBytes) {
      throw const FormatException('模型中转站设置超过安全上限。');
    }
    return encoded;
  }

  static void _validateSettingsPayload(Map<String, Object?> payload) {
    final routes = _optionalList(payload, 'routes');
    if (routes.length > _maxSettingsRoutes) {
      throw const FormatException('模型中转站路由数量超过安全上限。');
    }
    var totalBackends = 0;
    for (final route in routes) {
      if (route is! Map) throw const FormatException('模型中转站路由格式无效。');
      final routeMap = stringKeyedMapFromValue(route);
      final backends = _optionalList(routeMap, 'backends');
      if (backends.length > _maxBackendsPerRoute) {
        throw const FormatException('模型中转站单路由后备数量超过安全上限。');
      }
      if (backends.any((backend) => backend is! Map)) {
        throw const FormatException('模型中转站后备格式无效。');
      }
      totalBackends += backends.length;
      if (totalBackends > _maxTotalBackends) {
        throw const FormatException('模型中转站后备总数超过安全上限。');
      }
    }
    final recentRequests = _optionalList(payload, 'recent_requests');
    final dailyHealth = _optionalList(payload, 'daily_health');
    if (recentRequests.length > aiModelProxyRecentRequestLimit ||
        recentRequests.any((record) => record is! Map)) {
      throw const FormatException('模型中转站近期请求格式无效。');
    }
    for (final record in recentRequests.cast<Map>()) {
      final values = record.values.whereType<String>();
      if (values.any(
        (value) => value.length > aiModelProxyMaxRequestTextCharacters,
      )) {
        throw const FormatException('模型中转站近期请求文本超过安全上限。');
      }
    }
    if (dailyHealth.length > aiModelProxyStatusHistoryDays ||
        dailyHealth.any((record) => record is! Map)) {
      throw const FormatException('模型中转站健康历史格式无效。');
    }
  }

  static List<Object?> _optionalList(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value == null) return const <Object?>[];
    if (value is! List) throw FormatException('模型中转站字段 $key 必须为集合。');
    return value;
  }

  static void _validateSettings(AiModelProxySettings settings) {
    if (settings.listenHost.isEmpty ||
        settings.listenHost.length > _maxSettingsIdentifierCharacters ||
        settings.apiKey.length > _maxApiKeyCharacters ||
        settings.listenPort < aiModelProxyMinListenPort ||
        settings.listenPort > aiModelProxyMaxListenPort ||
        settings.limitThreshold < 1 ||
        settings.limitThreshold > 1000000 ||
        settings.retryCount < 1 ||
        settings.retryCount > 10 ||
        settings.recentRequests.length > aiModelProxyRecentRequestLimit ||
        settings.dailyHealth.length > aiModelProxyStatusHistoryDays) {
      throw const FormatException('模型中转站设置字段无效。');
    }
    if (settings.routes.length > _maxSettingsRoutes) {
      throw const FormatException('模型中转站路由数量超过安全上限。');
    }
    for (final request in settings.recentRequests) {
      if (request.id.isEmpty) {
        throw const FormatException('模型中转站近期请求编号无效。');
      }
      if (request.toJson().values.whereType<String>().any(
        (value) => value.length > aiModelProxyMaxRequestTextCharacters,
      )) {
        throw const FormatException('模型中转站近期请求文本超过安全上限。');
      }
    }
    for (final health in settings.dailyHealth) {
      if (health.day.isEmpty ||
          health.day.length > 64 ||
          health.models.length > aiModelProxyDailyModelCap ||
          health.models.keys.any(
            (model) =>
                model.isEmpty ||
                model.length > _maxSettingsIdentifierCharacters,
          )) {
        throw const FormatException('模型中转站健康历史字段无效。');
      }
    }
    var totalBackends = 0;
    final exposedModels = <String>{};
    for (final route in settings.routes) {
      final exposedModel = route.exposedModel.trim();
      if (exposedModel.isEmpty ||
          exposedModel.length > _maxSettingsIdentifierCharacters ||
          !exposedModels.add(exposedModel.toLowerCase()) ||
          route.backends.length > _maxBackendsPerRoute) {
        throw const FormatException('模型中转站路由字段无效。');
      }
      totalBackends += route.backends.length;
      if (totalBackends > _maxTotalBackends) {
        throw const FormatException('模型中转站后备总数超过安全上限。');
      }
      final backends = <String>{};
      for (final backend in route.backends) {
        final providerId = backend.providerId.trim();
        final modelId = backend.modelId.trim();
        final key = '${providerId.toLowerCase()}\u0000${modelId.toLowerCase()}';
        if (providerId.isEmpty ||
            modelId.isEmpty ||
            providerId.length > _maxSettingsIdentifierCharacters ||
            modelId.length > _maxSettingsIdentifierCharacters ||
            !backends.add(key)) {
          throw const FormatException('模型中转站后备字段无效。');
        }
      }
    }
  }
}
