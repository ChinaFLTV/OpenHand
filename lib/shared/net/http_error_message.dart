import 'dart:convert';

import '../util/input_value_parsing.dart';
import '../util/text_clip.dart';
import '../util/text_normalization.dart';

/// API 错误文本默认上限，防止异常响应淹没日志或弹窗。
const int kDefaultApiErrorMessageMaxLength = 4000;

const String _emptyErrorResponseMessage = '错误响应为空。';

/// 从 HTTP 错误正文提取可读信息，依次解析常见 JSON 字段、HTML 和纯文本。
/// 结果会折叠空白并限制到 [maxLength]；空正文使用 [emptyFallback]。
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
    // 非 JSON 响应继续按 HTML 或纯文本处理。
  }

  if (trimmed.contains('<html') || trimmed.contains('<HTML')) {
    final stripped = collapseInlineWhitespace(stripHtmlTags(trimmed));
    return bounded(stripped.isEmpty ? trimmed : stripped);
  }
  return bounded(trimmed);
}
