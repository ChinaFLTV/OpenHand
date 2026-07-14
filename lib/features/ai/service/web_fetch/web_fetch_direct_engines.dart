import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../../app/support/silent_log.dart';
import '../../../../shared/net/abortable_http_request.dart';
import '../../../../shared/net/http_response_utils.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../../tools/ai_tool_utils.dart';
import '../web_engine/web_engine_http_utils.dart';
import 'web_fetch_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 无 key 直连兜底引擎：duckduckgo / bing。
// 与 WebSearch 不同，WebFetch 场景下「无 key 兜底」其实就是
// 直接 HTTP GET 目标 URL，再把 HTML 转纯文本。
// 命名只为对齐 WebSearch 引擎枚举与 UI 卡片；具体实现完全独立于 DDG/Bing。
// ─────────────────────────────────────────────────────────────────────────────

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

  final String userAgent;

  @override
  bool get isReady => true;

  @override
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest req) async {
    final response = await _followRedirects(
      Uri.parse(req.url),
      maxRedirects: 5,
      cancelSignal: req.cancelSignal,
    );
    final status = response.statusCode;
    if (status < 200 || status >= 400) {
      await _discardResponse(response.stream);
      throw WebEngineHttpException('${kind.name} HTTP $status');
    }
    final boundedResponse = await collectBoundedWebEngineResponse(
      response,
      responseTimeout: Duration(seconds: config.responseTimeoutSeconds),
    );
    final headers = boundedResponse.headers;
    final contentType = (headers['content-type'] ?? '').toLowerCase();
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
  }) async {
    var current = uri;
    for (var i = 0; i < maxRedirects; i++) {
      final request = http.Request('GET', current);
      request.followRedirects = false;
      request.headers['user-agent'] = userAgent;
      request.headers['accept'] = 'text/html,application/xhtml+xml,*/*;q=0.8';
      final stream = await sendAbortableHttpRequest(
        client: httpClient,
        request: request,
        connectionTimeout: Duration(seconds: config.connectionTimeoutSeconds),
        cancelSignal: cancelSignal,
      );
      if (stream.statusCode >= 300 && stream.statusCode < 400) {
        final loc = stream.headers['location'];
        await _discardResponse(stream.stream);
        if (loc == null || loc.isEmpty) {
          throw WebEngineHttpException(
            '${kind.name} redirect missing Location',
          );
        }
        current = current.resolve(loc);
        continue;
      }
      return stream;
    }
    throw WebEngineHttpException('${kind.name} too many redirects');
  }

  Future<void> _discardResponse(Stream<List<int>> stream) async {
    try {
      await drainByteStreamWithTimeout(
        stream,
        idleTimeout: _redirectDrainIdleTimeout,
        totalTimeout: _redirectDrainTotalTimeout,
      );
    } catch (error, stack) {
      silentLog(
        'web_fetch_direct_engine',
        'discard HTTP response',
        error,
        stack,
      );
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
        userAgent:
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) '
            'Version/17.0 Safari/605.1.15',
      );
    case AiWebFetchEngineKind.bing:
      return WebFetchDirectHttpEngine(
        config: config,
        httpClient: httpClient,
        userAgent:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/121.0 Safari/537.36',
      );
    default:
      return null;
  }
}
