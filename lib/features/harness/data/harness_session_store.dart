import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/db/database_service.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/serial_task_queue.dart';
import '../../../shared/util/text_clip.dart';
import '../model/harness_session_record.dart';

/// 在 SQLite 中持久化单个 Harness Engineering 会话。
class HarnessSessionStore {
  HarnessSessionStore({Database? database}) : _database = database;

  final Database? _database;
  final SerialTaskQueue _operations = SerialTaskQueue();

  static const String _table = 'harness_sessions';
  static const int _maxPayloadBytes = 32 * kBytesPerMiB;
  static const int _compactLogLinesPerPhase = 100;
  static const int _compactChangedFilesPerPhase = 200;
  static const String _payloadCompactionMarker =
      '⚠ 会话载荷达到安全上限，恢复时仅保留精简阶段日志和文件列表。';

  Database get _db => _database ?? DatabaseService.instance.database;

  /// 加载会话；载荷缺失、损坏或超限时抛出格式异常。
  Future<HarnessSessionRecord?> load() {
    return _operations.enqueue(() async {
      final dataJson = await _db.transaction<String?>((txn) async {
        final metadataRows = await txn.rawQuery('''
        SELECT id,
               TYPEOF(data_json) AS payload_type,
               LENGTH(CAST(data_json AS BLOB)) AS payload_bytes
        FROM $_table
        LIMIT 1
      ''');
        if (metadataRows.isEmpty) {
          return null;
        }
        final metadata = metadataRows.first;
        final id = metadata['id'];
        final payloadBytes = optionalIntegralIntFromValue(
          metadata['payload_bytes'],
        );
        if (id is! String ||
            id.isEmpty ||
            metadata['payload_type'] != 'text' ||
            payloadBytes == null) {
          throw const FormatException('Harness 会话载荷缺失。');
        }
        if (payloadBytes > _maxPayloadBytes) {
          throw const FormatException('Harness 会话载荷超过安全上限。');
        }
        final rows = await txn.query(
          _table,
          columns: const <String>['data_json'],
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        if (rows.isEmpty || rows.first['data_json'] is! String) {
          throw const FormatException('Harness 会话载荷缺失。');
        }
        return rows.first['data_json']! as String;
      });
      if (dataJson == null) return null;
      final decoded = optionalStringKeyedMapFromJsonText(dataJson);
      if (decoded == null) {
        throw const FormatException('Harness 会话载荷格式无效。');
      }
      return HarnessSessionRecord.fromJson(decoded);
    });
  }

  /// 保存会话并替换旧记录，避免历史数据累积。
  Future<void> save(HarnessSessionRecord record) {
    return _operations.enqueue(() async {
      final payload = record.toJson();
      var dataJson = jsonEncode(payload);
      var payloadBytes = utf8ByteLength(dataJson);
      if (payloadBytes > _maxPayloadBytes) {
        dataJson = jsonEncode(_compactPayload(payload));
        payloadBytes = utf8ByteLength(dataJson);
      }
      if (payloadBytes > _maxPayloadBytes) {
        dataJson = jsonEncode(_compactPayload(payload, metadataOnly: true));
        payloadBytes = utf8ByteLength(dataJson);
      }
      if (payloadBytes > _maxPayloadBytes) {
        throw StateError('Harness 会话载荷超过安全上限，无法保存。');
      }
      final db = _db;
      await db.transaction((txn) async {
        await txn.delete(
          _table,
          where: 'id != ?',
          whereArgs: <Object?>[record.id],
        );
        await txn.insert(_table, <String, Object?>{
          'id': record.id,
          'data_json': dataJson,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    });
  }

  static Map<String, Object?> _compactPayload(
    Map<String, Object?> payload, {
    bool metadataOnly = false,
  }) {
    final phaseLogs = payload['phase_logs'];
    if (phaseLogs is! List) return payload;
    return <String, Object?>{
      ...payload,
      'phase_logs': <Map<String, Object?>>[
        for (final rawLog in phaseLogs)
          _compactPhaseLog(
            stringKeyedMapFromValue(rawLog),
            metadataOnly: metadataOnly,
          ),
      ],
    };
  }

  static Map<String, Object?> _compactPhaseLog(
    Map<String, Object?> log, {
    required bool metadataOnly,
  }) {
    final rawLines = log['lines'];
    final retainedLines = metadataOnly || rawLines is! List
        ? const <Object?>[]
        : rawLines.skip(
            rawLines.length > _compactLogLinesPerPhase
                ? rawLines.length - _compactLogLinesPerPhase
                : 0,
          );
    final rawChangedFiles = log['changed_files'];
    final retainedChangedFiles = metadataOnly || rawChangedFiles is! List
        ? const <Object?>[]
        : rawChangedFiles.take(_compactChangedFilesPerPhase);
    return <String, Object?>{
      ...log,
      'lines': <Object?>[_payloadCompactionMarker, ...retainedLines],
      'changed_files': <Map<String, Object?>>[
        for (final rawFile in retainedChangedFiles)
          <String, Object?>{
            ...stringKeyedMapFromValue(rawFile),
            'before_content': null,
            'after_content': null,
            'content_truncated': true,
          },
      ],
    };
  }

  /// 删除持久化会话。
  Future<void> clear() => _operations.enqueue<void>(() async {
    await _db.delete(_table);
  });
}
