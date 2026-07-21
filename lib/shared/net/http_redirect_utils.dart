/// AI 聊天与 MCP 工具发现共用的 HTTP 重定向工具。
library;

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
