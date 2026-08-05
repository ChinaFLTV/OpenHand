import 'dart:io';

import '../../shared/util/user_failure_message.dart';
import 'service/knowledge_embedding_service.dart';
import 'service/knowledge_indexing_control.dart';
import 'service/qdrant_http_client.dart';

String knowledgeBaseFailureMessage(Object error, {required String fallback}) {
  return userFailureMessage(
    error,
    fallback: fallback,
    detailResolver: (error) => switch (error) {
      KnowledgeEmbeddingException(:final message) => message,
      KnowledgeIndexingCancelledException(:final message) => message,
      QdrantHttpException(:final message, :final statusCode)
          when statusCode < HttpStatus.internalServerError =>
        message,
      _ => null,
    },
  );
}
