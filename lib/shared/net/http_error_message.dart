import 'dart:convert';

import '../util/input_value_parsing.dart';
import '../util/text_clip.dart';
import '../util/text_normalization.dart';

/// API 错误文本默认上限，防止异常响应淹没日志或弹窗。
const int kDefaultApiErrorMessageMaxLength = 4000;

const String _emptyErrorResponseMessage = '错误响应为空。';

/// gRPC 状态码 -> 规范名（用于把 `{code: 5, message: NOT_FOUND}` 这类
/// Google/gRPC 风格错误体转成带语义的文本，避免被误判为普通字符串）。
const Map<int, String> _kGrpcCodeNames = <int, String>{
  0: 'OK',
  1: 'CANCELLED',
  2: 'UNKNOWN',
  3: 'INVALID_ARGUMENT',
  4: 'DEADLINE_EXCEEDED',
  5: 'NOT_FOUND',
  6: 'ALREADY_EXISTS',
  7: 'PERMISSION_DENIED',
  8: 'RESOURCE_EXHAUSTED',
  9: 'FAILED_PRECONDITION',
  10: 'ABORTED',
  11: 'OUT_OF_RANGE',
  12: 'UNIMPLEMENTED',
  13: 'INTERNAL',
  14: 'UNAVAILABLE',
  15: 'DATA_LOSS',
  16: 'UNAUTHENTICATED',
};

/// 匹配 gRPC 风格错误体的 code，兼容合法 JSON 与 Dart/Go `toString()` 形态
/// （键名无引号）。捕获组 1 = code。
final RegExp _kGrpcCodeFieldPattern = RegExp(
  r'"?code"?\s*:\s*(\d+)\b',
);

/// 匹配 gRPC message 字段值：优先带引号字符串，否则取到逗号/大括号前的 token。
/// 捕获组 1 = 带引号内容，组 2 = 不带引号 token。
final RegExp _kGrpcMessageFieldPattern = RegExp(
  r'"?message"?\s*:\s*(?:"([^"]*)"|([^,\}\s]+))',
);

String? _extractGrpcMessage(String body) {
  final match = _kGrpcMessageFieldPattern.firstMatch(body);
  if (match == null) return null;
  final quoted = match.group(1);
  if (quoted != null) return quoted;
  return match.group(2);
}

/// 把 gRPC 状态码与 message 拼成带语义的文本，便于下游 [AiTransportDiagnosticMessages.httpStatus]
/// 识别。message 为空时退回状态规范名。
String _formatGrpcStatus(int code, String message) {
  final name = _kGrpcCodeNames[code];
  final label = message.trim().isNotEmpty
      ? message.trim()
      : (name ?? 'STATUS_$code');
  return '$label (gRPC code $code)';
}

/// 从 HTTP 错误正文提取可读信息，依次解析常见 JSON 字段、gRPC 状态、HTML 和纯文本。
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
      // gRPC 状态：{"code": 5, "message": "NOT_FOUND", "details": []}
      final code = decoded['code'];
      final hasDetails = decoded.containsKey('details');
      if (code != null && hasDetails) {
        final grpcCode = code is int ? code : int.tryParse('$code');
        if (grpcCode != null) {
          final grpcMessage = optionalStringFromValue(decoded['message']) ?? '';
          return bounded(_formatGrpcStatus(grpcCode, grpcMessage));
        }
      }
      final message =
          optionalStringFromValue(decoded['message']) ??
          optionalStringFromValue(decoded['error_description']);
      if (message != null) return bounded(message);
    }
  } catch (_) {
    // 非 JSON 响应继续按 gRPC 文本、HTML 或纯文本处理。
  }

  // 非 JSON 但形如 gRPC 状态（键名无引号的 Dart/Go toString 输出）。
  final codeMatch = _kGrpcCodeFieldPattern.firstMatch(trimmed);
  if (codeMatch != null && trimmed.contains('details')) {
    final code = int.tryParse(codeMatch.group(1) ?? '');
    if (code != null) {
      final message = _extractGrpcMessage(trimmed) ?? '';
      return bounded(_formatGrpcStatus(code, message));
    }
  }

  if (trimmed.contains('<html') || trimmed.contains('<HTML')) {
    final stripped = collapseInlineWhitespace(stripHtmlTags(trimmed));
    return bounded(stripped.isEmpty ? trimmed : stripped);
  }
  return bounded(trimmed);
}
