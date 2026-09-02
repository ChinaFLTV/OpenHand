import 'dart:async';
import 'dart:math' as math;

import '../../../app/support/silent_log.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../ai/index.dart';
import '../data/knowledge_base_store.dart';
import '../knowledge_base_errors.dart';
import '../model/knowledge_base_settings.dart';
import '../model/knowledge_retrieval_result.dart';
import 'knowledge_embedding_service.dart';
import 'knowledge_indexing_control.dart';
import 'knowledge_vector_store.dart';

const Duration _oneDay = Duration(days: 1);
const double _defaultMmrLambda = 0.72;
final RegExp _retrievalTokenPattern = RegExp(r'[A-Za-z0-9_\u4e00-\u9fff-]{2,}');
final RegExp _queryTagPattern = RegExp(r'(?:^|\s)(?:tag:|#)([^\s#]+)');
final RegExp _queryDayPattern = RegExp(
  r'\b(19\d{2}|20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b',
);
final RegExp _queryMonthPattern = RegExp(
  r'\b(19\d{2}|20\d{2})[-/.](\d{1,2})\b',
);
final RegExp _queryRecentDaysPattern = RegExp(
  r'(?:最近|近|last|past)\s*(\d{1,4})\s*(?:天|日|days?)',
);

class KnowledgeRetrievalService {
  KnowledgeRetrievalService({
    required this._store,
    required this._embeddingService,
    required this._vectorStore,
    AiRerankService? rerankService,
  }) : _rerankService = rerankService ?? AiRerankService(),
       _ownsRerankService = rerankService == null;

  final KnowledgeBaseStore _store;
  final KnowledgeEmbeddingService _embeddingService;
  final KnowledgeVectorStore _vectorStore;
  final AiRerankService _rerankService;
  final bool _ownsRerankService;

  Future<KnowledgeRetrievalResult> retrieve({
    required String query,
    required KnowledgeBaseSettings settings,
    required AiModelConfig embeddingModel,
    AiModelConfig? rerankModel,
    Future<void>? cancelSignal,
  }) async {
    final stopwatch = Stopwatch()..start();
    final cancelToken = cancelSignal == null
        ? null
        : KnowledgeIndexingCancelToken();
    if (cancelToken != null) {
      unawaited(
        cancelSignal!.then<void>(
          (_) => cancelToken.cancel(),
          onError: (Object _, StackTrace _) => cancelToken.cancel(),
        ),
      );
    }
    final vectors = await _embeddingService.embedBatch(
      settings: settings,
      model: embeddingModel,
      inputs: <String>[query],
      isQuery: true,
      cancelToken: cancelToken,
    );
    cancelToken?.throwIfCancelled();
    final rawHits = await _vectorStore.search(
      collectionName: settings.effectiveCollectionName,
      vector: vectors.first,
      limit: settings.topN,
      scoreThreshold: settings.minSimilarity,
      filter: _filterForQuery(query, settings),
      includeVector: true,
      cancelSignal: cancelSignal,
    );
    cancelToken?.throwIfCancelled();
    final chunkIds = stringListFromValue(
      rawHits
          .map((hit) => hit.payload['chunk_id'] ?? hit.id)
          .toList(growable: false),
    );
    final chunksById = await _store.loadChunksByIds(chunkIds);
    cancelToken?.throwIfCancelled();
    final sourcesById = await _store.loadSourcesByIds(
      chunksById.values.map((chunk) => chunk.sourceId),
    );
    cancelToken?.throwIfCancelled();
    final scored = <KnowledgeRetrievalHit>[];
    for (final raw in rawHits) {
      final chunkId = '${raw.payload['chunk_id'] ?? raw.id}'.trim();
      final chunk = chunksById[chunkId];
      if (chunk == null) continue;
      final source = sourcesById[chunk.sourceId];
      if (source == null) continue;
      final sourceTags = source.metadata['tags'];
      final effectiveChunk = chunk.tags.isNotEmpty || sourceTags is! List
          ? chunk
          : chunk.copyWith(tags: sourceTags.cast<String>());
      final finalScore = _hybridScore(
        query: query,
        vectorScore: raw.score,
        title: '${raw.payload['source_title'] ?? source.title}',
        tags: effectiveChunk.tags,
        documentTime: effectiveChunk.documentTime ?? source.documentTime,
        settings: settings,
      );
      scored.add(
        KnowledgeRetrievalHit(
          chunk: effectiveChunk,
          source: source,
          score: raw.score,
          vector: raw.vector,
          finalScore: finalScore,
          timeField: effectiveChunk.documentTime != null
              ? 'document_time'
              : source.documentTime != null
              ? 'source.document_time'
              : 'updated_at',
        ),
      );
    }
    final ranked = await _rankHits(
      query: query,
      hits: scored,
      settings: settings,
      embeddingModel: embeddingModel,
      rerankModel: rerankModel,
      cancelSignal: cancelSignal,
      cancelToken: cancelToken,
    );
    cancelToken?.throwIfCancelled();
    final capped = <KnowledgeRetrievalHit>[];
    final perSource = <String, int>{};
    final perSourceLimit = math.min(
      settings.sourceCap,
      settings.maxChunksPerSource,
    );
    for (final hit in ranked.hits) {
      final count = perSource[hit.source.id] ?? 0;
      if (count >= perSourceLimit) continue;
      perSource[hit.source.id] = count + 1;
      capped.add(hit);
      if (capped.length >= settings.topK) break;
    }
    final prompt = _buildPromptContext(
      hits: capped,
      settings: settings,
      query: query,
    );
    final rerankTrace = ranked.trace.copyWith(
      keptCount: capped.length,
      discardedCount: nonNegativeRemaining(scored.length, capped.length),
    );
    stopwatch.stop();
    return KnowledgeRetrievalResult(
      query: query,
      hits: capped,
      durationMs: stopwatch.elapsedMilliseconds,
      promptAppend: prompt.text,
      promptTokenEstimate: prompt.tokenEstimate,
      queryVector: vectors.first,
      rerankTrace: rerankTrace,
    );
  }

