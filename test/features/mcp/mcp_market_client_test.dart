import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/mcp/data/mcp_market_client.dart';

void main() {
  test('分类、搜索分页和中文筛选使用正确接口', () async {
    final requests = <Uri>[];
    final client = McpMarketClient(
      httpClient: MockClient((request) async {
        requests.add(request.url);
        return _response(
          jsonEncode(
            request.url.path.endsWith('categories')
                ? {
                    'items': [
                      {'key': '搜索与信息检索', 'count': 4},
                    ],
                  }
                : {
                    'items': [
                      {'slug': 'graphlit', 'name': '知识桥', 'status': 'visible'},
                    ],
                    'total': 27,
                  },
          ),
          200,
        );
      }),
    );
    addTearDown(client.close);
    expect(await client.categories(), [('搜索与信息检索', 4)]);
    final result = await client.search(
      page: 2,
      pageSize: 24,
      keyword: ' graphlit ',
      category: '搜索与信息检索',
    );
    expect(result.total, 27);
    expect(result.items.single.displayName, '知识桥');
    expect(requests.last.queryParameters, {
      'page': '2',
      'pageSize': '24',
      'sortBy': 'updated_at',
      'order': 'desc',
      'keyword': 'graphlit',
      'category': '搜索与信息检索',
    });
  });

  test('说明按纯文本读取，服务状态控制添加能力', () async {
    final client = McpMarketClient(
      httpClient: MockClient(
        (request) async => request.url.path.endsWith('/readme')
            ? _response('# 使用说明\n配置参数', 200)
            : _response(
                jsonEncode({
                  'slug': 'demo',
                  'banned': true,
                  'status': 'visible',
                }),
                200,
              ),
      ),
    );
    addTearDown(client.close);
    expect(await client.readme('demo'), '# 使用说明\n配置参数');
    expect((await client.detail('demo')).canConfigure, isFalse);
  });

  test('异常响应和超限内容可失败，失败后允许重试', () async {
    var attempt = 0;
    final client = McpMarketClient(
      httpClient: MockClient((_) async {
        attempt++;
        return switch (attempt) {
          1 => _response('失败', 503),
          2 => _response('x' * (McpMarketClient.maxResponseBytes + 1), 200),
          _ => _response('说明', 200),
        };
      }),
    );
    addTearDown(client.close);
    await expectLater(client.readme('demo'), throwsStateError);
    await expectLater(client.readme('demo'), throwsA(isA<Exception>()));
    expect(await client.readme('demo'), '说明');
    client.close();
    await expectLater(client.readme('demo'), throwsStateError);
  });

  test('切换服务和关闭市场会取消旧请求', () async {
    final transport = _PendingClient();
    final client = McpMarketClient(httpClient: transport);
    final first = client.readme('first');
    final firstFailure = expectLater(
      first,
      throwsA(isA<http.RequestAbortedException>()),
    );
    await Future<void>.delayed(Duration.zero);
    final second = client.readme('second');
    final secondFailure = expectLater(
      second,
      throwsA(isA<http.RequestAbortedException>()),
    );
    await firstFailure;
    client.close();
    await secondFailure;
    expect(transport.cancelled, 2);
  });
}

class _PendingClient extends http.BaseClient {
  int cancelled = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await (request as http.AbortableRequest).abortTrigger;
    cancelled++;
    throw http.RequestAbortedException(request.url);
  }
}

http.Response _response(String body, int status) =>
    http.Response.bytes(utf8.encode(body), status);
