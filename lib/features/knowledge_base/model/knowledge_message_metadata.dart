import 'dart:convert';

import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/stable_hash.dart';
import 'knowledge_base_settings.dart';
import 'knowledge_retrieval_result.dart';
import 'knowledge_vector_distribution.dart';

const String knowledgeBaseMessageMetadataKey = 'knowledge_base';
const String knowledgeBasePromptAppendMetadataKey = 'prompt_append_content';
const int _knowledgeUsagePreviewMaxChars = 420;

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

  static Map<String, Object?>? usedReferencesByAnswer(
    Map<String, Object?>? metadata,
    String answerText,
  ) {
    if (metadata == null) return null;
    if (metadata['enabled'] != true ||
        '${metadata['status'] ?? ''}' != 'success') {
      return null;
    }
    final usedResults = _resultsUsedByAnswer(_resultMaps(metadata), answerText);
    if (usedResults.isEmpty) return null;
    final promptAppend =
        promptAppendInfo(metadata) ?? const <String, Object?>{};
    final tokenEstimate = usedResults.fold<int>(
      0,
      (total, hit) =>
          total + nonNegativeIntFromValue(hit['token_estimate'], fallback: 0),
    );
    return <String, Object?>{
      ...metadata,
      'results': usedResults,
      'prompt_append': <String, Object?>{
        ...promptAppend,
        'chunk_count': usedResults.length,
        if (tokenEstimate > 0) 'token_estimate': tokenEstimate,
      },
    };
  }

  static Map<String, Object?>? usedReferencesFromToolMetadata({
    required Iterable<Map<String, Object?>> toolMessages,
    required String answerText,
  }) {
    final results = <Map<String, Object?>>[];
    final queries = <String>[];
    final seen = <String>{};
    Map<String, Object?>? embedding;
    final retrievalSteps = <Map<String, Object?>>[];
    final rerankSteps = <Map<String, Object?>>[];
    Map<String, Object?>? vectorDistribution;
    for (final toolMessage in toolMessages) {
      final extracted = _fromToolMessageMetadata(toolMessage);
      if (extracted == null) continue;
      final query = '${extracted['query'] ?? ''}'.trim();
      if (query.isNotEmpty) queries.add(query);
      embedding ??= object(extracted['embedding']);
      final retrieval = object(extracted['retrieval']);
      if (retrieval != null) retrievalSteps.add(retrieval);
      final rerank = object(extracted['rerank']);
      if (rerank != null) rerankSteps.add(rerank);
      vectorDistribution ??= object(extracted['vector_distribution']);
      for (final result in _resultMaps(extracted)) {
        final label = citationLabel(result);
        final key = citationKey(result, label);
        if (!seen.add(key)) continue;
        results.add(result);
      }
    }
    if (results.isEmpty) return null;
    return usedReferencesByAnswer(<String, Object?>{
      'enabled': true,
      'status': 'success',
      'query': queries.toSet().join(' | '),
      if (embedding != null) 'embedding': embedding,
      if (retrievalSteps.isNotEmpty)
        'retrieval': _toolStepMetadata(
          strategy: 'knowledge_tools',
          steps: retrievalSteps,
        ),
      if (rerankSteps.isNotEmpty)
        'rerank': _toolStepMetadata(
          strategy: 'knowledge_tools',
          steps: rerankSteps,
        ),
      if (vectorDistribution != null) 'vector_distribution': vectorDistribution,
      'results': results,
      'prompt_append': <String, Object?>{
        'chunk_count': results.length,
        'token_estimate': results.fold<int>(
          0,
          (total, hit) =>
              total +
              nonNegativeIntFromValue(hit['token_estimate'], fallback: 0),
        ),
      },
      'source': 'knowledge_tools',
    }, answerText);
  }

  static String citationKey(Map<String, Object?> hit, [String? label]) {
    final sourceId = '${hit['source_id'] ?? ''}'.trim();
    if (sourceId.isNotEmpty) return 'source:$sourceId';
    final path = '${hit['path'] ?? ''}'.trim();
    if (path.isNotEmpty) return 'path:$path';
    return 'label:${label ?? citationLabel(hit)}';
  }

  static String citationLabel(Map<String, Object?> hit) {
    final title = '${hit['source_title'] ?? hit['title'] ?? ''}'.trim();
    if (title.isNotEmpty) return title;
    final path = '${hit['path'] ?? ''}'.trim();
    if (path.isNotEmpty) {
      final normalized = path.replaceAll('\\', '/');
      final slash = normalized.lastIndexOf('/');
      return slash >= 0 ? normalized.substring(slash + 1) : normalized;
    }
    return '${hit['chunk_id'] ?? ''}'.trim();
  }

  static Map<String, Object?>? object(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return stringKeyedMapFromValue(value);
    if (value is String && value.trim().isNotEmpty) {
      return optionalStringKeyedMapFromJsonText(value);
    }
    return null;
  }

  static Map<String, Object?>? _fromToolMessageMetadata(
    Map<String, Object?> metadata,
  ) {
    final toolName = '${metadata['tool_name'] ?? ''}'.trim().toLowerCase();
    final isSearch =
        toolName == 'knowledgesearch' || toolName == 'knowledge_search';
    final isRead = toolName == 'knowledgeread' || toolName == 'knowledge_read';
    if (!isSearch && !isRead) return null;
    final status =
        '${metadata['tool_execution_status'] ?? metadata['status'] ?? ''}'
            .trim()
            .toLowerCase();
    if (status.isNotEmpty &&
        status != 'success' &&
        status != 'ok' &&
        status != 'completed') {
      return null;
    }
    final rawRows = _toolResultRows(metadata);
    if (rawRows.isEmpty) return null;
    final toolKnowledgeMetadata = _toolKnowledgeMetadata(metadata);
    final results = rawRows
        .map(isRead ? _readRowToMessageHit : _searchRowToHit)
        .where((hit) => citationLabel(hit).isNotEmpty)
        .toList(growable: false);
    if (results.isEmpty) return null;
    final promptAppend =
        promptAppendInfo(toolKnowledgeMetadata ?? {}) ??
        const <String, Object?>{};
    return <String, Object?>{
      'enabled': true,
      'status': 'success',
      'query': _toolQuery(metadata, isRead: isRead),
      if (toolKnowledgeMetadata?['embedding'] != null)
        'embedding': toolKnowledgeMetadata!['embedding'],
      if (toolKnowledgeMetadata?['retrieval'] != null)
        'retrieval': toolKnowledgeMetadata!['retrieval'],
      if (toolKnowledgeMetadata?['rerank'] != null)
        'rerank': toolKnowledgeMetadata!['rerank'],
      if (toolKnowledgeMetadata?['vector_distribution'] != null)
        'vector_distribution': toolKnowledgeMetadata!['vector_distribution'],
      'results': results,
      'prompt_append': <String, Object?>{
        ...promptAppend,
        'chunk_count': results.length,
        'token_estimate': results.fold<int>(
          0,
          (total, hit) =>
              total +
              nonNegativeIntFromValue(hit['token_estimate'], fallback: 0),
        ),
      },
    };
  }

  static Map<String, Object?>? _toolKnowledgeMetadata(
    Map<String, Object?> metadata,
  ) {
    return object(metadata[knowledgeBaseMessageMetadataKey]) ??
        (metadata.containsKey('retrieval') || metadata.containsKey('rerank')
            ? metadata
            : null);
  }

  static List<Map<String, Object?>> _toolResultRows(
    Map<String, Object?> metadata,
  ) {
    final toolKnowledgeMetadata = _toolKnowledgeMetadata(metadata);
    final direct = metadata['results'] ?? toolKnowledgeMetadata?['results'];
    if (direct is List) {
      return direct
          .whereType<Map>()
          .map((item) => Map<String, Object?>.from(item))
          .toList(growable: false);
    }
    final resultText =
        '${metadata['tool_execution_result'] ?? metadata['result_text'] ?? ''}'
            .trim();
    if (resultText.isEmpty) return const <Map<String, Object?>>[];
    try {
      final decoded = jsonDecode(resultText);
      if (decoded is Map) {
        final results = decoded['results'];
        if (results is List) {
          return results
              .whereType<Map>()
              .map((item) => Map<String, Object?>.from(item))
              .toList(growable: false);
        }
      }
    } catch (_) {
      return const <Map<String, Object?>>[];
    }
    return const <Map<String, Object?>>[];
  }

  static String _toolQuery(
    Map<String, Object?> metadata, {
    required bool isRead,
  }) {
    final toolKnowledgeMetadata = _toolKnowledgeMetadata(metadata);
    final direct =
        '${metadata['query'] ?? toolKnowledgeMetadata?['query'] ?? ''}'.trim();
    if (direct.isNotEmpty) return direct;
    final args = _toolArguments(metadata['tool_arguments']);
    if (!isRead) return '${args['query'] ?? ''}'.trim();
    final chunkId = '${args['chunk_id'] ?? metadata['chunk_id'] ?? ''}'.trim();
    if (chunkId.isNotEmpty) return 'chunk_id:$chunkId';
    final sourceId = '${args['source_id'] ?? metadata['source_id'] ?? ''}'
        .trim();
    return sourceId.isNotEmpty ? 'source_id:$sourceId' : '';
  }

  static Map<String, Object?> _toolArguments(Object? raw) {
    if (raw is Map) return Map<String, Object?>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } catch (_) {
        return const <String, Object?>{};
      }
    }
    return const <String, Object?>{};
  }

  static Map<String, Object?> _searchRowToHit(Map<String, Object?> row) {
    return <String, Object?>{
      ...row,
      'title': row['title'] ?? row['source_title'],
      'path': row['path'] ?? row['original_path'],
    };
  }

  static Map<String, Object?> _readRowToMessageHit(Map<String, Object?> row) {
    final content = '${row['content'] ?? ''}'.trim();
    final existingPreview = '${row['preview'] ?? ''}'.trim();
    final previewSource = existingPreview.isNotEmpty
        ? existingPreview
        : content;
    final preview = previewSource.length > _knowledgeUsagePreviewMaxChars
        ? '${previewSource.substring(0, _knowledgeUsagePreviewMaxChars)}...'
        : previewSource;
    return <String, Object?>{
      'chunk_id': row['chunk_id'] ?? row['id'],
      'source_id': row['source_id'],
      'title': row['source_title'] ?? row['title'],
      'path': row['original_path'] ?? row['path'],
      'source_kind': row['kind'] ?? row['source_kind'],
      'document_time': row['document_time'],
      'updated_at': row['updated_at'],
      'token_estimate': row['token_estimate'],
      'heading_path': row['heading_path'],
      'preview': preview,
      if (content.isNotEmpty) 'content': content,
    };
  }

  static List<Map<String, Object?>> _resultMaps(Map<String, Object?> metadata) {
    final results = metadata['results'];
    if (results is! List) return const <Map<String, Object?>>[];
    return results
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  static List<Map<String, Object?>> _resultsUsedByAnswer(
    List<Map<String, Object?>> results,
    String answerText,
  ) {
    if (results.isEmpty || answerText.trim().isEmpty) {
      return const <Map<String, Object?>>[];
    }
    final normalizedAnswer = _usageNormalize(answerText);
    if (normalizedAnswer.isEmpty) return const <Map<String, Object?>>[];
    final used = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final result in results) {
      if (!_hitUsedByAnswer(result, normalizedAnswer)) continue;
      final label = citationLabel(result);
      final key = citationKey(result, label);
      if (!seen.add(key)) continue;
      used.add(result);
    }
    return used;
  }

  static bool _hitUsedByAnswer(
    Map<String, Object?> hit,
    String normalizedAnswer,
  ) {
    for (final term in _hitUsageTerms(hit)) {
      final normalizedTerm = _usageNormalize(term);
      if (!_usageTermWorthMatching(term, normalizedTerm)) continue;
      if (normalizedAnswer.contains(normalizedTerm)) return true;
    }
    return false;
  }

  static Iterable<String> _hitUsageTerms(Map<String, Object?> hit) sync* {
    for (final key in const <String>[
      'source_title',
      'title',
      'path',
      'chunk_id',
      'source_id',
      'heading_path',
    ]) {
      final value = '${hit[key] ?? ''}'.trim();
      if (value.isEmpty) continue;
      yield value;
      if (key == 'path') {
        final normalized = value.replaceAll('\\', '/');
        final slash = normalized.lastIndexOf('/');
        if (slash >= 0 && slash + 1 < normalized.length) {
          yield normalized.substring(slash + 1);
        }
      }
      if (key == 'heading_path') {
        for (final part in value.split(RegExp(r'[>/\\|]+'))) {
          final trimmed = part.trim();
          if (trimmed.isNotEmpty) yield trimmed;
        }
      }
    }
    for (final key in const <String>['preview', 'content']) {
      final value = '${hit[key] ?? ''}'.trim();
      if (value.isEmpty) continue;
      yield* _stableTextFragments(value);
      yield* _quotedTitleFragments(value);
      yield* _markdownTableCellFragments(value);
    }
  }

  static Iterable<String> _stableTextFragments(String text) sync* {
    final parts = text.split(RegExp(r'[\r\n。！？!?；;]+'));
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.length < 12) continue;
      yield trimmed.length > 90 ? trimmed.substring(0, 90) : trimmed;
    }
  }

  static Iterable<String> _quotedTitleFragments(String text) sync* {
    final matches = RegExp(r'《([^》]{2,80})》').allMatches(text);
    for (final match in matches) {
      final title = match.group(0)?.trim();
      if (title != null && title.isNotEmpty) yield title;
    }
  }

  static Iterable<String> _markdownTableCellFragments(String text) sync* {
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final trimmedLine = line.trim();
      if (!trimmedLine.startsWith('|') || !trimmedLine.endsWith('|')) continue;
      if (RegExp(
        r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$',
      ).hasMatch(trimmedLine)) {
        continue;
      }
      for (final cell in trimmedLine.split('|')) {
        final trimmed = cell.trim();
        if (trimmed.isEmpty || trimmed.length < 4) continue;
        yield trimmed.length > 90 ? trimmed.substring(0, 90) : trimmed;
      }
    }
  }

  static bool _usageTermWorthMatching(String raw, String normalized) {
    if (normalized.isEmpty) return false;
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(raw);
    final minLength = hasCjk ? 4 : 8;
    if (normalized.length < minLength) return false;
    const generic = <String>{
      'knowledgebase',
      'knowledge',
      'document',
      'documents',
      'chunk',
      'chunks',
      '知识库',
      '文档',
      '资料',
      '片段',
      '名称',
      '说明',
      '时间',
    };
    return !generic.contains(normalized);
  }

  static String _usageNormalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'''[\s`~!@#$%^&*()_\-+={}\[\]|\\:;"'<>,.?/，。、《》？；：‘’“”【】（）！￥…—·、]+''',
          ),
          '',
        )
        .trim();
  }

  static Map<String, Object?> _toolStepMetadata({
    required String strategy,
    required List<Map<String, Object?>> steps,
  }) {
    if (steps.length == 1) return steps.single;
    final durationMs = steps.fold<int>(
      0,
      (total, step) =>
          total + nonNegativeIntFromValue(step['duration_ms'], fallback: 0),
    );
    return <String, Object?>{
      'strategy': strategy,
      'step_count': steps.length,
      if (durationMs > 0) 'duration_ms': durationMs,
      'steps': steps,
    };
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
