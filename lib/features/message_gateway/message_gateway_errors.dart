import 'dart:async';
import 'dart:io';

import '../../shared/util/text_clip.dart';
import '../../shared/util/text_normalization.dart';

const int _messageGatewayErrorMaxCharacters = 400;

String messageGatewayFailureMessage(Object error, {required String fallback}) {
  final detail = switch (error) {
    FormatException(:final message) => message,
    StateError(:final message) => message,
    FileSystemException(:final message) => message,
    TimeoutException(:final message) => message ?? '',
    _ => '',
  };
  final normalized = collapseInlineWhitespace(detail);
  return normalized.isEmpty
      ? fallback
      : clipTextWithEllipsis(normalized, _messageGatewayErrorMaxCharacters);
}
