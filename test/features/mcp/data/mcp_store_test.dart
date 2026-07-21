import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

class _UnusedMcpToolDiscoveryService implements McpToolDiscoveryService {
  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('测试不应调用 MCP 服务');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late File configFile;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_mcp_store_test_',
    );
    configFile = File('${tempDirectory.path}/mcp.json');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> writeServers(Map<String, Object?> servers) {
    return configFile.writeAsString(
      jsonEncode(<String, Object?>{'mcpServers': servers}),
    );
  }

  test('普通旧配置缺少字段时保持全部可见', () async {
    await writeServers(<String, Object?>{
      'Custom MCP': <String, Object?>{'type': 'stdio', 'command': 'custom-mcp'},
    });

    final result = await McpStore(serversFilePath: configFile.path).load();

    expect(result.canPersist, isTrue);
    expect(result.servers.single.visibleTemplateIds, isNull);
  });

  test('内置旧配置缺少字段时应用专属模板映射', () async {
    const expected = <String, String>{
      'Web Reverse CDP MCP': 'web_reverse_expert',
      'Playwright MCP': 'web_reverse_expert',
      'JS Reverse MCP': 'web_reverse_expert',
      'Android ADB MCP': 'android_reverse_expert',
      'Android Frida MCP': 'android_reverse_expert',
      'Anything Analyzer MCP': 'android_reverse_expert',
    };
    await writeServers(<String, Object?>{
      for (final name in expected.keys)
        name: <String, Object?>{'type': 'stdio', 'command': 'npx'},
    });

    final result = await McpStore(serversFilePath: configFile.path).load();

    expect(result.canPersist, isTrue);
    for (final entry in expected.entries) {
      final server = result.servers.singleWhere(
        (item) => item.name == entry.key,
      );
      expect(server.visibleTemplateIds, <String>{entry.value});
    }
  });

  test('显式模板集合去重并按稳定顺序往返持久化', () async {
    await writeServers(<String, Object?>{
      'Custom MCP': <String, Object?>{
        'type': 'stdio',
        'command': 'custom-mcp',
        'visibleTemplateIds': <String>[
          'programming_expert',
          'default',
          'programming_expert',
        ],
      },
    });
    final store = McpStore(serversFilePath: configFile.path);
    final firstLoad = await store.load();

    expect(firstLoad.canPersist, isTrue);
    expect(firstLoad.servers.single.visibleTemplateIds, <String>{
      'default',
      'programming_expert',
    });

    await store.save(firstLoad.servers);
    final savedRoot = jsonDecode(await configFile.readAsString()) as Map;
    final savedServers = savedRoot['mcpServers'] as Map;
    final savedServer = savedServers['Custom MCP'] as Map;
    expect(savedServer['visibleTemplateIds'], <String>[
      'default',
      'programming_expert',
    ]);

    final secondLoad = await McpStore(serversFilePath: configFile.path).load();
    expect(secondLoad.canPersist, isTrue);
    expect(secondLoad.servers.single.visibleTemplateIds, <String>{
      'default',
      'programming_expert',
    });
  });

  test('内置服务的显式多模板配置优先于默认映射', () async {
    await writeServers(<String, Object?>{
      'Web Reverse CDP MCP': <String, Object?>{
        'type': 'stdio',
        'command': 'npx',
        'visibleTemplateIds': <String>['default', 'web_reverse_expert'],
      },
    });

    final result = await McpStore(serversFilePath: configFile.path).load();

    expect(result.canPersist, isTrue);
    expect(result.servers.single.visibleTemplateIds, <String>{
      'default',
      'web_reverse_expert',
    });
  });

  test('内置服务显式全部可见可稳定往返', () async {
    final store = McpStore(serversFilePath: configFile.path);
    final initialLoad = await store.load();
    expect(initialLoad.canPersist, isTrue);

    await store.save(const <McpServer>[
      McpServer(
        name: 'Playwright MCP',
        type: McpServerType.stdio,
        enabled: true,
        command: 'npx',
      ),
    ]);

    final savedRoot = jsonDecode(await configFile.readAsString()) as Map;
    final savedServer =
        (savedRoot['mcpServers'] as Map)['Playwright MCP'] as Map;
    expect(savedServer.containsKey('visibleTemplateIds'), isTrue);
    expect(savedServer['visibleTemplateIds'], isNull);

    final result = await store.load();
    expect(result.canPersist, isTrue);
    expect(result.servers.single.visibleTemplateIds, isNull);
  });

  test('空集合或非字符串数组会拒绝加载', () async {
    final invalidValues = <Object?>[
      <String>[],
      <Object?>['default', 1],
      <String>[''],
      <String>[' default'],
    ];

    for (final value in invalidValues) {
      await writeServers(<String, Object?>{
        'Custom MCP': <String, Object?>{
          'type': 'stdio',
          'command': 'custom-mcp',
          'visibleTemplateIds': value,
        },
      });
      final result = await McpStore(serversFilePath: configFile.path).load();

      expect(result.canPersist, isFalse);
      expect(result.issue?.kind, McpPersistenceIssueKind.invalidContent);
    }
  });

  test('保存时再次拒绝被外部清空的显式集合', () async {
    final store = McpStore(serversFilePath: configFile.path);
    final loadResult = await store.load();
    expect(loadResult.canPersist, isTrue);
    final visibleTemplateIds = <String>{'default'};
    final server = McpServer(
      name: 'Custom MCP',
      type: McpServerType.stdio,
      enabled: true,
      command: 'custom-mcp',
      visibleTemplateIds: visibleTemplateIds,
    );
    visibleTemplateIds.clear();

    expect(
      () => store.save(<McpServer>[server]),
      throwsA(isA<FormatException>()),
    );
  });

  test('控制器保存时冻结模板可见性集合', () async {
    final controller = await McpController.create(
      initialFilePath: configFile.path,
      toolDiscoveryService: _UnusedMcpToolDiscoveryService(),
      healthCheckInterval: const Duration(days: 1),
    );
    final visibleTemplateIds = <String>{'default'};
    try {
      final saveFuture = controller.saveServer(
        McpServer(
          name: 'Custom MCP',
          type: McpServerType.stdio,
          enabled: false,
          command: 'custom-mcp',
          visibleTemplateIds: visibleTemplateIds,
        ),
      );
      visibleTemplateIds
        ..clear()
        ..add('web_reverse_expert');
      expect(await saveFuture, isTrue);

      expect(controller.servers.single.visibleTemplateIds, <String>{'default'});
    } finally {
      await controller.shutdown();
    }
  });
}
