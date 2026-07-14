import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/model/hook_config.dart';
import '../../../shared/db/database_service.dart';

/// Persistence layer for hooks configuration using SQLite.
class HooksStore {
  HooksStore({Database? database}) : _database = database;

  static const String _tableName = 'hooks';

  final Database? _database;

  Database get _db => _database ?? DatabaseService.instance.database;

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
        timeout_seconds INTEGER NOT NULL DEFAULT ${HookEntry.defaultTimeoutSeconds},
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
    final seenIds = <String>{};
    for (final row in rows) {
      final rawId = _text(row, 'id');
      final id = rawId.trim();
      final event = HookEvent.fromStorage(_text(row, 'event'));
      final enabledValue = row['enabled'];
      final enabled = enabledValue == 1
          ? true
          : enabledValue == 0
          ? false
          : null;
      final timeoutSeconds = row['timeout_seconds'];
      final sortOrder = row['sort_order'];
      if (id.isEmpty ||
          id != rawId ||
          !seenIds.add(id) ||
          event == null ||
          enabled == null ||
          timeoutSeconds is! int ||
          timeoutSeconds < HookEntry.minTimeoutSeconds ||
          timeoutSeconds > HookEntry.maxTimeoutSeconds ||
          sortOrder is! int ||
          sortOrder < 0) {
        throw FormatException('Invalid hook row: $id');
      }
      final scriptPath = _text(row, 'script_path');
      if (scriptPath != scriptPath.trim()) {
        throw FormatException('Invalid hook script path: $id');
      }
      final scriptContent = _text(row, 'script_content');
      entries.add(
        HookEntry(
          id: id,
          event: event,
          label: _text(row, 'label'),
          scriptPath: scriptPath.isEmpty ? null : scriptPath,
          scriptContent: scriptContent.isEmpty ? null : scriptContent,
          enabled: enabled,
          timeoutSeconds: timeoutSeconds,
        ),
      );
    }
    return entries;
  }

  Future<void> saveAll(List<HookEntry> entries) async {
    final batch = _db.batch();
    batch.delete(_tableName);
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      batch.insert(_tableName, _entryValues(entry, i));
    }
    await batch.commit(noResult: true);
  }

  String _text(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is String) return value;
    throw FormatException('Hook field $key must be text.');
  }

  Map<String, Object?> _entryValues(HookEntry entry, int sortOrder) {
    return <String, Object?>{
      'id': entry.id,
      'event': entry.event.storageValue,
      'label': entry.label,
      'script_path': entry.scriptPath ?? '',
      'script_content': entry.scriptContent ?? '',
      'enabled': entry.enabled ? 1 : 0,
      'timeout_seconds': HookEntry.normalizeTimeoutSeconds(
        entry.timeoutSeconds,
      ),
      'sort_order': sortOrder,
    };
  }
}
