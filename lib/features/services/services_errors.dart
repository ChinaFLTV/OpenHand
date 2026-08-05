import 'dart:async';
import 'dart:io';

import '../../app/support/silent_log.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/text_normalization.dart';
import 'service/ai_jungler_client.dart';

const int _servicesErrorMaxCharacters = 400;

String reportServicesFailure(
  String source,
  String action,
  Object error,
  StackTrace stack, {
  String? fallback,
}) {
  silentLog(source, action, error, stack);
  return servicesFailureMessage(
    error,
    fallback: fallback ?? '$action失败，请稍后重试。',
  );
}

String servicesFailureMessage(Object error, {required String fallback}) {
  final detail = switch (error) {
    AiJunglerApiException(:final message, :final statusCode)
        when statusCode == null ||
            statusCode < HttpStatus.internalServerError =>
      message,
    FormatException(:final message) => message,
    StateError(:final message) => message,
    UnsupportedError(:final message) => '$message',
    FileSystemException(:final message) => message,
    TimeoutException(:final message) => message ?? '',
    _ => '',
  };
  final normalized = collapseInlineWhitespace(detail);
  return normalized.isEmpty
      ? fallback
      : clipTextWithEllipsis(normalized, _servicesErrorMaxCharacters - 1);
}
