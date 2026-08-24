import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../model/ai_model_proxy_models.dart';

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
      final decoded = jsonDecode('${rows.first['value']}');
      return AiModelProxySettings.fromJson(decoded);
    } catch (error, stack) {
      silentLog('ai_model_proxy_store', '读取模型服务设置', error, stack);
      return const AiModelProxySettings();
    }
  }

  Future<void> save(AiModelProxySettings settings) async {
    await _database.insert('app_settings', <String, Object?>{
      'key': _key,
      'value': jsonEncode(settings.toJson()),
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
    } catch (error, stack) {
      silentLog('ai_model_proxy_store', '读取中转站遥测', error, stack);
      return const <AiModelProxyTelemetryBucket>[];
    }
  }

  Future<void> mergeTelemetry(
    Iterable<AiModelProxyTelemetryBucket> buckets,
  ) async {
    final values = buckets.toList(growable: false);
    if (values.isEmpty) return;
    await _pruneTelemetryIfNeeded();
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((txn) async {
      for (final bucket in values) {
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
            ingress_count = ingress_count + excluded.ingress_count,
            success_count = success_count + excluded.success_count,
            failure_count = failure_count + excluded.failure_count,
            ingress_error_count = ingress_error_count + excluded.ingress_error_count,
            inbound_bytes = inbound_bytes + excluded.inbound_bytes,
            outbound_bytes = outbound_bytes + excluded.outbound_bytes,
            connection_sample_count = connection_sample_count + excluded.connection_sample_count,
            connection_total = connection_total + excluded.connection_total,
            last_connections = CASE
              WHEN excluded.connection_sample_count > 0
              THEN excluded.last_connections
              ELSE last_connections
            END,
            peak_connections = MAX(peak_connections, excluded.peak_connections),
            peak_active_requests = MAX(peak_active_requests, excluded.peak_active_requests),
            duration_total_ms = duration_total_ms + excluded.duration_total_ms,
            token_count = token_count + excluded.token_count,
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
            jsonEncode(bucket.metadata),
            jsonEncode(bucket.environment),
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
    return AiModelProxyTelemetryBucket(
      bucketAtMs: _readInt(row['bucket_at_ms']),
      ingressCount: _readInt(row['ingress_count']),
      successCount: _readInt(row['success_count']),
      failureCount: _readInt(row['failure_count']),
      ingressErrorCount: _readInt(row['ingress_error_count']),
      inboundBytes: _readInt(row['inbound_bytes']),
      outboundBytes: _readInt(row['outbound_bytes']),
      connectionSampleCount: _readInt(row['connection_sample_count']),
      connectionTotal: _readInt(row['connection_total']),
      lastConnections: _readInt(row['last_connections']),
      peakConnections: _readInt(row['peak_connections']),
      peakActiveRequests: _readInt(row['peak_active_requests']),
      durationTotalMs: _readInt(row['duration_total_ms']),
      tokenCount: _readInt(row['token_count']),
      metadata: _decodeObjectMap(row['metadata_json']),
      environment: _decodeObjectMap(row['environment_json']),
    );
  }

  static int _readInt(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return (parsed ?? 0).clamp(0, 1 << 62).toInt();
  }

  static Map<String, Object?> _decodeObjectMap(Object? value) {
    try {
      final decoded = jsonDecode('$value');
      if (decoded is! Map) return const <String, Object?>{};
      return <String, Object?>{
        for (final entry in decoded.entries) '${entry.key}': entry.value,
      };
    } on FormatException {
      return const <String, Object?>{};
    }
  }
}
