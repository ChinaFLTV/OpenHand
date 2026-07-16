import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_keyword_index.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

const _server = McpServer(
  name: '刷新测试服务',
  type: McpServerType.streamableHttp,
  enabled: true,
  url: 'https://mcp.example.test/v1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('手动刷新立即清空旧目录并完整替换参数结构', () async {
    final fixture = await _ControllerFixture.create();
    addTearDown(fixture.dispose);
    fixture.discovery.nextCatalog = _catalogWithParameter('旧参数');
    await fixture.controller.refreshServerTools(_server.name);

    final pending = Completer<McpToolCatalog>();
    fixture.discovery.pendingCatalog = pending;
    final refresh = fixture.controller.refreshServerTools(_server.name);

    final loading = fixture.controller.toolCatalogFor(_server.name);
    expect(loading.status, McpToolCatalogStatus.loading);
    expect(loading.tools, isEmpty);

    pending.complete(_catalogWithParameter('新参数'));
    await refresh;
    final refreshed = fixture.controller.toolCatalogFor(_server.name);
    expect(refreshed.status, McpToolCatalogStatus.ready);
    expect(_parameterNames(refreshed), {'新参数'});
  });

  test('刷新失败不会回填旧 Tool 数据', () async {
    final fixture = await _ControllerFixture.create();
    addTearDown(fixture.dispose);
    fixture.discovery.nextCatalog = _catalogWithParameter('旧参数');
    await fixture.controller.refreshServerTools(_server.name);

    fixture.discovery.nextCatalog = McpToolCatalog(
      status: McpToolCatalogStatus.failed,
      errorMessage: '服务端刷新失败',
      lastScannedAt: DateTime.now().toUtc(),
    );
    await fixture.controller.refreshServerTools(_server.name);

    final failed = fixture.controller.toolCatalogFor(_server.name);
    expect(failed.status, McpToolCatalogStatus.failed);
    expect(failed.tools, isEmpty);
    expect(failed.errorMessage, '服务端刷新失败');
  });

  test('自动刷新保留可用目录直到新目录原子替换', () async {
    final fixture = await _ControllerFixture.create();
    addTearDown(fixture.dispose);
    fixture.discovery.nextCatalog = _catalogWithParameter('当前参数');
    await fixture.controller.refreshServerTools(_server.name);

    final pending = Completer<McpToolCatalog>();
    fixture.discovery.pendingCatalog = pending;
    final refresh = fixture.controller.refreshServerTools(
      _server.name,
      clearCachedTools: false,
    );

    final duringRefresh = fixture.controller.toolCatalogFor(_server.name);
    expect(duringRefresh.status, McpToolCatalogStatus.ready);
    expect(_parameterNames(duringRefresh), {'当前参数'});

    pending.complete(_catalogWithParameter('自动更新参数'));
    await refresh;
    expect(_parameterNames(fixture.controller.toolCatalogFor(_server.name)), {
      '自动更新参数',
    });
  });

  test('关键词索引只替换目标服务的 Tool 数据', () {
    final index = McpKeywordIndex(
      byName: const <String, List<McpToolRef>>{
        '旧参数': <McpToolRef>[
          McpToolRef(serverName: '目标服务', toolId: 'old', toolName: '旧工具'),
        ],
        '保留参数': <McpToolRef>[
          McpToolRef(serverName: '其他服务', toolId: 'keep', toolName: '保留工具'),
        ],
      },
      byDescription: const <String, List<McpToolRef>>{},
      bySearchHint: const <String, List<McpToolRef>>{},
      totalTools: 2,
      totalServers: 2,
      builtAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      durationMs: 1,
    );

    final replaced = index.replaceServerTools(
      serverName: '目标服务',
      tools: <McpTool>[
        const McpTool(
          id: 'new',
          name: '新参数',
          description: '',
          inputSchema: <String, Object?>{'type': 'object'},
        ),
      ],
    );

    expect(replaced.byName, isNot(contains('旧参数')));
    expect(replaced.byName['保留参数']?.single.serverName, '其他服务');
    expect(replaced.byName['新参数']?.single.toolId, 'new');
    expect(replaced.totalTools, 2);
    expect(replaced.totalServers, 2);
  });

  test('落盘关键词索引按顺序清除并写入目标服务新目录', () async {
    final directory = await Directory.systemTemp.createTemp(
      'openhand_mcp_index_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final service = McpKeywordIndexService(storageDir: directory);
    const otherServer = McpServer(
      name: '其他服务',
      type: McpServerType.streamableHttp,
      enabled: true,
      url: 'https://other.example.test/v1',
    );
    await service.build(
      servers: const <McpServer>[_server, otherServer],
      resolveTools: (server) => <McpTool>[
        McpTool(
          id: server.name,
          name: server.name == _server.name ? '旧目录' : '保留目录',
          description: '',
          inputSchema: const <String, Object?>{'type': 'object'},
        ),
      ],
      onProgress: (_) {},
    );

    await service.replacePersistedServerTools(
      serverName: _server.name,
      tools: const <McpTool>[
        McpTool(
          id: 'new',
          name: '全新目录',
          description: '',
          inputSchema: <String, Object?>{'type': 'object'},
        ),
      ],
    );
    final loaded = await service.loadFromDisk();

    expect(loaded, isNotNull);
    expect(loaded!.byName, isNot(contains('旧目录')));
    expect(loaded.byName, contains('全新目录'));
    expect(loaded.byName, contains('保留目录'));
  });
}

McpToolCatalog _catalogWithParameter(String parameterName) {
  return McpToolCatalog(
    status: McpToolCatalogStatus.ready,
    tools: <McpTool>[
      McpTool(
        id: 'query',
        name: 'query',
        description: '查询工具',
        inputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            parameterName: <String, Object?>{'type': 'string'},
          },
        },
      ),
    ],
    lastScannedAt: DateTime.now().toUtc(),
  );
}

Set<String> _parameterNames(McpToolCatalog catalog) {
  final properties = catalog.tools.single.inputSchema['properties'];
  return properties is Map
      ? properties.keys.map((key) => '$key').toSet()
      : const <String>{};
}

class _ControllerFixture {
  _ControllerFixture({
    required this.directory,
    required this.controller,
    required this.discovery,
  });

  final Directory directory;
  final McpController controller;
  final _FakeDiscoveryService discovery;

  static Future<_ControllerFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'openhand_mcp_refresh_',
    );
    final filePath = '${directory.path}/mcp.json';
    final store = McpStore(serversFilePath: filePath);
    await store.load();
    await store.save(const <McpServer>[_server]);
    final discovery = _FakeDiscoveryService();
    final controller = await McpController.create(
      initialFilePath: filePath,
      store: store,
      toolDiscoveryService: discovery,
    );
    return _ControllerFixture(
      directory: directory,
      controller: controller,
      discovery: discovery,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await directory.delete(recursive: true);
  }
}

class _FakeDiscoveryService implements McpToolDiscoveryService {
  McpToolCatalog nextCatalog = const McpToolCatalog();
  Completer<McpToolCatalog>? pendingCatalog;

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) {
    final pending = pendingCatalog;
    pendingCatalog = null;
    return pending?.future ?? Future<McpToolCatalog>.value(nextCatalog);
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
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
    return const McpToolCallResult(outputText: '完成');
  }

  @override
  void dispose() {}
}
