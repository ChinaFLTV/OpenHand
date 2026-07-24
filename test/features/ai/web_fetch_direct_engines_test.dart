import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_web_fetch_settings.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_direct_engines.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_engine.dart';

void main() {
  group('WebFetchDirectHttpEngine', () {
    test('跟随受支持的重定向并返回最终内容', () async {
      final requested = <Uri>[];
      final client = MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/start') {
          return http.Response(
            '',
            302,
            headers: const <String, String>{'Location': '/final'},
            request: request,
          );
        }
        return http.Response(
          '<title>Page title</title><p>Page body</p>',
          200,
          headers: const <String, String>{'content-type': 'text/html'},
          request: request,
        );
      });

      final result = await _engine(client).fetch(_request('/start'));

      expect(requested.map((uri) => uri.path), <String>['/start', '/final']);
      expect(result, hasLength(1));
      expect(result.single.title, 'Page title');
      expect(result.single.content, contains('Page body'));
      expect(result.single.url, 'https://example.com/final');
    });

    test('不将非跳转状态码误判为重定向', () async {
      final client = MockClient(
        (request) async => http.Response('', 304, request: request),
      );

      await expectLater(
        _engine(client).fetch(_request('/cached')),
        throwsA(
          isA<WebEngineHttpException>().having(
            (error) => error.message,
            'message',
            contains('HTTP 304'),
          ),
        ),
      );
    });

    test('限制重定向次数', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(
          '',
          302,
          headers: <String, String>{'location': '/redirect-$requestCount'},
          request: request,
        );
      });

      await expectLater(
        _engine(client).fetch(_request('/start')),
        throwsA(
          isA<WebEngineHttpException>().having(
            (error) => error.message,
            'message',
            contains('重定向次数过多'),
          ),
        ),
      );
      expect(requestCount, 6);
    });
  });
}

WebFetchDirectHttpEngine _engine(http.Client client) {
  return WebFetchDirectHttpEngine(
    config: const AiWebFetchEngineConfig(kind: AiWebFetchEngineKind.bing),
    httpClient: client,
    userAgent: 'OpenHand 测试',
  );
}

WebFetchEngineRequest _request(String path) {
  return WebFetchEngineRequest(
    url: 'https://example.com$path',
    prompt: '读取页面',
    maxChars: 1000,
    uriBlockReason: (_) async => null,
  );
}