  Future<({List<KnowledgeRetrievalHit> hits, KnowledgeRerankTrace trace})>
  _rankHits({
    required String query,
    required List<KnowledgeRetrievalHit> hits,
    required KnowledgeBaseSettings settings,
    required AiModelConfig embeddingModel,
    required AiModelConfig? rerankModel,
    required Future<void>? cancelSignal,
    required KnowledgeIndexingCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final mode = KnowledgeRerankMode.normalize(settings.rerankMode);
    if (hits.isEmpty) {
      return (
        hits: hits,
        trace: KnowledgeRerankTrace(
          mode: mode,
          strategy: 'empty',
          candidateCount: 0,
        ),
      );
    }
    final localRanked = _localHybridRank(hits);
    return switch (mode) {
      KnowledgeRerankMode.off => (
        hits: _vectorRank(hits),
        trace: KnowledgeRerankTrace(
          mode: mode,
          strategy: 'vector_order',
          candidateCount: hits.length,
        ),
      ),
      KnowledgeRerankMode.mmr => (
        hits: _mmrRank(localRanked, settings),
        trace: KnowledgeRerankTrace(
          mode: mode,
          strategy: 'mmr',
          candidateCount: hits.length,
          rerankInputCount: math.min(settings.rerankTopN, localRanked.length),
        ),
      ),
      KnowledgeRerankMode.model => await _modelRerank(
        query: query,
        vectorRanked: _vectorRank(hits),
        localRanked: localRanked,
        settings: settings,
        embeddingModel: embeddingModel,
        rerankModel: rerankModel,
        cancelSignal: cancelSignal,
        cancelToken: cancelToken,
      ),
      _ => (
        hits: localRanked,
        trace: KnowledgeRerankTrace(
          mode: mode,
          strategy: 'local_hybrid',
          candidateCount: hits.length,
        ),
      ),
    };
  }

  List<KnowledgeRetrievalHit> _localHybridRank(
    List<KnowledgeRetrievalHit> hits,
  ) {
    return List<KnowledgeRetrievalHit>.of(hits)..sort(
      (a, b) => (b.finalScore ?? b.score).compareTo(a.finalScore ?? a.score),
    );
  }

  List<KnowledgeRetrievalHit> _vectorRank(List<KnowledgeRetrievalHit> hits) {
    return List<KnowledgeRetrievalHit>.of(hits)
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  List<KnowledgeRetrievalHit> _mmrRank(
    List<KnowledgeRetrievalHit> localRanked,
    KnowledgeBaseSettings settings,
  ) {
    if (localRanked.length <= 2) return localRanked;
    final lambda = finiteUnitInterval(
      settings.mmrLambda,
      fallback: _defaultMmrLambda,
    );
    final candidateLimit = math.min(settings.rerankTopN, localRanked.length);
    final candidates = localRanked.take(candidateLimit).toList(growable: true);
    final tail = localRanked.skip(candidateLimit).toList(growable: false);
    final selected = <KnowledgeRetrievalHit>[];
    final topScore = candidates
        .map((hit) => hit.finalScore ?? hit.score)
        .fold<double>(0, math.max);
    while (candidates.isNotEmpty) {
      KnowledgeRetrievalHit? best;
      var bestScore = double.negativeInfinity;
      for (final candidate in candidates) {
        final relevance = unitRatio(
          candidate.finalScore ?? candidate.score,
          topScore,
        );
        final redundancy = selected.isEmpty
            ? 0.0
            : selected
                  .map((hit) => _chunkSimilarity(candidate, hit))
                  .fold<double>(0, math.max);
        final mmrScore = lambda * relevance - (1 - lambda) * redundancy;
        if (mmrScore > bestScore) {
          bestScore = mmrScore;
          best = candidate;
        }
      }
      final chosen = best ?? candidates.first;
      selected.add(chosen.copyWith(finalScore: bestScore));
      candidates.remove(chosen);
    }
    return <KnowledgeRetrievalHit>[...selected, ...tail];
  }

  Future<({List<KnowledgeRetrievalHit> hits, KnowledgeRerankTrace trace})>
  _modelRerank({
    required String query,
    required List<KnowledgeRetrievalHit> vectorRanked,
    required List<KnowledgeRetrievalHit> localRanked,
    required KnowledgeBaseSettings settings,
    required AiModelConfig embeddingModel,
    required AiModelConfig? rerankModel,
    required Future<void>? cancelSignal,
    required KnowledgeIndexingCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    if (_shouldSkipModelRerankForDualCapability(
      settings: settings,
      embeddingModel: embeddingModel,
    )) {
      return (
        hits: vectorRanked,
        trace: KnowledgeRerankTrace(
          mode: KnowledgeRerankMode.model,
          strategy: 'model_skipped_dual_capability',
          candidateCount: vectorRanked.length,
          providerConfigId: settings.rerankProviderConfigId,
          modelId: settings.rerankModelId,
        ),
      );
    }
    if (!settings.hasRerankModel || rerankModel == null) {
      if (settings.failureStrategy == KnowledgeFailureStrategy.failClosed) {
        throw StateError('已选择模型重排序，但未配置可用的 rerank 模型。');
      }
      return (
        hits: localRanked,
        trace: KnowledgeRerankTrace(
          mode: KnowledgeRerankMode.model,
          strategy: 'model_unavailable_fallback',
          candidateCount: localRanked.length,
          providerConfigId: settings.rerankProviderConfigId,
          modelId: settings.rerankModelId,
          error: 'rerank_model_unavailable',
        ),
      );
    }
    final candidateLimit = math.min(settings.rerankTopN, localRanked.length);
    final candidates = localRanked.take(candidateLimit).toList(growable: false);
    if (candidates.length <= 1) {
      return (
        hits: localRanked,
        trace: KnowledgeRerankTrace(
          mode: KnowledgeRerankMode.model,
          strategy: 'model_not_needed',
          candidateCount: localRanked.length,
          rerankInputCount: candidates.length,
          providerConfigId: settings.rerankProviderConfigId,
          modelId: settings.rerankModelId,
        ),
      );
    }
    final stopwatch = Stopwatch()..start();
    try {
      final result = await AiUsageTraceContext.runDerived(
        source: AiUsageSource.knowledgeBase,
        operation: 'retrieval_rerank',
        metadata: <String, Object?>{'candidate_count': candidates.length},
        body: () => _rerankService.rerank(
          model: rerankModel,
          query: query,
          documents: candidates
              .map<Object>(_rerankDocumentText)
              .toList(growable: false),
          topN: candidateLimit,
          returnDocuments: false,
          timeout: Duration(seconds: settings.rerankTimeoutSeconds),
          cancelSignal: cancelSignal,
        ),
      );
      cancelToken?.throwIfCancelled();
      stopwatch.stop();
      if (result.items.isEmpty) {
        return (
          hits: localRanked,
          trace: KnowledgeRerankTrace(
            mode: KnowledgeRerankMode.model,
            strategy: 'model_empty_fallback',
            candidateCount: localRanked.length,
            rerankInputCount: candidates.length,
            durationMs: stopwatch.elapsedMilliseconds,
            providerConfigId: settings.rerankProviderConfigId,
            modelId: settings.rerankModelId,
          ),
        );
      }
      final ordered = List<AiRerankItem>.of(result.items)
        ..sort((a, b) => b.score.compareTo(a.score));
      final usedIndexes = <int>{};
      final reranked = <KnowledgeRetrievalHit>[];
      for (final item in ordered) {
        if (item.index < 0 || item.index >= candidates.length) continue;
        if (!usedIndexes.add(item.index)) continue;
        reranked.add(
          candidates[item.index].copyWith(
            rerankScore: item.score,
            finalScore: item.score,
          ),
        );
      }
      if (reranked.isEmpty) {
        return (
          hits: localRanked,
          trace: KnowledgeRerankTrace(
            mode: KnowledgeRerankMode.model,
            strategy: 'model_invalid_output_fallback',
            candidateCount: localRanked.length,
            rerankInputCount: candidates.length,
            rerankOutputCount: result.items.length,
            durationMs: stopwatch.elapsedMilliseconds,
            providerConfigId: settings.rerankProviderConfigId,
            modelId: settings.rerankModelId,
          ),
        );
      }
      for (var i = 0; i < candidates.length; i++) {
        if (!usedIndexes.contains(i)) reranked.add(candidates[i]);
      }
      reranked.addAll(localRanked.skip(candidateLimit));
      return (
        hits: reranked,
        trace: KnowledgeRerankTrace(
          mode: KnowledgeRerankMode.model,
          strategy: 'model',
          candidateCount: localRanked.length,
          rerankInputCount: candidates.length,
          rerankOutputCount: result.items.length,
          durationMs: stopwatch.elapsedMilliseconds,
          providerConfigId: settings.rerankProviderConfigId,
          modelId: settings.rerankModelId,
        ),
      );
    } catch (error, stackTrace) {
      stopwatch.stop();
      cancelToken?.throwIfCancelled();
      if (settings.failureStrategy == KnowledgeFailureStrategy.failClosed) {
        rethrow;
      }
      silentLog('knowledge_retrieval', '模型重排序失败', error, stackTrace);
      return (
        hits: localRanked,
        trace: KnowledgeRerankTrace(
          mode: KnowledgeRerankMode.model,
          strategy: 'model_failed_fallback',
          candidateCount: localRanked.length,
          rerankInputCount: candidates.length,
          durationMs: stopwatch.elapsedMilliseconds,
          providerConfigId: settings.rerankProviderConfigId,
          modelId: settings.rerankModelId,
          error: knowledgeBaseFailureMessage(
            error,
            fallback: '模型重排序失败，已回退到本地排序。',
          ),
        ),
      );
    }
  }

  bool _shouldSkipModelRerankForDualCapability({
    required KnowledgeBaseSettings settings,
    required AiModelConfig embeddingModel,
  }) {
    if (!settings.skipModelRerankWhenEmbeddingSupportsRerank) return false;
    final selectedEmbeddingModelId = settings.modelId.trim();
    if (selectedEmbeddingModelId.isEmpty) return false;
    final profile = embeddingModel.profileFor(selectedEmbeddingModelId);
    return profile.supportsEmbeddings && profile.supportsRerank;
  }

  String _rerankDocumentText(KnowledgeRetrievalHit hit) {
    final originalPath = nullIfBlank(hit.source.originalPath);
    final headingPath = nullIfBlank(hit.chunk.headingPath);
    return <String>[
      'Title: ${hit.source.title}',
      if (originalPath != null) 'Source: $originalPath',
      if (headingPath != null) 'Heading: $headingPath',
      if (hit.chunk.tags.isNotEmpty) 'Tags: ${hit.chunk.tags.join(", ")}',
      '',
      hit.chunk.content.trim(),
    ].join('\n');
  }

  double _chunkSimilarity(KnowledgeRetrievalHit a, KnowledgeRetrievalHit b) {
    var score = 0.0;
    if (a.source.id == b.source.id) score = math.max(score, 0.72);
    if (a.chunk.headingPath.isNotEmpty &&
        a.chunk.headingPath == b.chunk.headingPath) {
      score = math.max(score, 0.55);
    }
    final tokensA = _tokenSet(a.chunk.content);
    final tokensB = _tokenSet(b.chunk.content);
    if (tokensA.isEmpty || tokensB.isEmpty) return score;
    final shared = tokensA.intersection(tokensB).length;
    final union = tokensA.union(tokensB).length;
    if (union == 0) return score;
    return math.max(score, unitRatio(shared, union));
  }

  Set<String> _tokenSet(String value) {
    return _retrievalTokenPattern
        .allMatches(value.toLowerCase())
        .take(96)
        .map((match) => match.group(0)!)
        .toSet();
  }

  Map<String, Object?>? _filterForQuery(
    String query,
    KnowledgeBaseSettings settings,
  ) {
    final must = <Object?>[];
    final tags = stringListFromValue(
      _queryTagPattern
          .allMatches(query)
          .map((match) => match.group(1))
          .toList(growable: false),
    );
    if (tags.isNotEmpty) {
      if (settings.tagFilterMode == KnowledgeTagFilterMode.all) {
        must.addAll(
          tags.map(
            (tag) => <String, Object?>{
              'key': 'tags',
              'match': <String, Object?>{'value': tag},
            },
          ),
        );
      } else {
        must.add(<String, Object?>{
          'key': 'tags',
          'match': <String, Object?>{'any': tags},
        });
      }
    }
    if (settings.dateFilterMode == KnowledgeDateFilterMode.hardWhenExplicit) {
      final range = _dateRangeForQuery(
        query,
        allowNaturalLanguage: settings.parseNaturalLanguageTime,
      );
      if (range != null) {
        must.add(<String, Object?>{
          'key': 'document_time',
          'range': <String, Object?>{
            'gte': range.start.toUtc().toIso8601String(),
            'lt': range.end.toUtc().toIso8601String(),
          },
        });
      }
    }
    if (must.isEmpty) return null;
    return <String, Object?>{'must': must};
  }

  double _hybridScore({
    required String query,
    required double vectorScore,
    required String title,
    required List<String> tags,
    required DateTime? documentTime,
    required KnowledgeBaseSettings settings,
  }) {
    final normalizedQuery = query.toLowerCase();
    final titleScore = title.toLowerCase().contains(normalizedQuery)
        ? 1.0
        : 0.0;
    final tagScore =
        tags.any((tag) => normalizedQuery.contains(tag.toLowerCase()))
        ? 1.0
        : 0.0;
    final exactPhraseScore =
        normalizedQuery.length >= 4 &&
            title.toLowerCase().contains(normalizedQuery)
        ? 1.0
        : 0.0;
    final timeScore =
        settings.recencyBoostEnabled &&
            settings.dateFilterMode != KnowledgeDateFilterMode.off
        ? _timeScore(query, documentTime)
        : 0.0;
    return vectorScore * settings.vectorWeight +
        titleScore * settings.titleWeight +
        tagScore * settings.tagWeight +
        timeScore * settings.timeWeight +
        exactPhraseScore * settings.exactPhraseWeight +
        1.0 * settings.sourceQualityWeight;
  }

  double _timeScore(String query, DateTime? documentTime) {
    if (documentTime == null) return 0;
    final normalized = query.toLowerCase();
    final hasRecentIntent =
        normalized.contains('最近') ||
        normalized.contains('最新') ||
        normalized.contains('近期') ||
        normalized.contains('recent') ||
        normalized.contains('latest');
    if (!hasRecentIntent) return 0.2;
    final ageDays = DateTime.now().toUtc().difference(documentTime).inDays;
    return clampUnitInterval(math.exp(-math.max(0, ageDays) / 90));
  }

  ({DateTime start, DateTime end})? _dateRangeForQuery(
    String query, {
    required bool allowNaturalLanguage,
  }) {
    final normalized = query.toLowerCase();
    final dayMatch = _queryDayPattern.firstMatch(normalized);
    if (dayMatch != null) {
      final start = _utcDateOrNull(
        int.parse(dayMatch.group(1)!),
        int.parse(dayMatch.group(2)!),
        int.parse(dayMatch.group(3)!),
      );
      if (start != null) return (start: start, end: start.add(_oneDay));
    }

    final monthMatch = _queryMonthPattern.firstMatch(normalized);
    if (monthMatch != null) {
      final start = _utcDateOrNull(
        int.parse(monthMatch.group(1)!),
        int.parse(monthMatch.group(2)!),
        1,
      );
      if (start != null) {
        return (start: start, end: DateTime.utc(start.year, start.month + 1));
      }
    }

    if (!allowNaturalLanguage) return null;
    final now = DateTime.now().toUtc();
    if (normalized.contains('今天') || normalized.contains('today')) {
      final start = DateTime.utc(now.year, now.month, now.day);
      return (start: start, end: start.add(_oneDay));
    }
    if (normalized.contains('昨天') || normalized.contains('yesterday')) {
      final start = DateTime.utc(
        now.year,
        now.month,
        now.day,
      ).subtract(_oneDay);
      return (start: start, end: start.add(_oneDay));
    }
    final recentDaysMatch = _queryRecentDaysPattern.firstMatch(normalized);
    if (recentDaysMatch == null) return null;
    final days = optionalPositiveIntFromValue(recentDaysMatch.group(1));
    if (days == null || days > 3650) return null;
    return (start: now.subtract(Duration(days: days)), end: now.add(_oneDay));
  }

  DateTime? _utcDateOrNull(int year, int month, int day) {
    final value = DateTime.utc(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      return null;
    }
    return value;
  }

  ({String text, int tokenEstimate}) _buildPromptContext({
    required List<KnowledgeRetrievalHit> hits,
    required KnowledgeBaseSettings settings,
    required String query,
  }) {
    if (hits.isEmpty) return (text: '', tokenEstimate: 0);
    final buffer = StringBuffer()
      ..writeln('<OpenHandKnowledgeBaseContext>')
      ..writeln('The user enabled Knowledge Base references for this message.')
      ..writeln(
        'Use the following retrieved local knowledge only when relevant.',
      )
      ..writeln(
        'Do not invent citations. If the retrieved context is insufficient, say so.',
      )
      ..writeln();
    var tokenEstimate = 0;
    var count = 0;
    for (final hit in hits) {
      if (count >= settings.maxPromptChunks) break;
      if (tokenEstimate + hit.chunk.tokenEstimate > settings.maxPromptTokens) {
        break;
      }
      count += 1;
      tokenEstimate += hit.chunk.tokenEstimate;
      buffer
        ..writeln('[KB-$count]')
        ..writeln('Title: ${hit.source.title}')
        ..writeln('Source: ${hit.source.originalPath}');
      if (settings.includeChunkId) buffer.writeln('Chunk ID: ${hit.chunk.id}');
      if (settings.includeTags) {
        buffer.writeln('Tags: ${hit.chunk.tags.join(", ")}');
      }
      if (settings.includeDate) {
        buffer.writeln(
          'Document Time: ${hit.chunk.documentTime?.toUtc().toIso8601String() ?? ""}',
        );
      }
      if (settings.includeScore) {
        buffer.writeln(
          'Score: ${(hit.finalScore ?? hit.score).toStringAsFixed(4)}',
        );
      }
      buffer
        ..writeln('Content:')
        ..writeln(hit.chunk.content.trim())
        ..writeln();
    }
    buffer.write('</OpenHandKnowledgeBaseContext>');
    return (text: buffer.toString(), tokenEstimate: tokenEstimate);
  }

  void dispose() {
    if (_ownsRerankService) {
      _rerankService.dispose();
    }
  }
}
