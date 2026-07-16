import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

const _server = McpServer(
  name: '测试服务',
  type: McpServerType.streamableHttp,
  enabled: true,
  url: 'https://mcp.example.test/v1',
);

void main() {
  test('无效 JSON 错误包含服务端原始响应', () async {
    const rawResponse = '<html>上游网关返回了 502 页面</html>';
    final service = DefaultMcpToolDiscoveryService(
      client: MockClient(
        (_) async => http.Response(
          rawResponse,
          200,
          headers: const {'content-type': 'text/html; charset=utf-8'},
        ),
      ),
    );

    final catalog = await service.discoverTools(_server);

    expect(catalog.status, McpToolCatalogStatus.failed);
    expect(catalog.errorMessage, contains(rawResponse));
    service.dispose();
  });

  test('JSON-RPC 错误完整展示错误数据', () async {
    final service = DefaultMcpToolDiscoveryService(
      client: MockClient((request) async {
        expect(
          request.headers['cache-control'],
          'no-cache, no-store, max-age=0',
        );
        expect(request.headers['pragma'], 'no-cache');
        final payload = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': payload['id'],
            'error': <String, Object?>{
              'code': -32603,
              'message': '服务端执行失败',
              'data': <String, Object?>{'trace_id': 'trace-actual-42'},
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final catalog = await service.discoverTools(_server);

    expect(catalog.status, McpToolCatalogStatus.failed);
    expect(catalog.errorMessage, contains('服务端执行失败'));
    expect(catalog.errorMessage, contains('trace-actual-42'));
    service.dispose();
  });

  test('工具元数据告警附带对应服务端响应', () async {
    var closeRequests = 0;
    final service = DefaultMcpToolDiscoveryService(
      client: MockClient((request) async {
        if (request.method == 'DELETE') {
          closeRequests += 1;
          expect(request.headers['mcp-session-id'], 'fresh-session');
          return http.Response('', 204);
        }
        final payload = jsonDecode(request.body) as Map<String, Object?>;
        final method = payload['method'];
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        final result = method == 'initialize'
            ? <String, Object?>{
                'protocolVersion': '2025-11-25',
                'capabilities': <String, Object?>{},
              }
            : <String, Object?>{
                'tools': <Object?>[
                  <String, Object?>{
                    'name': '缺少输入结构',
                    'server_marker': 'tool-response-actual-42',
                  },
                ],
              };
        return http.Response(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': payload['id'],
            'result': result,
          }),
          200,
          headers: <String, String>{
            'content-type': 'application/json',
            if (method == 'initialize') 'mcp-session-id': 'fresh-session',
          },
        );
      }),
    );

    final catalog = await service.discoverTools(_server);

    expect(catalog.status, McpToolCatalogStatus.ready);
    expect(catalog.warningMessage, contains('tool-response-actual-42'));
    expect(closeRequests, 1);
    service.dispose();
  });

  test('工具列表响应完成后才关闭 Streamable HTTP 会话', () async {
    final events = <String>[];
    final service = DefaultMcpToolDiscoveryService(
      client: MockClient((request) async {
        if (request.method == 'DELETE') {
          events.add('关闭会话');
          return http.Response('', 204);
        }
        final payload = jsonDecode(request.body) as Map<String, Object?>;
        final method = payload['method'];
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        if (method == 'tools/list') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          events.add('工具列表完成');
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': payload['id'],
            'result': method == 'initialize'
                ? <String, Object?>{
                    'protocolVersion': '2025-11-25',
                    'capabilities': <String, Object?>{},
                  }
                : <String, Object?>{'tools': <Object?>[]},
          }),
          200,
          headers: <String, String>{
            'content-type': 'application/json',
            if (method == 'initialize') 'mcp-session-id': 'ordered-session',
          },
        );
      }),
    );

    final catalog = await service.discoverTools(_server);

    expect(catalog.status, McpToolCatalogStatus.ready);
    expect(events, <String>['工具列表完成', '关闭会话']);
    service.dispose();
  });

  test('工具列表 HTTP 500 转为失败目录且不会逃逸到 Zone', () async {
    const rawResponse =
        '{"jsonrpc":"2.0","id":"server-error","error":'
        '{"code":-32600,"message":"Error processing request: No response received"}}';
    final events = <String>[];
    final uncaughtErrors = <Object>[];
    final service = DefaultMcpToolDiscoveryService(
      client: MockClient((request) async {
        if (request.method == 'DELETE') {
          events.add('关闭会话');
          return http.Response('', 204);
        }
        final payload = jsonDecode(request.body) as Map<String, Object?>;
        final method = payload['method'];
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        if (method == 'tools/list') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          events.add('工具列表失败');
          return http.Response(
            rawResponse,
            500,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': payload['id'],
            'result': <String, Object?>{
              'protocolVersion': '2025-11-25',
              'capabilities': <String, Object?>{},
            },
          }),
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
            'mcp-session-id': 'failed-session',
          },
        );
      }),
    );
    late McpToolCatalog catalog;

    await runZonedGuarded<Future<void>>(() async {
      catalog = await service.discoverTools(_server);
    }, (error, _) => uncaughtErrors.add(error));
    await Future<void>.delayed(Duration.zero);

    expect(catalog.status, McpToolCatalogStatus.failed);
    expect(catalog.errorMessage, contains('HTTP 500'));
    expect(catalog.errorMessage, contains('No response received'));
    expect(events, <String>['工具列表失败', '关闭会话']);
    expect(uncaughtErrors, isEmpty);
    service.dispose();
  });
}
