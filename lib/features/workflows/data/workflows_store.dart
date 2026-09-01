import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/db/database_service.dart';
import '../model/workflow_definition.dart';

class WorkflowsStore {
  WorkflowsStore({this._database});

  static const String _tableName = 'workflows';

  final Database? _database;

  Database get _db => _database ?? DatabaseService.instance.database;

  Future<void> ensureTable() async {
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id              TEXT PRIMARY KEY,
        name            TEXT NOT NULL,
        definition_json TEXT NOT NULL,
        created_at      TEXT NOT NULL,
        updated_at      TEXT NOT NULL
      )
    ''');
    await _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_workflows_updated_at '
      'ON $_tableName(updated_at DESC)',
    );
  }

  Future<List<WorkflowDefinition>> loadAll() async {
    final rows = await _db.query(_tableName, orderBy: 'updated_at DESC');
    return rows
        .map((row) {
          final raw = row['definition_json'];
          if (raw is! String || raw.length > 4 * 1024 * 1024) {
            throw const FormatException('工作流配置大小无效。');
          }
          final decoded = jsonDecode(raw);
          if (decoded is! Map) throw const FormatException('工作流配置格式无效。');
          return WorkflowDefinition.fromJson(<String, Object?>{
            for (final entry in decoded.entries) '${entry.key}': entry.value,
          });
        })
        .toList(growable: false);
  }

  Future<void> save(WorkflowDefinition workflow) async {
    await _db.insert(_tableName, <String, Object?>{
      'id': workflow.id,
      'name': workflow.name,
      'definition_json': workflow.encode(),
      'created_at': workflow.createdAt.toUtc().toIso8601String(),
      'updated_at': workflow.updatedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
