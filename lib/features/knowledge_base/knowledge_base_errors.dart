import 'dart:async';
import 'dart:io';

import '../../app/support/silent_log.dart';
import '../../shared/util/user_failure_message.dart';
import 'service/knowledge_embedding_service.dart';
import 'service/knowledge_indexing_control.dart';
import 'service/qdrant_http_client.dart';

const String _kDartTimeoutIncompleteMessage = 'Future not completed';

String knowledgeBaseFailureMessage(Object error, {required String fallback}) {
  return userFailureMessage(
    error,
    fallback: fallback,
    detailResolver: (error) => switch (error) {
      KnowledgeEmbeddingException(:final message) => message,
      KnowledgeIndexingCancelledException(:final message) => message,
      QdrantHttpException(:final userFacingMessage) => userFacingMessage,
      TimeoutException(:final message)
          when message != null &&
              message.trim().isNotEmpty &&
              message != _kDartTimeoutIncompleteMessage =>
        message,
      _ => null,
    },
  );
}

bool isExpectedQdrantAvailabilityError(Object error) {
  return switch (error) {
    QdrantHttpException(:final isRetryable) => isRetryable,
    TimeoutException() => true,
    SocketException() => true,
    _ => false,
  };
}

void logKnowledgeDialogFailure(
  String tag,
  String action,
  Object error, [
  StackTrace? stack,
]) {
  if (isExpectedQdrantAvailabilityError(error)) return;
  silentLog(tag, action, error, stack);
}
