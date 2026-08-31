import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_web_fetch_settings.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_engine.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_scrape_engines.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_scrapling_bridge.dart';

void main() {
  group('Scrapling 重定向隔离', () {
    test('安全重定向逐跳抓取并返回最终内容', () async {
      final bridge = _FakeScraplingBridge(<WebFetchScraplingBridgeResult>[
        _result(
          url: 'https://example.com/start',
          statusCode: 302,
          headers: const <String, String>{'LOCATION': '/final'},
        ),
        _result(
          url: 'https://example.com/final',
          statusCode: 200,
          content: '最终正文',
        ),
      ]);
      final client = http.Client();
      addTearDown(client.close);
      final engine = _engine(bridge, client);

      final contents = await engine.fetch(
        _request(uriBlockReason: (_) async => null),
      );

      expect(bridge.requestedUrls, <String>[
        'https://example.com/start',
        'https://example.com/final',
      ]);
      expect(contents.single.content, '最终正文');
      expect(contents.single.url, 'https://example.com/final');
    });

    test('重定向到受限地址时在发起请求前拒绝', () async {
      final bridge = _FakeScraplingBridge(<WebFetchScraplingBridgeResult>[
        _result(
          url: 'https://example.com/start',
          statusCode: 302,
          headers: const <String, String>{'location': 'http://127.0.0.1/admin'},
        ),
      ]);
      final client = http.Client();
      addTearDown(client.close);
      final engine = _engine(bridge, client);

      await expectLater(
        engine.fetch(
          _request(
            uriBlockReason: (uri) async =>
                uri.host == '127.0.0.1' ? '回环地址' : null,
          ),
        ),
        throwsA(
          isA<WebEngineHttpException>().having(
            (error) => error.toString(),
            '错误信息',
            contains('回环地址'),
          ),
        ),
      );
      expect(bridge.requestedUrls, <String>['https://example.com/start']);
    });

    test('重定向响应缺少目标地址时明确失败', () async {
      final bridge = _FakeScraplingBridge(<WebFetchScraplingBridgeResult>[
        _result(url: 'https://example.com/start', statusCode: 301),
      ]);
      final client = http.Client();
      addTearDown(client.close);

      await expectLater(
        _engine(
          bridge,
          client,
        ).fetch(_request(uriBlockReason: (_) async => null)),
        throwsA(
          isA<WebEngineHttpException>().having(
            (error) => error.toString(),
            '错误信息',
            contains('缺少 Location'),
          ),
        ),
      );
    });
  });
}

WebFetchScraplingEngine _engine(
  WebFetchScraplingBridge bridge,
  http.Client client,
) {
  return WebFetchScraplingEngine(
    config: const AiWebFetchEngineConfig(kind: AiWebFetchEngineKind.scrapling),
    httpClient: client,
    scraplingBridge: bridge,
    scraplingSettings: const AiWebFetchScraplingSettings(),
  );
}

WebFetchEngineRequest _request({
  required WebFetchUriBlockReason uriBlockReason,
}) {
  return WebFetchEngineRequest(
    url: 'https://example.com/start',
    prompt: '提取正文',
    maxChars: 10000,
    uriBlockReason: uriBlockReason,
  );
}

WebFetchScraplingBridgeResult _result({
  required String url,
  required int statusCode,
  String content = '',
  Map<String, String> headers = const <String, String>{},
}) {
  return WebFetchScraplingBridgeResult(
    url: url,
    title: '',
    content: content,
    contentType: 'text/html',
    statusCode: statusCode,
    responseHeaders: headers,
  );
}

class _FakeScraplingBridge extends WebFetchScraplingBridge {
  _FakeScraplingBridge(Iterable<WebFetchScraplingBridgeResult> responses)
    : _responses = Queue<WebFetchScraplingBridgeResult>.of(responses);

  final Queue<WebFetchScraplingBridgeResult> _responses;
  final List<String> requestedUrls = <String>[];

  @override
  Future<WebFetchScraplingBridgeResult> fetch({
    required String url,
    required int maxChars,
    required AiWebFetchScraplingSettings settings,
    Future<void>? cancelSignal,
  }) async {
    requestedUrls.add(url);
    if (_responses.isEmpty) throw StateError('缺少伪造响应。');
    return _responses.removeFirst();
  }
}
