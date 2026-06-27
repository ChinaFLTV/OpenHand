import 'dart:math' as math;

import '../../ai/index.dart';
import '../data/knowledge_base_store.dart';
import '../model/knowledge_base_settings.dart';
import '../model/knowledge_retrieval_result.dart';
import 'knowledge_embedding_service.dart';
import 'knowledge_vector_store.dart';

const Duration _oneDay = Duration(days: 1);

class KnowledgeRetrievalService {
  KnowledgeRetrievalService({
    required KnowledgeBaseStore store,
    required KnowledgeEmbeddingService embeddingService,
    required KnowledgeVectorStore vectorStore,
  }) : _store = store,
       _embeddingService = embeddingService,
       _vectorStore = vectorStore;

  final KnowledgeBaseStore _store;
  final KnowledgeEmbeddingService _embeddingService;
  final KnowledgeVectorStore _vectorStore;

  Future<KnowledgeRetrievalResult> retrieve({
    required String query,
    required KnowledgeBaseSettings settings,
    required AiModelConfig embeddingModel,
  }) async {
    final stopwatch = Stopwatch()..start();
    final vectors = await _embeddingService.embedBatch(
      settings: settings,
      model: embeddingModel,
      inputs: <String>[query],
      isQuery: true,
    );
    final rawHits = await _vectorStore.search(
      collectionName: settings.effectiveCollectionName,
      vector: vectors.first,
      limit: settings.topN,
      scoreThreshold: settings.minSimilarity,
      filter: _filterForQuery(query, settings),
    );
    final chunkIds = rawHits
        .map((hit) => '${hit.payload['chunk_id'] ?? hit.id}'.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final chunksById = await _store.loadChunksByIds(chunkIds);
    final sourcesById = await _store.loadSourcesByIds(
      chunksById.values.map((chunk) => chunk.sourceId),
    );
    final scored = <KnowledgeRetrievalHit>[];
    for (final raw in rawHits) {
      final chunkId = '${raw.payload['chunk_id'] ?? raw.id}'.trim();
      final chunk = chunksById[chunkId];
      if (chunk == null) continue;
      final source = sourcesById[chunk.sourceId];
      if (source == null) continue;
      final finalScore = _hybridScore(
        query: query,
        vectorScore: raw.score,
        title: '${raw.payload['source_title'] ?? source.title}',
        tags: chunk.tags,
        documentTime: chunk.documentTime ?? source.documentTime,
        settings: settings,
      );
      scored.add(
        KnowledgeRetrievalHit(
          chunk: chunk,
          source: source,
          score: raw.score,
          finalScore: finalScore,
          timeField: chunk.documentTime != null
              ? 'document_time'
              : source.documentTime != null
              ? 'source.document_time'
              : 'updated_at',
        ),
      );
    }
    scored.sort(
      (a, b) => (b.finalScore ?? b.score).compareTo(a.finalScore ?? a.score),
    );
    final capped = <KnowledgeRetrievalHit>[];
    final perSource = <String, int>{};
    final perSourceLimit = math.min(
      settings.sourceCap,
      settings.maxChunksPerSource,
    );
    for (final hit in scored) {
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
    stopwatch.stop();
    return KnowledgeRetrievalResult(
      query: query,
      hits: capped,
      durationMs: stopwatch.elapsedMilliseconds,
      promptAppend: prompt.text,
      promptTokenEstimate: prompt.tokenEstimate,
    );
  }

  Map<String, Object?>? _filterForQuery(
    String query,
    KnowledgeBaseSettings settings,
  ) {
    final must = <Object?>[];
    final tags = RegExp(r'(?:^|\s)(?:tag:|#)([^\s#]+)')
        .allMatches(query)
        .map((match) => match.group(1)?.trim())
        .whereType<String>()
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    if (tags.isNotEmpty) {
      if (settings.tagFilterMode == 'all') {
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
    if (settings.dateFilterMode == 'hard_when_explicit') {
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
        settings.recencyBoostEnabled && settings.dateFilterMode != 'off'
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
    return math.exp(-math.max(0, ageDays) / 90).clamp(0.0, 1.0);
  }

  ({DateTime start, DateTime end})? _dateRangeForQuery(
    String query, {
    required bool allowNaturalLanguage,
  }) {
    final normalized = query.toLowerCase();
    final dayMatch = RegExp(
      r'\b(19\d{2}|20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b',
    ).firstMatch(normalized);
    if (dayMatch != null) {
      final start = _utcDateOrNull(
        int.parse(dayMatch.group(1)!),
        int.parse(dayMatch.group(2)!),
        int.parse(dayMatch.group(3)!),
      );
      if (start != null) return (start: start, end: start.add(_oneDay));
    }

    final monthMatch = RegExp(
      r'\b(19\d{2}|20\d{2})[-/.](\d{1,2})\b',
    ).firstMatch(normalized);
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
    final recentDaysMatch = RegExp(
      r'(?:最近|近|last|past)\s*(\d{1,4})\s*(?:天|日|days?)',
    ).firstMatch(normalized);
    if (recentDaysMatch == null) return null;
    final days = int.tryParse(recentDaysMatch.group(1)!);
    if (days == null || days <= 0 || days > 3650) return null;
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
}
