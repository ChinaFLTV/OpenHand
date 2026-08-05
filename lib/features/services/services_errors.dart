import 'dart:io';

import '../../app/support/silent_log.dart';
import '../../shared/util/user_failure_message.dart';
import 'service/ai_jungler_client.dart';

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
  return userFailureMessage(
    error,
    fallback: fallback,
    detailResolver: (error) => switch (error) {
      AiJunglerApiException(:final message, :final statusCode)
          when statusCode == null ||
              statusCode < HttpStatus.internalServerError =>
        message,
      _ => null,
    },
  );
}
