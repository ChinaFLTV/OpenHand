/// AI 聊天与 MCP 工具发现共用的 HTTP 重定向工具。
library;

import 'package:http/http.dart' as http;

import '../util/input_value_parsing.dart';
import 'abortable_http_request.dart';

const Set<String> _sensitiveRedirectHeaderNames = <String>{
  'authorization',
  'cookie',
  'proxy-authorization',
};

/// `Location` 响应头名。
const String kLocationHeaderName = 'location';

/// 手动跟随 HTTP 重定向，直到拿到非重定向响应或超出 [maxRedirects]。
///
/// 之所以不用 package:http 自带的跟随：需要在跨源跳转时剥离 `Authorization`
/// 一类的敏感头，并把 303 降级为 GET。AI 聊天与 MCP 工具发现此前各维护一份
/// 逐行相同的实现，这类安全语义一旦分叉就是漏洞。差异部分通过回调注入：
///
/// - [drainResponse]：排空被丢弃的中间响应，避免连接悬挂。
/// - [onTooManyRedirects]：超出跳转上限时抛出调用方自己的异常类型。
Future<http.StreamedResponse> sendHttpRequestFollowingRedirects({
  required http.Client client,
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  required Duration timeout,
  required int maxRedirects,
  required Future<void> Function(http.StreamedResponse response) drainResponse,
  required Future<Never> Function(http.StreamedResponse response)
  onTooManyRedirects,
  String? body,
  Set<String> additionalSensitiveHeaderNames = const <String>{},
  Future<void>? cancelSignal,
}) async {
  var currentMethod = method;
  var currentUri = uri;
  var currentBody = body;
  final currentHeaders = Map<String, String>.from(headers);

  for (var redirectCount = 0; ; redirectCount++) {
    final request = http.Request(currentMethod, currentUri)
      ..followRedirects = false
      ..headers.addAll(currentHeaders);
    if (currentBody != null) {
      request.body = currentBody;
    }

    final response = await sendAbortableHttpRequest(
      client: client,
      request: request,
      connectionTimeout: timeout,
      cancelSignal: cancelSignal,
    );
    if (!isRedirectStatusCode(response.statusCode)) {
      return response;
    }

    final redirectLocation = readResponseHeader(
      response.headers,
      kLocationHeaderName,
    );
    if (redirectLocation.isEmpty) {
      return response;
    }
    if (redirectCount >= maxRedirects) {
      await onTooManyRedirects(response);
    }

    await drainResponse(response);
    final redirectedUri = currentUri.resolve(redirectLocation);
    if (isCrossOriginRedirect(currentUri, redirectedUri)) {
      stripSensitiveRedirectHeaders(
        currentHeaders,
        additionalNames: additionalSensitiveHeaderNames,
      );
    }
    currentUri = redirectedUri;
    // 303 要求后续请求改用 GET 且不携带原始请求体（RFC 7231 §6.4.4）。
    if (response.statusCode == 303 &&
        currentMethod != 'GET' &&
        currentMethod != 'HEAD') {
      currentMethod = 'GET';
      currentBody = null;
    }
  }
}

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
