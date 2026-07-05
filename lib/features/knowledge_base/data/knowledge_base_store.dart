import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/db/database_service.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/knowledge_chunk.dart';
import '../model/knowledge_source.dart';

const String _knowledgeSourcesTable = 'knowledge_sources';
const String _knowledgeChunksTable = 'knowledge_chunks';
const String _knowledgeIdColumn = 'id';
// Stay below SQLite's common 999 variable default while leaving room to grow.
const int _maxSqlWhereInParameters = 900;

class KnowledgeBaseStore {
  KnowledgeBaseStore({Database? database})
    : _db = database ?? DatabaseService.instance.database;

  final Database _db;

  Future<List<KnowledgeSource>> loadSources({String query = ''}) async {
    final normalized = query.trim();
    final rows = await _db.query(
      'knowledge_sources',
      where: normalized.isEmpty ? null : 'title LIKE ? OR original_path LIKE ?',
      whereArgs: normalized.isEmpty
          ? null
          : <Object?>['%$normalized%', '%$normalized%'],
      orderBy: 'updated_at DESC',
      limit: 300,
    );
    return rows.map(KnowledgeSource.fromRow).toList(growable: false);
  }

  Future<KnowledgeSource?> loadSource(String sourceId) async {
    final rows = await _db.query(
      'knowledge_sources',
      where: 'id = ?',
      whereArgs: <Object?>[sourceId],
      limit: 1,
    );
    return rows.isEmpty ? null : KnowledgeSource.fromRow(rows.first);
  }

  Future<void> upsertSource(KnowledgeSource source) async {
    await _db.transaction((txn) async {
      final row = source.toRow();
      final updated = await txn.update(
        'knowledge_sources',
        row,
        where: 'id = ?',
        whereArgs: <Object?>[source.id],
      );
      if (updated > 0) {
        return;
      }
      await txn.insert('knowledge_sources', row);
    });
  }

  Future<void> deleteSource(String sourceId) async {
    await _db.delete(
      'knowledge_sources',
      where: 'id = ?',
      whereArgs: <Object?>[sourceId],
    );
  }

  Future<void> replaceChunks({
    required String sourceId,
    required List<KnowledgeChunk> chunks,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'knowledge_chunks',
        where: 'source_id = ?',
        whereArgs: <Object?>[sourceId],
      );
      final batch = txn.batch();
      for (final chunk in chunks) {
        batch.insert(
          'knowledge_chunks',
          chunk.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<KnowledgeChunk>> loadChunksForSource(String sourceId) async {
    final rows = await _db.query(
      'knowledge_chunks',
      where: 'source_id = ?',
      whereArgs: <Object?>[sourceId],
      orderBy: 'chunk_index ASC',
    );
    return rows.map(KnowledgeChunk.fromRow).toList(growable: false);
  }

  Future<Map<String, KnowledgeChunk>> loadChunksByIds(
    Iterable<String> ids,
  ) async {
    final rows = await _loadRowsByIds(table: _knowledgeChunksTable, ids: ids);
    return <String, KnowledgeChunk>{
      for (final row in rows)
        if (row['id'] is String)
          row['id'] as String: KnowledgeChunk.fromRow(row),
    };
  }

  Future<Map<String, KnowledgeSource>> loadSourcesByIds(
    Iterable<String> ids,
  ) async {
    final rows = await _loadRowsByIds(table: _knowledgeSourcesTable, ids: ids);
    return <String, KnowledgeSource>{
      for (final row in rows)
        if (row['id'] is String)
          row['id'] as String: KnowledgeSource.fromRow(row),
    };
  }

  Future<({int sourceCount, int chunkCount, int pendingJobs, int failedJobs})>
  loadStats() async {
    Future<int> scalar(String sql) async {
      final rows = await _db.rawQuery(sql);
      final value = rows.isEmpty ? null : rows.first.values.first;
      return nonNegativeIntFromValue(value, fallback: 0);
    }

    return (
      sourceCount: await scalar('SELECT COUNT(*) FROM knowledge_sources'),
      chunkCount: await scalar('SELECT COUNT(*) FROM knowledge_chunks'),
      pendingJobs: await scalar(
        "SELECT COUNT(*) FROM knowledge_embedding_jobs WHERE status = 'pending'",
      ),
      failedJobs: await scalar(
        "SELECT COUNT(*) FROM knowledge_embedding_jobs WHERE status = 'failed'",
      ),
    );
  }

  Future<List<Map<String, Object?>>> _loadRowsByIds({
    required String table,
    required Iterable<String> ids,
  }) async {
    final normalized = stringListFromValue(
      ids.toList(growable: false),
    ).toSet().toList(growable: false);
    if (normalized.isEmpty) return const <Map<String, Object?>>[];

    final rows = <Map<String, Object?>>[];
    for (
      var start = 0;
      start < normalized.length;
      start += _maxSqlWhereInParameters
    ) {
      final end = (start + _maxSqlWhereInParameters).clamp(
        0,
        normalized.length,
      );
      final batch = normalized.sublist(start, end);
      final placeholders = List<String>.filled(batch.length, '?').join(',');
      rows.addAll(
        await _db.rawQuery(
          'SELECT * FROM $table WHERE $_knowledgeIdColumn IN ($placeholders)',
          batch,
        ),
      );
    }
    return rows;
  }
}
