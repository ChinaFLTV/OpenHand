import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../model/ai_model_health.dart';

const int _maxHealthRecordCount = 10000;
const int _maxHealthRecordBytes = kBytesPerMiB;
const int _maxHealthRecordsTotalBytes = 64 * kBytesPerMiB;
const int _maxHealthMetadataBytes = 512 * kBytesPerKiB;
const int _maxHealthIdentifierCharacters = 2048;
const int _maxHealthMessageCharacters = 256 * kBytesPerKiB;
const List<String> _healthRecordTextColumns = <String>[
  'id',
  'provider_config_id',
  'provider_name',
  'model_id',
  'checked_at',
  'status',
  'request_mode',
  'host',
  'model_kind',
  'error_message',
  'metadata_json',
];

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
      final safeLimit = limit.clamp(1, _maxHealthRecordCount);
      await _validateRecentScale(safeLimit);
      final rows = await _database.query(
        'ai_model_health_records',
        orderBy: 'checked_at_ms DESC',
        limit: safeLimit,
      );
      return rows.map(_recordFromRow).toList(growable: false);
    } on FormatException {
      rethrow;
    } catch (error, stack) {
      silentLog('ai_model_health_store', '读取模型健康巡检记录', error, stack);
      return const <AiModelHealthRecord>[];
    }
  }

  Future<void> insert(AiModelHealthRecord record) async {
    final metadata = record.metadata;
    validateCanonicalJsonSubset(
      metadata,
      metadata,
      path: 'ai_model_health_record.metadata',
      maxDepth: 16,
      maxContainerItems: 4096,
      maxTotalNodes: 32768,
    );
    final metadataJson = jsonEncode(metadata);
    if (utf8ByteLength(metadataJson) > _maxHealthMetadataBytes) {
      throw const FormatException('模型健康记录元数据超过安全上限。');
    }
    final row = <String, Object?>{
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
      'metadata_json': metadataJson,
    };
    _recordFromRow(row);
    if (_payloadBytes(row) > _maxHealthRecordBytes) {
      throw const FormatException('模型健康记录载荷超过安全上限。');
    }
    await _database.insert(
      'ai_model_health_records',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    final id = _requiredText(
      row,
      'id',
      allowEmpty: false,
      maxCharacters: _maxHealthIdentifierCharacters,
    );
    final checkedAtMs = _requiredNonNegativeInt(row, 'checked_at_ms');
    final checkedAtText = _requiredText(
      row,
      'checked_at',
      allowEmpty: false,
      maxCharacters: 64,
    );
    final checkedAt = DateTime.tryParse(checkedAtText);
    if (checkedAt == null ||
        !checkedAt.isUtc ||
        checkedAt.millisecondsSinceEpoch != checkedAtMs) {
      throw FormatException('模型健康记录时间无效：$id');
    }
    final success = row['success'];
    if (success is! int || (success != 0 && success != 1)) {
      throw FormatException('模型健康记录成功状态无效：$id');
    }
    final responseCode = _optionalInt(row, 'response_code');
    final port = _optionalInt(row, 'port');
    if ((responseCode != null && (responseCode < 100 || responseCode > 599)) ||
        (port != null && (port < 1 || port > 65535))) {
      throw FormatException('模型健康记录网络字段无效：$id');
    }
    final metadataJson = _requiredText(
      row,
      'metadata_json',
      allowEmpty: false,
      maxCharacters: _maxHealthMetadataBytes,
    );
    final decodedMetadata = jsonDecode(metadataJson);
    if (decodedMetadata is! Map) {
      throw FormatException('模型健康记录元数据必须为对象：$id');
    }
    final metadata = stringKeyedMapFromValue(decodedMetadata);
    validateCanonicalJsonSubset(
      metadata,
      metadata,
      path: 'ai_model_health_records.$id.metadata',
      maxDepth: 16,
      maxContainerItems: 4096,
      maxTotalNodes: 32768,
    );
    return AiModelHealthRecord(
      id: id,
      providerConfigId: _requiredText(
        row,
        'provider_config_id',
        maxCharacters: _maxHealthIdentifierCharacters,
      ),
      providerName: _requiredText(
        row,
        'provider_name',
        maxCharacters: _maxHealthIdentifierCharacters,
      ),
      modelId: _requiredText(
        row,
        'model_id',
        maxCharacters: _maxHealthIdentifierCharacters,
      ),
      checkedAt: checkedAt,
      success: success == 1,
      status: _requiredText(row, 'status', maxCharacters: 64),
      latencyMs: _requiredNonNegativeInt(row, 'latency_ms'),
      durationMs: _requiredNonNegativeInt(row, 'duration_ms'),
      responseCode: responseCode,
      requestMode: AiModelHealthRequestMode.fromStorage(row['request_mode']),
      host: _requiredText(
        row,
        'host',
        maxCharacters: _maxHealthIdentifierCharacters,
      ),
      port: port,
      modelKind: _requiredText(
        row,
        'model_kind',
        allowEmpty: false,
        maxCharacters: 64,
      ),
      errorMessage: _requiredText(
        row,
        'error_message',
        maxCharacters: _maxHealthMessageCharacters,
      ),
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  Future<void> _validateRecentScale(int limit) async {
    final payload = _healthRecordTextColumns
        .map((column) => 'COALESCE(LENGTH(CAST($column AS BLOB)), 0)')
        .join(' + ');
    final rows = await _database.rawQuery(
      '''
      SELECT COUNT(*) AS entry_count,
             COALESCE(MAX(payload_bytes), 0) AS max_entry_bytes,
             COALESCE(SUM(payload_bytes), 0) AS total_bytes
      FROM (
        SELECT $payload AS payload_bytes
        FROM ai_model_health_records
        ORDER BY checked_at_ms DESC
        LIMIT ?
      )
      ''',
      <Object?>[limit],
    );
    final row = rows.firstOrNull;
    final entryCount = optionalIntegralIntFromValue(row?['entry_count']);
    final maxEntryBytes = optionalIntegralIntFromValue(row?['max_entry_bytes']);
    final totalBytes = optionalIntegralIntFromValue(row?['total_bytes']);
    if (entryCount == null || maxEntryBytes == null || totalBytes == null) {
      throw const FormatException('模型健康记录统计无效。');
    }
    if (entryCount > limit ||
        maxEntryBytes > _maxHealthRecordBytes ||
        totalBytes > _maxHealthRecordsTotalBytes) {
      throw const FormatException('模型健康记录存储规模超过安全上限。');
    }
  }

  String _requiredText(
    Map<String, Object?> row,
    String key, {
    bool allowEmpty = true,
    required int maxCharacters,
  }) {
    final value = row[key];
    if (value is! String ||
        (!allowEmpty && value.isEmpty) ||
        value.length > maxCharacters) {
      throw FormatException('模型健康记录字段 $key 无效。');
    }
    return value;
  }

  int _requiredNonNegativeInt(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! int || value < 0) {
      throw FormatException('模型健康记录字段 $key 无效。');
    }
    return value;
  }

  int? _optionalInt(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! int) {
      throw FormatException('模型健康记录字段 $key 无效。');
    }
    return value;
  }

  int _payloadBytes(Map<String, Object?> row) {
    return _healthRecordTextColumns.fold<int>(
      0,
      (total, column) => total + utf8ByteLength('${row[column] ?? ''}'),
    );
  }
}
