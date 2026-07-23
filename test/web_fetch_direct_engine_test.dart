import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_web_fetch_settings.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_direct_engines.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_engine.dart';

void main() {
  test('直连抓取会拒绝重定向到受限地址', () async {
    final client = _RedirectClient();
    final engine = WebFetchDirectHttpEngine(
      config: const AiWebFetchEngineConfig(
        kind: AiWebFetchEngineKind.duckduckgo,
        maxRetries: 0,
      ),
      httpClient: client,
      userAgent: 'OpenHand 测试',
    );

    final result = await engine.run(
      WebFetchEngineRequest(
        url: 'https://example.com/start',
        prompt: '测试',
        maxChars: 100,
        uriBlockReason: (uri) async =>
            uri.host == '127.0.0.1' ? 'loopback addresses' : null,
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('拒绝访问 127.0.0.1'));
    expect(client.requestedUrls, <Uri>[Uri.parse('https://example.com/start')]);
  });
}

class _RedirectClient extends http.BaseClient {
  final List<Uri> requestedUrls = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUrls.add(request.url);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('redirect')),
      302,
      headers: const <String, String>{'location': 'http://127.0.0.1/admin'},
      request: request,
    );
  }
}
