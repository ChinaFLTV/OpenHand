import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:openhand/app/model/app_language.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/mcp_view.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  testWidgets('McpView saves request headers through key-value rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settingsController = await SettingsController.create(
      store: _InMemorySettingsStore(),
    );
    final mcpStore = _InMemoryMcpStore();
    final mcpController = await McpController.create(
      initialFilePath: mcpStore.serversFilePath,
      store: mcpStore,
      toolDiscoveryService: _FakeMcpToolDiscoveryService(),
      healthCheckInterval: const Duration(days: 1),
    );
    addTearDown(settingsController.dispose);
    addTearDown(mcpController.dispose);
    await settingsController.updateLanguage(AppLanguage.english);

    await tester.pumpWidget(
      _buildTestApp(
        settingsController: settingsController,
        mcpController: mcpController,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('New Server'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Ops');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'https://api.example.com/mcp',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('mcpHeaderNameField-0')),
      'Authorization',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('mcpHeaderValueField-0')),
      'Bearer secret-token',
    );

    await tester.tap(find.byKey(const ValueKey<String>('mcpHeaderAddButton')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey<String>('mcpHeaderNameField-1')),
      'X-Workspace',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('mcpHeaderValueField-1')),
      'openhand',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('mcpHeaderRemoveButton-1')),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('mcpHeaderAddButton')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey<String>('mcpHeaderNameField-1')),
      'X-Workspace',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('mcpHeaderValueField-1')),
      'openhand',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(mcpController.servers, hasLength(1));
    expect(mcpController.servers.single.headers, <String, String>{
      'Authorization': 'Bearer secret-token',
      'X-Workspace': 'openhand',
    });
  });

  testWidgets('McpView renders markdown tool descriptions without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settingsController = await SettingsController.create(
      store: _InMemorySettingsStore(),
    );
    final mcpStore = _InMemoryMcpStore(
      servers: <McpServer>[
        const McpServer(
          name: 'Grafana',
          type: McpServerType.streamableHttp,
          enabled: true,
          url: 'https://api.example.com/mcp',
        ),
      ],
    );
    final mcpController = await McpController.create(
      initialFilePath: mcpStore.serversFilePath,
      store: mcpStore,
      toolDiscoveryService: _FakeMcpToolDiscoveryService(
        toolsByServer: <String, List<McpTool>>{
          'Grafana': <McpTool>[
            const McpTool(
              id: 'grafana_query_from_url',
              name: 'grafana_query_from_url',
              description: '''
从 Grafana/Thanos 面板 URL 查询监控数据，并返回完整查询结果。

## 适用场景
- 查询特定面板的监控指标
- 分析系统性能数据
- 获取实时监控信息

## 参数说明
- `url`: Grafana/Thanos 面板的完整 URL（必需）
- `time_from`: 查询开始时间（可选）
- `time_to`: 查询结束时间（可选）

## 常用示例
- 最近 1 小时：`time_from='now-1h'`
- 最近 24 小时：`time_from='now-1d'`
- 指定日期：`time_from='2024-01-01T00:00:00Z'`
''',
              inputSchema: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{},
              },
            ),
          ],
        },
      ),
      healthCheckInterval: const Duration(days: 1),
    );
    addTearDown(settingsController.dispose);
    addTearDown(mcpController.dispose);
    await settingsController.updateLanguage(AppLanguage.english);
    await mcpController.refreshServerTools('Grafana');

    await tester.pumpWidget(
      _buildTestApp(
        settingsController: settingsController,
        mcpController: mcpController,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('grafana_query_from_url'));
    await tester.pump();

    expect(find.text('查询特定面板的监控指标'), findsOneWidget);
    expect(
      find.textContaining('Tool ID: grafana_query_from_url'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _buildTestApp({
  required SettingsController settingsController,
  required McpController mcpController,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
      ),
      ChangeNotifierProvider<McpController>.value(value: mcpController),
    ],
    child: MaterialApp(
      locale: settingsController.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: OpenHandTheme.light(OpenHandThemePreset.deepSeaBlue),
      home: const Scaffold(body: McpView()),
    ),
  );
}

class _InMemorySettingsStore extends SettingsStore {
  _InMemorySettingsStore() : super(settingsFilePath: '/tmp/mcp-view-test.toml');

  AppSettingsSnapshot _snapshot = AppSettingsSnapshot.defaults();

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: _snapshot);
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}

class _InMemoryMcpStore extends McpStore {
  _InMemoryMcpStore({List<McpServer> servers = const <McpServer>[]})
    : _servers = List<McpServer>.from(servers),
      super(serversFilePath: '/tmp/mcp-view-test.json');

  List<McpServer> _servers;

  @override
  Future<McpLoadResult> load() async {
    return McpLoadResult(servers: List<McpServer>.unmodifiable(_servers));
  }

  @override
  Future<void> save(List<McpServer> servers) async {
    _servers = List<McpServer>.from(servers);
  }
}

class _FakeMcpToolDiscoveryService implements McpToolDiscoveryService {
  _FakeMcpToolDiscoveryService({
    this.toolsByServer = const <String, List<McpTool>>{},
  });

  final Map<String, List<McpTool>> toolsByServer;

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    return McpToolCatalog(
      status: McpToolCatalogStatus.ready,
      tools: toolsByServer[server.name] ?? const <McpTool>[],
      lastScannedAt: DateTime.utc(2026, 3, 25, 4, 0, 0),
    );
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    return McpServerHealth(
      status: McpServerHealthStatus.healthy,
      lastCheckedAt: DateTime.utc(2026, 3, 25, 4, 0, 0),
    );
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    return const McpToolCallResult(outputText: '');
  }

  @override
  void dispose() {}
}
