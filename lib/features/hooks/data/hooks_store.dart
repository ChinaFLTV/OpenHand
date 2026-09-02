import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/model/hook_config.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';

/// 基于 SQLite 的 Hook 配置持久化层。
class HooksStore {
  HooksStore({this._database});

  static const String _tableName = 'hooks';
  static const List<String> _textColumns = <String>[
    'id',
    'event',
    'label',
    'script_path',
    'script_content',
  ];

  final Database? _database;

  Database get _db => _database ?? DatabaseService.instance.database;

  /// 确保 Hook 数据表存在，启动时调用一次。
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
    await _validateStoredScale();
    final rows = await _db.query(
      _tableName,
      orderBy: 'sort_order ASC, rowid ASC',
      limit: HookEntry.maxEntries + 1,
    );
    if (rows.length > HookEntry.maxEntries) {
      throw const FormatException('Hook 数量超过安全上限。');
    }
    final entries = <HookEntry>[];
    final seenIds = <String>{};
    var totalPayloadBytes = 0;
    for (final row in rows) {
      final payloadBytes = _payloadBytes(row);
      totalPayloadBytes += payloadBytes;
      if (payloadBytes > HookEntry.maxEntryPayloadBytes ||
          totalPayloadBytes > HookEntry.maxTotalPayloadBytes) {
        throw const FormatException('Hook 存储规模超过安全上限。');
      }
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
          id.length > HookEntry.maxIdCharacters ||
          !seenIds.add(id) ||
          event == null ||
          enabled == null ||
          timeoutSeconds is! int ||
          timeoutSeconds < HookEntry.minTimeoutSeconds ||
          timeoutSeconds > HookEntry.maxTimeoutSeconds ||
          sortOrder is! int ||
          sortOrder < 0) {
        throw FormatException('Hook 数据行无效：$id');
      }
      final scriptPath = _text(row, 'script_path');
      final scriptContent = _text(row, 'script_content');
      final label = _text(row, 'label');
      if (label.isEmpty ||
          label != label.trim() ||
          label.length > HookEntry.maxLabelCharacters ||
          scriptPath != scriptPath.trim() ||
          scriptPath.length > HookEntry.maxScriptPathCharacters ||
          scriptPath.contains('\u0000') ||
          (scriptPath.isNotEmpty == scriptContent.trim().isNotEmpty)) {
        throw FormatException('Hook 数据行无效：$id');
      }
      entries.add(
        HookEntry(
          id: id,
          event: event,
          label: label,
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
    _validateEntriesForWrite(entries);
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
    throw FormatException('Hook 字段 $key 必须为文本。');
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

  Future<void> _validateStoredScale() async {
    final payloadExpression = _textColumns
        .map((column) => 'COALESCE(LENGTH(CAST($column AS BLOB)), 0)')
        .join(' + ');
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS entry_count,
             COALESCE(MAX($payloadExpression), 0) AS max_entry_bytes,
             COALESCE(SUM($payloadExpression), 0) AS total_payload_bytes,
             COALESCE(SUM(CASE WHEN
               TYPEOF(id) != 'text' OR TYPEOF(event) != 'text' OR
               TYPEOF(label) != 'text' OR TYPEOF(script_path) != 'text' OR
               TYPEOF(script_content) != 'text'
             THEN 1 ELSE 0 END), 0) AS invalid_count
      FROM $_tableName
    ''');
    final row = rows.firstOrNull;
    final entryCount = optionalIntegralIntFromValue(row?['entry_count']);
    final maxEntryBytes = optionalIntegralIntFromValue(row?['max_entry_bytes']);
    final totalPayloadBytes = optionalIntegralIntFromValue(
      row?['total_payload_bytes'],
    );
    final invalidCount = optionalIntegralIntFromValue(row?['invalid_count']);
    if (entryCount == null ||
        maxEntryBytes == null ||
        totalPayloadBytes == null ||
        invalidCount == null) {
      throw const FormatException('Hook 存储统计无效。');
    }
    if (entryCount > HookEntry.maxEntries ||
        maxEntryBytes > HookEntry.maxEntryPayloadBytes ||
        totalPayloadBytes > HookEntry.maxTotalPayloadBytes ||
        invalidCount != 0) {
      throw const FormatException('Hook 存储规模超过安全上限。');
    }
  }

  void _validateEntriesForWrite(List<HookEntry> entries) {
    if (entries.length > HookEntry.maxEntries) {
      throw const FormatException('Hook 数量超过安全上限。');
    }
    final seenIds = <String>{};
    var totalPayloadBytes = 0;
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final scriptPath = entry.scriptPath ?? '';
      final scriptContent = entry.scriptContent ?? '';
      if (entry.id.isEmpty ||
          entry.id != entry.id.trim() ||
          entry.id.length > HookEntry.maxIdCharacters ||
          !seenIds.add(entry.id) ||
          entry.label.isEmpty ||
          entry.label != entry.label.trim() ||
          entry.label.length > HookEntry.maxLabelCharacters ||
          scriptPath != scriptPath.trim() ||
          scriptPath.length > HookEntry.maxScriptPathCharacters ||
          scriptPath.contains('\u0000') ||
          (scriptPath.isNotEmpty == scriptContent.trim().isNotEmpty) ||
          entry.timeoutSeconds < HookEntry.minTimeoutSeconds ||
          entry.timeoutSeconds > HookEntry.maxTimeoutSeconds) {
        throw FormatException('Hook 配置无效：${entry.id}');
      }
      final payloadBytes = _payloadBytes(_entryValues(entry, index));
      totalPayloadBytes += payloadBytes;
      if (payloadBytes > HookEntry.maxEntryPayloadBytes ||
          totalPayloadBytes > HookEntry.maxTotalPayloadBytes) {
        throw const FormatException('Hook 配置规模超过安全上限。');
      }
    }
  }

  int _payloadBytes(Map<String, Object?> row) {
    return _textColumns.fold<int>(
      0,
      (total, column) => total + utf8ByteLength('${row[column] ?? ''}'),
    );
  }
}
