import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../shared/data/database_service.dart';
import 'model/hardness_session_record.dart';

/// Persists a single Hardness Engineering session record in the SQLite
/// database so the session entry survives application restarts.
class HardnessSessionStore {
  HardnessSessionStore();

  Database get _db => DatabaseService.instance.database;

  /// Loads the persisted record, or returns `null` if none exists.
  ///
  /// Returns `null` if no record exists or if the persisted JSON is malformed.
  /// Throws [DatabaseException] or similar for serious database-level errors.
  Future<HardnessSessionRecord?> load() async {
    try {
      final rows = await _db.query('hardness_sessions', limit: 1);
      if (rows.isEmpty) {
        debugPrint('[HardnessSessionStore] load: no rows found');
        return null;
      }
      final dataJson = rows.first['data_json'] as String?;
      if (dataJson == null || dataJson.isEmpty) {
        debugPrint('[HardnessSessionStore] load: data_json is null or empty');
        return null;
      }
      final decoded = jsonDecode(dataJson);
      if (decoded is! Map) {
        debugPrint('[HardnessSessionStore] load: decoded JSON is not a Map');
        return null;
      }
      final record = HardnessSessionRecord.fromJson(
        Map<String, Object?>.from(decoded),
      );
      debugPrint('[HardnessSessionStore] load: successfully loaded record id=${record.id}');
      return record;
    } on FormatException catch (e) {
      // Corrupted JSON - treat as missing record rather than crashing.
      debugPrint('[HardnessSessionStore] load: JSON parse error: $e');
      return null;
    } catch (e) {
      debugPrint('[HardnessSessionStore] load: unexpected error: $e');
      rethrow;
    }
  }

  /// Persists [record] to the database.
  ///
  /// Replaces any previously stored session — the table is designed to hold
  /// at most one record at a time.  Old rows with a different primary key are
  /// explicitly deleted before the upsert to prevent stale data accumulation.
  Future<void> save(HardnessSessionRecord record) async {
    try {
      final dataJson = jsonEncode(record.toJson());
      final db = _db;
      await db.transaction((txn) async {
        // Remove any rows whose id differs from the current record so that
        // only one session exists at a time.
        await txn.delete(
          'hardness_sessions',
          where: 'id != ?',
          whereArgs: [record.id],
        );
        await txn.insert(
          'hardness_sessions',
          <String, Object?>{
            'id': record.id,
            'data_json': dataJson,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      debugPrint('[HardnessSessionStore] save: successfully saved record id=${record.id}');
    } catch (e) {
      debugPrint('[HardnessSessionStore] save: error saving record: $e');
      rethrow;
    }
  }

  /// Removes the persisted record.
  Future<void> clear() async {
    await _db.delete('hardness_sessions');
    debugPrint('[HardnessSessionStore] clear: deleted all records');
  }
}
