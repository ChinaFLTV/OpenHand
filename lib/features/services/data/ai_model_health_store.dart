import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/ai_model_health.dart';

class AiModelHealthStore {
  static const String settingsKey = 'ai_model_health_settings_v1';
  Database get _database => DatabaseService.instance.database;

  Future<AiModelHealthSettings> loadSettings() async {
    try {
      final rows = await _database.query(
        'app_settings',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object?>[settingsKey],
        limit: 1,
      );
      if (rows.isEmpty) return const AiModelHealthSettings();
      return AiModelHealthSettings.fromJson(
        jsonDecode('${rows.first['value']}'),
      );
    } catch (error, stack) {
      silentLog('ai_model_health_store', '读取模型健康巡检设置', error, stack);
      return const AiModelHealthSettings();
    }
  }

  Future<void> saveSettings(AiModelHealthSettings settings) async {
    await _database.insert('app_settings', <String, Object?>{
      'key': settingsKey,
      'value': jsonEncode(settings.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AiModelHealthRecord>> loadRecent({int limit = 4000}) async {
    try {
      final rows = await _database.query(
        'ai_model_health_records',
        orderBy: 'checked_at_ms DESC',
        limit: limit.clamp(1, 10000),
      );
      return rows.map(_recordFromRow).toList(growable: false);
    } catch (error, stack) {
      silentLog('ai_model_health_store', '读取模型健康巡检记录', error, stack);
      return const <AiModelHealthRecord>[];
    }
  }

  Future<void> insert(AiModelHealthRecord record) async {
    await _database.insert('ai_model_health_records', <String, Object?>{
      'id': record.id,
      'provider_config_id': record.providerConfigId,
      'provider_name': record.providerName,
      'model_id': record.modelId,
      'checked_at_ms': record.checkedAt.millisecondsSinceEpoch,
      'checked_at': record.checkedAt.toUtc().toIso8601String(),
      'success': record.success ? 1 : 0,
      'status': record.status,
      'latency_ms': record.latencyMs,
      'duration_ms': record.durationMs,
      'response_code': record.responseCode,
      'request_mode': record.requestMode.storageValue,
      'host': record.host,
      'port': record.port,
      'model_kind': record.modelKind,
      'error_message': record.errorMessage,
      'metadata_json': jsonEncode(record.metadata),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> prune(int retentionDays) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: retentionDays.clamp(1, 3650)))
        .millisecondsSinceEpoch;
    await _database.delete(
      'ai_model_health_records',
      where: 'checked_at_ms < ?',
      whereArgs: <Object?>[cutoff],
    );
  }

  AiModelHealthRecord _recordFromRow(Map<String, Object?> row) {
    final metadata = jsonDecode('${row['metadata_json'] ?? '{}'}');
    return AiModelHealthRecord(
      id: '${row['id'] ?? ''}',
      providerConfigId: '${row['provider_config_id'] ?? ''}',
      providerName: '${row['provider_name'] ?? ''}',
      modelId: '${row['model_id'] ?? ''}',
      checkedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['checked_at_ms'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      success: (row['success'] as num?)?.toInt() == 1,
      status: '${row['status'] ?? ''}',
      latencyMs: (row['latency_ms'] as num?)?.toInt() ?? 0,
      durationMs: (row['duration_ms'] as num?)?.toInt() ?? 0,
      responseCode: (row['response_code'] as num?)?.toInt(),
      requestMode: AiModelHealthRequestMode.fromStorage(row['request_mode']),
      host: '${row['host'] ?? ''}',
      port: (row['port'] as num?)?.toInt(),
      modelKind: '${row['model_kind'] ?? 'text'}',
      errorMessage: '${row['error_message'] ?? ''}',
      metadata: stringKeyedMapFromValue(metadata),
    );
  }
}
