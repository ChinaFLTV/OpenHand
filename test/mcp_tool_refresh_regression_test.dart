import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_catalog_cache.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同一服务刷新单飞且缓存写入不阻塞目录状态更新', () async {
    final directory = await Directory.systemTemp.createTemp(
      'openhand_mcp_refresh_test_',
    );
    final discovery = _ImmediateDiscoveryService();
    final cache = _BlockingToolCatalogCache(directory);
    final controller = await McpController.create(
      initialFilePath: '${directory.path}/mcp.json',
      store: McpStore(serversFilePath: '${directory.path}/mcp.json'),
      toolDiscoveryService: discovery,
      toolCatalogCacheService: cache,
    );
    addTearDown(() async {
      controller.dispose();
      await directory.delete(recursive: true);
    });

    const server = McpServer(
      name: 'regression-server',
      type: McpServerType.streamableHttp,
      enabled: true,
      url: 'https://example.com/mcp',
    );
    expect(await controller.saveServer(server), isTrue);

    final firstRefresh = controller.refreshServerTools(server.name);
    final secondRefresh = controller.refreshServerTools(server.name);
    expect(identical(firstRefresh, secondRefresh), isTrue);

    await cache.replaceStarted.future;
    expect(discovery.discoverCallCount, 1);
    expect(
      controller.toolCatalogFor(server.name).status,
      McpToolCatalogStatus.ready,
    );
    expect(controller.toolCatalogFor(server.name).tools, hasLength(1));

    cache.releaseReplace();
    await firstRefresh;
  });

  test('同一服务健康探测单飞且结果只记录一次', () async {
    final directory = await Directory.systemTemp.createTemp(
      'openhand_mcp_health_test_',
    );
    final discovery = _ImmediateDiscoveryService();
    final controller = await McpController.create(
      initialFilePath: '${directory.path}/mcp.json',
      store: McpStore(serversFilePath: '${directory.path}/mcp.json'),
      toolDiscoveryService: discovery,
    );
    addTearDown(() async {
      controller.dispose();
      await directory.delete(recursive: true);
    });

    const server = McpServer(
      name: 'health-server',
      type: McpServerType.streamableHttp,
      enabled: true,
      url: 'https://example.com/mcp',
    );
    expect(await controller.saveServer(server), isTrue);
    controller.setPageActive(true);

    final firstCheck = controller.checkServerHealth(server.name);
    final secondCheck = controller.checkServerHealth(server.name);
    expect(identical(firstCheck, secondCheck), isTrue);

    await firstCheck;
    expect(discovery.healthCheckCallCount, 1);
    expect(
      controller.healthStatusFor(server.name).status,
      McpServerHealthStatus.healthy,
    );
    expect(controller.healthStatusFor(server.name).recentProbes, hasLength(1));
  });
}

class _ImmediateDiscoveryService implements McpToolDiscoveryService {
  int discoverCallCount = 0;
  int healthCheckCallCount = 0;

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    discoverCallCount += 1;
    return McpToolCatalog(
      status: McpToolCatalogStatus.ready,
      tools: const <McpTool>[
        McpTool(
          id: 'tool-1',
          name: 'tool_1',
          description: '测试工具',
          inputSchema: <String, Object?>{},
        ),
      ],
      lastScannedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    healthCheckCallCount += 1;
    return const McpServerHealth(status: McpServerHealthStatus.healthy);
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
    Map<String, String>? customHeaders,
    Future<void>? cancelSignal,
  }) async {
    return const McpToolCallResult(outputText: '');
  }

  @override
  void dispose() {}
}

class _BlockingToolCatalogCache extends McpToolCatalogCacheService {
  _BlockingToolCatalogCache(Directory directory) : super(storageDir: directory);

  final Completer<void> replaceStarted = Completer<void>();
  final Completer<void> _replaceReleased = Completer<void>();

  @override
  Future<void> replace({
    required McpServer server,
    required McpToolCatalog catalog,
  }) {
    if (!replaceStarted.isCompleted) replaceStarted.complete();
    return _replaceReleased.future;
  }

  void releaseReplace() {
    if (!_replaceReleased.isCompleted) _replaceReleased.complete();
  }
}
