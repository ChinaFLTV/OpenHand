import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite_common/sqlite_api.dart';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/database_service.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../knowledge_base/index.dart';
import '../../model/ai_model_config.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

const int _defaultKnowledgeSearchTopK = 6;
const int _minKnowledgeSearchTopK = 1;
const int _maxKnowledgeSearchTopK = 20;
const int _searchCandidateMinLimit = 80;
const int _searchCandidateMaxLimit = 500;
const int _queryTermMaxCount = 8;
const int _defaultKnowledgeReadLimit = 4;
const int _minKnowledgeReadLimit = 1;
const int _maxKnowledgeReadLimit = 8;
const int _sourcePreviewMaxChunks = 4;
const int _knowledgeToolPreviewMaxChars = 420;
const int _knowledgeReadContentMaxChars = 4000;

class AiKnowledgeSearchTool extends AiTool {
  AiKnowledgeSearchTool({
    KnowledgeBaseController? Function()? knowledgeBaseControllerProvider,
    List<AiModelConfig> Function()? aiModelsProvider,
  }) : _knowledgeBaseControllerProvider = knowledgeBaseControllerProvider,
       _aiModelsProvider = aiModelsProvider;

  final KnowledgeBaseController? Function()? _knowledgeBaseControllerProvider;
  final List<AiModelConfig> Function()? _aiModelsProvider;

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
    final vectorResult = await _executeVectorSearch(
      query: query,
      topK: topK,
      stopwatch: sw,
    );
    if (vectorResult != null) return vectorResult;
    final terms = _knowledgeQueryTerms(query);
    final db = DatabaseService.instance.database;
    final rows = await _loadSearchCandidates(
      db,
      query: query,
      terms: terms,
      sourceIds: _stringList(args['source_ids']),
      dateFrom: '${args['date_from'] ?? ''}'.trim(),
      dateTo: '${args['date_to'] ?? ''}'.trim(),
      limit: _candidateLimitFor(topK),
    );
    final rankedRows = _rankSearchRows(rows, query: query, terms: terms);
    final hits = rankedRows
        .take(topK)
        .map((row) => _searchHitJson(row, query: query, terms: terms))
        .toList(growable: false);
    final output = hits.isEmpty
        ? 'No Knowledge Base chunks matched query="$query".'
        : const JsonEncoder.withIndent(
            '  ',
          ).convert(<String, Object?>{'query': query, 'results': hits});
    final metadata = _knowledgeToolMetadata(
      status: hits.isEmpty ? 'skipped' : 'success',
      query: query,
      results: hits,
      durationMs: sw.elapsedMilliseconds,
      retrieval: <String, Object?>{
        'strategy': 'local_chunk_rank',
        'duration_ms': sw.elapsedMilliseconds,
        'top_k': topK,
        'candidate_count': rows.length,
        'matched_count': rankedRows.length,
        'filters': <String, Object?>{
          'source_ids': _stringList(args['source_ids']),
          'date_from': '${args['date_from'] ?? ''}'.trim(),
          'date_to': '${args['date_to'] ?? ''}'.trim(),
        },
      },
      rerank: <String, Object?>{
        'mode': 'local',
        'strategy': 'weighted_chunk_rank',
        'candidate_count': rows.length,
        'rerank_input_count': rankedRows.length,
        'rerank_output_count': hits.length,
        'kept_count': hits.length,
        'discarded_count': math.max(0, rankedRows.length - hits.length),
        'duration_ms': sw.elapsedMilliseconds,
      },
    );
    return AiToolUtils.simpleSuccessResult(
      command: 'KnowledgeSearch query=$query',
      output: output,
      durationMs: sw.elapsedMilliseconds,
      metadata: metadata,
    );
  }

  Future<AiToolExecutionResult?> _executeVectorSearch({
    required String query,
    required int topK,
    required Stopwatch stopwatch,
  }) async {
    try {
      final controller = _knowledgeBaseControllerProvider?.call();
      final models = _aiModelsProvider?.call() ?? const <AiModelConfig>[];
      if (controller == null || models.isEmpty) return null;
      final retrieval = await controller.retrieveForTool(
        query: query,
        topK: topK,
        models: models,
      );
      if (retrieval == null) return null;
      final result = retrieval.result;
      final hits = result.hits.map(_retrievalHitJson).toList(growable: false);
      final output = hits.isEmpty
          ? 'No Knowledge Base chunks matched query="$query".'
          : const JsonEncoder.withIndent(
              '  ',
            ).convert(<String, Object?>{'query': query, 'results': hits});
      final knowledgeBase = <String, Object?>{
        ...KnowledgeMessageMetadata.success(
          settings: retrieval.settings,
          result: result,
          embeddingDurationMs: result.durationMs,
          promptAppendContent: result.promptAppend,
        ),
        'results': hits,
      };
      return AiToolUtils.simpleSuccessResult(
        command: 'KnowledgeSearch query=$query',
        output: output,
        durationMs: stopwatch.elapsedMilliseconds,
        metadata: <String, Object?>{
          ...knowledgeBase,
          knowledgeBaseMessageMetadataKey: knowledgeBase,
          'count': hits.length,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
    } catch (error, stack) {
      silentLog(
        'ai_knowledge_base_tool',
        'vector retrieval fallback',
        error,
        stack,
      );
      return null;
    }
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
    final aroundChunkId = '${args['around_chunk_id'] ?? ''}'.trim();
    if (chunkId.isEmpty && sourceId.isEmpty && aroundChunkId.isEmpty) {
      return AiToolUtils.invalidResult(
        'KnowledgeRead',
        'KnowledgeRead requires chunk_id, around_chunk_id, or source_id.',
      );
    }
    final requestedLimit = AiToolUtils.readClampedInt(
      args['limit'],
      fallback: _defaultKnowledgeReadLimit,
      min: _minKnowledgeReadLimit,
      max: _maxKnowledgeReadLimit,
    );
    final db = DatabaseService.instance.database;
    final rows = chunkId.isNotEmpty
        ? await _readChunk(db, chunkId)
        : aroundChunkId.isNotEmpty
        ? await _readAroundChunk(
            db,
            aroundChunkId: aroundChunkId,
            sourceId: sourceId,
            limit: requestedLimit,
          )
        : await _readSourcePreview(
            db,
            sourceId,
            math.min(requestedLimit, _sourcePreviewMaxChunks),
          );
    final includeContent = chunkId.isNotEmpty || aroundChunkId.isNotEmpty;
    final hits = rows
        .map((row) => _readHitJson(row, includeContent: includeContent))
        .toList(growable: false);
    final output = hits.isEmpty
        ? 'No Knowledge Base content found.'
        : const JsonEncoder.withIndent('  ').convert(<String, Object?>{
            'results': hits,
            if (!includeContent)
              'note':
                  'source_id reads return a small preview only. Use KnowledgeSearch, then KnowledgeRead with chunk_id for exact chunk content.',
          });
    final readMode = chunkId.isNotEmpty
        ? 'chunk'
        : aroundChunkId.isNotEmpty
        ? 'chunk_window'
        : 'source_preview';
    final query = chunkId.isNotEmpty
        ? 'chunk_id:$chunkId'
        : aroundChunkId.isNotEmpty
        ? 'around_chunk_id:$aroundChunkId'
        : 'source_id:$sourceId';
    final metadata = _knowledgeToolMetadata(
      status: hits.isEmpty ? 'skipped' : 'success',
      query: query,
      results: hits,
      durationMs: sw.elapsedMilliseconds,
      retrieval: <String, Object?>{
        'strategy': 'knowledge_read',
        'read_mode': readMode,
        'duration_ms': sw.elapsedMilliseconds,
        'requested_limit': requestedLimit,
        'returned_count': hits.length,
      },
      rerank: <String, Object?>{
        'mode': 'none',
        'strategy': 'preserve_chunk_order',
        'candidate_count': rows.length,
        'kept_count': hits.length,
        'discarded_count': 0,
      },
    );
    return AiToolUtils.simpleSuccessResult(
      command: chunkId.isNotEmpty
          ? 'KnowledgeRead chunk_id=$chunkId'
          : aroundChunkId.isNotEmpty
          ? 'KnowledgeRead around_chunk_id=$aroundChunkId'
          : 'KnowledgeRead source_id=$sourceId',
      output: output,
      durationMs: sw.elapsedMilliseconds,
      metadata: metadata,
    );
  }
}

Future<List<Map<String, Object?>>> _loadSearchCandidates(
  Database db, {
  required String query,
  required List<String> terms,
  required List<String> sourceIds,
  required String dateFrom,
  required String dateTo,
  required int limit,
}) {
  final effectiveTerms = terms.isEmpty ? <String>[query] : terms;
  final where = <String>[];
  final args = <Object?>[];
  final termClauses = <String>[];
  for (final term in effectiveTerms) {
    final like = _likePattern(term);
    termClauses.add('''
(c.content LIKE ? ESCAPE '\\'
 OR c.title LIKE ? ESCAPE '\\'
 OR c.heading_path LIKE ? ESCAPE '\\'
 OR s.title LIKE ? ESCAPE '\\')
''');
    args.addAll(<Object?>[like, like, like, like]);
  }
  if (termClauses.isNotEmpty) {
    where.add('(${termClauses.join(' OR ')})');
  }
  if (sourceIds.isNotEmpty) {
    where.add(
      'c.source_id IN (${List<String>.filled(sourceIds.length, '?').join(',')})',
    );
    args.addAll(sourceIds);
  }
  if (dateFrom.isNotEmpty) {
    where.add('(c.document_time >= ? OR s.document_time >= ?)');
    args.addAll(<Object?>[dateFrom, dateFrom]);
  }
  if (dateTo.isNotEmpty) {
    where.add('(c.document_time <= ? OR s.document_time <= ?)');
    args.addAll(<Object?>[dateTo, dateTo]);
  }
  args.add(limit);
  return db.rawQuery('''
SELECT c.id AS chunk_id, c.source_id, c.chunk_index,
       c.title AS chunk_title, c.heading_path, c.content,
       c.token_estimate, c.document_time, c.updated_at AS chunk_updated_at,
       s.title AS source_title, s.kind, s.document_time AS source_document_time,
       s.updated_at AS source_updated_at
FROM knowledge_chunks c
JOIN knowledge_sources s ON s.id = c.source_id
WHERE ${where.isEmpty ? '1 = 1' : where.join(' AND ')}
ORDER BY s.updated_at DESC, c.chunk_index ASC
LIMIT ?
''', args);
}

List<_KnowledgeRankedRow> _rankSearchRows(
  List<Map<String, Object?>> rows, {
  required String query,
  required List<String> terms,
}) {
  final strict = <_KnowledgeRankedRow>[];
  final fallback = <_KnowledgeRankedRow>[];
  for (final row in rows) {
    final score = _scoreSearchRow(row, query: query, terms: terms);
    if (score.strongMatchedTermCount <= 0 && !score.exactPhraseInStrongText) {
      continue;
    }
    final ranked = _KnowledgeRankedRow(row: row, score: score);
    if (terms.length <= 1 ||
        score.exactPhraseInStrongText ||
        score.strongMatchedTermCount >= terms.length) {
      strict.add(ranked);
    } else {
      fallback.add(ranked);
    }
  }
  final rankedRows = strict.isNotEmpty ? strict : fallback;
  rankedRows.sort((left, right) {
    final scoreCompare = right.score.normalizedScore.compareTo(
      left.score.normalizedScore,
    );
    if (scoreCompare != 0) return scoreCompare;
    final updatedCompare = _stringValue(
      right.row['source_updated_at'],
    ).compareTo(_stringValue(left.row['source_updated_at']));
    if (updatedCompare != 0) return updatedCompare;
    return _intValue(
      left.row['chunk_index'],
    ).compareTo(_intValue(right.row['chunk_index']));
  });
  return rankedRows;
}

_KnowledgeSearchScore _scoreSearchRow(
  Map<String, Object?> row, {
  required String query,
  required List<String> terms,
}) {
  final content = _stringValue(row['content']);
  final chunkTitle = _stringValue(row['chunk_title']);
  final headingPath = _stringValue(row['heading_path']);
  final sourceTitle = _stringValue(row['source_title']);
  final strongText = '$chunkTitle\n$headingPath\n$content';
  final normalizedStrongText = _normalizeForMatch(strongText);
  final normalizedQuery = _normalizeForMatch(query);
  var score = 0.0;
  final matchedTerms = <String>{};
  var strongMatchedTermCount = 0;
  final exactPhraseInStrongText =
      normalizedQuery.isNotEmpty &&
      normalizedStrongText.contains(normalizedQuery);
  if (exactPhraseInStrongText) score += 5;
  for (final term in terms.isEmpty ? <String>[query] : terms) {
    final normalizedTerm = _normalizeForMatch(term);
    if (normalizedTerm.isEmpty) continue;
    var strongMatched = false;
    if (_containsNormalized(content, normalizedTerm)) {
      score += 2.4;
      strongMatched = true;
    }
    if (_containsNormalized(headingPath, normalizedTerm)) {
      score += 3.2;
      strongMatched = true;
    }
    if (_containsNormalized(chunkTitle, normalizedTerm)) {
      score += 2.6;
      strongMatched = true;
    }
    if (_containsNormalized(sourceTitle, normalizedTerm)) {
      score += 0.35;
    }
    if (strongMatched) {
      strongMatchedTermCount += 1;
      matchedTerms.add(term);
    }
  }
  final coverage = terms.isEmpty
      ? 1.0
      : strongMatchedTermCount / math.max(1, terms.length);
  score += coverage * 4;
  final tokenEstimate = _intValue(row['token_estimate']);
  if (tokenEstimate > 0) score += 0.2;
  final normalizedScore = score <= 0 ? 0.0 : score / (score + 12);
  return _KnowledgeSearchScore(
    normalizedScore: normalizedScore,
    matchedTerms: matchedTerms.toList(growable: false),
    strongMatchedTermCount: strongMatchedTermCount,
    exactPhraseInStrongText: exactPhraseInStrongText,
  );
}

Map<String, Object?> _searchHitJson(
  _KnowledgeRankedRow ranked, {
  required String query,
  required List<String> terms,
}) {
  final row = ranked.row;
  final content = _stringValue(row['content']);
  final preview = _contentPreview(content, query: query, terms: terms);
  return <String, Object?>{
    'chunk_id': row['chunk_id'],
    'source_id': row['source_id'],
    'title': row['source_title'],
    'source_kind': row['kind'],
    'document_time': row['document_time'] ?? row['source_document_time'],
    'updated_at': row['chunk_updated_at'] ?? row['source_updated_at'],
    'score': ranked.score.normalizedScore,
    'token_estimate': row['token_estimate'],
    'heading_path': row['heading_path'],
    'preview': preview,
    'matched_terms': ranked.score.matchedTerms,
  };
}

Map<String, Object?> _retrievalHitJson(KnowledgeRetrievalHit hit) {
  return <String, Object?>{
    ...hit.toMessageJson()..remove('path'),
    'source_kind': hit.source.kind,
    'heading_path': hit.chunk.headingPath,
  };
}

Map<String, Object?> _readHitJson(
  Map<String, Object?> row, {
  required bool includeContent,
}) {
  final content = _stringValue(row['content']).trim();
  final preview = _truncate(content, _knowledgeToolPreviewMaxChars);
  final contentView = includeContent
      ? _truncate(content, _knowledgeReadContentMaxChars)
      : '';
  return <String, Object?>{
    'chunk_id': row['chunk_id'] ?? row['id'],
    'source_id': row['source_id'],
    'title': row['source_title'] ?? row['title'],
    'source_kind': row['kind'] ?? row['source_kind'],
    'document_time': row['document_time'],
    'updated_at': row['updated_at'],
    'token_estimate': row['token_estimate'],
    'heading_path': row['heading_path'],
    'preview': preview,
    if (includeContent) ...<String, Object?>{
      'content': contentView,
      'content_truncated': contentView.length < content.length,
    },
  };
}

Future<List<Map<String, Object?>>> _readChunk(Database db, String id) {
  return db.rawQuery(
    '''
SELECT c.id AS chunk_id, c.source_id, c.title, c.heading_path, c.content,
       c.token_estimate, c.document_time, c.updated_at,
       s.title AS source_title, s.kind
FROM knowledge_chunks c
JOIN knowledge_sources s ON s.id = c.source_id
WHERE c.id = ?
LIMIT 1
''',
    <Object?>[id],
  );
}

Future<List<Map<String, Object?>>> _readAroundChunk(
  Database db, {
  required String aroundChunkId,
  required String sourceId,
  required int limit,
}) async {
  final anchors = await db.rawQuery(
    '''
SELECT source_id, chunk_index
FROM knowledge_chunks
WHERE id = ? ${sourceId.isEmpty ? '' : 'AND source_id = ?'}
LIMIT 1
''',
    <Object?>[aroundChunkId, if (sourceId.isNotEmpty) sourceId],
  );
  if (anchors.isEmpty) return const <Map<String, Object?>>[];
  final anchor = anchors.first;
  final anchorSourceId = _stringValue(anchor['source_id']);
  final anchorIndex = _intValue(anchor['chunk_index']);
  final startIndex = math.max(0, anchorIndex - (limit ~/ 2));
  return db.rawQuery(
    '''
SELECT c.id AS chunk_id, c.source_id, c.title, c.heading_path, c.content,
       c.token_estimate, c.document_time, c.updated_at,
       s.title AS source_title, s.kind
FROM knowledge_chunks c
JOIN knowledge_sources s ON s.id = c.source_id
WHERE c.source_id = ? AND c.chunk_index >= ?
ORDER BY c.chunk_index ASC
LIMIT ?
''',
    <Object?>[anchorSourceId, startIndex, limit],
  );
}

Future<List<Map<String, Object?>>> _readSourcePreview(
  Database db,
  String id,
  int limit,
) {
  return db.rawQuery(
    '''
SELECT c.id AS chunk_id, c.source_id, c.title, c.heading_path, c.content,
       c.token_estimate, c.document_time, c.updated_at,
       s.title AS source_title, s.kind
FROM knowledge_chunks c
JOIN knowledge_sources s ON s.id = c.source_id
WHERE c.source_id = ?
ORDER BY c.chunk_index ASC
LIMIT ?
''',
    <Object?>[id, limit],
  );
}

Map<String, Object?> _knowledgeToolMetadata({
  required String status,
  required String query,
  required List<Map<String, Object?>> results,
  required int durationMs,
  required Map<String, Object?> retrieval,
  required Map<String, Object?> rerank,
}) {
  final tokenEstimate = results.fold<int>(
    0,
    (total, hit) => total + _intValue(hit['token_estimate']),
  );
  final knowledgeBase = <String, Object?>{
    'enabled': true,
    'status': status,
    'query': query,
    'embedding': const <String, Object?>{
      'strategy': 'not_invoked',
      'reason': 'tool_context_has_no_embedding_model',
    },
    'retrieval': retrieval,
    'rerank': rerank,
    'results': results,
    'prompt_append': <String, Object?>{
      'chunk_count': results.length,
      'source_count': results
          .map((hit) => _stringValue(hit['source_id']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .length,
      'token_estimate': tokenEstimate,
    },
  };
  return <String, Object?>{
    ...knowledgeBase,
    knowledgeBaseMessageMetadataKey: knowledgeBase,
    'count': results.length,
    'duration_ms': durationMs,
  };
}

List<String> _knowledgeQueryTerms(String query) {
  final terms = <String>[];
  final seen = <String>{};
  final pattern = RegExp(r'[A-Za-z0-9_]+|[\u4e00-\u9fff]+');
  for (final match in pattern.allMatches(query)) {
    final raw = match.group(0)?.trim() ?? '';
    if (raw.isEmpty) continue;
    final normalized = _normalizeForMatch(raw);
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(raw);
    if (!hasCjk && normalized.length < 2) continue;
    if (hasCjk && normalized.length < 2) continue;
    if (!_isWorthwhileTerm(normalized)) continue;
    if (!seen.add(normalized)) continue;
    terms.add(raw);
    if (terms.length >= _queryTermMaxCount) break;
  }
  if (terms.isEmpty && query.trim().isNotEmpty) {
    terms.add(query.trim());
  }
  return terms;
}

bool _isWorthwhileTerm(String normalized) {
  const stopWords = <String>{
    'the',
    'and',
    'for',
    'with',
    'from',
    'this',
    'that',
    '怎么',
    '什么',
    '一下',
    '知识库',
  };
  return !stopWords.contains(normalized);
}

String _contentPreview(
  String content, {
  required String query,
  required List<String> terms,
}) {
  if (content.isEmpty) return '';
  final probes = <String>[query, ...terms]
      .map(_normalizeForMatch)
      .where((term) => term.isNotEmpty)
      .toList(growable: false);
  final normalizedContent = _normalizeForMatch(content);
  var index = -1;
  for (final probe in probes) {
    index = normalizedContent.indexOf(probe);
    if (index >= 0) break;
  }
  final start = index < 0 ? 0 : math.max(0, index - 120);
  final end = index < 0
      ? math.min(content.length, 260)
      : math.min(content.length, index + 260);
  return content.substring(start, end).trim();
}

int _candidateLimitFor(int topK) {
  return math.min(
    _searchCandidateMaxLimit,
    math.max(_searchCandidateMinLimit, topK * 24),
  );
}

String _likePattern(String value) {
  final escaped = value
      .replaceAll('\\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}

bool _containsNormalized(String value, String normalizedTerm) {
  if (value.trim().isEmpty || normalizedTerm.isEmpty) return false;
  return _normalizeForMatch(value).contains(normalizedTerm);
}

String _normalizeForMatch(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

String _truncate(String value, int maxChars) {
  if (value.length <= maxChars) return value;
  return '${value.substring(0, maxChars)}...';
}

String _stringValue(Object? value) => '${value ?? ''}'.trim();

int _intValue(Object? value) {
  if (value is int) return math.max(0, value);
  if (value is num && value.isFinite) return math.max(0, value.round());
  return math.max(0, int.tryParse('${value ?? ''}') ?? 0);
}

List<String> _stringList(Object? value) {
  return stringListFromValueOrJsonText(
    value,
  ).where((item) => item.isNotEmpty).toSet().take(32).toList(growable: false);
}

class _KnowledgeRankedRow {
  const _KnowledgeRankedRow({required this.row, required this.score});

  final Map<String, Object?> row;
  final _KnowledgeSearchScore score;
}

class _KnowledgeSearchScore {
  const _KnowledgeSearchScore({
    required this.normalizedScore,
    required this.matchedTerms,
    required this.strongMatchedTermCount,
    required this.exactPhraseInStrongText,
  });

  final double normalizedScore;
  final List<String> matchedTerms;
  final int strongMatchedTermCount;
  final bool exactPhraseInStrongText;
}
