import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_web_search_settings.dart';
import 'package:openhand/features/ai/service/web_search/web_search_engine.dart';
import 'package:openhand/features/ai/service/web_search/web_search_html_engines.dart';

void main() {
  group('WebSearchBingEngine', () {
    test('兼容结果容器和标题节点携带额外属性', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'www.bing.com');
        return http.Response.bytes(
          utf8.encode(_bingResultsHtml),
          200,
          request: request,
          headers: const {'content-type': 'text/html; charset=utf-8'},
        );
      });
      addTearDown(client.close);
      final engine = WebSearchBingEngine(
        config: const AiWebSearchEngineConfig(
          kind: AiWebSearchEngineKind.bing,
          enabled: true,
          maxRetries: 0,
        ),
        httpClient: client,
      );

      final result = await engine.run(
        const WebSearchEngineRequest(query: '武汉宜科中心 地址', maxResults: 8),
      );

      expect(result.error, isNull);
      expect(result.hits, hasLength(2));
      expect(result.hits.first.title, '武汉 宜科中心 地址');
      expect(result.hits.first.url, 'https://example.com/address?a=1&b=2');
      expect(result.hits.first.snippet, '湖北省武汉市江夏区示例路 1 号');
      expect(result.hits.last.snippet, isEmpty);
    });

    test('页面含结果容器但无法解析时返回明确失败', () async {
      final client = MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(
            '<li class="b_algo"><h2 class="new-layout">缺少链接</h2></li>',
          ),
          200,
          request: request,
          headers: const {'content-type': 'text/html; charset=utf-8'},
        ),
      );
      addTearDown(client.close);
      final engine = WebSearchBingEngine(
        config: const AiWebSearchEngineConfig(
          kind: AiWebSearchEngineKind.bing,
          enabled: true,
          maxRetries: 0,
        ),
        httpClient: client,
      );

      final result = await engine.run(
        const WebSearchEngineRequest(query: '测试查询', maxResults: 8),
      );

      expect(result.hits, isEmpty);
      expect(result.error, contains('Bing result parsing failed'));
    });
  });
}

const String _bingResultsHtml = '''
<ol id="b_results">
  <li class="b_algo" data-id="SERP.1">
    <h2 class=""><a target="_blank" href="https://example.com/address?a=1&amp;b=2">武汉<strong>宜科中心</strong>地址</a></h2>
    <div class="b_caption"><p class="b_lineclamp2">湖北省武汉市江夏区示例路 1 号</p></div>
  </li>
  <li data-id="SERP.2" class="result b_algo">
    <h2 data-priority="2"><a href='https://example.com/map'>宜科中心地图</a></h2>
  </li>
</ol>
''';
