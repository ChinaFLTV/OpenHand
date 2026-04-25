import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../app/model/hook_config.dart';
import '../../shared/data/database_service.dart';

/// Persistence layer for hooks configuration using SQLite.
class HooksStore {
  HooksStore();

  static const String _tableName = 'hooks';

  Database get _db => DatabaseService.instance.database;

  /// Ensures the hooks table exists. Call once at startup.
  Future<void> ensureTable() async {
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id              TEXT PRIMARY KEY,
        event           TEXT NOT NULL,
        label           TEXT NOT NULL DEFAULT '',
        script_path     TEXT NOT NULL DEFAULT '',
        script_content  TEXT NOT NULL DEFAULT '',
        enabled         INTEGER NOT NULL DEFAULT 1,
        timeout_seconds INTEGER NOT NULL DEFAULT 12,
        sort_order      INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<List<HookEntry>> loadAll() async {
    final rows = await _db.query(
      _tableName,
      orderBy: 'sort_order ASC, rowid ASC',
    );
    final entries = <HookEntry>[];
    for (final row in rows) {
      try {
        entries.add(
          HookEntry(
            id: '${row['id']}'.trim(),
            event:
                HookEvent.fromStorage('${row['event']}') ??
                HookEvent.sessionStart,
            label: '${row['label'] ?? ''}'.trim(),
            scriptPath: _nullIfEmpty('${row['script_path'] ?? ''}'),
            scriptContent: _nullIfEmpty('${row['script_content'] ?? ''}'),
            enabled: (row['enabled'] as int?) == 1,
            timeoutSeconds: (row['timeout_seconds'] as int?) ?? 12,
          ),
        );
      } catch (error) {
        assert(() {
          debugPrint(
            '[hooks_store] skipped malformed row id=${row['id']}: $error',
          );
          return true;
        }());
      }
    }
    return entries;
  }

  Future<void> save(HookEntry entry, int sortOrder) async {
    await _db.insert(_tableName, <String, Object?>{
      'id': entry.id,
      'event': entry.event.storageValue,
      'label': entry.label,
      'script_path': entry.scriptPath ?? '',
      'script_content': entry.scriptContent ?? '',
      'enabled': entry.enabled ? 1 : 0,
      'timeout_seconds': entry.timeoutSeconds,
      'sort_order': sortOrder,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveAll(List<HookEntry> entries) async {
    final batch = _db.batch();
    batch.delete(_tableName);
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      batch.insert(_tableName, <String, Object?>{
        'id': entry.id,
        'event': entry.event.storageValue,
        'label': entry.label,
        'script_path': entry.scriptPath ?? '',
        'script_content': entry.scriptContent ?? '',
        'enabled': entry.enabled ? 1 : 0,
        'timeout_seconds': entry.timeoutSeconds,
        'sort_order': i,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> delete(String id) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: <Object?>[id]);
  }
}

String? _nullIfEmpty(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
