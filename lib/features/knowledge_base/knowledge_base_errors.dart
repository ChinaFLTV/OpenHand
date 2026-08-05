import 'dart:async';
import 'dart:io';

import '../../shared/util/text_clip.dart';
import '../../shared/util/text_normalization.dart';
import 'service/knowledge_embedding_service.dart';
import 'service/knowledge_indexing_control.dart';
import 'service/qdrant_http_client.dart';

const int _knowledgeBaseErrorMaxCharacters = 400;

String knowledgeBaseFailureMessage(Object error, {required String fallback}) {
  final detail = switch (error) {
    KnowledgeEmbeddingException(:final message) => message,
    KnowledgeIndexingCancelledException(:final message) => message,
    QdrantHttpException(:final message, :final statusCode)
        when statusCode < HttpStatus.internalServerError =>
      message,
    FormatException(:final message) => message,
    StateError(:final message) => message,
    FileSystemException(:final message) => message,
    TimeoutException(:final message) => message ?? '',
    _ => '',
  };
  final normalized = collapseInlineWhitespace(detail);
  return normalized.isEmpty
      ? fallback
      : clipTextWithEllipsis(normalized, _knowledgeBaseErrorMaxCharacters - 1);
}
