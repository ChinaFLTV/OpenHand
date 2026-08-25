/// AI 聊天与 MCP 工具发现共用的 HTTP 重定向工具。
library;

import 'dart:io';

import 'package:http/http.dart' as http;

import '../util/argument_guards.dart';
import '../util/input_value_parsing.dart';
import 'abortable_http_request.dart';

const Set<String> _sensitiveRedirectHeaderNames = <String>{
  kAuthorizationHeaderName,
  'cookie',
  'host',
  'proxy-authorization',
};

const Set<String> _redirectEntityHeaderNames = <String>{
  HttpHeaders.contentEncodingHeader,
  'content-disposition',
  HttpHeaders.contentLanguageHeader,
  HttpHeaders.contentLengthHeader,
  HttpHeaders.contentLocationHeader,
  'content-md5',
  kContentTypeHeaderName,
  'digest',
  'expect',
  'trailer',
  HttpHeaders.transferEncodingHeader,
};

/// `Location` 响应头名。
const String kLocationHeaderName = 'location';

/// 手动跟随 HTTP 重定向，直到拿到非重定向响应或超出 [maxRedirects]。
///
/// 需要在跨源跳转时剥离敏感头，并统一 301 / 302 / 303 的请求方法语义。
/// 差异部分通过回调注入：
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
  requireNonNegativeInt(maxRedirects, 'maxRedirects');
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
    if (_redirectUsesGet(response.statusCode, currentMethod)) {
      currentMethod = 'GET';
      currentBody = null;
      currentHeaders.removeWhere(
        (name, _) => _redirectEntityHeaderNames.contains(name.toLowerCase()),
      );
    }
  }
}

/// 301 / 302 对 POST 沿用浏览器兼容语义，303 则把除 GET / HEAD 外的方法转为 GET。
bool _redirectUsesGet(int statusCode, String method) {
  final normalizedMethod = method.toUpperCase();
  return (statusCode == HttpStatus.movedPermanently ||
              statusCode == HttpStatus.found) &&
          normalizedMethod == 'POST' ||
      statusCode == HttpStatus.seeOther &&
          normalizedMethod != 'GET' &&
          normalizedMethod != 'HEAD';
}

