import 'dart:convert';

import '../../../shared/util/stable_hash.dart';
import 'knowledge_base_settings.dart';
import 'knowledge_retrieval_result.dart';

const String knowledgeBaseMessageMetadataKey = 'knowledge_base';
const String knowledgeBasePromptAppendMetadataKey = 'prompt_append_content';
const String knowledgeBaseSessionToggleMetadataKey =
    'knowledge_base_reference_enabled';

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
      'results': result.hits
          .map((hit) => hit.toMessageJson())
          .toList(growable: false),
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

  static Map<String, Object?>? object(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } catch (_) {}
    }
    return null;
  }
}
