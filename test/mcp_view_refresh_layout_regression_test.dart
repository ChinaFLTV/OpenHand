import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';
import 'package:openhand/features/mcp/widgets/mcp_view.dart';
import 'package:openhand/features/thread_template_runtime/template_runtime_linkage_controller.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory directory;
  late _RefreshLayoutDiscoveryService discovery;
  late McpController controller;
  late SettingsController settings;
  late TemplateRuntimeLinkageController linkage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'openhand_mcp_layout_test_',
    );
    discovery = _RefreshLayoutDiscoveryService();
    controller = await McpController.create(
      initialFilePath: '${directory.path}/mcp.json',
      store: McpStore(serversFilePath: '${directory.path}/mcp.json'),
      toolDiscoveryService: discovery,
    );
    settings = await SettingsController.create(store: _MemorySettingsStore());
    linkage = TemplateRuntimeLinkageController();

    const server = McpServer(
      name: 'layout-server',
      type: McpServerType.streamableHttp,
      enabled: true,
      probeEnabled: false,
      url: 'https://example.com/mcp',
    );
    expect(await controller.saveServer(server), isTrue);
    await controller.refreshServerTools(server.name);
  });

  tearDown(() async {
    controller.dispose();
    settings.dispose();
    linkage.dispose();
    await directory.delete(recursive: true);
  });

  Future<Finder> pumpMcpView(WidgetTester tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: linkage),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: McpView()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    final card = find.byKey(
      const ValueKey<String>('mcp-server-card-layout-server'),
    );
    final serverList = find.descendant(
      of: find.byKey(const ValueKey<String>('mcp-list')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(card, 400, scrollable: serverList.first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(card, findsOneWidget);
    return card;
  }

  testWidgets('自动刷新改变卡片高度时不创建隐式尺寸动画', (tester) async {
    final card = await pumpMcpView(tester);
    expect(
      find.descendant(of: card, matching: find.byType(AnimatedSize)),
      findsNothing,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final cardCenter = tester.getCenter(card);
    await mouse.addPointer(location: cardCenter);
    discovery.failNextRefresh = true;
    final refresh = controller.refreshServerTools(
      'layout-server',
      clearCachedTools: false,
    );
    await tester.pump(Duration.zero, EnginePhase.build);
    await refresh;
    await tester.pump(Duration.zero, EnginePhase.build);
    await tester.pump(const Duration(milliseconds: 80), EnginePhase.build);
    await mouse.moveTo(cardCenter + const Offset(1, 0));

    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await mouse.removePointer();
  });

  testWidgets('胶囊数量较少时仍从卡片左侧起排', (tester) async {
    final card = await pumpMcpView(tester);
    final toggleChip = find.ancestor(
      of: find.descendant(
        of: card,
        matching: find.byIcon(Icons.check_circle_outline_rounded),
      ),
      matching: find.byType(ActionChip),
    );

    expect(toggleChip, findsOneWidget);
    expect(
      tester.getTopLeft(toggleChip).dx,
      closeTo(tester.getTopLeft(card).dx + 24, 0.5),
    );
  });

  testWidgets('探测状态胶囊先连续补位再弹性插入', (tester) async {
    final card = await pumpMcpView(tester);
    final latencyChip = find.descendant(
      of: card,
      matching: find.byIcon(Icons.speed_rounded),
    );
    final attentionChip = find.descendant(
      of: card,
      matching: find.byIcon(Icons.priority_high_rounded),
    );

    await controller.checkServerHealth('layout-server');
    await tester.pumpAndSettle();
    expect(latencyChip, findsOneWidget);

    discovery.healthStatus = McpServerHealthStatus.unhealthy;
    for (var attempt = 0; attempt < 3; attempt++) {
      await controller.checkServerHealth('layout-server');
      for (var frame = 0; frame < 18; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
    }
    expect(attentionChip, findsOneWidget);
    expect(latencyChip, findsNothing);

    discovery.healthStatus = McpServerHealthStatus.healthy;
    await controller.checkServerHealth('layout-server');
    await tester.pump();
    expect(attentionChip, findsOneWidget);
    expect(latencyChip, findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    expect(attentionChip, findsOneWidget);
    expect(latencyChip, findsNothing);
    final exitingFadeTransitions = tester.widgetList<FadeTransition>(
      find.ancestor(of: attentionChip, matching: find.byType(FadeTransition)),
    );
    expect(exitingFadeTransitions, isNotEmpty);
    for (final transition in exitingFadeTransitions) {
      expect(transition.opacity.value, closeTo(1, 0.001));
    }

    await tester.pumpAndSettle();
    expect(attentionChip, findsNothing);
    expect(latencyChip, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MemorySettingsStore extends SettingsStore {
  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(
      snapshot: AppSettingsSnapshot.defaults(),
      canPersist: true,
    );
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {}
}

class _RefreshLayoutDiscoveryService implements McpToolDiscoveryService {
  bool failNextRefresh = false;
  McpServerHealthStatus healthStatus = McpServerHealthStatus.healthy;

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    if (failNextRefresh) {
      failNextRefresh = false;
      throw StateError('模拟工具目录刷新失败');
    }
    return McpToolCatalog(
      status: McpToolCatalogStatus.ready,
      tools: const [
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
    return McpServerHealth(status: healthStatus);
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
