import 'dart:convert';

import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/stable_hash.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/model/ai_session_message.dart';
import 'knowledge_base_settings.dart';
import 'knowledge_retrieval_result.dart';
import 'knowledge_vector_distribution.dart';

const String knowledgeBaseMessageMetadataKey = 'knowledge_base';
const String knowledgeBasePromptAppendMetadataKey = 'prompt_append_content';
const int _knowledgeUsagePreviewMaxChars = 420;
const int _knowledgeUsageTermMaxChars = 90;
const List<String> _knowledgeTitleKeys = <String>[
  'source_title',
  'title',
  'chunk_title',
];
const List<String> _knowledgeSourceKeys = <String>[
  'path',
  'original_path',
  'source_path',
  'source_id',
];
const List<String> _knowledgeUsageTermKeys = <String>[
  'source_title',
  'title',
  'path',
  'chunk_id',
  'source_id',
  'heading_path',
];
final RegExp _knowledgeHeadingPathSeparatorPattern = RegExp(r'[>/\\|]+');
final RegExp _knowledgeStableFragmentSeparatorPattern = RegExp(
  r'[\r\n。！？!?；;]+',
);
final RegExp _knowledgeQuotedTitlePattern = RegExp(r'《([^》]{2,80})》');
final RegExp _knowledgeLineBreakPattern = RegExp(r'[\r\n]+');
final RegExp _knowledgeMarkdownTableSeparatorPattern = RegExp(
  r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$',
);
final RegExp _knowledgeCjkPattern = RegExp(r'[\u4e00-\u9fff]');
final RegExp _knowledgeUsageNormalizeNoisePattern = RegExp(
  r'''[\s`~!@#$%^&*()_\-+={}\[\]|\\:;"'<>,.?/，。、《》？；：‘’“”【】（）！￥…—·、]+''',
);

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
    final direct = rawPromptAppendContent(metadata);
    if (direct.isNotEmpty) return direct;
    final kb = fromMessageMetadata(metadata);
    if (kb == null) return '';
    if (!_looksLikeKnowledgeMetadata(kb)) return '';
    return promptAppendContentFromResults(
      _resultMaps(kb),
      query: '${kb['query'] ?? ''}'.trim(),
    );
  }

  static String rawPromptAppendContent(Map<String, Object?> metadata) {
    final kb = fromMessageMetadata(metadata);
    return '${kb?[knowledgeBasePromptAppendMetadataKey] ?? ''}'.trim();
  }

  static Map<String, Object?>? promptAppendInfo(Map<String, Object?> metadata) {
    final kb = fromMessageMetadata(metadata);
    return object(kb?['prompt_append']);
  }

  static String promptAppendContentFromResults(
    List<Map<String, Object?>> results, {
    String query = '',
  }) {
    final usable = results
        .where((hit) => nullIfBlank(_contextContent(hit)) != null)
        .toList(growable: false);
    if (usable.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('<OpenHandKnowledgeBaseContext>')
      ..writeln('Knowledge Base context retained for this message.')
      ..writeln('Use it only when relevant; do not invent citations.');
    final normalizedQuery = query.trim();
    if (normalizedQuery.isNotEmpty) {
      buffer.writeln('Query: $normalizedQuery');
    }
    buffer.writeln();
    for (var index = 0; index < usable.length; index++) {
      final hit = usable[index];
      final content = _contextContent(hit).trim();
      final hasExactContent = _textValue(hit, 'content').isNotEmpty;
      final title = _contextTitle(hit);
      final source = _contextSource(hit);
      final heading = _textValue(hit, 'heading_path');
      final chunkId = _textValue(hit, 'chunk_id');
      final documentTime = _textValue(hit, 'document_time');
      final score = hit['final_score'] ?? hit['rerank_score'] ?? hit['score'];
      buffer.writeln('[KB-${index + 1}]');
      if (title.isNotEmpty) buffer.writeln('Title: $title');
      if (source.isNotEmpty) buffer.writeln('Source: $source');
      if (chunkId.isNotEmpty) buffer.writeln('Chunk ID: $chunkId');
      if (heading.isNotEmpty) buffer.writeln('Heading: $heading');
      if (documentTime.isNotEmpty) {
        buffer.writeln('Document Time: $documentTime');
      }
      if (score != null && nullIfBlank('$score') != null) {
        buffer.writeln('Score: $score');
      }
      if (_isTruthy(hit['content_truncated'])) {
        buffer.writeln('Content Status: truncated');
      }
      buffer
        ..writeln(hasExactContent ? 'Content:' : 'Content Preview:')
        ..writeln(content)
        ..writeln();
    }
    buffer.write('</OpenHandKnowledgeBaseContext>');
    return buffer.toString();
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
    final rawPromptAppend = rawPromptAppendContent(metadata);
    final tokenEstimate = usedResults.fold<int>(
      0,
      (total, hit) =>
          total + nonNegativeIntFromValue(hit['token_estimate'], fallback: 0),
    );
    final promptAppendContent = rawPromptAppend.isNotEmpty
        ? rawPromptAppend
        : promptAppendContentFromResults(
            usedResults,
            query: '${metadata['query'] ?? ''}'.trim(),
          );
    return <String, Object?>{
      ...metadata,
      'results': usedResults,
      'prompt_append': <String, Object?>{
        ...promptAppend,
        'chunk_count': usedResults.length,
        if (tokenEstimate > 0) 'token_estimate': tokenEstimate,
      },
      if (promptAppendContent.trim().isNotEmpty)
        knowledgeBasePromptAppendMetadataKey: promptAppendContent,
    };
  }

  static Map<String, Object?>? usedReferencesFromToolMetadata({
    required Iterable<Map<String, Object?>> toolMessages,
    required String answerText,
  }) {
    final resultsByKey = <String, Map<String, Object?>>{};
    final queries = <String>[];
    final seenToolExecutions = <String>{};
    Map<String, Object?>? embedding;
    final retrievalSteps = <Map<String, Object?>>[];
    final rerankSteps = <Map<String, Object?>>[];
    Map<String, Object?>? vectorDistribution;
    for (final toolMessage in toolMessages) {
      final extracted = _fromToolMessageMetadata(toolMessage);
      if (extracted == null) continue;
      final toolExecutionKey = _toolExecutionKey(toolMessage);
      if (toolExecutionKey.isNotEmpty &&
          !seenToolExecutions.add(toolExecutionKey)) {
        continue;
      }
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
        if (label.isEmpty) continue;
        final key = _resultKey(result, label);
        final existing = resultsByKey[key];
        resultsByKey[key] = existing == null
            ? result
            : _mergePreferredResultHit(existing, result);
      }
    }
    final results = resultsByKey.values.toList(growable: false);
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
    final sourceId = _textValue(hit, 'source_id');
    if (sourceId.isNotEmpty) return 'source:$sourceId';
    final path = _textValue(hit, 'path');
    if (path.isNotEmpty) return 'path:$path';
    return 'label:${label ?? citationLabel(hit)}';
  }

  static String citationLabel(Map<String, Object?> hit) {
    final title = _firstTextValue(hit, const <String>['source_title', 'title']);
    if (title.isNotEmpty) return title;
    final path = _textValue(hit, 'path');
    if (path.isNotEmpty) {
      final normalized = path.replaceAll('\\', '/');
      final slash = normalized.lastIndexOf('/');
      return slash >= 0 ? normalized.substring(slash + 1) : normalized;
    }
    return _textValue(hit, 'chunk_id');
  }

  static String _resultKey(Map<String, Object?> hit, [String? label]) {
    final chunkId = _firstTextValue(hit, const <String>['chunk_id', 'id']);
    if (chunkId.isNotEmpty) return 'chunk:$chunkId';
    final sourceId = _textValue(hit, 'source_id');
    final heading = _textValue(hit, 'heading_path');
    if (sourceId.isNotEmpty && heading.isNotEmpty) {
      return 'source-heading:$sourceId:$heading';
    }
    final title = _firstTextValue(hit, const <String>['title', 'source_title']);
    if (sourceId.isNotEmpty && title.isNotEmpty) {
      return 'source-title:$sourceId:$title';
    }
    return citationKey(hit, label);
  }

  static Map<String, Object?> _mergePreferredResultHit(
    Map<String, Object?> existing,
    Map<String, Object?> candidate,
  ) {
    final candidateQuality = _hitContentQuality(candidate);
    final existingQuality = _hitContentQuality(existing);
    final preferred = candidateQuality > existingQuality ? candidate : existing;
    final fallback = identical(preferred, candidate) ? existing : candidate;
    return <String, Object?>{...fallback, ...preferred};
  }

  static int _hitContentQuality(Map<String, Object?> hit) {
    final content = _textValue(hit, 'content');
    if (content.isNotEmpty) {
      return 2000 +
          content.length -
          (_isTruthy(hit['content_truncated']) ? 500 : 0);
    }
    final preview = _textValue(hit, 'preview');
    return preview.isNotEmpty ? preview.length : 0;
  }

  static String _toolExecutionKey(Map<String, Object?> metadata) {
    final toolName = _textValue(metadata, 'tool_name').toLowerCase();
    final callId = _textValue(metadata, aiSessionMessageToolCallIdMetadataKey);
    if (toolName.isNotEmpty && callId.isNotEmpty) {
      return '$toolName:$callId';
    }
    final command =
        '${metadata['tool_execution_command'] ?? metadata['command'] ?? ''}'
            .trim();
    final args = _textValue(metadata, 'tool_arguments');
    if (toolName.isEmpty && command.isEmpty && args.isEmpty) return '';
    return '$toolName|$command|$args';
  }

  static String _contextContent(Map<String, Object?> hit) {
    final content = _textValue(hit, 'content');
    if (content.isNotEmpty) return content;
    return _textValue(hit, 'preview');
  }

  static String _contextTitle(Map<String, Object?> hit) {
    return _firstTextValue(hit, _knowledgeTitleKeys);
  }

  static String _contextSource(Map<String, Object?> hit) {
    return _firstTextValue(hit, _knowledgeSourceKeys, ignoreLiteralNull: true);
  }

  static bool _isTruthy(Object? value) {
    return boolFromValue(value);
  }

  static bool _looksLikeKnowledgeMetadata(Map<String, Object?> metadata) {
    return metadata['enabled'] == true ||
        metadata['source'] == 'knowledge_tools' ||
        metadata.containsKey('prompt_append') ||
        metadata.containsKey('embedding') ||
        metadata.containsKey('retrieval') ||
        metadata.containsKey('vector_distribution');
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
      return stringKeyedMapListFromValue(direct);
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
          return stringKeyedMapListFromValue(results);
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
    final direct = _textFromValue(
      metadata['query'] ?? toolKnowledgeMetadata?['query'],
    );
    if (direct.isNotEmpty) return direct;
    final args = _toolArguments(metadata['tool_arguments']);
    if (!isRead) return _textValue(args, 'query');
    final chunkId = _textFromValue(args['chunk_id'] ?? metadata['chunk_id']);
    if (chunkId.isNotEmpty) return 'chunk_id:$chunkId';
    final sourceId = _textFromValue(args['source_id'] ?? metadata['source_id']);
    return sourceId.isNotEmpty ? 'source_id:$sourceId' : '';
  }

  static Map<String, Object?> _toolArguments(Object? raw) {
    if (raw is Map) return stringKeyedMapFromValue(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return stringKeyedMapFromValue(decoded);
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
    final preview = clipText(previewSource, _knowledgeUsagePreviewMaxChars);
    return <String, Object?>{
      'chunk_id': row['chunk_id'] ?? row['id'],
      'source_id': row['source_id'],
      'title': row['source_title'] ?? row['title'],
      if (row['source_title'] != null) 'source_title': row['source_title'],
      if (row['chunk_title'] != null) 'chunk_title': row['chunk_title'],
      'path': row['original_path'] ?? row['path'],
      'source_kind': row['kind'] ?? row['source_kind'],
      'document_time': row['document_time'],
      'updated_at': row['updated_at'],
      'token_estimate': row['token_estimate'],
      'heading_path': row['heading_path'],
      'preview': preview,
      if (content.isNotEmpty) 'content': content,
      if (row['content_truncated'] != null)
        'content_truncated': row['content_truncated'],
      if (row['content_status'] != null)
        'content_status': row['content_status'],
      if (row['content_char_limit'] != null)
        'content_char_limit': row['content_char_limit'],
    };
  }

  static List<Map<String, Object?>> _resultMaps(Map<String, Object?> metadata) {
    final results = metadata['results'];
    if (results is! List) return const <Map<String, Object?>>[];
    return stringKeyedMapListFromValue(results);
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
      final key = _resultKey(result, label);
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
    for (final key in _knowledgeUsageTermKeys) {
      final value = _textValue(hit, key);
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
        yield* splitTrimmedNonEmpty(
          value,
          separator: _knowledgeHeadingPathSeparatorPattern,
        );
      }
    }
    for (final key in const <String>['preview', 'content']) {
      final value = _textValue(hit, key);
      if (value.isEmpty) continue;
      yield* _stableTextFragments(value);
      yield* _quotedTitleFragments(value);
      yield* _markdownTableCellFragments(value);
    }
  }

  static Iterable<String> _stableTextFragments(String text) sync* {
    final parts = text.split(_knowledgeStableFragmentSeparatorPattern);
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.length < 12) continue;
      yield clipText(trimmed, _knowledgeUsageTermMaxChars, suffix: '');
    }
  }

  static Iterable<String> _quotedTitleFragments(String text) sync* {
    final matches = _knowledgeQuotedTitlePattern.allMatches(text);
    for (final match in matches) {
      final title = match.group(0)?.trim();
      if (title != null && title.isNotEmpty) yield title;
    }
  }

  static Iterable<String> _markdownTableCellFragments(String text) sync* {
    for (final line in text.split(_knowledgeLineBreakPattern)) {
      final trimmedLine = line.trim();
      if (!trimmedLine.startsWith('|') || !trimmedLine.endsWith('|')) continue;
      if (_knowledgeMarkdownTableSeparatorPattern.hasMatch(trimmedLine)) {
        continue;
      }
      for (final cell in trimmedLine.split('|')) {
        final trimmed = cell.trim();
        if (trimmed.isEmpty || trimmed.length < 4) continue;
        yield clipText(trimmed, _knowledgeUsageTermMaxChars, suffix: '');
      }
    }
  }

  static bool _usageTermWorthMatching(String raw, String normalized) {
    if (normalized.isEmpty) return false;
    final hasCjk = _knowledgeCjkPattern.hasMatch(raw);
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
        .replaceAll(_knowledgeUsageNormalizeNoisePattern, '')
        .trim();
  }

  static String _textValue(Map<String, Object?> source, String key) {
    return _textFromValue(source[key]);
  }

  static String _textFromValue(Object? value) {
    return '${value ?? ''}'.trim();
  }

  static String _firstTextValue(
    Map<String, Object?> source,
    Iterable<String> keys, {
    bool ignoreLiteralNull = false,
  }) {
    for (final key in keys) {
      final value = _textValue(source, key);
      if (value.isEmpty) continue;
      if (ignoreLiteralNull && value == 'null') continue;
      return value;
    }
    return '';
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
