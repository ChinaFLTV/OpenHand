import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const server = McpServer(
    name: 'session-close-test',
    type: McpServerType.streamableHttp,
    enabled: true,
    url: 'https://example.com/mcp',
  );

  for (final message in <String>[
    'HTTP request failed. Client is already closed.',
    'Connection closed before full header was received',
  ]) {
    test('Streamable HTTP 会话关闭遇到预期终态时不输出异常：$message', () async {
      final client = _SessionCloseClient(http.ClientException(message));
      final service = DefaultMcpToolDiscoveryService(client: client);
      addTearDown(service.dispose);

      final logs = await _captureDebugLogs(() async {
        final health = await service.checkHealth(server);
        expect(health.status, McpServerHealthStatus.healthy);
      });

      expect(client.deleteCount, 1);
      expect(logs, isEmpty);
    });
  }

  test('Streamable HTTP 会话关闭遇到非预期异常时保留诊断', () async {
    final client = _SessionCloseClient(StateError('测试关闭异常'));
    final service = DefaultMcpToolDiscoveryService(client: client);
    addTearDown(service.dispose);

    final logs = await _captureDebugLogs(() async {
      final health = await service.checkHealth(server);
      expect(health.status, McpServerHealthStatus.healthy);
    });

    expect(client.deleteCount, 1);
    expect(logs, hasLength(1));
    expect(logs.single, contains('关闭 Streamable HTTP 会话'));
    expect(logs.single, contains('测试关闭异常'));
  });

  test('服务销毁后不再启动 Streamable HTTP 会话关闭请求', () async {
    final initialized = Completer<void>();
    final releaseInitialized = Completer<void>();
    final client = _SessionCloseClient(
      StateError('不应发送关闭请求'),
      onInitialized: () async {
        initialized.complete();
        await releaseInitialized.future;
      },
    );
    final service = DefaultMcpToolDiscoveryService(client: client);

    final healthFuture = service.checkHealth(server);
    await initialized.future;
    service
      ..dispose()
      ..dispose();
    releaseInitialized.complete();

    final health = await healthFuture;
    expect(health.status, McpServerHealthStatus.healthy);
    expect(client.deleteCount, 0);
  });
}

Future<List<String>> _captureDebugLogs(
  Future<void> Function() operation,
) async {
  final previousDebugPrint = debugPrint;
  final logs = <String>[];
  debugPrint = (message, {wrapWidth}) {
    if (message != null) logs.add(message);
  };
  try {
    await operation();
    return logs;
  } finally {
    debugPrint = previousDebugPrint;
  }
}

class _SessionCloseClient extends http.BaseClient {
  _SessionCloseClient(this.closeError, {this.onInitialized});

  final Object closeError;
  final Future<void> Function()? onInitialized;
  int _postCount = 0;
  int deleteCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'DELETE') {
      deleteCount += 1;
      throw closeError;
    }

    _postCount += 1;
    if (_postCount == 1) {
      return _response(
        request,
        200,
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'result': <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
          },
        },
        headers: const <String, String>{
          'content-type': 'application/json',
          'mcp-session-id': 'test-session',
        },
      );
    }
    if (_postCount == 2) {
      await onInitialized?.call();
      return _response(request, 202, null);
    }
    throw StateError('收到非预期的 MCP 请求：${request.method} ${request.url}');
  }

  http.StreamedResponse _response(
    http.BaseRequest request,
    int statusCode,
    Object? body, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final bytes = body == null ? <int>[] : utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      request: request,
      headers: headers,
    );
  }
}
