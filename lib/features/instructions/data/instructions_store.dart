/// 用户指令持久化层。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/db/database_service.dart';
import '../model/user_instruction_entry.dart';

class InstructionsStore {
  InstructionsStore({Database? database})
    : _db = database ?? DatabaseService.instance.database;

  final Database _db;

  static const String _table = 'user_instructions';

  Future<List<UserInstructionEntry>> loadAll() async {
    final rows = await _db.query(
      _table,
      orderBy: 'sort_order ASC, created_at ASC',
      limit: UserInstructionEntry.maxEntries + 1,
    );
    if (rows.length > UserInstructionEntry.maxEntries) {
      throw const FormatException('用户指令数量超过安全上限。');
    }
    final result = <UserInstructionEntry>[];
    final seenIds = <String>{};
    for (final row in rows) {
      final entry = _rowToEntry(row);
      if (!seenIds.add(entry.id)) {
        throw FormatException('用户指令 ID 重复：${entry.id}');
      }
      result.add(entry);
    }
    return result;
  }

  Future<void> saveAll(List<UserInstructionEntry> entries) async {
    if (entries.length > UserInstructionEntry.maxEntries) {
      throw const FormatException('用户指令数量超过安全上限。');
    }
    final batch = _db.batch();
    batch.delete(_table);
    for (final entry in entries) {
      batch.insert(_table, _entryToRow(entry));
    }
    await batch.commit(noResult: true);
  }

  Map<String, Object?> _entryToRow(UserInstructionEntry entry) {
    return <String, Object?>{
      'id': entry.id,
      'name': UserInstructionEntry.normalizeName(entry.name),
      'body': UserInstructionEntry.normalizeBody(entry.body),
      'description': UserInstructionEntry.normalizeOneLine(
        entry.description,
        UserInstructionEntry.maxDescriptionLength,
      ),
      'version': UserInstructionEntry.normalizeVersion(entry.version),
      'apply_to': UserInstructionEntry.normalizeOneLine(
        entry.applyTo,
        UserInstructionEntry.maxApplyToLength,
      ),
      'notes_json': jsonEncode(
        UserInstructionEntry.normalizeStringList(
          entry.notes,
          maxItems: UserInstructionEntry.maxNotes,
          maxItemLength: UserInstructionEntry.maxNoteLength,
        ),
      ),
      'task_types_json': jsonEncode(
        UserInstructionEntry.normalizeStringList(
          entry.taskTypes,
          maxItems: UserInstructionEntry.maxTaskTypes,
          maxItemLength: 64,
          dedupeCaseInsensitive: true,
        ),
      ),
      'keywords_json': jsonEncode(
        UserInstructionEntry.normalizeStringList(
          entry.keywords,
          maxItems: UserInstructionEntry.maxKeywords,
          maxItemLength: 64,
          dedupeCaseInsensitive: true,
        ),
      ),
      'enabled': entry.enabled ? 1 : 0,
      'sort_order': entry.sortOrder,
      'created_at': entry.createdAt.toUtc().toIso8601String(),
      'updated_at': entry.updatedAt.toUtc().toIso8601String(),
    };
  }

  UserInstructionEntry _rowToEntry(Map<String, Object?> row) {
    final rawId = _text(row, 'id');
    final id = rawId.trim();
    final rawName = _text(row, 'name');
    final rawBody = _text(row, 'body');
    final rawDescription = _text(row, 'description');
    final rawVersion = _text(row, 'version');
    final rawApplyTo = _text(row, 'apply_to');
    final name = UserInstructionEntry.normalizeName(rawName);
    final body = UserInstructionEntry.normalizeBody(rawBody);
    final description = UserInstructionEntry.normalizeOneLine(
      rawDescription,
      UserInstructionEntry.maxDescriptionLength,
    );
    final version = UserInstructionEntry.normalizeVersion(rawVersion);
    final applyTo = UserInstructionEntry.normalizeOneLine(
      rawApplyTo,
      UserInstructionEntry.maxApplyToLength,
    );
    final enabledValue = row['enabled'];
    final enabled = enabledValue == 1
        ? true
        : enabledValue == 0
        ? false
        : null;
    final sortOrder = row['sort_order'];
    final createdAt = _dateTime(row, 'created_at');
    final updatedAt = _dateTime(row, 'updated_at');
    if (id.isEmpty ||
        id != rawId ||
        name.isEmpty ||
        body.isEmpty ||
        name != rawName ||
        body != rawBody ||
        description != rawDescription ||
        version != rawVersion ||
        applyTo != rawApplyTo ||
        enabled == null ||
        sortOrder is! int ||
        sortOrder < 0) {
      throw FormatException('用户指令记录无效：$id');
    }
    final notes = _decodeStringList(
      row['notes_json'],
      maxItems: UserInstructionEntry.maxNotes,
      maxItemLength: UserInstructionEntry.maxNoteLength,
    );
    final taskTypes = _decodeStringList(
      row['task_types_json'],
      maxItems: UserInstructionEntry.maxTaskTypes,
      maxItemLength: 64,
      dedupeCaseInsensitive: true,
    );
    final keywords = _decodeStringList(
      row['keywords_json'],
      maxItems: UserInstructionEntry.maxKeywords,
      maxItemLength: 64,
      dedupeCaseInsensitive: true,
    );
    return UserInstructionEntry(
      id: id,
      name: name,
      body: body,
      description: description,
      version: version,
      applyTo: applyTo,
      notes: notes,
      taskTypes: taskTypes,
      keywords: keywords,
      enabled: enabled,
      sortOrder: sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  List<String> _decodeStringList(
    Object? raw, {
    required int maxItems,
    required int maxItemLength,
    bool dedupeCaseInsensitive = false,
  }) {
    if (raw is! String) {
      throw const FormatException('用户指令列表字段必须是 JSON 文本。');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.any((item) => item is! String)) {
      throw const FormatException('用户指令列表字段必须是数组。');
    }
    final normalized = UserInstructionEntry.normalizeStringList(
      decoded.cast<String>(),
      maxItems: maxItems,
      maxItemLength: maxItemLength,
      dedupeCaseInsensitive: dedupeCaseInsensitive,
    );
    if (!listEquals(decoded.cast<String>(), normalized)) {
      throw const FormatException('用户指令列表字段格式不规范。');
    }
    return normalized;
  }

  String _text(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is String) return value;
    throw FormatException('用户指令字段 $key 必须是文本。');
  }

  DateTime _dateTime(Map<String, Object?> row, String key) {
    final raw = _text(row, key);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || parsed.toUtc().toIso8601String() != raw) {
      throw FormatException('用户指令字段 $key 无效。');
    }
    return parsed;
  }
}
