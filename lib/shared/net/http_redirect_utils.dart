/// AI 聊天与 MCP 工具发现共用的 HTTP 重定向工具。
library;

import '../util/input_value_parsing.dart';

const Set<String> _sensitiveRedirectHeaderNames = <String>{
  'authorization',
  'cookie',
  'proxy-authorization',
};

/// 判断状态码是否为需要跟随的重定向响应。
bool isRedirectStatusCode(int statusCode) {
  return statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

/// 判断目标地址是否跨越源、主机或有效端口边界。
bool isCrossOriginRedirect(Uri source, Uri target) {
  return _normalizedOriginScheme(source) != _normalizedOriginScheme(target) ||
      _normalizedOriginHost(source) != _normalizedOriginHost(target) ||
      effectivePort(source) != effectivePort(target);
}

/// 校验浏览器 `Origin` 请求头，并与请求地址比较同源性。
bool isSameHttpOrigin(Uri requestUri, String? rawOrigin) {
  final value = rawOrigin?.trim() ?? '';
  final origin = value.isEmpty ? null : Uri.tryParse(value);
  if (!_isValidHttpOrigin(requestUri) ||
      origin == null ||
      !_isValidHttpOrigin(origin) ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      (origin.path.isNotEmpty && origin.path != '/')) {
    return false;
  }
  return !isCrossOriginRedirect(requestUri, origin);
}

bool _isValidHttpOrigin(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
}

String _normalizedOriginScheme(Uri uri) => uri.scheme.toLowerCase();

String _normalizedOriginHost(Uri uri) => uri.host.toLowerCase();

/// 返回显式端口或协议默认端口；未知协议返回 -1。
int effectivePort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return switch (uri.scheme.toLowerCase()) {
    'http' => 80,
    'https' => 443,
    _ => -1,
  };
}

/// 忽略大小写读取响应头；不存在时返回空字符串。
String readResponseHeader(Map<String, String> headers, String name) {
  final target = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == target) {
      return entry.value.trim();
    }
  }
  return '';
}

/// 忽略大小写读取响应头；不存在或为空白时返回 null。
///
/// 与 [readResponseHeader] 的空字符串约定并列存在：调用方需要用
/// null 区分“未携带该头”时选用本变体，勿互相替换。
String? readResponseHeaderOrNull(Map<String, String> headers, String name) {
  return nullIfBlank(readResponseHeader(headers, name));
}

/// `Content-Type` 头名，避免各处重复书写字面量后大小写不一致。
const String kContentTypeHeaderName = 'content-type';

/// 取 `Content-Type` 的 MIME 部分（丢掉 `; charset=...` 参数），统一转小写；
/// 缺失时返回空字符串。
String responseMimeType(Map<String, String> headers) {
  return mimeTypeFromContentType(
    readResponseHeader(headers, kContentTypeHeaderName),
  );
}

/// 从完整的 `Content-Type` 取值里提取 MIME 部分，统一转小写。
String mimeTypeFromContentType(String? contentType) {
  return lowercaseStringFromValue((contentType ?? '').split(';').first);
}

/// MIME 是否为 JSON 载荷。
///
/// 覆盖 `application/json`、历史遗留的 `text/json` / `application/x-json`，
/// 以及 `application/problem+json` 一类的 `+json` 结构化后缀。此前传输层与
/// 媒体生成各维护一份名单，收录范围并不一致。
bool isJsonMimeType(String? contentType) {
  final mimeType = mimeTypeFromContentType(contentType);
  if (mimeType.isEmpty) return false;
  return _jsonMimeTypes.contains(mimeType) || mimeType.endsWith('+json');
}

const Set<String> _jsonMimeTypes = <String>{
  'application/json',
  'application/x-json',
  'text/json',
};

/// 删除跨域重定向时不得透传的敏感请求头。
void stripSensitiveRedirectHeaders(
  Map<String, String> headers, {
  Iterable<String> additionalNames = const <String>[],
}) {
  final normalizedAdditionalNames = additionalNames
      .map((name) => name.toLowerCase())
      .toSet();
  headers.removeWhere((name, _) {
    final normalizedName = name.toLowerCase();
    return _sensitiveRedirectHeaderNames.contains(normalizedName) ||
        normalizedAdditionalNames.contains(normalizedName);
  });
}
