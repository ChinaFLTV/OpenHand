import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/db/database_service.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../model/knowledge_chunk.dart';
import '../model/knowledge_source.dart';

const String _knowledgeSourcesTable = 'knowledge_sources';
const String _knowledgeChunksTable = 'knowledge_chunks';
const String _knowledgeIdColumn = 'id';
// 低于 SQLite 常见的 999 个变量上限，并预留扩展空间。
const int _maxSqlWhereInParameters = 900;
const int _chunkInsertBatchSize = 200;
const List<String> _sourceTextColumns = <String>[
  'id',
  'title',
  'kind',
  'original_path',
  'stored_path',
  'mime_type',
  'content_hash',
  'status',
  'error_message',
  'document_time',
  'imported_at',
  'indexed_at',
  'created_at',
  'updated_at',
  'metadata_json',
];
const List<String> _chunkTextColumns = <String>[
  'id',
  'source_id',
  'parent_chunk_id',
  'title',
  'heading_path',
  'content',
  'content_hash',
  'document_time',
  'created_at',
  'updated_at',
  'metadata_json',
];

class KnowledgeBaseStore {
  KnowledgeBaseStore({Database? database})
    : _db = database ?? DatabaseService.instance.database;

  final Database _db;
  bool _sourceScaleValidated = false;

  Future<List<KnowledgeSource>> loadSources({String query = ''}) async {
    await _validateSourceStorageScale();
    final normalized = query.trim();
    if (normalized.length > kKnowledgeMaxSourceQueryCharacters) {
      throw const FormatException('知识源搜索内容超过安全上限。');
    }
    final rows = await _db.query(
      _knowledgeSourcesTable,
      where: normalized.isEmpty ? null : 'title LIKE ? OR original_path LIKE ?',
      whereArgs: normalized.isEmpty
          ? null
          : <Object?>['%$normalized%', '%$normalized%'],
      orderBy: 'updated_at DESC',
      limit: 300,
    );
    _validateLoadedRows(
      rows,
      textColumns: _sourceTextColumns,
      maxEntryBytes: kKnowledgeMaxSourcePayloadBytes,
      maxTotalBytes: kKnowledgeMaxTotalSourcePayloadBytes,
    );
    return rows.map(KnowledgeSource.fromRow).toList(growable: false);
  }

  Future<KnowledgeSource?> loadSource(String sourceId) async {
    final normalizedId = _validateId(
      sourceId,
      maxCharacters: kKnowledgeMaxSourceIdCharacters,
      field: '知识源 ID',
    );
    await _validateSelectionScale(
      table: _knowledgeSourcesTable,
      textColumns: _sourceTextColumns,
      where: 'id = ?',
      whereArgs: <Object?>[normalizedId],
      maxEntries: 1,
      maxEntryBytes: kKnowledgeMaxSourcePayloadBytes,
      maxTotalBytes: kKnowledgeMaxSourcePayloadBytes,
    );
    final rows = await _db.query(
      _knowledgeSourcesTable,
      where: 'id = ?',
      whereArgs: <Object?>[normalizedId],
      limit: 1,
    );
    return rows.isEmpty ? null : KnowledgeSource.fromRow(rows.first);
  }

  Future<void> upsertSource(KnowledgeSource source) async {
    final row = source.toRow();
    KnowledgeSource.fromRow(row);
    final payloadBytes = _payloadBytes(row, _sourceTextColumns);
    if (payloadBytes > kKnowledgeMaxSourcePayloadBytes) {
      throw const FormatException('知识源载荷超过安全上限。');
    }
    await _db.transaction((txn) async {
      final usage = await _queryUsage(
        txn,
        table: _knowledgeSourcesTable,
        textColumns: _sourceTextColumns,
      );
      _validateUsage(
        usage,
        maxEntries: kKnowledgeMaxSourceCount,
        maxEntryBytes: kKnowledgeMaxSourcePayloadBytes,
        maxTotalBytes: kKnowledgeMaxTotalSourcePayloadBytes,
        message: '知识源存储规模超过安全上限。',
      );
      final existingRows = await txn.rawQuery(
        'SELECT ${_payloadExpression(_sourceTextColumns)} AS payload_bytes '
        'FROM $_knowledgeSourcesTable WHERE id = ? LIMIT 1',
        <Object?>[source.id],
      );
      final existingBytes = existingRows.isEmpty
          ? 0
          : optionalIntegralIntFromValue(existingRows.single['payload_bytes']);
      if (existingBytes == null) {
        throw const FormatException('知识源现有载荷统计无效。');
      }
      if (existingRows.isEmpty &&
          usage.entryCount >= kKnowledgeMaxSourceCount) {
        throw StateError('知识源数量超过安全上限。');
      }
      if (usage.totalPayloadBytes - existingBytes + payloadBytes >
          kKnowledgeMaxTotalSourcePayloadBytes) {
        throw StateError('知识源总载荷超过安全上限。');
      }
      final updated = await txn.update(
        _knowledgeSourcesTable,
        row,
        where: 'id = ?',
        whereArgs: <Object?>[source.id],
      );
      if (updated > 0) {
        return;
      }
      await txn.insert(_knowledgeSourcesTable, row);
    });
    _sourceScaleValidated = true;
  }

