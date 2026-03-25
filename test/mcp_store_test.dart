import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

void main() {
  test('McpStore persists and recovers MCP servers json', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_mcp_store_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final serversFilePath = p.join(
      tempDirectory.path,
      '.openhand',
      'mcp',
      'mcp_servers.json',
    );
    final store = McpStore(serversFilePath: serversFilePath);

    final initialLoad = await store.load();
    expect(initialLoad.servers, isEmpty);
    expect(File(serversFilePath).existsSync(), isTrue);

    await store.save(const <McpServer>[
      McpServer(
        name: 'amap-maps',
        type: McpServerType.streamableHttp,
        enabled: true,
        url: 'https://mcp.example/amap',
        headers: <String, String>{
          'Authorization': 'Bearer secret-token',
          'X-Workspace': 'openhand',
        },
      ),
      McpServer(
        name: 'local-shell',
        type: McpServerType.stdio,
        enabled: false,
        command: 'npx',
        args: <String>['-y', '@example/mcp-shell'],
      ),
    ]);

    final reloaded = await store.load();
    expect(reloaded.servers, hasLength(2));
    expect(reloaded.servers.first.name, 'amap-maps');
    expect(reloaded.servers.first.headers, <String, String>{
      'Authorization': 'Bearer secret-token',
      'X-Workspace': 'openhand',
    });
    expect(reloaded.servers.last.enabled, isFalse);
    expect(File(serversFilePath).readAsStringSync(), contains('"mcpServers"'));
    expect(File(serversFilePath).readAsStringSync(), contains('"headers"'));
    expect(
      File(serversFilePath).readAsStringSync(),
      contains('"transport": "http"'),
    );

    await File(serversFilePath).writeAsString('{broken', flush: true);
    final recovered = await store.load();
    expect(recovered.servers, isEmpty);
    expect(recovered.issue?.kind, McpPersistenceIssueKind.recoveredInvalidFile);
    final backupFiles = Directory(p.dirname(serversFilePath))
        .listSync()
        .whereType<File>()
        .where(
          (file) => p.basename(file.path).startsWith('mcp_servers.invalid-'),
        )
        .toList();
    expect(backupFiles, isNotEmpty);
  });

  test('McpStore loads Cursor-style transport fields', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_mcp_transport_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final serversFilePath = p.join(
      tempDirectory.path,
      '.openhand',
      'mcp',
      'mcp_servers.json',
    );
    final targetFile = File(serversFilePath);
    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsString('''
{
  "mcpServers": {
    "odin-cloud-manager": {
      "transport": "sse",
      "url": "https://cloud.op.zuoyebang.cc/mcp/v1"
    }
  }
}
''', flush: true);

    final store = McpStore(serversFilePath: serversFilePath);
    final loaded = await store.load();

    expect(loaded.issue, isNotNull);
    expect(loaded.servers, hasLength(1));
    expect(loaded.servers.single.name, 'odin-cloud-manager');
    expect(loaded.servers.single.type, McpServerType.sse);
    expect(loaded.servers.single.enabled, isTrue);
    expect(loaded.servers.single.url, 'https://cloud.op.zuoyebang.cc/mcp/v1');
  });

  test('McpStore falls back to transport when type is invalid', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_mcp_transport_fallback_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final serversFilePath = p.join(
      tempDirectory.path,
      '.openhand',
      'mcp',
      'mcp_servers.json',
    );
    final targetFile = File(serversFilePath);
    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsString('''
{
  "mcpServers": {
    "odin-cloud-manager": {
      "type": "legacy-http",
      "transport": "http",
      "url": "https://cloud.op.zuoyebang.cc/mcp/v1"
    }
  }
}
''', flush: true);

    final store = McpStore(serversFilePath: serversFilePath);
    final loaded = await store.load();

    expect(loaded.servers, hasLength(1));
    expect(loaded.servers.single.name, 'odin-cloud-manager');
    expect(loaded.servers.single.type, McpServerType.streamableHttp);
  });

  test('McpStore sanitizes invalid header entries', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_mcp_headers_sanitize_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final serversFilePath = p.join(
      tempDirectory.path,
      '.openhand',
      'mcp',
      'mcp_servers.json',
    );
    final targetFile = File(serversFilePath);
    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsString('''
{
  "mcpServers": {
    "odin-cloud-manager": {
      "type": "streamable_http",
      "transport": "http",
      "url": "https://cloud.op.zuoyebang.cc/mcp/v1",
      "headers": {
        "Authorization": "Bearer token",
        "": "ignored",
        "X-Empty": ""
      }
    }
  }
}
''', flush: true);

    final store = McpStore(serversFilePath: serversFilePath);
    final loaded = await store.load();

    expect(loaded.issue, isNotNull);
    expect(loaded.servers, hasLength(1));
    expect(loaded.servers.single.headers, <String, String>{
      'Authorization': 'Bearer token',
    });
  });

  test('McpController serializes save and refresh operations', () async {
    final store = _QueuedMcpStore(initialServers: const <McpServer>[]);
    final controller = await McpController.create(
      initialFilePath: store.serversFilePath,
      store: store,
    );
    expect(store.loadCallCount, 1);

    const server = McpServer(
      name: 'amap-maps',
      type: McpServerType.streamableHttp,
      enabled: true,
      url: 'https://mcp.example/amap',
    );

    final saveFuture = controller.saveServer(server);
    final refreshFuture = controller.refresh();

    await Future<void>.delayed(Duration.zero);

    expect(store.pendingSaveCount, 1);
    expect(store.loadCallCount, 1);
    expect(controller.servers, hasLength(1));

    store.completeNextSave();

    await saveFuture;
    await refreshFuture;

    expect(store.loadCallCount, 2);
    expect(controller.servers, hasLength(1));
    expect(controller.servers.single.name, server.name);
    expect(controller.errorMessage, isNull);
  });

  test(
    'McpController applies queued saves against latest server list',
    () async {
      final store = _QueuedMcpStore(initialServers: const <McpServer>[]);
      final controller = await McpController.create(
        initialFilePath: store.serversFilePath,
        store: store,
      );

      const firstServer = McpServer(
        name: 'amap-maps',
        type: McpServerType.streamableHttp,
        enabled: true,
        url: 'https://mcp.example/amap',
      );
      const secondServer = McpServer(
        name: 'local-shell',
        type: McpServerType.stdio,
        enabled: false,
        command: 'npx',
        args: <String>['-y', '@example/mcp-shell'],
      );

      final firstSave = controller.saveServer(firstServer);
      final secondSave = controller.saveServer(secondServer);

      await Future<void>.delayed(Duration.zero);
      expect(store.pendingSaveCount, 1);
      expect(controller.servers, hasLength(1));

      store.completeNextSave();
      await Future<void>.delayed(Duration.zero);

      expect(store.pendingSaveCount, 1);
      expect(controller.servers, hasLength(2));

      store.completeNextSave();

      expect(await firstSave, isTrue);
      expect(await secondSave, isTrue);
      expect(controller.servers, hasLength(2));
      expect(controller.servers.first.name, 'amap-maps');
      expect(controller.servers.last.name, 'local-shell');
    },
  );

  test('McpController ignores late refresh completion after dispose', () async {
    final store = _QueuedMcpStore(initialServers: const <McpServer>[]);
    final controller = await McpController.create(
      initialFilePath: store.serversFilePath,
      store: store,
    );

    store.blockNextLoad();
    final refreshFuture = controller.refresh();

    await Future<void>.delayed(Duration.zero);
    expect(store.pendingLoadCount, 1);

    controller.dispose();
    store.completeNextLoad();

    await refreshFuture;
  });

  test(
    'McpController only auto scans enabled servers after the page becomes active',
    () async {
      final store = _QueuedMcpStore(
        initialServers: const <McpServer>[
          McpServer(
            name: 'amap-maps',
            type: McpServerType.sse,
            enabled: true,
            url: 'https://mcp.example/amap',
          ),
        ],
      );
      final discoveryService = _FakeMcpToolDiscoveryService();
      final controller = await McpController.create(
        initialFilePath: store.serversFilePath,
        store: store,
        toolDiscoveryService: discoveryService,
      );
      addTearDown(controller.dispose);

      expect(discoveryService.requestedServerNames, isEmpty);
      expect(discoveryService.requestedHealthServerNames, isEmpty);

      controller.setPageActive(true);
      await Future<void>.delayed(Duration.zero);

      expect(discoveryService.requestedServerNames, <String>['amap-maps']);
      expect(discoveryService.requestedHealthServerNames, <String>[
        'amap-maps',
      ]);
      expect(controller.toolCatalogFor('amap-maps').isLoading, isTrue);
      expect(controller.healthStatusFor('amap-maps').isChecking, isTrue);

      discoveryService.completeNext(
        const McpToolCatalog(
          status: McpToolCatalogStatus.ready,
          tools: <McpTool>[
            McpTool(
              id: 'search_orders',
              name: 'Search Orders',
              description: 'Search available orders.',
              inputSchema: <String, Object?>{'type': 'object'},
            ),
          ],
        ),
      );
      discoveryService.completeNextHealth(
        const McpServerHealth(status: McpServerHealthStatus.healthy),
      );
      await Future<void>.delayed(Duration.zero);

      final catalog = controller.toolCatalogFor('amap-maps');
      expect(catalog.status, McpToolCatalogStatus.ready);
      expect(catalog.tools, hasLength(1));
      expect(catalog.tools.single.id, 'search_orders');
      expect(
        controller.healthStatusFor('amap-maps').status,
        McpServerHealthStatus.healthy,
      );
    },
  );

  test('McpController periodically re-checks enabled server health', () async {
    final store = _QueuedMcpStore(
      initialServers: const <McpServer>[
        McpServer(
          name: 'amap-maps',
          type: McpServerType.sse,
          enabled: true,
          url: 'https://mcp.example/amap',
        ),
      ],
    );
    final discoveryService = _FakeMcpToolDiscoveryService();
    discoveryService.queueResult(
      const McpToolCatalog(status: McpToolCatalogStatus.ready),
    );
    discoveryService.queueHealthResult(
      const McpServerHealth(status: McpServerHealthStatus.healthy),
    );
    discoveryService.queueHealthResult(
      const McpServerHealth(status: McpServerHealthStatus.unhealthy),
    );
    final controller = await McpController.create(
      initialFilePath: store.serversFilePath,
      store: store,
      toolDiscoveryService: discoveryService,
      healthCheckInterval: const Duration(milliseconds: 60),
    );
    addTearDown(controller.dispose);

    controller.setPageActive(true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(
      controller.healthStatusFor('amap-maps').status,
      McpServerHealthStatus.healthy,
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));
    await Future<void>.delayed(Duration.zero);

    expect(
      discoveryService.requestedHealthServerNames.length,
      greaterThanOrEqualTo(2),
    );
    expect(
      controller.healthStatusFor('amap-maps').status,
      McpServerHealthStatus.unhealthy,
    );
  });

  test(
    'McpController stops periodic health checks when the page becomes inactive',
    () async {
      final store = _QueuedMcpStore(
        initialServers: const <McpServer>[
          McpServer(
            name: 'amap-maps',
            type: McpServerType.sse,
            enabled: true,
            url: 'https://mcp.example/amap',
          ),
        ],
      );
      final discoveryService = _FakeMcpToolDiscoveryService();
      discoveryService.queueResult(
        const McpToolCatalog(status: McpToolCatalogStatus.ready),
      );
      discoveryService.queueHealthResult(
        const McpServerHealth(status: McpServerHealthStatus.healthy),
      );
      final controller = await McpController.create(
        initialFilePath: store.serversFilePath,
        store: store,
        toolDiscoveryService: discoveryService,
        healthCheckInterval: const Duration(milliseconds: 40),
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(discoveryService.requestedHealthServerNames, isEmpty);

      controller.setPageActive(true);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(discoveryService.requestedHealthServerNames, <String>[
        'amap-maps',
      ]);

      controller.setPageActive(false);
      final requestCountWhenInactive =
          discoveryService.requestedHealthServerNames.length;

      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(
        discoveryService.requestedHealthServerNames.length,
        requestCountWhenInactive,
      );
    },
  );

  test(
    'McpController restarts health checks cleanly after the page becomes active again',
    () async {
      final store = _QueuedMcpStore(
        initialServers: const <McpServer>[
          McpServer(
            name: 'amap-maps',
            type: McpServerType.sse,
            enabled: true,
            url: 'https://mcp.example/amap',
          ),
        ],
      );
      final discoveryService = _FakeMcpToolDiscoveryService();
      discoveryService.queueResult(
        const McpToolCatalog(status: McpToolCatalogStatus.ready),
      );
      final controller = await McpController.create(
        initialFilePath: store.serversFilePath,
        store: store,
        toolDiscoveryService: discoveryService,
        healthCheckInterval: const Duration(seconds: 5),
      );
      addTearDown(controller.dispose);

      controller.setPageActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(discoveryService.requestedHealthServerNames, <String>[
        'amap-maps',
      ]);

      controller.setPageActive(false);
      discoveryService.completeNextHealth(
        const McpServerHealth(status: McpServerHealthStatus.healthy),
      );
      await Future<void>.delayed(Duration.zero);

      controller.setPageActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(discoveryService.requestedHealthServerNames, <String>[
        'amap-maps',
        'amap-maps',
      ]);

      discoveryService.completeNextHealth(
        const McpServerHealth(status: McpServerHealthStatus.unhealthy),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.healthStatusFor('amap-maps').status,
        McpServerHealthStatus.unhealthy,
      );
    },
  );

  test(
    'McpController stores health checks independently from tool scans',
    () async {
      final store = _QueuedMcpStore(
        initialServers: const <McpServer>[
          McpServer(
            name: 'local-shell',
            type: McpServerType.stdio,
            enabled: false,
            command: 'npx',
            args: <String>['-y', '@example/mcp-shell'],
          ),
        ],
      );
      final discoveryService = _FakeMcpToolDiscoveryService();
      final controller = await McpController.create(
        initialFilePath: store.serversFilePath,
        store: store,
        toolDiscoveryService: discoveryService,
      );
      addTearDown(controller.dispose);

      controller.setPageActive(true);
      final checkFuture = controller.checkServerHealth('local-shell');
      await Future<void>.delayed(Duration.zero);

      expect(discoveryService.requestedHealthServerNames, <String>[
        'local-shell',
      ]);
      expect(controller.healthStatusFor('local-shell').isChecking, isTrue);
      expect(discoveryService.requestedServerNames, isEmpty);

      discoveryService.completeNextHealth(
        const McpServerHealth(
          status: McpServerHealthStatus.unhealthy,
          errorMessage: 'Health check request failed with HTTP 307',
        ),
      );
      await checkFuture;

      final health = controller.healthStatusFor('local-shell');
      expect(health.status, McpServerHealthStatus.unhealthy);
      expect(health.errorMessage, contains('HTTP 307'));
      expect(
        controller.toolCatalogFor('local-shell').status,
        McpToolCatalogStatus.idle,
      );
    },
  );

  test(
    'McpController skips health checks while the page is inactive',
    () async {
      final store = _QueuedMcpStore(
        initialServers: const <McpServer>[
          McpServer(
            name: 'local-shell',
            type: McpServerType.stdio,
            enabled: true,
            command: 'npx',
            args: <String>['-y', '@example/mcp-shell'],
          ),
        ],
      );
      final discoveryService = _FakeMcpToolDiscoveryService();
      final controller = await McpController.create(
        initialFilePath: store.serversFilePath,
        store: store,
        toolDiscoveryService: discoveryService,
      );
      addTearDown(controller.dispose);

      await controller.checkServerHealth('local-shell');

      expect(discoveryService.requestedHealthServerNames, isEmpty);
      expect(
        controller.healthStatusFor('local-shell').status,
        McpServerHealthStatus.idle,
      );
    },
  );

  test(
    'McpController supports manual tool refresh recovery after failures',
    () async {
      final store = _QueuedMcpStore(
        initialServers: const <McpServer>[
          McpServer(
            name: 'local-shell',
            type: McpServerType.stdio,
            enabled: false,
            command: 'npx',
            args: <String>['-y', '@example/mcp-shell'],
          ),
        ],
      );
      final discoveryService = _FakeMcpToolDiscoveryService();
      discoveryService.queueResult(
        const McpToolCatalog(
          status: McpToolCatalogStatus.failed,
          errorMessage: 'Tool scan timed out.',
        ),
      );
      discoveryService.queueResult(
        const McpToolCatalog(
          status: McpToolCatalogStatus.ready,
          tools: <McpTool>[
            McpTool(
              id: 'tail_logs',
              name: 'Tail Logs',
              description: 'Inspect service logs.',
              inputSchema: <String, Object?>{'type': 'object'},
            ),
          ],
        ),
      );
      final controller = await McpController.create(
        initialFilePath: store.serversFilePath,
        store: store,
        toolDiscoveryService: discoveryService,
      );
      addTearDown(controller.dispose);

      expect(discoveryService.requestedServerNames, isEmpty);

      await controller.refreshServerTools('local-shell');
      expect(
        controller.toolCatalogFor('local-shell').errorMessage,
        'Tool scan timed out.',
      );

      await controller.refreshServerTools('local-shell');
      final catalog = controller.toolCatalogFor('local-shell');
      expect(catalog.status, McpToolCatalogStatus.ready);
      expect(catalog.tools.single.id, 'tail_logs');
    },
  );

  test(
    'McpController keeps the previous tool list when a later refresh fails',
    () async {
      final store = _QueuedMcpStore(
        initialServers: const <McpServer>[
          McpServer(
            name: 'local-shell',
            type: McpServerType.stdio,
            enabled: false,
            command: 'npx',
            args: <String>['-y', '@example/mcp-shell'],
          ),
        ],
      );
      final discoveryService = _FakeMcpToolDiscoveryService();
      discoveryService.queueResult(
        const McpToolCatalog(
          status: McpToolCatalogStatus.ready,
          tools: <McpTool>[
            McpTool(
              id: 'tail_logs',
              name: 'Tail Logs',
              description: 'Inspect service logs.',
              inputSchema: <String, Object?>{'type': 'object'},
            ),
          ],
        ),
      );
      discoveryService.queueResult(
        const McpToolCatalog(
          status: McpToolCatalogStatus.failed,
          errorMessage: 'Tool scan timed out.',
        ),
      );
      final controller = await McpController.create(
        initialFilePath: store.serversFilePath,
        store: store,
        toolDiscoveryService: discoveryService,
      );
      addTearDown(controller.dispose);

      await controller.refreshServerTools('local-shell');
      expect(controller.toolCatalogFor('local-shell').tools, hasLength(1));

      await controller.refreshServerTools('local-shell');
      final catalog = controller.toolCatalogFor('local-shell');
      expect(catalog.status, McpToolCatalogStatus.failed);
      expect(catalog.errorMessage, 'Tool scan timed out.');
      expect(catalog.tools, hasLength(1));
      expect(catalog.tools.single.id, 'tail_logs');
    },
  );

  test(
    'McpController ignores late tool scan results after the page becomes inactive',
    () async {
      final store = _QueuedMcpStore(
        initialServers: const <McpServer>[
          McpServer(
            name: 'amap-maps',
            type: McpServerType.sse,
            enabled: true,
            url: 'https://mcp.example/amap',
          ),
        ],
      );
      final discoveryService = _FakeMcpToolDiscoveryService();
      final controller = await McpController.create(
        initialFilePath: store.serversFilePath,
        store: store,
        toolDiscoveryService: discoveryService,
      );
      addTearDown(controller.dispose);

      controller.setPageActive(true);
      await Future<void>.delayed(Duration.zero);

      expect(discoveryService.requestedServerNames, <String>['amap-maps']);
      expect(
        controller.toolCatalogFor('amap-maps').status,
        McpToolCatalogStatus.loading,
      );

      controller.setPageActive(false);
      expect(
        controller.toolCatalogFor('amap-maps').status,
        McpToolCatalogStatus.idle,
      );

      discoveryService.completeNext(
        const McpToolCatalog(
          status: McpToolCatalogStatus.ready,
          tools: <McpTool>[
            McpTool(
              id: 'search_orders',
              name: 'Search Orders',
              description: 'Search available orders.',
              inputSchema: <String, Object?>{'type': 'object'},
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.toolCatalogFor('amap-maps').status,
        McpToolCatalogStatus.idle,
      );
      expect(controller.toolCatalogFor('amap-maps').tools, isEmpty);

      controller.setPageActive(true);
      await Future<void>.delayed(Duration.zero);

      expect(discoveryService.requestedServerNames, <String>[
        'amap-maps',
        'amap-maps',
      ]);

      discoveryService.completeNext(
        const McpToolCatalog(
          status: McpToolCatalogStatus.ready,
          tools: <McpTool>[
            McpTool(
              id: 'search_orders',
              name: 'Search Orders',
              description: 'Search available orders.',
              inputSchema: <String, Object?>{'type': 'object'},
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.toolCatalogFor('amap-maps').status,
        McpToolCatalogStatus.ready,
      );
      expect(controller.toolCatalogFor('amap-maps').tools, hasLength(1));
    },
  );

  test(
    'McpController restores tool catalogs after a failed save rollback',
    () async {
      final store = _QueuedMcpStore(
        initialServers: const <McpServer>[
          McpServer(
            name: 'amap-maps',
            type: McpServerType.sse,
            enabled: true,
            url: 'https://mcp.example/amap',
          ),
        ],
      );
      final discoveryService = _FakeMcpToolDiscoveryService();
      discoveryService.queueResult(
        const McpToolCatalog(
          status: McpToolCatalogStatus.ready,
          tools: <McpTool>[
            McpTool(
              id: 'search_orders',
              name: 'Search Orders',
              description: 'Search available orders.',
              inputSchema: <String, Object?>{'type': 'object'},
            ),
          ],
        ),
      );
      final controller = await McpController.create(
        initialFilePath: store.serversFilePath,
        store: store,
        toolDiscoveryService: discoveryService,
      );
      addTearDown(controller.dispose);

      controller.setPageActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.toolCatalogFor('amap-maps').tools, hasLength(1));

      final saveFuture = controller.saveServer(
        const McpServer(
          name: 'renamed-amap',
          type: McpServerType.sse,
          enabled: true,
          url: 'https://mcp.example/amap-v2',
        ),
        previousName: 'amap-maps',
      );

      await Future<void>.delayed(Duration.zero);
      store.failNextSave();

      expect(await saveFuture, isFalse);
      expect(controller.servers.single.name, 'amap-maps');
      final restoredCatalog = controller.toolCatalogFor('amap-maps');
      expect(restoredCatalog.status, McpToolCatalogStatus.ready);
      expect(restoredCatalog.tools, hasLength(1));
      expect(restoredCatalog.tools.single.id, 'search_orders');
      expect(
        controller.toolCatalogFor('renamed-amap').status,
        McpToolCatalogStatus.idle,
      );
    },
  );
}

class _QueuedMcpStore extends McpStore {
  _QueuedMcpStore({required List<McpServer> initialServers})
    : _persistedServers = List<McpServer>.from(initialServers),
      super(serversFilePath: '/tmp/openhand-test-mcp.json');

  List<McpServer> _persistedServers;
  int loadCallCount = 0;
  final List<_PendingMcpSave> _pendingSaves = <_PendingMcpSave>[];
  final List<Completer<void>> _pendingLoads = <Completer<void>>[];
  bool _blockLoads = false;

  int get pendingSaveCount => _pendingSaves.length;
  int get pendingLoadCount => _pendingLoads.length;

  @override
  Future<McpLoadResult> load() async {
    loadCallCount += 1;
    if (_blockLoads) {
      final completer = Completer<void>();
      _pendingLoads.add(completer);
      _blockLoads = false;
      await completer.future;
    }
    return McpLoadResult(servers: List<McpServer>.from(_persistedServers));
  }

  @override
  Future<void> save(List<McpServer> servers) {
    final completer = Completer<void>();
    _pendingSaves.add(
      _PendingMcpSave(
        completer: completer,
        servers: List<McpServer>.from(servers),
      ),
    );
    return completer.future;
  }

  void completeNextSave() {
    final pendingSave = _pendingSaves.removeAt(0);
    _persistedServers = pendingSave.servers;
    pendingSave.completer.complete();
  }

  void failNextSave([Object error = 'save failed']) {
    final pendingSave = _pendingSaves.removeAt(0);
    pendingSave.completer.completeError(error);
  }

  void blockNextLoad() {
    _blockLoads = true;
  }

  void completeNextLoad() {
    final completer = _pendingLoads.removeAt(0);
    completer.complete();
  }
}

class _PendingMcpSave {
  const _PendingMcpSave({required this.completer, required this.servers});

  final Completer<void> completer;
  final List<McpServer> servers;
}

class _FakeMcpToolDiscoveryService implements McpToolDiscoveryService {
  final List<String> requestedServerNames = <String>[];
  final List<String> requestedHealthServerNames = <String>[];
  final List<McpToolCatalog> _queuedResults = <McpToolCatalog>[];
  final List<Completer<McpToolCatalog>> _pendingRequests =
      <Completer<McpToolCatalog>>[];
  final List<McpServerHealth> _queuedHealthResults = <McpServerHealth>[];
  final List<Completer<McpServerHealth>> _pendingHealthRequests =
      <Completer<McpServerHealth>>[];

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) {
    requestedServerNames.add(server.name);
    if (_queuedResults.isNotEmpty) {
      return Future<McpToolCatalog>.value(_queuedResults.removeAt(0));
    }
    final completer = Completer<McpToolCatalog>();
    _pendingRequests.add(completer);
    return completer.future;
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) {
    requestedHealthServerNames.add(server.name);
    if (_queuedHealthResults.isNotEmpty) {
      return Future<McpServerHealth>.value(_queuedHealthResults.removeAt(0));
    }
    final completer = Completer<McpServerHealth>();
    _pendingHealthRequests.add(completer);
    return completer.future;
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    return Future<McpToolCallResult>.value(
      const McpToolCallResult(outputText: 'fake-mcp-tool-result'),
    );
  }

  void queueResult(McpToolCatalog catalog) {
    _queuedResults.add(catalog);
  }

  void completeNext(McpToolCatalog catalog) {
    final completer = _pendingRequests.removeAt(0);
    completer.complete(catalog);
  }

  void queueHealthResult(McpServerHealth health) {
    _queuedHealthResults.add(health);
  }

  void completeNextHealth(McpServerHealth health) {
    final completer = _pendingHealthRequests.removeAt(0);
    completer.complete(health);
  }

  @override
  void dispose() {}
}
