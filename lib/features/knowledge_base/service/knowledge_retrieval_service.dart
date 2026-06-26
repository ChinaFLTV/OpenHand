import 'dart:math' as math;

import '../../ai/index.dart';
import '../data/knowledge_base_store.dart';
import '../model/knowledge_base_settings.dart';
import '../model/knowledge_retrieval_result.dart';
import 'knowledge_embedding_service.dart';
import 'knowledge_vector_store.dart';

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
      filter: _filterForQuery(query),
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
    for (final hit in scored) {
      final count = perSource[hit.source.id] ?? 0;
      if (count >= settings.maxChunksPerSource) continue;
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

  Map<String, Object?>? _filterForQuery(String query) {
    final tags = RegExp(r'(?:^|\s)(?:tag:|#)([^\s#]+)')
        .allMatches(query)
        .map((match) => match.group(1)?.trim())
        .whereType<String>()
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    if (tags.isEmpty) return null;
    return <String, Object?>{
      'must': <Object?>[
        <String, Object?>{
          'key': 'tags',
          'match': <String, Object?>{'any': tags},
        },
      ],
    };
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
    final timeScore = _timeScore(query, documentTime);
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
