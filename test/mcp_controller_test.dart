import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

void main() {
  test('McpController rejects tool calls for disabled servers', () async {
    final discoveryService = _FakeMcpToolDiscoveryService();
    final controller = await McpController.create(
      initialFilePath: '/tmp/mcp_controller_test_disabled.json',
      store: _InMemoryMcpStore(
        servers: const <McpServer>[
          McpServer(
            name: 'Disabled',
            type: McpServerType.streamableHttp,
            enabled: false,
            url: 'https://api.example.com/mcp',
          ),
        ],
      ),
      toolDiscoveryService: discoveryService,
      healthCheckInterval: const Duration(days: 1),
    );
    addTearDown(controller.dispose);

    expect(
      () => controller.callTool(serverName: 'Disabled', toolName: 'tail_logs'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('disabled'),
        ),
      ),
    );
    expect(discoveryService.calls, isEmpty);
  });

  test(
    'McpController trims tool names before dispatching tool calls',
    () async {
      final discoveryService = _FakeMcpToolDiscoveryService();
      final controller = await McpController.create(
        initialFilePath: '/tmp/mcp_controller_test_enabled.json',
        store: _InMemoryMcpStore(
          servers: const <McpServer>[
            McpServer(
              name: 'Enabled',
              type: McpServerType.streamableHttp,
              enabled: true,
              url: 'https://api.example.com/mcp',
            ),
          ],
        ),
        toolDiscoveryService: discoveryService,
        healthCheckInterval: const Duration(days: 1),
      );
      addTearDown(controller.dispose);

      final result = await controller.callTool(
        serverName: 'Enabled',
        toolName: '  tail_logs  ',
        arguments: const <String, Object?>{'limit': 20},
      );

      expect(result.outputText, 'ok');
      expect(discoveryService.calls, hasLength(1));
      expect(discoveryService.calls.single.serverName, 'Enabled');
      expect(discoveryService.calls.single.toolName, 'tail_logs');
      expect(discoveryService.calls.single.arguments, const <String, Object?>{
        'limit': 20,
      });
    },
  );

  test(
    'McpController trims server names before dispatching tool calls',
    () async {
      final discoveryService = _FakeMcpToolDiscoveryService();
      final controller = await McpController.create(
        initialFilePath: '/tmp/mcp_controller_test_trimmed_server.json',
        store: _InMemoryMcpStore(
          servers: const <McpServer>[
            McpServer(
              name: 'Enabled',
              type: McpServerType.streamableHttp,
              enabled: true,
              url: 'https://api.example.com/mcp',
            ),
          ],
        ),
        toolDiscoveryService: discoveryService,
        healthCheckInterval: const Duration(days: 1),
      );
      addTearDown(controller.dispose);

      final result = await controller.callTool(
        serverName: '  Enabled  ',
        toolName: 'tail_logs',
      );

      expect(result.outputText, 'ok');
      expect(discoveryService.calls, hasLength(1));
      expect(discoveryService.calls.single.serverName, 'Enabled');
    },
  );

  test(
    'McpController trims server names for tool refresh and health checks',
    () async {
      final discoveryService = _FakeMcpToolDiscoveryService();
      final controller = await McpController.create(
        initialFilePath: '/tmp/mcp_controller_test_trimmed_refresh.json',
        store: _InMemoryMcpStore(
          servers: const <McpServer>[
            McpServer(
              name: 'Enabled',
              type: McpServerType.streamableHttp,
              enabled: true,
              url: 'https://api.example.com/mcp',
            ),
          ],
        ),
        toolDiscoveryService: discoveryService,
        healthCheckInterval: const Duration(days: 1),
      );
      addTearDown(controller.dispose);

      controller.setPageActive(true);
      await controller.refreshServerTools('  Enabled  ');
      await controller.checkServerHealth('  Enabled  ');

      expect(
        controller.toolCatalogFor('  Enabled  ').status,
        McpToolCatalogStatus.ready,
      );
      expect(
        controller.healthStatusFor('  Enabled  ').status,
        McpServerHealthStatus.healthy,
      );
      expect(discoveryService.discoveredServerNames, contains('Enabled'));
      expect(discoveryService.healthCheckedServerNames, contains('Enabled'));
    },
  );
}

class _InMemoryMcpStore extends McpStore {
  _InMemoryMcpStore({required List<McpServer> servers})
    : _servers = List<McpServer>.from(servers),
      super(serversFilePath: '/tmp/openhand-mcp-controller-test.json');

  List<McpServer> _servers;

  @override
  Future<McpLoadResult> load() async {
    return McpLoadResult(servers: List<McpServer>.from(_servers));
  }

  @override
  Future<void> save(List<McpServer> servers) async {
    _servers = List<McpServer>.from(servers);
  }
}

class _FakeMcpToolDiscoveryService implements McpToolDiscoveryService {
  final List<_ToolCallRecord> calls = <_ToolCallRecord>[];
  final List<String> discoveredServerNames = <String>[];
  final List<String> healthCheckedServerNames = <String>[];

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    discoveredServerNames.add(server.name);
    return const McpToolCatalog(status: McpToolCatalogStatus.ready);
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    healthCheckedServerNames.add(server.name);
    return const McpServerHealth(status: McpServerHealthStatus.healthy);
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    calls.add(
      _ToolCallRecord(
        serverName: server.name,
        toolName: toolName,
        arguments: Map<String, Object?>.from(arguments),
      ),
    );
    return const McpToolCallResult(outputText: 'ok');
  }

  @override
  void dispose() {}
}

class _ToolCallRecord {
  const _ToolCallRecord({
    required this.serverName,
    required this.toolName,
    required this.arguments,
  });

  final String serverName;
  final String toolName;
  final Map<String, Object?> arguments;
}
