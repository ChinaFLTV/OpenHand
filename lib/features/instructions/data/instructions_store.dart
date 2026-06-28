/// Instructions persistence layer
library;

import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/db/database_service.dart';
import '../../../shared/util/input_value_parsing.dart';
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
    );
    final result = <UserInstructionEntry>[];
    for (final row in rows) {
      try {
        result.add(_rowToEntry(row));
      } catch (_) {
        // Skip corrupt rows; never blow up controller load.
        continue;
      }
    }
    return result;
  }

  Future<void> saveAll(List<UserInstructionEntry> entries) async {
    final batch = _db.batch();
    batch.delete(_table);
    for (final entry in entries) {
      batch.insert(_table, _entryToRow(entry));
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsert(UserInstructionEntry entry) async {
    await _db.insert(
      _table,
      _entryToRow(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteById(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: <Object?>[id]);
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
    final createdAt =
        DateTime.tryParse('${row['created_at'] ?? ''}') ?? DateTime.now();
    final updatedAt =
        DateTime.tryParse('${row['updated_at'] ?? ''}') ?? createdAt;
    return UserInstructionEntry(
      id: '${row['id'] ?? ''}',
      name: UserInstructionEntry.normalizeName('${row['name'] ?? ''}'),
      body: UserInstructionEntry.normalizeBody('${row['body'] ?? ''}'),
      description: UserInstructionEntry.normalizeOneLine(
        '${row['description'] ?? ''}',
        UserInstructionEntry.maxDescriptionLength,
      ),
      version: UserInstructionEntry.normalizeVersion(
        '${row['version'] ?? '1.0'}',
      ),
      applyTo: UserInstructionEntry.normalizeOneLine(
        '${row['apply_to'] ?? ''}',
        UserInstructionEntry.maxApplyToLength,
      ),
      notes: notes,
      taskTypes: taskTypes,
      keywords: keywords,
      enabled: boolFromValue(row['enabled'], defaultValue: true),
      sortOrder: intFromValue(row['sort_order'], fallback: 0),
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
    if (raw is! String || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      return UserInstructionEntry.normalizeStringList(
        stringListFromValue(decoded),
        maxItems: maxItems,
        maxItemLength: maxItemLength,
        dedupeCaseInsensitive: dedupeCaseInsensitive,
      );
    } catch (_) {}
    return const <String>[];
  }
}
