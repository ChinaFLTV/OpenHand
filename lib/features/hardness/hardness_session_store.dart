import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../shared/data/database_service.dart';
import 'model/hardness_session_record.dart';

/// Persists a single Hardness Engineering session record in the SQLite
/// database so the session entry survives application restarts.
class HardnessSessionStore {
  HardnessSessionStore();

  Database get _db => DatabaseService.instance.database;

  /// Loads the persisted record, or returns `null` if none exists.
  Future<HardnessSessionRecord?> load() async {
    try {
      final rows = await _db.query('hardness_sessions', limit: 1);
      if (rows.isEmpty) return null;
      final dataJson = rows.first['data_json'] as String?;
      if (dataJson == null || dataJson.isEmpty) return null;
      final decoded = jsonDecode(dataJson);
      if (decoded is! Map) return null;
      return HardnessSessionRecord.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  /// Persists [record] to the database.
  Future<void> save(HardnessSessionRecord record) async {
    final dataJson = jsonEncode(record.toJson());
    await _db.insert(
      'hardness_sessions',
      <String, Object?>{
        'id': record.id,
        'data_json': dataJson,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes the persisted record.
  Future<void> clear() async {
    await _db.delete('hardness_sessions');
  }
}