  Future<void> deleteSource(String sourceId) async {
    final normalizedId = _validateId(
      sourceId,
      maxCharacters: kKnowledgeMaxSourceIdCharacters,
      field: '知识源 ID',
    );
    await _db.delete(
      _knowledgeSourcesTable,
      where: 'id = ?',
      whereArgs: <Object?>[normalizedId],
    );
  }

  Future<void> replaceChunks({
    required String sourceId,
    required List<KnowledgeChunk> chunks,
  }) async {
    final normalizedSourceId = _validateId(
      sourceId,
      maxCharacters: kKnowledgeMaxSourceIdCharacters,
      field: '知识源 ID',
    );
    final newPayloadBytes = _validateChunkCollection(
      normalizedSourceId,
      chunks,
    );
    await _db.transaction((txn) async {
      final remainingUsage = await _queryUsage(
        txn,
        table: _knowledgeChunksTable,
        textColumns: _chunkTextColumns,
        where: 'source_id <> ?',
        whereArgs: <Object?>[normalizedSourceId],
      );
      if (remainingUsage.maxEntryBytes > kKnowledgeMaxChunkPayloadBytes) {
        throw const FormatException('知识分块单项载荷超过安全上限。');
      }
      if (remainingUsage.entryCount + chunks.length > kKnowledgeMaxChunkCount ||
          remainingUsage.totalPayloadBytes + newPayloadBytes >
              kKnowledgeMaxTotalChunkPayloadBytes) {
        throw StateError('知识分块存储规模超过安全上限。');
      }
      await txn.delete(
        _knowledgeChunksTable,
        where: 'source_id = ?',
        whereArgs: <Object?>[normalizedSourceId],
      );
      for (
        var start = 0;
        start < chunks.length;
        start += _chunkInsertBatchSize
      ) {
        final end = (start + _chunkInsertBatchSize).clamp(0, chunks.length);
        final batch = txn.batch();
        for (var index = start; index < end; index++) {
          batch.insert(
            _knowledgeChunksTable,
            chunks[index].toRow(),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        await batch.commit(noResult: true);
      }
    });
  }

  Future<List<KnowledgeChunk>> loadChunksForSource(String sourceId) async {
    final normalizedSourceId = _validateId(
      sourceId,
      maxCharacters: kKnowledgeMaxSourceIdCharacters,
      field: '知识源 ID',
    );
    await _validateSelectionScale(
      table: _knowledgeChunksTable,
      textColumns: _chunkTextColumns,
      where: 'source_id = ?',
      whereArgs: <Object?>[normalizedSourceId],
      maxEntries: kKnowledgeMaxChunkCountPerSource,
      maxEntryBytes: kKnowledgeMaxChunkPayloadBytes,
      maxTotalBytes: kKnowledgeMaxTotalChunkPayloadBytes,
    );
    final rows = await _db.query(
      _knowledgeChunksTable,
      where: 'source_id = ?',
      whereArgs: <Object?>[normalizedSourceId],
      orderBy: 'chunk_index ASC',
      limit: kKnowledgeMaxChunkCountPerSource + 1,
    );
    if (rows.length > kKnowledgeMaxChunkCountPerSource) {
      throw const FormatException('知识分块数量超过安全上限。');
    }
    _validateLoadedRows(
      rows,
      textColumns: _chunkTextColumns,
      maxEntryBytes: kKnowledgeMaxChunkPayloadBytes,
      maxTotalBytes: kKnowledgeMaxTotalChunkPayloadBytes,
    );
    final chunks = rows.map(KnowledgeChunk.fromRow).toList(growable: false);
    if (chunks.isEmpty || chunks.every((chunk) => chunk.tags.isNotEmpty)) {
      return chunks;
    }
    final source = await loadSource(normalizedSourceId);
    final tags = _sourceTags(source);
    if (tags.isEmpty) return chunks;
    return chunks
        .map((chunk) => chunk.tags.isEmpty ? chunk.copyWith(tags: tags) : chunk)
        .toList(growable: false);
  }

  Future<Map<String, KnowledgeChunk>> loadChunksByIds(
    Iterable<String> ids,
  ) async {
    final rows = await _loadRowsByIds(table: _knowledgeChunksTable, ids: ids);
    final result = <String, KnowledgeChunk>{};
    for (final row in rows) {
      final chunk = KnowledgeChunk.fromRow(row);
      if (result.putIfAbsent(chunk.id, () => chunk) != chunk) {
        throw FormatException('知识分块 ID 重复：${chunk.id}');
      }
    }
    return result;
  }

  Future<Map<String, KnowledgeSource>> loadSourcesByIds(
    Iterable<String> ids,
  ) async {
    final rows = await _loadRowsByIds(table: _knowledgeSourcesTable, ids: ids);
    final result = <String, KnowledgeSource>{};
    for (final row in rows) {
      final source = KnowledgeSource.fromRow(row);
      if (result.putIfAbsent(source.id, () => source) != source) {
        throw FormatException('知识源 ID 重复：${source.id}');
      }
    }
    return result;
  }

  Future<({int sourceCount, int chunkCount, int pendingJobs, int failedJobs})>
  loadStats() async {
    Future<int> scalar(String sql) async {
      final rows = await _db.rawQuery(sql);
      final value = rows.length == 1 ? rows.single.values.firstOrNull : null;
      if (value is! int || value < 0) {
        throw const FormatException('知识库统计结果无效。');
      }
      return value;
    }

    return (
      sourceCount: await scalar('SELECT COUNT(*) FROM $_knowledgeSourcesTable'),
      chunkCount: await scalar('SELECT COUNT(*) FROM $_knowledgeChunksTable'),
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
    final normalized = _normalizeLookupIds(ids);
    if (normalized.isEmpty) return const <Map<String, Object?>>[];

    final textColumns = table == _knowledgeChunksTable
        ? _chunkTextColumns
        : _sourceTextColumns;
    final maxEntryBytes = table == _knowledgeChunksTable
        ? kKnowledgeMaxChunkPayloadBytes
        : kKnowledgeMaxSourcePayloadBytes;
    final maxTotalBytes = table == _knowledgeChunksTable
        ? kKnowledgeMaxTotalChunkPayloadBytes
        : kKnowledgeMaxTotalSourcePayloadBytes;
    var totalPayloadBytes = 0;
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
      final usage = await _queryUsage(
        _db,
        table: table,
        textColumns: textColumns,
        where: '$_knowledgeIdColumn IN ($placeholders)',
        whereArgs: batch,
      );
      if (usage.maxEntryBytes > maxEntryBytes) {
        throw const FormatException('知识记录单项载荷超过安全上限。');
      }
      totalPayloadBytes += usage.totalPayloadBytes;
      if (totalPayloadBytes > maxTotalBytes) {
        throw const FormatException('知识记录总载荷超过安全上限。');
      }
    }

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
    _validateLoadedRows(
      rows,
      textColumns: textColumns,
      maxEntryBytes: maxEntryBytes,
      maxTotalBytes: maxTotalBytes,
    );
    return rows;
  }

  Future<void> _validateSourceStorageScale() async {
    if (_sourceScaleValidated) return;
    final usage = await _queryUsage(
      _db,
      table: _knowledgeSourcesTable,
      textColumns: _sourceTextColumns,
    );
    _validateUsage(
      usage,
      maxEntries: kKnowledgeMaxSourceCount,
      maxEntryBytes: kKnowledgeMaxSourcePayloadBytes,
      maxTotalBytes: kKnowledgeMaxTotalSourcePayloadBytes,
      message: '知识源存储规模超过安全上限。',
    );
    _sourceScaleValidated = true;
  }

  Future<void> _validateSelectionScale({
    required String table,
    required List<String> textColumns,
    required String where,
    required List<Object?> whereArgs,
    required int maxEntries,
    required int maxEntryBytes,
    required int maxTotalBytes,
  }) async {
    final usage = await _queryUsage(
      _db,
      table: table,
      textColumns: textColumns,
      where: where,
      whereArgs: whereArgs,
    );
    _validateUsage(
      usage,
      maxEntries: maxEntries,
      maxEntryBytes: maxEntryBytes,
      maxTotalBytes: maxTotalBytes,
      message: '知识记录存储规模超过安全上限。',
    );
  }

  Future<_KnowledgeStorageUsage> _queryUsage(
    DatabaseExecutor executor, {
    required String table,
    required List<String> textColumns,
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final payloadExpression = _payloadExpression(textColumns);
    final rows = await executor.rawQuery('''
      SELECT COUNT(*) AS entry_count,
             COALESCE(MAX($payloadExpression), 0) AS max_entry_bytes,
             COALESCE(SUM($payloadExpression), 0) AS total_payload_bytes
      FROM $table${where == null ? '' : ' WHERE $where'}
      ''', whereArgs);
    final row = rows.firstOrNull;
    final entryCount = optionalIntegralIntFromValue(row?['entry_count']);
    final maxEntryBytes = optionalIntegralIntFromValue(row?['max_entry_bytes']);
    final totalPayloadBytes = optionalIntegralIntFromValue(
      row?['total_payload_bytes'],
    );
    if (entryCount == null ||
        maxEntryBytes == null ||
        totalPayloadBytes == null) {
      throw const FormatException('知识存储统计无效。');
    }
    return _KnowledgeStorageUsage(
      entryCount: entryCount,
      maxEntryBytes: maxEntryBytes,
      totalPayloadBytes: totalPayloadBytes,
    );
  }

  void _validateUsage(
    _KnowledgeStorageUsage usage, {
    required int maxEntries,
    required int maxEntryBytes,
    required int maxTotalBytes,
    required String message,
  }) {
    if (usage.entryCount > maxEntries ||
        usage.maxEntryBytes > maxEntryBytes ||
        usage.totalPayloadBytes > maxTotalBytes) {
      throw FormatException(message);
    }
  }

  int _validateChunkCollection(String sourceId, List<KnowledgeChunk> chunks) {
    if (chunks.length > kKnowledgeMaxChunkCountPerSource) {
      throw const FormatException('知识分块数量超过安全上限。');
    }
    final ids = <String>{};
    var totalPayloadBytes = 0;
    for (var index = 0; index < chunks.length; index++) {
      final chunk = chunks[index];
      if (chunk.sourceId != sourceId ||
          chunk.chunkIndex != index ||
          !ids.add(chunk.id) ||
          chunk.tags.length > kKnowledgeTagMaxCount ||
          chunk.tags.any(
            (tag) =>
                tag.isEmpty ||
                tag.trim() != tag ||
                tag.length > kKnowledgeTagMaxCharacters,
          ) ||
          chunk.tags.map((tag) => tag.toLowerCase()).toSet().length !=
              chunk.tags.length) {
        throw FormatException('知识分块配置无效：${chunk.id}');
      }
      final row = chunk.toRow();
      KnowledgeChunk.fromRow(row, tags: chunk.tags);
      final payloadBytes = _payloadBytes(row, _chunkTextColumns);
      totalPayloadBytes += payloadBytes;
      if (payloadBytes > kKnowledgeMaxChunkPayloadBytes ||
          totalPayloadBytes > kKnowledgeMaxTotalChunkPayloadBytes) {
        throw const FormatException('知识分块载荷超过安全上限。');
      }
    }
    return totalPayloadBytes;
  }

  void _validateLoadedRows(
    List<Map<String, Object?>> rows, {
    required List<String> textColumns,
    required int maxEntryBytes,
    required int maxTotalBytes,
  }) {
    var totalPayloadBytes = 0;
    for (final row in rows) {
      final payloadBytes = _payloadBytes(row, textColumns);
      totalPayloadBytes += payloadBytes;
      if (payloadBytes > maxEntryBytes || totalPayloadBytes > maxTotalBytes) {
        throw const FormatException('知识记录载荷超过安全上限。');
      }
    }
  }

  List<String> _normalizeLookupIds(Iterable<String> ids) {
    final result = <String>[];
    final seen = <String>{};
    var inspected = 0;
    for (final raw in ids) {
      inspected += 1;
      if (inspected > kKnowledgeMaxChunkLookupIds) {
        throw const FormatException('知识记录查询数量超过安全上限。');
      }
      final id = raw.trim();
      if (id.isEmpty ||
          id != raw ||
          id.length > kKnowledgeMaxChunkIdCharacters) {
        throw const FormatException('知识记录 ID 无效。');
      }
      if (seen.add(id)) result.add(id);
    }
    return result;
  }

  String _validateId(
    String value, {
    required int maxCharacters,
    required String field,
  }) {
    if (value.isEmpty ||
        value.trim() != value ||
        value.length > maxCharacters) {
      throw FormatException('$field 无效。');
    }
    return value;
  }

  List<String> _sourceTags(KnowledgeSource? source) {
    final raw = source?.metadata['tags'];
    if (raw == null) {
      return const <String>[];
    }
    if (raw is! List || raw.any((item) => item is! String)) {
      throw const FormatException('知识源标签无效。');
    }
    return List<String>.unmodifiable(raw.cast<String>());
  }

  String _payloadExpression(List<String> columns) {
    return columns
        .map((column) => 'COALESCE(LENGTH(CAST($column AS BLOB)), 0)')
        .join(' + ');
  }

  int _payloadBytes(Map<String, Object?> row, List<String> columns) {
    return columns.fold<int>(
      0,
      (total, column) => total + utf8ByteLength('${row[column] ?? ''}'),
    );
  }
}

class _KnowledgeStorageUsage {
  const _KnowledgeStorageUsage({
    required this.entryCount,
    required this.maxEntryBytes,
    required this.totalPayloadBytes,
  });

  final int entryCount;
  final int maxEntryBytes;
  final int totalPayloadBytes;
}
