import 'dart:async';
import 'dart:math' as math;

import 'package:openhand/shared/util/text_normalization.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/database_service.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../knowledge_base/index.dart';
import '../../model/ai_model_config.dart';
import '../../service/bash/ai_bash_tool_service.dart';
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
const Duration _knowledgeDatabaseQueryTimeout = Duration(seconds: 10);

class AiKnowledgeSearchTool extends AiTool {
  AiKnowledgeSearchTool({
    this._knowledgeBaseControllerProvider,
    this._aiModelsProvider,
  });

  final KnowledgeBaseController? Function()? _knowledgeBaseControllerProvider;
  final List<AiModelConfig> Function()? _aiModelsProvider;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.knowledgeSearch;

  @override
  List<String> get aliases => const <String>['knowledge_search'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final sw = Stopwatch()..start();
    AiToolExecutionResult cancelledResult() => AiToolUtils.cancelledResult(
      command: 'KnowledgeSearch',
      durationMs: sw.elapsedMilliseconds,
    );

    final args = context.decodedArguments;
    final query = AiToolUtils.readString(args['query']);
    if (query.isEmpty) {
      return AiToolUtils.invalidResult(
        'KnowledgeSearch',
        'KnowledgeSearch 需要非空 query。',
      );
    }
    if (query.length > kAiKnowledgeSearchMaxQueryCharacters) {
      return AiToolUtils.invalidResult(
        'KnowledgeSearch',
        'query 超过 $kAiKnowledgeSearchMaxQueryCharacters 个字符上限。',
      );
    }
    var sourceIds = _stringList(
      args['source_ids'],
      maxItems: kAiKnowledgeSearchMaxSourceIds + 1,
    );
    final allowedSourceIds = _dingtalkAllowedSourceIds(context);
    if (allowedSourceIds != null) {
      if (allowedSourceIds.isEmpty) {
        return AiToolUtils.invalidResult('KnowledgeSearch', '钉钉网关未启用任何知识库资源。');
      }
      sourceIds = sourceIds.isEmpty
          ? allowedSourceIds
          : sourceIds.where(allowedSourceIds.contains).toList(growable: false);
      if (sourceIds.isEmpty) {
        return AiToolUtils.invalidResult(
          'KnowledgeSearch',
          '请求的知识库资源不在钉钉网关允许范围内。',
        );
      }
    }
    if (sourceIds.length > kAiKnowledgeSearchMaxSourceIds) {
      return AiToolUtils.invalidResult(
        'KnowledgeSearch',
        'source_ids 超过 $kAiKnowledgeSearchMaxSourceIds 项上限。',
      );
    }
    if (sourceIds.any((id) => id.length > kAiKnowledgeIdMaxCharacters)) {
      return AiToolUtils.invalidResult(
        'KnowledgeSearch',
        '存在 source_id 超过 $kAiKnowledgeIdMaxCharacters 个字符上限。',
      );
    }
    final tags = _stringList(
      args['tags'],
      maxItems: kAiKnowledgeSearchMaxTags + 1,
    );
    if (tags.length > kAiKnowledgeSearchMaxTags) {
      return AiToolUtils.invalidResult(
        'KnowledgeSearch',
        'tags 超过 $kAiKnowledgeSearchMaxTags 项上限。',
      );
    }
    if (tags.any((tag) => tag.length > kAiKnowledgeTagMaxCharacters)) {
      return AiToolUtils.invalidResult(
        'KnowledgeSearch',
        '存在 tag 超过 $kAiKnowledgeTagMaxCharacters 个字符上限。',
      );
    }
    final dateFrom = AiToolUtils.readString(args['date_from']);
    final dateTo = AiToolUtils.readString(args['date_to']);
    final parsedDateFrom = _parseKnowledgeDateFilter(dateFrom);
    final parsedDateTo = _parseKnowledgeDateFilter(dateTo, endOfDay: true);
    if ((dateFrom.isNotEmpty && parsedDateFrom == null) ||
        (dateTo.isNotEmpty && parsedDateTo == null)) {
      return AiToolUtils.invalidResult(
        'KnowledgeSearch',
        'date_from 和 date_to 必须为有效 ISO 8601 日期或时间。',
      );
    }
    if (parsedDateFrom != null &&
        parsedDateTo != null &&
        parsedDateFrom.isAfter(parsedDateTo)) {
      return AiToolUtils.invalidResult(
        'KnowledgeSearch',
        'date_from 不能晚于 date_to。',
      );
    }
    final effectiveDateFrom = parsedDateFrom?.toIso8601String() ?? '';
    final effectiveDateTo = parsedDateTo?.toIso8601String() ?? '';
    final topK = AiToolUtils.readClampedInt(
      args['top_k'],
      fallback: _defaultKnowledgeSearchTopK,
      min: _minKnowledgeSearchTopK,
      max: _maxKnowledgeSearchTopK,
    );
    if (await isCancelSignalCompleted(context.cancelSignal)) {
      return cancelledResult();
    }
    final hasExplicitFilters =
        sourceIds.isNotEmpty ||
        tags.isNotEmpty ||
        effectiveDateFrom.isNotEmpty ||
        effectiveDateTo.isNotEmpty;
    if (!hasExplicitFilters) {
      final vectorResult = await _executeVectorSearch(
        query: query,
        topK: topK,
        stopwatch: sw,
        cancelSignal: context.cancelSignal,
      );
      if (vectorResult != null) return vectorResult;
    }
    if (await isCancelSignalCompleted(context.cancelSignal)) {
      return cancelledResult();
    }
    final terms = _knowledgeQueryTerms(query);
    final db = DatabaseService.instance.database;
    final List<Map<String, Object?>>? rows;
    try {
      rows = await _awaitKnowledgeRows(
        _loadSearchCandidates(
          db,
          query: query,
          terms: terms,
          sourceIds: sourceIds,
          tags: tags,
          dateFrom: effectiveDateFrom,
          dateTo: effectiveDateTo,
          limit: _candidateLimitFor(topK),
        ),
        cancelSignal: context.cancelSignal,
      );
    } on TimeoutException catch (error, stack) {
      if (await isCancelSignalCompleted(context.cancelSignal)) {
        return cancelledResult();
      }
      silentLog('ai_knowledge_base_tool', '本地知识库检索超时', error, stack);
      return _knowledgeTimedOutResult('KnowledgeSearch', sw);
    } catch (error, stack) {
      if (await isCancelSignalCompleted(context.cancelSignal)) {
        return cancelledResult();
      }
      silentLog('ai_knowledge_base_tool', '本地知识库检索失败', error, stack);
      return _knowledgeFailedResult('KnowledgeSearch', sw);
    }
    if (rows == null) return cancelledResult();
    if (await isCancelSignalCompleted(context.cancelSignal)) {
      return cancelledResult();
    }
    final rankedRows = _rankSearchRows(rows, query: query, terms: terms);
    final hits = rankedRows
        .take(topK)
        .map((row) => _searchHitJson(row, query: query, terms: terms))
        .toList(growable: false);
    final output = hits.isEmpty
        ? '知识库中没有匹配 query=“$query”的内容。'
        : prettyPrintJson(<String, Object?>{'query': query, 'results': hits});
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
          'source_ids': sourceIds,
          'tags': tags,
          'date_from': effectiveDateFrom,
          'date_to': effectiveDateTo,
        },
      },
      rerank: <String, Object?>{
        'mode': 'local',
        'strategy': 'weighted_chunk_rank',
        'candidate_count': rows.length,
        'rerank_input_count': rankedRows.length,
        'rerank_output_count': hits.length,
        'kept_count': hits.length,
        'discarded_count': nonNegativeRemaining(rankedRows.length, hits.length),
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
    required Future<void>? cancelSignal,
  }) async {
    try {
      final controller = _knowledgeBaseControllerProvider?.call();
      final models = _aiModelsProvider?.call() ?? const <AiModelConfig>[];
      if (controller == null || models.isEmpty) return null;
      final retrieval = await controller.retrieveForTool(
        query: query,
        topK: topK,
        models: models,
        cancelSignal: cancelSignal,
      );
      if (retrieval == null) return null;
      final result = retrieval.result;
      final hits = result.hits.map(_retrievalHitJson).toList(growable: false);
      final output = hits.isEmpty
          ? '知识库中没有匹配 query=“$query”的内容。'
          : prettyPrintJson(<String, Object?>{'query': query, 'results': hits});
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
      if (await isCancelSignalCompleted(cancelSignal)) {
        return null;
      }
      silentLog('ai_knowledge_base_tool', '向量检索失败，已降级为本地检索', error, stack);
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
    final chunkId = AiToolUtils.readString(args['chunk_id']);
    final sourceId = AiToolUtils.readString(args['source_id']);
    final aroundChunkId = AiToolUtils.readString(args['around_chunk_id']);
    final allowedSourceIds = _dingtalkAllowedSourceIds(context);
    if (allowedSourceIds != null) {
      if (allowedSourceIds.isEmpty) {
        return AiToolUtils.invalidResult('KnowledgeRead', '钉钉网关未启用任何知识库资源。');
      }
      if (sourceId.isNotEmpty && !allowedSourceIds.contains(sourceId)) {
        return AiToolUtils.invalidResult(
          'KnowledgeRead',
          '请求的知识库资源不在钉钉网关允许范围内。',
        );
      }
    }
    if (chunkId.isEmpty && sourceId.isEmpty && aroundChunkId.isEmpty) {
      return AiToolUtils.invalidResult(
        'KnowledgeRead',
        'KnowledgeRead 需要 chunk_id、around_chunk_id 或 source_id。',
      );
    }
    if (chunkId.isNotEmpty &&
        (sourceId.isNotEmpty || aroundChunkId.isNotEmpty)) {
      return AiToolUtils.invalidResult(
        'KnowledgeRead',
        'chunk_id 不能与 around_chunk_id 或 source_id 同时使用。',
      );
    }
    if (<String>[
      chunkId,
      sourceId,
      aroundChunkId,
    ].any((id) => id.length > kAiKnowledgeIdMaxCharacters)) {
      return AiToolUtils.invalidResult(
        'KnowledgeRead',
        '知识库 ID 超过 $kAiKnowledgeIdMaxCharacters 个字符上限。',
      );
    }
    AiToolExecutionResult cancelledResult() => AiToolUtils.cancelledResult(
      command: 'KnowledgeRead',
      durationMs: sw.elapsedMilliseconds,
    );
    if (await isCancelSignalCompleted(context.cancelSignal)) {
      return cancelledResult();
    }
    final requestedLimit = AiToolUtils.readClampedInt(
      args['limit'],
      fallback: _defaultKnowledgeReadLimit,
      min: _minKnowledgeReadLimit,
      max: _maxKnowledgeReadLimit,
    );
    final db = DatabaseService.instance.database;
    final List<Map<String, Object?>>? rows;
    try {
      rows = await _awaitKnowledgeRows(
        chunkId.isNotEmpty
            ? _readChunk(db, chunkId)
            : aroundChunkId.isNotEmpty
            ? _readAroundChunk(
                db,
                aroundChunkId: aroundChunkId,
                sourceId: sourceId,
                limit: requestedLimit,
              )
            : _readSourcePreview(
                db,
                sourceId,
                math.min(requestedLimit, _sourcePreviewMaxChunks),
              ),
        cancelSignal: context.cancelSignal,
      );
    } on TimeoutException catch (error, stack) {
      if (await isCancelSignalCompleted(context.cancelSignal)) {
        return cancelledResult();
      }
      silentLog('ai_knowledge_base_tool', '读取本地知识库超时', error, stack);
      return _knowledgeTimedOutResult('KnowledgeRead', sw);
    } catch (error, stack) {
      if (await isCancelSignalCompleted(context.cancelSignal)) {
        return cancelledResult();
      }
      silentLog('ai_knowledge_base_tool', '读取本地知识库失败', error, stack);
      return _knowledgeFailedResult('KnowledgeRead', sw);
    }
    if (rows == null) return cancelledResult();
    final visibleRows = allowedSourceIds == null
        ? rows
        : rows
              .where(
                (row) => allowedSourceIds.contains(
                  stringFromValue(row['source_id']),
                ),
              )
              .toList(growable: false);
    if (allowedSourceIds != null &&
        visibleRows.isEmpty &&
        (chunkId.isNotEmpty || aroundChunkId.isNotEmpty)) {
      return AiToolUtils.invalidResult('KnowledgeRead', '请求的知识库内容不在钉钉网关允许范围内。');
    }
    final includeContent = chunkId.isNotEmpty || aroundChunkId.isNotEmpty;
    final hits = visibleRows
        .map((row) => _readHitJson(row, includeContent: includeContent))
        .toList(growable: false);
    final output = hits.isEmpty
        ? '未找到知识库内容。'
        : prettyPrintJson(<String, Object?>{
            'results': hits,
            if (!includeContent)
              'note':
                  'source_id 仅返回少量预览；如需精确内容，请先用 KnowledgeSearch，再用 chunk_id 调用 KnowledgeRead。',
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
        'candidate_count': visibleRows.length,
        'kept_count': hits.length,
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

List<String>? _dingtalkAllowedSourceIds(AiToolExecutionContext context) {
  if (!context.metadata.containsKey('dingtalk_allowed_knowledge_source_ids')) {
    return null;
  }
  return _stringList(context.metadata['dingtalk_allowed_knowledge_source_ids']);
}

Future<List<Map<String, Object?>>> _loadSearchCandidates(
  Database db, {
  required String query,
  required List<String> terms,
  required List<String> sourceIds,
  required List<String> tags,
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
  for (final tag in tags) {
    where.add('''
EXISTS (
  SELECT 1
  FROM json_each(
    CASE WHEN json_valid(s.metadata_json) THEN s.metadata_json ELSE '{"tags":[]}' END,
    '\$.tags'
  ) AS source_tag
  WHERE LOWER(CAST(source_tag.value AS TEXT)) = LOWER(?)
)
''');
    args.add(tag);
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
       s.updated_at AS source_updated_at,
       s.metadata_json AS source_metadata_json
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
    final updatedCompare = stringFromValue(
      right.row['source_updated_at'],
    ).compareTo(stringFromValue(left.row['source_updated_at']));
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
  final content = stringFromValue(row['content']);
  final chunkTitle = stringFromValue(row['chunk_title']);
  final headingPath = stringFromValue(row['heading_path']);
  final sourceTitle = stringFromValue(row['source_title']);
  // 每个字段只归一化一次。此前是在词循环里对整段正文重复归一化，单次检索
  // 最坏要跑 500 候选 × 8 词 × 4 字段 = 16000 次全文 lowercase + 全量替换，
  // 且全部同步执行在 UI isolate 上。
  final normalizedContent = _normalizeForMatch(content);
  final normalizedHeadingPath = _normalizeForMatch(headingPath);
  final normalizedChunkTitle = _normalizeForMatch(chunkTitle);
  final normalizedSourceTitle = _normalizeForMatch(sourceTitle);
  // 归一化会剥掉全部空白，因此拼接后再归一化与先归一化再拼接等价。
  final normalizedStrongText =
      '$normalizedChunkTitle$normalizedHeadingPath$normalizedContent';
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
    if (normalizedContent.contains(normalizedTerm)) {
      score += 2.4;
      strongMatched = true;
    }
    if (normalizedHeadingPath.contains(normalizedTerm)) {
      score += 3.2;
      strongMatched = true;
    }
    if (normalizedChunkTitle.contains(normalizedTerm)) {
      score += 2.6;
      strongMatched = true;
    }
    if (normalizedSourceTitle.contains(normalizedTerm)) {
      score += 0.35;
    }
    if (strongMatched) {
      strongMatchedTermCount += 1;
      matchedTerms.add(term);
    }
  }
  final coverage = terms.isEmpty
      ? 1.0
      : unitRatio(strongMatchedTermCount, terms.length);
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
  final content = stringFromValue(row['content']);
  final preview = _contentPreview(content, query: query, terms: terms);
  final tags = _sourceTagsFromRow(row);
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
    if (tags.isNotEmpty) 'tags': tags,
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
  final content = stringFromValue(row['content']).trim();
  final chunkTitle = stringFromValue(row['title']);
  final sourceTitle = stringFromValue(row['source_title']);
  final contentView = includeContent
      ? clipText(content, _knowledgeReadContentMaxChars)
      : '';
  final contentTruncated = contentView.length < content.length;
  final tags = _sourceTagsFromRow(row);
  return <String, Object?>{
    'chunk_id': row['chunk_id'] ?? row['id'],
    'source_id': row['source_id'],
    'title': sourceTitle.isNotEmpty ? sourceTitle : chunkTitle,
    if (sourceTitle.isNotEmpty) 'source_title': sourceTitle,
    if (chunkTitle.isNotEmpty) 'chunk_title': chunkTitle,
    'source_kind': row['kind'] ?? row['source_kind'],
    'document_time': row['document_time'],
    'updated_at': row['updated_at'],
    'token_estimate': row['token_estimate'],
    'heading_path': row['heading_path'],
    if (tags.isNotEmpty) 'tags': tags,
    if (!includeContent)
      'preview': clipText(content, _knowledgeToolPreviewMaxChars),
    if (includeContent) ...<String, Object?>{
      'content': contentView,
      'content_truncated': contentTruncated,
      'content_status': contentTruncated ? 'truncated' : 'complete',
      if (contentTruncated) 'content_char_limit': _knowledgeReadContentMaxChars,
    },
  };
}

Future<List<Map<String, Object?>>> _readChunk(Database db, String id) {
  return db.rawQuery(
    '''
SELECT c.id AS chunk_id, c.source_id, c.title, c.heading_path, c.content,
       c.token_estimate, c.document_time, c.updated_at,
       s.title AS source_title, s.kind,
       s.metadata_json AS source_metadata_json
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
  final anchorSourceId = stringFromValue(anchor['source_id']);
  final anchorIndex = _intValue(anchor['chunk_index']);
  final startIndex = math.max(0, anchorIndex - (limit ~/ 2));
  return db.rawQuery(
    '''
SELECT c.id AS chunk_id, c.source_id, c.title, c.heading_path, c.content,
       c.token_estimate, c.document_time, c.updated_at,
       s.title AS source_title, s.kind,
       s.metadata_json AS source_metadata_json
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
       s.title AS source_title, s.kind,
       s.metadata_json AS source_metadata_json
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
      'reason': 'local_database_path',
    },
    'retrieval': retrieval,
    'rerank': rerank,
    'results': results,
    'prompt_append': <String, Object?>{
      'chunk_count': results.length,
      'source_count': results
          .map((hit) => stringFromValue(hit['source_id']))
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
  for (final match in _queryTokenPattern.allMatches(query)) {
    final raw = match.group(0)?.trim() ?? '';
    if (raw.isEmpty) continue;
    final normalized = _normalizeForMatch(raw);
    final hasCjk = _cjkCharPattern.hasMatch(raw);
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
  final indexedContent = _normalizedTextWithOriginalOffsets(content);
  var index = -1;
  for (final probe in probes) {
    index = indexedContent.text.indexOf(probe);
    if (index >= 0) break;
  }
  if (index < 0 || indexedContent.originalOffsets.isEmpty) {
    return clipText(content, _knowledgeToolPreviewMaxChars).trim();
  }
  final originalIndex = indexedContent.originalOffsets[index];
  final start = safeUtf16SuffixStart(content, math.max(0, originalIndex - 120));
  final end = safeUtf16PrefixCodeUnits(
    content,
    math.min(content.length, originalIndex + 300),
  );
  return content.substring(start, end).trim();
}

({String text, List<int> originalOffsets}) _normalizedTextWithOriginalOffsets(
  String value,
) {
  final text = StringBuffer();
  final originalOffsets = <int>[];
  var originalOffset = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    if (!kInlineWhitespacePattern.hasMatch(character)) {
      final normalized = character.toLowerCase();
      text.write(normalized);
      originalOffsets.addAll(
        List<int>.filled(normalized.length, originalOffset),
      );
    }
    originalOffset += character.length;
  }
  return (text: text.toString(), originalOffsets: originalOffsets);
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

/// 归一化匹配用的模式常量。提到顶层复用，避免在打分热路径上反复编译。
final RegExp _queryTokenPattern = RegExp('[A-Za-z0-9_]+|[一-鿿]+');
final RegExp _cjkCharPattern = RegExp('[一-鿿]');

String _normalizeForMatch(String value) {
  return value.toLowerCase().replaceAll(kInlineWhitespacePattern, '');
}

int _intValue(Object? value) {
  return nonNegativeIntFromValue(value, fallback: 0);
}

List<String> _stringList(Object? value, {int maxItems = 32}) {
  return stringListFromValueOrJsonText(value)
      .where((item) => item.isNotEmpty)
      .toSet()
      .take(maxItems)
      .toList(growable: false);
}

List<String> _sourceTagsFromRow(Map<String, Object?> row) {
  final metadata = stringKeyedMapFromJsonText(
    stringFromValue(row['source_metadata_json']),
  );
  return _stringList(metadata['tags']);
}

final RegExp _knowledgeDateOnlyPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

DateTime? _parseKnowledgeDateFilter(String value, {bool endOfDay = false}) {
  if (value.isEmpty || value.length > 64) return null;
  final dateOnly = _knowledgeDateOnlyPattern.firstMatch(value);
  if (dateOnly != null) {
    final year = int.parse(dateOnly.group(1)!);
    final month = int.parse(dateOnly.group(2)!);
    final day = int.parse(dateOnly.group(3)!);
    final parsed = DateTime.utc(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return endOfDay
        ? parsed
              .add(const Duration(days: 1))
              .subtract(const Duration(microseconds: 1))
        : parsed;
  }
  return DateTime.tryParse(value)?.toUtc();
}

Future<List<Map<String, Object?>>?> _awaitKnowledgeRows(
  Future<List<Map<String, Object?>>> rows, {
  required Future<void>? cancelSignal,
}) {
  return awaitWithCancelSignal(
    rows.timeout(_knowledgeDatabaseQueryTimeout),
    cancelSignal: cancelSignal,
  );
}

AiToolExecutionResult _knowledgeTimedOutResult(String command, Stopwatch sw) {
  const message = '知识库查询超时。';
  return AiToolExecutionResult(
    status: BashToolExecutionStatus.timedOut,
    command: command,
    workingDirectory: AiToolUtils.defaultWorkingDirectory(),
    stdout: '',
    stderr: message,
    durationMs: sw.elapsedMilliseconds,
    resultText: 'status: timed_out\nerror: $message',
  );
}

AiToolExecutionResult _knowledgeFailedResult(String command, Stopwatch sw) {
  const message = '知识库查询失败。';
  return AiToolExecutionResult(
    status: BashToolExecutionStatus.failed,
    command: command,
    workingDirectory: AiToolUtils.defaultWorkingDirectory(),
    stdout: '',
    stderr: message,
    durationMs: sw.elapsedMilliseconds,
    resultText: 'status: failed\nerror: $message',
  );
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
