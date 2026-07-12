import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/model/mcp_server_ops.dart';
import 'package:openhand/features/mcp/service/mcp_server_ops_runtime.dart';

void main() {
  test('runtime validates the concurrent request limit', () {
    expect(
      () => McpServerOpsRuntime(
        toolListProvider: () => const <McpOpsToolDefinition>[],
        toolInvoker: (_, _, _) async =>
            const McpOpsToolInvocationResult(text: ''),
        approvalGate: (_) async => true,
        auditSink: (_) {},
        snapshotSink: (_) {},
        maxConcurrentRequests: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => McpServerOpsRuntime(
        toolListProvider: () => const <McpOpsToolDefinition>[],
        toolInvoker: (_, _, _) async =>
            const McpOpsToolInvocationResult(text: ''),
        approvalGate: (_) async => true,
        auditSink: (_) {},
        snapshotSink: (_) {},
        maxBatchItems: 0,
      ),
      throwsArgumentError,
    );
  });

  group('readBoundedMcpOpsRequestBody', () {
    test('decodes UTF-8 split across chunks', () async {
      final encoded = utf8.encode('你好 MCP');

      final body = await readBoundedMcpOpsRequestBody(
        Stream<List<int>>.fromIterable(<List<int>>[
          encoded.sublist(0, 1),
          encoded.sublist(1, 4),
          encoded.sublist(4),
        ]),
        maxBytes: 64,
        idleTimeout: const Duration(seconds: 1),
        totalTimeout: const Duration(seconds: 2),
      );

      expect(body, '你好 MCP');
    });

    test('rejects a body above the byte limit', () async {
      final controller = StreamController<List<int>>();
      final bodyFuture = readBoundedMcpOpsRequestBody(
        controller.stream,
        maxBytes: 4,
        idleTimeout: const Duration(seconds: 1),
        totalTimeout: const Duration(seconds: 2),
      );

      controller.add(<int>[1, 2, 3]);
      controller.add(<int>[4, 5]);

      await expectLater(
        bodyFuture,
        throwsA(
          isA<McpOpsRequestBodyTooLargeException>()
              .having((error) => error.maxBytes, 'maxBytes', 4)
              .having((error) => error.receivedBytes, 'receivedBytes', 5),
        ),
      );
      await controller.close();
    });

    test('rejects a body that exceeds the idle timeout', () async {
      final controller = StreamController<List<int>>();

      await expectLater(
        readBoundedMcpOpsRequestBody(
          controller.stream,
          maxBytes: 64,
          idleTimeout: const Duration(milliseconds: 40),
          totalTimeout: const Duration(seconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await controller.close();
    });

    test('enforces the total timeout despite continuous chunks', () async {
      final controller = StreamController<List<int>>();
      final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        controller.add(const <int>[0x61]);
      });
      try {
        await expectLater(
          readBoundedMcpOpsRequestBody(
            controller.stream,
            maxBytes: 1024,
            idleTimeout: const Duration(seconds: 2),
            totalTimeout: const Duration(milliseconds: 100),
          ),
          throwsA(
            isA<TimeoutException>().having(
              (error) => error.message,
              'message',
              contains('total time limit'),
            ),
          ),
        );
      } finally {
        timer.cancel();
        await controller.close();
      }
    });
  });

  group('McpServerOpsRuntime request body limits', () {
    late McpServerOpsRuntime runtime;
    late McpOpsToolInvoker toolInvoker;
    late List<McpOpsToolDefinition> tools;
    late List<McpOpsAuditEntry> audits;
    late int port;

    setUp(() async {
      tools = <McpOpsToolDefinition>[];
      audits = <McpOpsAuditEntry>[];
      toolInvoker = (_, _, _) async =>
          const McpOpsToolInvocationResult(text: '');
      runtime = McpServerOpsRuntime(
        toolListProvider: () => tools,
        toolInvoker: (tool, arguments, context) =>
            toolInvoker(tool, arguments, context),
        approvalGate: (_) async => true,
        auditSink: audits.add,
        snapshotSink: (_) {},
        maxRequestBodyBytes: 512,
        requestBodyIdleTimeout: const Duration(milliseconds: 300),
        requestBodyTotalTimeout: const Duration(seconds: 1),
        maxConcurrentRequests: 1,
        maxBatchItems: 2,
      );
      await runtime.start(
        const McpOpsConfig(listenPort: 0, rpmLimit: 1, timeoutMs: 50),
      );
      port = runtime.snapshot.boundPort!;
    });

    tearDown(() async {
      await runtime.stop();
    });

    test('rejects browser-originated requests without CORS access', () async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/mcp'),
        );
        request.headers.contentType = ContentType.json;
        request.headers.set('origin', 'https://evil.example');
        request.write(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/list',
          }),
        );

        final response = await request.close();
        expect(response.statusCode, HttpStatus.forbidden);
        expect(response.headers.value('access-control-allow-origin'), isNull);
        expect(
          await response.transform(utf8.decoder).join(),
          contains('Browser-originated'),
        );
        expect(audits.single.errorMessage, contains('Browser-originated'));
      } finally {
        client.close(force: true);
      }
    });

    test('rejects browser preflight without permissive headers', () async {
      final client = HttpClient();
      try {
        final request = await client.openUrl(
          'OPTIONS',
          Uri.parse('http://127.0.0.1:$port/mcp'),
        );
        request.headers.set('origin', 'null');
        request.headers.set('access-control-request-method', 'POST');

        final response = await request.close();
        expect(response.statusCode, HttpStatus.forbidden);
        expect(response.headers.value('access-control-allow-origin'), isNull);
        await response.drain<void>();
      } finally {
        client.close(force: true);
      }
    });

    test('ignores spoofed forwarding headers for peer identity', () async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/mcp'),
        );
        request.headers.contentType = ContentType.json;
        request.headers.set('x-forwarded-for', '203.0.113.77');
        request.headers.set('x-real-ip', '198.51.100.12');
        request.write(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'ping',
          }),
        );

        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        await response.drain<void>();
        expect(audits.single.ipAddress, startsWith('127.0.0.1:'));
      } finally {
        client.close(force: true);
      }
    });

    test('rejects excess slow requests before buffering their body', () async {
      final slowClient = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
      );
      try {
        slowClient.add(
          ascii.encode(
            'POST /mcp HTTP/1.1\r\n'
            'Host: 127.0.0.1:$port\r\n'
            'Content-Type: application/json\r\n'
            'Transfer-Encoding: chunked\r\n'
            '\r\n'
            '1\r\n{\r\n',
          ),
        );
        await slowClient.flush();
        await _waitForActiveRequests(runtime, 1);

        final client = HttpClient();
        try {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:$port/health'),
          );
          final response = await request.close();
          expect(response.statusCode, HttpStatus.tooManyRequests);
          expect(
            await response.transform(utf8.decoder).join(),
            contains('Too many concurrent'),
          );
        } finally {
          client.close(force: true);
        }
      } finally {
        slowClient.destroy();
      }
      await _expectNoActiveRequests(runtime);
    });

    test('rejects a JSON-RPC batch above the configured item cap', () async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/mcp'),
        );
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode(<Object?>[
            <String, Object?>{'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
            <String, Object?>{'jsonrpc': '2.0', 'id': 2, 'method': 'ping'},
            <String, Object?>{'jsonrpc': '2.0', 'id': 3, 'method': 'ping'},
          ]),
        );

        final response = await request.close();
        expect(response.statusCode, HttpStatus.badRequest);
        expect(
          await response.transform(utf8.decoder).join(),
          contains('Invalid JSON-RPC batch'),
        );
        expect(audits.single.errorMessage, contains('item limit'));
      } finally {
        client.close(force: true);
      }
    });

    test('notifications consume the configured request rate budget', () async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/mcp'),
        );
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode(<Object?>[
            <String, Object?>{
              'jsonrpc': '2.0',
              'method': 'notifications/initialized',
            },
            <String, Object?>{
              'jsonrpc': '2.0',
              'method': 'notifications/initialized',
            },
          ]),
        );

        final response = await request.close();
        expect(response.statusCode, HttpStatus.accepted);
        await response.drain<void>();
        expect(audits.map((entry) => entry.status), <String>[
          'success',
          'blocked',
        ]);
      } finally {
        client.close(force: true);
      }
    });

    test('returns 413 and releases the active request', () async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/mcp'),
        );
        request.headers.contentType = ContentType.json;
        request.contentLength = 513;
        request.add(List<int>.filled(513, 0x61));

        final response = await request.close();
        expect(response.statusCode, HttpStatus.requestEntityTooLarge);
        expect(
          await response.transform(utf8.decoder).join(),
          contains('too large'),
        );
        await _expectNoActiveRequests(runtime);
      } finally {
        client.close(force: true);
      }
    });

    test('returns 413 for an oversized chunked body', () async {
      final oversizedChunk = List<String>.filled(513, 'a').join();
      final response = await _sendRawHttpRequest(
        port,
        'POST /mcp HTTP/1.1\r\n'
        'Host: 127.0.0.1:$port\r\n'
        'Content-Type: application/json\r\n'
        'Transfer-Encoding: chunked\r\n'
        'Connection: close\r\n'
        '\r\n'
        '201\r\n$oversizedChunk\r\n',
      );

      expect(response, startsWith('HTTP/1.1 413'));
      expect(response, contains('MCP request body is too large.'));
      await _expectNoActiveRequests(runtime);
    });

    test(
      'returns 408 for an idle chunked body and releases the request',
      () async {
        final response = await _sendRawHttpRequest(
          port,
          'POST /mcp HTTP/1.1\r\n'
          'Host: 127.0.0.1:$port\r\n'
          'Content-Type: application/json\r\n'
          'Transfer-Encoding: chunked\r\n'
          'Connection: close\r\n'
          '\r\n'
          '1\r\n{\r\n',
        );

        expect(response, startsWith('HTTP/1.1 408'));
        expect(response, contains('MCP request body timed out.'));
        await _expectNoActiveRequests(runtime);
      },
    );

    test('tool timeout propagates cancellation to the invoker', () async {
      final cancellationObserved = Completer<void>();
      tools = const <McpOpsToolDefinition>[
        McpOpsToolDefinition(
          name: 'slow_tool',
          title: 'Slow tool',
          description: 'Waits for cancellation.',
          surface: McpOpsExposureSurface.builtinTools,
          itemId: 'slow',
          endpointId: 'wait',
          inputSchema: <String, Object?>{'type': 'object'},
        ),
      ];
      toolInvoker = (_, _, context) async {
        await context.cancelSignal;
        if (!cancellationObserved.isCompleted) cancellationObserved.complete();
        return const McpOpsToolInvocationResult(text: 'cancelled');
      };

      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/mcp'),
        );
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': <String, Object?>{
              'name': 'slow_tool',
              'arguments': <String, Object?>{},
            },
          }),
        );

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        expect(response.statusCode, HttpStatus.ok);
        expect(body, contains('MCP tool call timed out.'));
        await cancellationObserved.future.timeout(const Duration(seconds: 1));
      } finally {
        client.close(force: true);
      }
    });
  });
}

Future<String> _sendRawHttpRequest(int port, String requestText) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  try {
    socket.add(ascii.encode(requestText));
    await socket.flush();
    return await socket
        .cast<List<int>>()
        .transform(latin1.decoder)
        .join()
        .timeout(const Duration(seconds: 2));
  } finally {
    socket.destroy();
  }
}

Future<void> _expectNoActiveRequests(McpServerOpsRuntime runtime) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (runtime.snapshot.activeRequests != 0 &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(runtime.snapshot.activeRequests, 0);
}

Future<void> _waitForActiveRequests(
  McpServerOpsRuntime runtime,
  int expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (runtime.snapshot.activeRequests != expected &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(runtime.snapshot.activeRequests, expected);
}
