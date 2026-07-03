import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mcp lifecycle cancellation', () {
    test('marks stdio closing errors as expected lifecycle cancellation', () {
      expect(
        isExpectedMcpToolDiscoveryLifecycleError(
          const McpToolDiscoveryException(
            kMcpStdioSessionClosingMessage,
            isExpectedLifecycleCancellation: true,
          ),
        ),
        isTrue,
      );
      expect(
        isExpectedMcpToolDiscoveryLifecycleError(
          const McpToolDiscoveryException('invalid JSON-RPC response'),
        ),
        isFalse,
      );
    });

    test('keeps previous tool catalog when refresh is cancelled', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_mcp_controller_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final discovery = _FakeMcpToolDiscoveryService()
        ..catalogs.add(_readyCatalog());
      final controller = await McpController.create(
        initialFilePath: '${tempDir.path}/mcp_servers.json',
        toolDiscoveryService: discovery,
      );
      addTearDown(controller.dispose);

      await controller.saveServer(_server());
      await controller.refreshServerTools('demo');
      expect(
        controller.toolCatalogFor('demo').status,
        McpToolCatalogStatus.ready,
      );
      expect(controller.toolCatalogFor('demo').tools.single.id, 'demo_tool');

      discovery.catalogs.add(const McpToolCatalog());
      await controller.refreshServerTools('demo');

      final catalog = controller.toolCatalogFor('demo');
      expect(catalog.status, McpToolCatalogStatus.ready);
      expect(catalog.tools.single.id, 'demo_tool');
    });

    test('does not count health cancellation as a failed probe', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_mcp_controller_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final discovery = _FakeMcpToolDiscoveryService()
        ..healthChecks.add(
          McpServerHealth(
            status: McpServerHealthStatus.healthy,
            lastCheckedAt: DateTime.utc(2026),
          ),
        );
      final controller = await McpController.create(
        initialFilePath: '${tempDir.path}/mcp_servers.json',
        toolDiscoveryService: discovery,
      );
      addTearDown(controller.dispose);

      await controller.saveServer(_server());
      controller.setPageActive(true);
      await controller.checkServerHealth('demo');

      final healthy = controller.healthStatusFor('demo');
      expect(healthy.status, McpServerHealthStatus.healthy);
      expect(healthy.consecutiveFailures, 0);
      expect(healthy.recentProbes, hasLength(1));

      discovery.healthChecks.add(const McpServerHealth());
      await controller.checkServerHealth('demo');
      controller.setPageActive(false);

      final afterCancel = controller.healthStatusFor('demo');
      expect(afterCancel.status, McpServerHealthStatus.healthy);
      expect(afterCancel.consecutiveFailures, 0);
      expect(afterCancel.recentProbes, hasLength(1));
    });
  });
}

McpServer _server() {
  return const McpServer(
    name: 'demo',
    type: McpServerType.streamableHttp,
    enabled: true,
    url: 'https://example.com/mcp',
  );
}

McpToolCatalog _readyCatalog() {
  return McpToolCatalog(
    status: McpToolCatalogStatus.ready,
    tools: const <McpTool>[
      McpTool(
        id: 'demo_tool',
        name: 'Demo Tool',
        description: 'Demo tool.',
        inputSchema: <String, Object?>{'type': 'object'},
      ),
    ],
    lastScannedAt: DateTime.utc(2026),
  );
}

class _FakeMcpToolDiscoveryService implements McpToolDiscoveryService {
  final Queue<McpToolCatalog> catalogs = Queue<McpToolCatalog>();
  final Queue<McpServerHealth> healthChecks = Queue<McpServerHealth>();

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    if (catalogs.isEmpty) {
      return const McpToolCatalog();
    }
    return catalogs.removeFirst();
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    if (healthChecks.isEmpty) {
      return const McpServerHealth();
    }
    return healthChecks.removeFirst();
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
    Map<String, String>? customHeaders,
  }) async {
    return const McpToolCallResult(outputText: '');
  }

  @override
  void dispose() {}
}
