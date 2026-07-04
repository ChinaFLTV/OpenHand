import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/db/database_service.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/harness_session_record.dart';

/// Persists a single Harness Engineering session record in the SQLite
/// database so the session entry survives application restarts.
class HarnessSessionStore {
  HarnessSessionStore({Database? database}) : _database = database;

  final Database? _database;

  static const String _table = 'harness_sessions';

  Database get _db => _database ?? DatabaseService.instance.database;

  /// Loads the persisted record, or returns `null` if none exists.
  ///
  /// Returns `null` if no record exists or if the persisted JSON is malformed.
  /// Throws [DatabaseException] or similar for serious database-level errors.
  Future<HarnessSessionRecord?> load() async {
    try {
      final rows = await _db.query(_table, limit: 1);
      if (rows.isEmpty) {
        return null;
      }
      final dataJson = optionalStringFromValue(rows.first['data_json']);
      if (dataJson == null) {
        return null;
      }
      final decoded = optionalStringKeyedMapFromJsonText(dataJson);
      if (decoded == null) {
        return null;
      }
      return HarnessSessionRecord.fromJson(decoded);
    } on FormatException {
      // Corrupted JSON - treat as missing record rather than crashing.
      return null;
    }
  }

  /// Persists [record] to the database.
  ///
  /// Replaces any previously stored session — the table is designed to hold
  /// at most one record at a time.  Old rows with a different primary key are
  /// explicitly deleted before the upsert to prevent stale data accumulation.
  Future<void> save(HarnessSessionRecord record) async {
    final dataJson = jsonEncode(record.toJson());
    final db = _db;
    await db.transaction((txn) async {
      // Remove any rows whose id differs from the current record so that
      // only one session exists at a time.
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
  }

  /// Removes the persisted record.
  Future<void> clear() async {
    await _db.delete(_table);
  }
}
