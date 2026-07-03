import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/db/database_service.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/knowledge_chunk.dart';
import '../model/knowledge_source.dart';

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
    final normalized = stringListFromValue(
      ids.toList(growable: false),
    ).toSet().toList(growable: false);
    if (normalized.isEmpty) return const <String, KnowledgeChunk>{};
    final placeholders = List<String>.filled(normalized.length, '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT * FROM knowledge_chunks WHERE id IN ($placeholders)',
      normalized,
    );
    return <String, KnowledgeChunk>{
      for (final row in rows)
        if (row['id'] is String)
          row['id'] as String: KnowledgeChunk.fromRow(row),
    };
  }

  Future<Map<String, KnowledgeSource>> loadSourcesByIds(
    Iterable<String> ids,
  ) async {
    final normalized = stringListFromValue(
      ids.toList(growable: false),
    ).toSet().toList(growable: false);
    if (normalized.isEmpty) return const <String, KnowledgeSource>{};
    final placeholders = List<String>.filled(normalized.length, '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT * FROM knowledge_sources WHERE id IN ($placeholders)',
      normalized,
    );
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
}
