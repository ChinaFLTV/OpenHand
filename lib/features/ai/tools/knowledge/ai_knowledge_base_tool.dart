import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../../shared/db/database_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

const int _defaultKnowledgeSearchTopK = 6;
const int _minKnowledgeSearchTopK = 1;
const int _maxKnowledgeSearchTopK = 20;
const int _defaultKnowledgeReadLimit = 12;
const int _minKnowledgeReadLimit = 1;
const int _maxKnowledgeReadLimit = 50;

class AiKnowledgeSearchTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.knowledgeSearch;

  @override
  List<String> get aliases => const <String>['knowledge_search'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final sw = Stopwatch()..start();
    final args = context.decodedArguments;
    final query = '${args['query'] ?? ''}'.trim();
    if (query.isEmpty) {
      return AiToolUtils.invalidResult(
        'KnowledgeSearch',
        'KnowledgeSearch requires non-empty query.',
      );
    }
    final topK = AiToolUtils.readClampedInt(
      args['top_k'],
      fallback: _defaultKnowledgeSearchTopK,
      min: _minKnowledgeSearchTopK,
      max: _maxKnowledgeSearchTopK,
    );
    final db = DatabaseService.instance.database;
    final like = '%${query.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final rows = await db.rawQuery(
      '''
SELECT c.id AS chunk_id, c.source_id, c.title AS chunk_title,
       c.heading_path, c.content, c.token_estimate, c.document_time,
       s.title AS source_title, s.original_path, s.kind, s.updated_at
FROM knowledge_chunks c
JOIN knowledge_sources s ON s.id = c.source_id
WHERE c.content LIKE ? ESCAPE '\\'
   OR c.title LIKE ? ESCAPE '\\'
   OR c.heading_path LIKE ? ESCAPE '\\'
   OR s.title LIKE ? ESCAPE '\\'
   OR s.original_path LIKE ? ESCAPE '\\'
ORDER BY s.updated_at DESC, c.chunk_index ASC
LIMIT ?
''',
      <Object?>[like, like, like, like, like, topK],
    );
    final hits = rows
        .map((row) => _hitJson(row, query))
        .toList(growable: false);
    final output = hits.isEmpty
        ? 'No Knowledge Base chunks matched query="$query".'
        : const JsonEncoder.withIndent(
            '  ',
          ).convert(<String, Object?>{'query': query, 'results': hits});
    return AiToolUtils.simpleSuccessResult(
      command: 'KnowledgeSearch query=$query',
      output: output,
      durationMs: sw.elapsedMilliseconds,
      metadata: <String, Object?>{
        'query': query,
        'count': hits.length,
        'results': hits,
      },
    );
  }

  Map<String, Object?> _hitJson(Map<String, Object?> row, String query) {
    final content = '${row['content'] ?? ''}';
    final lower = content.toLowerCase();
    final queryLower = query.toLowerCase();
    final index = lower.indexOf(queryLower);
    final score = index < 0 ? 0.35 : 0.75;
    final start = index < 0 ? 0 : (index - 120).clamp(0, content.length);
    final end = index < 0
        ? content.length.clamp(0, 260)
        : (index + query.length + 220).clamp(0, content.length);
    return <String, Object?>{
      'chunk_id': row['chunk_id'],
      'source_id': row['source_id'],
      'title': row['source_title'],
      'path': row['original_path'],
      'source_kind': row['kind'],
      'document_time': row['document_time'],
      'updated_at': row['updated_at'],
      'score': score,
      'token_estimate': row['token_estimate'],
      'heading_path': row['heading_path'],
      'preview': content.substring(start, end).trim(),
    };
  }
}

class AiKnowledgeReadTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.knowledgeRead;

  @override
  List<String> get aliases => const <String>['knowledge_read'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final sw = Stopwatch()..start();
    final args = context.decodedArguments;
    final chunkId = '${args['chunk_id'] ?? ''}'.trim();
    final sourceId = '${args['source_id'] ?? ''}'.trim();
    if (chunkId.isEmpty && sourceId.isEmpty) {
      return AiToolUtils.invalidResult(
        'KnowledgeRead',
        'KnowledgeRead requires chunk_id or source_id.',
      );
    }
    final limit = AiToolUtils.readClampedInt(
      args['limit'],
      fallback: _defaultKnowledgeReadLimit,
      min: _minKnowledgeReadLimit,
      max: _maxKnowledgeReadLimit,
    );
    final db = DatabaseService.instance.database;
    final rows = chunkId.isNotEmpty
        ? await _readChunk(db, chunkId)
        : await _readSource(db, sourceId, limit);
    final output = rows.isEmpty
        ? 'No Knowledge Base content found.'
        : const JsonEncoder.withIndent(
            '  ',
          ).convert(<String, Object?>{'results': rows});
    return AiToolUtils.simpleSuccessResult(
      command: chunkId.isNotEmpty
          ? 'KnowledgeRead chunk_id=$chunkId'
          : 'KnowledgeRead source_id=$sourceId',
      output: output,
      durationMs: sw.elapsedMilliseconds,
      metadata: <String, Object?>{
        'chunk_id': chunkId,
        'source_id': sourceId,
        'count': rows.length,
      },
    );
  }

  Future<List<Map<String, Object?>>> _readChunk(Database db, String id) {
    return db.rawQuery(
      '''
SELECT c.*, s.title AS source_title, s.original_path, s.kind
FROM knowledge_chunks c
JOIN knowledge_sources s ON s.id = c.source_id
WHERE c.id = ?
LIMIT 1
''',
      <Object?>[id],
    );
  }

  Future<List<Map<String, Object?>>> _readSource(
    Database db,
    String id,
    int limit,
  ) {
    return db.rawQuery(
      '''
SELECT c.*, s.title AS source_title, s.original_path, s.kind
FROM knowledge_chunks c
JOIN knowledge_sources s ON s.id = c.source_id
WHERE c.source_id = ?
ORDER BY c.chunk_index ASC
LIMIT ?
''',
      <Object?>[id, limit],
    );
  }
}