/// 判断状态码是否为需要跟随的重定向响应。
bool isRedirectStatusCode(int statusCode) {
  return statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
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

/// `Authorization` 头名常量。
const String kAuthorizationHeaderName = 'authorization';

/// `Accept` 头名常量。
const String kAcceptHeaderName = 'accept';

/// `User-Agent` 头名常量。
const String kUserAgentHeaderName = 'user-agent';

/// `Cache-Control: no-store` 头值常量。
const String kCacheControlNoStore = 'no-store';

/// `Connection: keep-alive` 头值常量。
const String kConnectionKeepAlive = 'keep-alive';

/// `Connection: close` 头值常量。
const String kConnectionClose = 'close';

/// JSON MIME 类型常量，避免全库重复书写字面量。
const String kApplicationJsonMimeType = 'application/json';

/// 二进制流 MIME 类型常量。
const String kApplicationOctetStreamMimeType = 'application/octet-stream';

/// SSE (Server-Sent Events) MIME 类型常量。
const String kTextEventStreamMimeType = 'text/event-stream';

/// 表单提交 MIME 类型常量。
const String kFormUrlEncodedMimeType = 'application/x-www-form-urlencoded';

/// Markdown MIME 类型常量。
const String kTextMarkdownMimeType = 'text/markdown';

/// YAML MIME 类型常量。
const String kApplicationYamlMimeType = 'application/yaml';

/// HTML MIME 类型常量。
const String kTextHtmlMimeType = 'text/html';

/// PDF MIME 类型常量。
const String kApplicationPdfMimeType = 'application/pdf';

/// 带 UTF-8 charset 的纯文本 Content-Type。
const String kTextPlainUtf8ContentType = 'text/plain; charset=utf-8';

/// 带 UTF-8 charset 的 JSON `Content-Type` 取值，供发送 JSON 请求体时复用。
const String kApplicationJsonUtf8ContentType =
    '$kApplicationJsonMimeType; charset=utf-8';

/// 带 UTF-8 charset 的 SSE `Content-Type` 取值，供本地 SSE 服务响应复用。
const String kTextEventStreamUtf8ContentType =
    '$kTextEventStreamMimeType; charset=utf-8';

/// PNG 图片 MIME 类型常量。
const String kImagePngMimeType = 'image/png';

/// JPEG 图片 MIME 类型常量。
const String kImageJpegMimeType = 'image/jpeg';

/// GIF 图片 MIME 类型常量。
const String kImageGifMimeType = 'image/gif';

/// WebP 图片 MIME 类型常量。
const String kImageWebpMimeType = 'image/webp';

/// SVG 图片 MIME 类型常量。
const String kImageSvgXmlMimeType = 'image/svg+xml';

/// 纯文本 MIME 类型常量（不含 charset）。
const String kTextPlainMimeType = 'text/plain';

/// MP3 / MPEG 音频 MIME 类型常量。
const String kAudioMpegMimeType = 'audio/mpeg';

/// MP3 别名 MIME 类型（`audio/mp3`）。
const String kAudioMp3AliasMimeType = 'audio/mp3';

/// MP4 音频 MIME 类型常量。
const String kAudioMp4MimeType = 'audio/mp4';

/// WAV 音频 MIME 类型常量。
const String kAudioWavMimeType = 'audio/wav';

/// WAV 音频别名 MIME 类型（`audio/wave`）。
const String kAudioWaveAliasMimeType = 'audio/wave';

/// WAV 音频别名 MIME 类型（`audio/x-wav`）。
const String kAudioXWavAliasMimeType = 'audio/x-wav';

/// OGG 音频 MIME 类型常量。
const String kAudioOggMimeType = 'audio/ogg';

/// FLAC 音频 MIME 类型常量。
const String kAudioFlacMimeType = 'audio/flac';

/// AAC 音频 MIME 类型常量。
const String kAudioAacMimeType = 'audio/aac';

/// MP4 视频 MIME 类型常量。
const String kVideoMp4MimeType = 'video/mp4';

/// WebM 视频 MIME 类型常量。
const String kVideoWebmMimeType = 'video/webm';

/// QuickTime 视频 MIME 类型常量。
const String kVideoQuickTimeMimeType = 'video/quicktime';

/// Matroska 视频 MIME 类型常量。
const String kVideoMatroskaMimeType = 'video/x-matroska';

/// AVI 视频 MIME 类型常量。
const String kVideoAviMimeType = 'video/x-msvideo';

/// MOV 视频（QuickTime 容器的旧别名）MIME 类型常量。
const String kVideoMovMimeType = 'video/mov';

/// WMV 视频 MIME 类型常量。
const String kVideoWmvMimeType = 'video/x-ms-wmv';

/// XML MIME 类型常量。
const String kApplicationXmlMimeType = 'application/xml';

/// TOML MIME 类型常量。
const String kApplicationTomlMimeType = 'application/toml';

/// BMP 图片 MIME 类型常量。
const String kImageBmpMimeType = 'image/bmp';

/// CSV MIME 类型常量。
const String kTextCsvMimeType = 'text/csv';

/// TSV (Tab-Separated Values) MIME 类型常量。
const String kTextTsvMimeType = 'text/tab-separated-values';

/// NDJSON (Newline-Delimited JSON) MIME 类型常量。
const String kApplicationNdjsonMimeType = 'application/x-ndjson';

/// NDJSON UTF-8 Content-Type 常量。
const String kApplicationNdjsonUtf8ContentType =
    'application/x-ndjson; charset=utf-8';

/// Word 文档（.docx）MIME 类型常量。
const String kApplicationDocxMimeType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// Excel 表格（.xlsx）MIME 类型常量。
const String kApplicationXlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// PowerPoint 演示文稿（.pptx）MIME 类型常量。
const String kApplicationPptxMimeType =
    'application/vnd.openxmlformats-officedocument.presentationml.presentation';

/// 旧版 Excel 表格（.xls）MIME 类型常量。
const String kApplicationXlsMimeType = 'application/vnd.ms-excel';

/// 讯飞 TTS 原始音频格式（16kHz 16-bit PCM）。
const String kAudioL16Rate16000 = 'audio/L16;rate=16000';

/// SSML (Speech Synthesis Markup Language) MIME 类型常量。
const String kApplicationSsmlXmlMimeType = 'application/ssml+xml';

/// GitHub REST API v3 Accept 头常量。
const String kGitHubApiV3AcceptHeader = 'application/vnd.github.v3+json';

/// GitHub REST API（默认）Accept 头常量。
const String kGitHubApiAcceptHeader = 'application/vnd.github+json';

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
  kApplicationJsonMimeType,
  'application/x-json',
  'text/json',
};

/// MIME 是否为图片类型（image/*）。
bool isImageMimeType(String? contentType) {
  return mimeTypeFromContentType(contentType).startsWith('image/');
}

/// MIME 是否为音频类型（audio/*）。
bool isAudioMimeType(String? contentType) {
  return mimeTypeFromContentType(contentType).startsWith('audio/');
}

/// MIME 是否为视频类型（video/*）。
bool isVideoMimeType(String? contentType) {
  return mimeTypeFromContentType(contentType).startsWith('video/');
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
