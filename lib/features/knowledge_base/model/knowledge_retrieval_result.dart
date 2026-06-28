import 'knowledge_chunk.dart';
import 'knowledge_source.dart';

class KnowledgeRetrievalHit {
  const KnowledgeRetrievalHit({
    required this.chunk,
    required this.source,
    required this.score,
    this.vector = const <double>[],
    this.rerankScore,
    this.finalScore,
    this.timeField = '',
  });

  final KnowledgeChunk chunk;
  final KnowledgeSource source;
  final double score;
  final List<double> vector;
  final double? rerankScore;
  final double? finalScore;
  final String timeField;

  KnowledgeRetrievalHit copyWith({
    double? score,
    List<double>? vector,
    double? rerankScore,
    double? finalScore,
    String? timeField,
  }) {
    return KnowledgeRetrievalHit(
      chunk: chunk,
      source: source,
      score: score ?? this.score,
      vector: vector ?? this.vector,
      rerankScore: rerankScore ?? this.rerankScore,
      finalScore: finalScore ?? this.finalScore,
      timeField: timeField ?? this.timeField,
    );
  }

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

class KnowledgeRerankTrace {
  const KnowledgeRerankTrace({
    required this.mode,
    required this.strategy,
    required this.candidateCount,
    this.rerankInputCount = 0,
    this.rerankOutputCount = 0,
    this.keptCount = 0,
    this.discardedCount = 0,
    this.durationMs,
    this.providerConfigId = '',
    this.modelId = '',
    this.error = '',
  });

  final String mode;
  final String strategy;
  final int candidateCount;
  final int rerankInputCount;
  final int rerankOutputCount;
  final int keptCount;
  final int discardedCount;
  final int? durationMs;
  final String providerConfigId;
  final String modelId;
  final String error;

  KnowledgeRerankTrace copyWith({
    String? mode,
    String? strategy,
    int? candidateCount,
    int? rerankInputCount,
    int? rerankOutputCount,
    int? keptCount,
    int? discardedCount,
    int? durationMs,
    String? providerConfigId,
    String? modelId,
    String? error,
  }) {
    return KnowledgeRerankTrace(
      mode: mode ?? this.mode,
      strategy: strategy ?? this.strategy,
      candidateCount: candidateCount ?? this.candidateCount,
      rerankInputCount: rerankInputCount ?? this.rerankInputCount,
      rerankOutputCount: rerankOutputCount ?? this.rerankOutputCount,
      keptCount: keptCount ?? this.keptCount,
      discardedCount: discardedCount ?? this.discardedCount,
      durationMs: durationMs ?? this.durationMs,
      providerConfigId: providerConfigId ?? this.providerConfigId,
      modelId: modelId ?? this.modelId,
      error: error ?? this.error,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': mode,
      'strategy': strategy,
      'candidate_count': candidateCount,
      'rerank_input_count': rerankInputCount,
      'rerank_output_count': rerankOutputCount,
      'kept_count': keptCount,
      'discarded_count': discardedCount,
      if (durationMs != null) 'duration_ms': durationMs,
      if (providerConfigId.isNotEmpty) 'provider_config_id': providerConfigId,
      if (modelId.isNotEmpty) 'model_id': modelId,
      if (error.isNotEmpty) 'error': error,
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
    this.queryVector = const <double>[],
    this.rerankTrace,
    this.error = '',
  });

  final String query;
  final List<KnowledgeRetrievalHit> hits;
  final int durationMs;
  final String promptAppend;
  final int promptTokenEstimate;
  final List<double> queryVector;
  final KnowledgeRerankTrace? rerankTrace;
  final String error;

  bool get isSuccess => error.isEmpty;
}
