import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/stable_hash.dart';
import 'knowledge_base_settings.dart';
import 'knowledge_retrieval_result.dart';
import 'knowledge_vector_distribution.dart';

const String knowledgeBaseMessageMetadataKey = 'knowledge_base';
const String knowledgeBasePromptAppendMetadataKey = 'prompt_append_content';

class KnowledgeMessageMetadata {
  const KnowledgeMessageMetadata._();

  static Map<String, Object?> skipped({
    required bool enabled,
    required String reason,
    required String query,
  }) {
    return <String, Object?>{
      'enabled': enabled,
      'status': 'skipped',
      'query': query,
      'error': reason,
    };
  }

  static Map<String, Object?> failed({
    required String query,
    required String error,
    required KnowledgeBaseSettings settings,
    int? embeddingDurationMs,
    int? retrievalDurationMs,
  }) {
    return <String, Object?>{
      'enabled': true,
      'status': 'failed',
      'query': query,
      'embedding': <String, Object?>{
        'provider_config_id': settings.providerConfigId,
        'model_id': settings.modelId,
        'dimensions': settings.dimensions,
        if (embeddingDurationMs != null) 'duration_ms': embeddingDurationMs,
      },
      'retrieval': <String, Object?>{
        if (retrievalDurationMs != null) 'duration_ms': retrievalDurationMs,
        'top_n': settings.topN,
        'top_k': settings.topK,
        'min_similarity': settings.minSimilarity,
      },
      'results': const <Object?>[],
      'prompt_append': const <String, Object?>{
        'chunk_count': 0,
        'token_estimate': 0,
        'content_hash': '',
      },
      'error': error,
    };
  }

  static Map<String, Object?> success({
    required KnowledgeBaseSettings settings,
    required KnowledgeRetrievalResult result,
    required int embeddingDurationMs,
    required String promptAppendContent,
  }) {
    return <String, Object?>{
      'enabled': true,
      'status': result.hits.isEmpty ? 'skipped' : 'success',
      'query': result.query,
      'embedding': <String, Object?>{
        'provider_config_id': settings.providerConfigId,
        'model_id': settings.modelId,
        'dimensions': settings.dimensions,
        'duration_ms': embeddingDurationMs,
      },
      'retrieval': <String, Object?>{
        'duration_ms': result.durationMs,
        'top_n': settings.topN,
        'top_k': settings.topK,
        'min_similarity': settings.minSimilarity,
        'filters': const <String, Object?>{
          'tags': <String>[],
          'date_from': null,
          'date_to': null,
        },
      },
      if (result.rerankTrace != null) 'rerank': result.rerankTrace!.toJson(),
      'results': result.hits
          .map((hit) => hit.toMessageJson())
          .toList(growable: false),
      if (_messageVectorDistribution(result, settings) case final distribution?)
        'vector_distribution': distribution.toJson(),
      'prompt_append': <String, Object?>{
        'chunk_count': result.hits.length,
        'token_estimate': result.promptTokenEstimate,
        'content_hash': stableFnv1a32Hex(promptAppendContent),
      },
      knowledgeBasePromptAppendMetadataKey: promptAppendContent,
      'error': result.error,
    };
  }

  static bool hasReferences(Map<String, Object?> metadata) {
    final kb = fromMessageMetadata(metadata);
    if (kb == null) return false;
    return kb['enabled'] == true &&
        '${kb['status'] ?? ''}' == 'success' &&
        (kb['results'] is List) &&
        (kb['results'] as List).isNotEmpty;
  }

  static Map<String, Object?>? fromMessageMetadata(
    Map<String, Object?> metadata,
  ) {
    return object(metadata[knowledgeBaseMessageMetadataKey]) ??
        object(metadata);
  }

  static String promptAppendContent(Map<String, Object?> metadata) {
    final kb = fromMessageMetadata(metadata);
    return '${kb?[knowledgeBasePromptAppendMetadataKey] ?? ''}'.trim();
  }

  static Map<String, Object?>? promptAppendInfo(Map<String, Object?> metadata) {
    final kb = fromMessageMetadata(metadata);
    return object(kb?['prompt_append']);
  }

  static KnowledgeVectorDistribution? vectorDistribution(
    Map<String, Object?> metadata,
  ) {
    final kb = fromMessageMetadata(metadata);
    return KnowledgeVectorDistribution.fromJson(kb?['vector_distribution']);
  }

  static Map<String, Object?>? object(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return stringKeyedMapFromValue(value);
    if (value is String && value.trim().isNotEmpty) {
      return optionalStringKeyedMapFromJsonText(value);
    }
    return null;
  }

  static KnowledgeVectorDistribution? _messageVectorDistribution(
    KnowledgeRetrievalResult result,
    KnowledgeBaseSettings settings,
  ) {
    if (result.queryVector.isEmpty ||
        result.queryVector.any((value) => !value.isFinite)) {
      return null;
    }
    final inputs = <KnowledgeVectorProjectionInput>[
      KnowledgeVectorProjectionInput(
        id: 'query',
        kind: KnowledgeVectorPointKind.query,
        title: 'Query',
        preview: result.query,
        vector: result.queryVector,
      ),
      for (final hit in result.hits)
        if (hit.vector.isNotEmpty && hit.vector.any((value) => value.isFinite))
          KnowledgeVectorProjectionInput(
            id: hit.chunk.id,
            kind: KnowledgeVectorPointKind.match,
            title: hit.chunk.title.isNotEmpty
                ? hit.chunk.title
                : hit.source.title,
            preview: hit.chunk.content,
            vector: hit.vector,
            score: hit.score,
            rerankScore: hit.rerankScore,
          ),
    ];
    if (inputs.length <= 1) return null;
    return KnowledgeVectorProjector.project(
      inputs: inputs,
      originalDimensions: settings.dimensions,
      generatedAt: DateTime.now().toUtc(),
    );
  }
}
