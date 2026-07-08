import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/model/mcp_server_ops.dart';
import 'package:openhand/features/mcp/service/mcp_ops_endpoint.dart';
import 'package:openhand/features/mcp/service/mcp_server_ops_runtime.dart';

void main() {
  group('MCP ops endpoint addressing', () {
    test('uses loopback for local self-test when listening on wildcard', () {
      expect(mcpOpsClientHost('0.0.0.0'), mcpOpsDefaultListenHost);
      expect(mcpOpsClientHost('::'), mcpOpsDefaultListenHost);
    });

    test('advertises discovered LAN host for external clients', () {
      expect(
        mcpOpsAdvertisedClientHost(
          '0.0.0.0',
          discoveredHosts: const <String>['192.168.1.23'],
        ),
        '192.168.1.23',
      );
      expect(
        mcpOpsAdvertisedClientHost(
          '127.0.0.1',
          discoveredHosts: const <String>['192.168.1.23'],
        ),
        '127.0.0.1',
      );
    });

    test('bind address uses platform any address for wildcard hosts', () {
      expect(mcpOpsListenAddress('0.0.0.0'), InternetAddress.anyIPv4);
      expect(mcpOpsListenAddress('::'), InternetAddress.anyIPv6);
      expect(mcpOpsListenAddress('127.0.0.1'), '127.0.0.1');
    });

    test('formats IPv6 authorities with brackets', () {
      expect(mcpOpsAuthority('::1', 8765), '[::1]:8765');
      expect(mcpOpsAuthority('[::1]', 8765), '[::1]:8765');
    });
  });

  group('MCP ops runtime listener', () {
    test(
      'serves streamable HTTP on wildcard bind and self-tests via loopback',
      () async {
        final runtime = _newRuntime();
        final port = await _freePort();
        try {
          await runtime.start(
            McpOpsConfig(
              listenHost: mcpOpsWildcardIpv4Host,
              listenPort: port,
              networkMode: McpOpsNetworkMode.lan,
            ),
          );
          expect(runtime.snapshot.isRunning, isTrue);
          expect(runtime.snapshot.boundPort, port);

          final result = await runtime.testConnectivity();
          expect(result.ok, isTrue);
        } finally {
          await runtime.stop();
        }
      },
    );

    test('start rebinds when the saved listener changes', () async {
      final runtime = _newRuntime();
      final firstPort = await _freePort();
      final secondPort = await _freePort();
      try {
        await runtime.start(McpOpsConfig(listenPort: firstPort));
        expect(runtime.snapshot.boundPort, firstPort);

        await runtime.start(McpOpsConfig(listenPort: secondPort));
        expect(runtime.snapshot.boundPort, secondPort);
      } finally {
        await runtime.stop();
      }
    });
  });
}

McpServerOpsRuntime _newRuntime() {
  return McpServerOpsRuntime(
    toolListProvider: () => const <McpOpsToolDefinition>[],
    toolInvoker: (_, _) async => const McpOpsToolInvocationResult(text: ''),
    approvalGate: (_) async => true,
    auditSink: (_) {},
    snapshotSink: (_) {},
  );
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
