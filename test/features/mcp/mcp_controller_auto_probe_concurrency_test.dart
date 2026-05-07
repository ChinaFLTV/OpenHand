import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

void main() {
  test(
    'auto tools refresh and health checks share one concurrency pool',
    () async {
      final servers = List<McpServer>.generate(
        4,
        (index) => McpServer(
          name: 'server-$index',
          type: McpServerType.streamableHttp,
          enabled: true,
          url: 'http://127.0.0.1:${9000 + index}/mcp',
        ),
      );
      final service = _CountingDiscoveryService(
        delay: const Duration(milliseconds: 25),
      );
      final controller = McpController.uninitialized(
        initialFilePath: '/tmp/openhand-mcp-test.json',
        store: _MemoryMcpStore(servers),
        toolDiscoveryService: service,
        autoProbeConcurrency: 2,
      );

      addTearDown(controller.dispose);

      await controller.refresh();
      controller.setPageActive(true);
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(service.toolCalls, servers.length);
      expect(service.healthCalls, servers.length);
      expect(service.maxActive, lessThanOrEqualTo(2));
    },
  );
}

class _MemoryMcpStore extends McpStore {
  _MemoryMcpStore(this._servers)
    : super(serversFilePath: '/tmp/openhand-mcp-test.json');

  final List<McpServer> _servers;

  @override
  Future<McpLoadResult> load() async => McpLoadResult(servers: _servers);

  @override
  Future<void> save(List<McpServer> servers) async {}

  @override
  Future<void> openStorageDirectory() async {}
}

class _CountingDiscoveryService implements McpToolDiscoveryService {
  _CountingDiscoveryService({required this.delay});

  final Duration delay;
  int active = 0;
  int maxActive = 0;
  int toolCalls = 0;
  int healthCalls = 0;

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    toolCalls += 1;
    await _trackActiveOperation();
    return McpToolCatalog(
      status: McpToolCatalogStatus.ready,
      lastScannedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    healthCalls += 1;
    await _trackActiveOperation();
    return McpServerHealth(
      status: McpServerHealthStatus.healthy,
      lastCheckedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> _trackActiveOperation() async {
    active += 1;
    maxActive = math.max(maxActive, active);
    try {
      await Future<void>.delayed(delay);
    } finally {
      active -= 1;
    }
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
  }) async {
    return const McpToolCallResult(outputText: 'ok');
  }

  @override
  void dispose() {}
}
