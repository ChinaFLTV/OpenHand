import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../../app/support/silent_log.dart';
import '../../../../app/support/url_validation.dart';
import '../../../../shared/net/abortable_http_request.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_response_utils.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../../tools/ai_tool_utils.dart';
import '../web_engine/web_engine_http_utils.dart';
import 'web_fetch_engine.dart';

// 无 key 直连兜底引擎：duckduckgo / bing。
// 与 WebSearch 不同，WebFetch 场景下「无 key 兜底」其实就是
// 直接 HTTP GET 目标 URL，再把 HTML 转纯文本。
// 命名只为对齐 WebSearch 引擎枚举与 UI 卡片；具体实现完全独立于 DDG/Bing。

class WebFetchDirectHttpEngine extends WebFetchEngine {
  WebFetchDirectHttpEngine({
    required super.config,
    required super.httpClient,
    required this.userAgent,
  });

  static final RegExp _htmlTitlePattern = RegExp(
    r'<title[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  );
  static const Duration _redirectDrainIdleTimeout = Duration(seconds: 2);
  static const Duration _redirectDrainTotalTimeout = Duration(seconds: 3);
  static const int _maxRedirects = 5;

  final String userAgent;

  @override
  bool get isReady => true;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final response = await _followRedirects(
      Uri.parse(req.url),
      maxRedirects: _maxRedirects,
      cancelSignal: req.cancelSignal,
      uriBlockReason: req.uriBlockReason ?? agentFetchBlockReasonForResolvedUri,
    );
    final status = response.statusCode;
    if (!isHttpSuccessStatus(status)) {
      await _discardResponse(response.stream);
      throw WebEngineHttpException('${kind.name} HTTP $status');
    }
    final boundedResponse = await collectBoundedWebEngineResponse(
      response,
      responseTimeout: Duration(seconds: config.responseTimeoutSeconds),
    );
    final headers = boundedResponse.headers;
    final contentType = (headers[kContentTypeHeaderName] ?? '').toLowerCase();
    final body = boundedResponse.text();
    final isHtml = contentType.contains('html');
    final text = isHtml ? AiToolUtils.htmlToText(body) : body;
    if (text.isEmpty) return const <WebFetchEngineContent>[];
    final title = isHtml ? _extractTitle(body) : '';
    return [
      WebFetchEngineContent(
        url: boundedResponse.requestUrl?.toString() ?? req.url,
        title: title.isEmpty ? req.url : title,
        content: text,
        contentType: contentType,
        statusCode: status,
        responseHeaders: headers,
      ),
    ];
  }

  Future<http.StreamedResponse> _followRedirects(
    Uri uri, {
    required int maxRedirects,
    Future<void>? cancelSignal,
    required WebFetchUriBlockReason uriBlockReason,
  }) async {
    var current = uri;
    var redirectCount = 0;
    while (true) {
      final blockedReason = await uriBlockReason(current);
      if (blockedReason != null) {
        throw WebEngineHttpException(
          '${kind.name} 拒绝访问 ${current.host}: $blockedReason',
        );
      }
      final request = http.Request('GET', current);
      request.followRedirects = false;
      request.headers[kUserAgentHeaderName] = userAgent;
      request.headers[kAcceptHeaderName] =
          'text/html,application/xhtml+xml,*/*;q=0.8';
      final stream = await sendAbortableHttpRequest(
        client: httpClient,
        request: request,
        connectionTimeout: Duration(seconds: config.connectionTimeoutSeconds),
        cancelSignal: cancelSignal,
      );
      if (!isRedirectStatusCode(stream.statusCode)) return stream;

      if (redirectCount >= maxRedirects) {
        await _discardResponse(stream.stream);
        throw WebEngineHttpException('${kind.name} 重定向次数过多');
      }
      final location = readResponseHeader(stream.headers, 'location');
      await _discardResponse(stream.stream);
      if (location.isEmpty) {
        throw WebEngineHttpException('${kind.name} 重定向缺少 Location');
      }
      current = current.resolve(location);
      redirectCount++;
    }
  }

  Future<void> _discardResponse(Stream<List<int>> stream) async {
    try {
      await drainByteStreamWithTimeout(
        stream,
        idleTimeout: _redirectDrainIdleTimeout,
        totalTimeout: _redirectDrainTotalTimeout,
      );
    } catch (error, stack) {
      silentLog('web_fetch_direct_engine', '丢弃 HTTP 响应', error, stack);
    }
  }

  static String _extractTitle(String html) {
    final m = _htmlTitlePattern.firstMatch(html);
    return m == null ? '' : AiToolUtils.htmlToText(m.group(1) ?? '').trim();
  }
}

WebFetchEngine? buildDirectEngine({
  required AiWebFetchEngineConfig config,
  required http.Client httpClient,
}) {
  switch (config.kind) {
    case AiWebFetchEngineKind.duckduckgo:
      return WebFetchDirectHttpEngine(
        config: config,
        httpClient: httpClient,
        userAgent: kWebEngineSafariUserAgent,
      );
    case AiWebFetchEngineKind.bing:
      return WebFetchDirectHttpEngine(
        config: config,
        httpClient: httpClient,
        userAgent: kWebEngineChromeUserAgent,
      );
    default:
      return null;
  }
}
