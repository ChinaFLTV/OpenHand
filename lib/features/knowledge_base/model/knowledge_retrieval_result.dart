import 'knowledge_chunk.dart';
import 'knowledge_source.dart';

class KnowledgeRetrievalHit {
  const KnowledgeRetrievalHit({
    required this.chunk,
    required this.source,
    required this.score,
    this.rerankScore,
    this.finalScore,
    this.timeField = '',
  });

  final KnowledgeChunk chunk;
  final KnowledgeSource source;
  final double score;
  final double? rerankScore;
  final double? finalScore;
  final String timeField;

  Map<String, Object?> toMessageJson() {
    final preview = chunk.content.trim();
    return <String, Object?>{
      'chunk_id': chunk.id,
      'source_id': source.id,
      'title': chunk.title.isNotEmpty ? chunk.title : source.title,
      'path': source.originalPath,
      'tags': chunk.tags,
      'document_time': chunk.documentTime?.toUtc().toIso8601String(),
      'updated_at': chunk.updatedAt.toUtc().toIso8601String(),
      'score': score,
      if (rerankScore != null) 'rerank_score': rerankScore,
      if (finalScore != null) 'final_score': finalScore,
      'time_field': timeField,
      'token_estimate': chunk.tokenEstimate,
      'preview': preview.length > 420
          ? '${preview.substring(0, 420)}...'
          : preview,
    };
  }
}

class KnowledgeRetrievalResult {
  const KnowledgeRetrievalResult({
    required this.query,
    required this.hits,
    required this.durationMs,
    required this.promptAppend,
    required this.promptTokenEstimate,
    this.error = '',
  });

  final String query;
  final List<KnowledgeRetrievalHit> hits;
  final int durationMs;
  final String promptAppend;
  final int promptTokenEstimate;
  final String error;

  bool get isSuccess => error.isEmpty;
}
