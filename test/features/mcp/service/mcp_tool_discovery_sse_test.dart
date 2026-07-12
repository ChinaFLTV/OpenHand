import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

const int _legacySseLimitBytes = 4 * 1024 * 1024;

void main() {
  const server = McpServer(
    name: 'bounded-sse',
    type: McpServerType.sse,
    enabled: true,
    url: 'https://mcp.example.test/sse',
  );

  test(
    'legacy SSE parses fragmented CRLF and flushes the final event at EOF',
    () async {
      final client = _LegacyProtocolClient();
      final service = DefaultMcpToolDiscoveryService(client: client);
      addTearDown(() async {
        service.dispose();
        await client.dispose();
      });

      final health = await service
          .checkHealth(server)
          .timeout(const Duration(seconds: 2));

      expect(health.status, McpServerHealthStatus.healthy);
    },
  );

  test(
    'legacy SSE rejects and cancels an oversized unterminated line',
    () async {
      final payload = Uint8List(_legacySseLimitBytes + 1)
        ..fillRange(0, _legacySseLimitBytes + 1, 0x78);
      final client = _ControlledSseClient(payload, stallCancellation: true);
      final service = DefaultMcpToolDiscoveryService(client: client);
      addTearDown(() async {
        service.dispose();
        await client.dispose();
      });

      final health = await service
          .checkHealth(server)
          .timeout(const Duration(seconds: 2));

      expect(health.status, McpServerHealthStatus.unhealthy);
      expect(health.errorMessage, contains('MCP SSE line exceeds'));
      await client.cancellationObserved.timeout(const Duration(seconds: 1));
    },
  );

  test('legacy SSE bounds an event that never receives a blank line', () async {
    final payload = _oversizedUnterminatedEvent();
    final client = _ControlledSseClient(payload);
    final service = DefaultMcpToolDiscoveryService(client: client);
    addTearDown(() async {
      service.dispose();
      await client.dispose();
    });

    final health = await service
        .checkHealth(server)
        .timeout(const Duration(seconds: 2));

    expect(health.status, McpServerHealthStatus.unhealthy);
    expect(health.errorMessage, contains('MCP SSE event exceeds'));
    await client.cancellationObserved.timeout(const Duration(seconds: 1));
  });
}

Uint8List _oversizedUnterminatedEvent() {
  final bytes = BytesBuilder()..add(utf8.encode('event: endpoint\n'));
  final dataLine = utf8.encode('data: ${'x' * 1024}\n');
  for (var i = 0; i < 4200; i++) {
    bytes.add(dataLine);
  }
  return bytes.takeBytes();
}

class _LegacyProtocolClient extends http.BaseClient {
  StreamController<List<int>>? _events;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET') {
      if (_events != null) throw StateError('Duplicate SSE connection.');
      late final StreamController<List<int>> events;
      events = StreamController<List<int>>(
        sync: true,
        onListen: () {
          scheduleMicrotask(() {
            for (final chunk in const <String>[
              'event: endpoint\r',
              '\ndata: /messages\r',
              '\n\r',
              '\n',
            ]) {
              if (!events.hasListener) break;
              events.add(utf8.encode(chunk));
            }
          });
        },
      );
      _events = events;
      return http.StreamedResponse(
        events.stream,
        200,
        headers: const <String, String>{'content-type': 'text/event-stream'},
        request: request,
      );
    }

    if (request is! http.Request || request.method != 'POST') {
      throw StateError('Unexpected MCP test request: ${request.method}');
    }
    final payload = jsonDecode(request.body) as Map<String, Object?>;
    final requestId = payload['id'];
    if (requestId != null) {
      scheduleMicrotask(() {
        final events = _events;
        if (events == null || !events.hasListener) return;
        for (final chunk in <String>[
          'event: message\r',
          '\ndata: {"jsonrpc":"2.0",\r',
          '\ndata: "id":${jsonEncode(requestId)},\r',
          '\ndata: "result":{"protocolVersion":"2024-11-05",',
          '"capabilities":{}}}',
        ]) {
          events.add(utf8.encode(chunk));
        }
        // No final line break or blank event boundary: EOF must flush this
        // otherwise complete JSON-RPC response.
        unawaited(events.close());
      });
    }
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      202,
      request: request,
    );
  }

  Future<void> dispose() async {
    final events = _events;
    if (events != null && !events.isClosed) {
      await events.close();
    }
  }

  @override
  void close() {
    unawaited(dispose());
  }
}

class _ControlledSseClient extends http.BaseClient {
  _ControlledSseClient(this.payload, {this.stallCancellation = false});

  final List<int> payload;
  final bool stallCancellation;
  final Completer<void> _cancellationObserved = Completer<void>();
  final Completer<void> _cancellationRelease = Completer<void>();
  StreamController<List<int>>? _responseController;

  Future<void> get cancellationObserved => _cancellationObserved.future;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET' || _responseController != null) {
      throw StateError('Unexpected MCP test request: ${request.method}');
    }

    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        scheduleMicrotask(() {
          if (!controller.isClosed && controller.hasListener) {
            controller.add(payload);
          }
        });
      },
      onCancel: () {
        if (!_cancellationObserved.isCompleted) {
          _cancellationObserved.complete();
        }
        return stallCancellation
            ? _cancellationRelease.future
            : Future<void>.value();
      },
    );
    _responseController = controller;
    return http.StreamedResponse(
      controller.stream,
      200,
      headers: const <String, String>{'content-type': 'text/event-stream'},
      request: request,
    );
  }

  Future<void> dispose() async {
    if (!_cancellationRelease.isCompleted) {
      _cancellationRelease.complete();
    }
    final controller = _responseController;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  @override
  void close() {
    unawaited(dispose());
  }
}
