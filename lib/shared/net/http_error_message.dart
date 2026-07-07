import 'dart:convert';

import '../util/input_value_parsing.dart';
import '../util/text_clip.dart';
import '../util/text_normalization.dart';

/// Default cap for extracted error text so a runaway HTML page or verbose JSON
/// payload can't flood logs or dialogs.
const int kDefaultApiErrorMessageMaxLength = 4000;

const String _emptyErrorResponseMessage = 'Empty error response.';

/// Extracts a human-readable message from an HTTP error [body].
///
/// Resolution order mirrors the shapes returned by OpenAI-compatible, Ollama
/// and image-generation endpoints:
///   1. JSON `error` string, or `error.message` / `error.error` / `error.code`;
///   2. top-level `message` / `error_description`;
///   3. tags stripped from an HTML error page (nginx 4xx/5xx);
///   4. the raw trimmed body.
///
/// The result is always whitespace-collapsed and clipped to [maxLength].
/// [emptyFallback] is returned when [body] is blank; when null, blank input
/// yields [_emptyErrorResponseMessage].
String extractApiErrorMessage(
  String body, {
  int maxLength = kDefaultApiErrorMessageMaxLength,
  String? emptyFallback,
}) {
  String bounded(String message) =>
      clipText(collapseInlineWhitespace(message), maxLength);

  final trimmed = nullIfBlank(body);
  if (trimmed == null) return emptyFallback ?? _emptyErrorResponseMessage;

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, Object?>) {
      final error = decoded['error'];
      final errorText = optionalStringFromValue(error);
      if (errorText != null) return bounded(errorText);
      if (error is Map) {
        final map = stringKeyedMapFromValue(error);
        final message =
            optionalStringFromValue(map['message']) ??
            optionalStringFromValue(map['error']) ??
            optionalStringFromValue(map['code']);
        if (message != null) return bounded(message);
      }
      final message =
          optionalStringFromValue(decoded['message']) ??
          optionalStringFromValue(decoded['error_description']);
      if (message != null) return bounded(message);
    }
  } catch (_) {
    // Plain text or HTML error response — fall through to tag stripping.
  }

  if (trimmed.contains('<html') || trimmed.contains('<HTML')) {
    final stripped = collapseInlineWhitespace(stripHtmlTags(trimmed));
    return bounded(stripped.isEmpty ? trimmed : stripped);
  }
  return bounded(trimmed);
}
