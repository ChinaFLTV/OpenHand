import 'dart:io';

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
  late McpController controller;
  late SettingsController settings;
  late TemplateRuntimeLinkageController linkage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'openhand_mcp_scroll_test_',
    );
    controller = McpController.uninitialized(
      initialFilePath: '${directory.path}/mcp.json',
      store: McpStore(serversFilePath: '${directory.path}/mcp.json'),
      toolDiscoveryService: _FailingHealthDiscoveryService(),
    );
    await controller.refresh();
    settings = await SettingsController.create(store: _MemorySettingsStore());
    linkage = TemplateRuntimeLinkageController();

    for (var index = 1; index <= 4; index++) {
      expect(
        await controller.saveServer(
          McpServer(
            name: 'server-$index',
            type: McpServerType.streamableHttp,
            enabled: true,
            probeEnabled: false,
            url: 'https://example.com/mcp/$index',
          ),
        ),
        isTrue,
      );
    }
  });

  tearDown(() async {
    await controller.shutdown();
    settings.dispose();
    linkage.dispose();
    await directory.delete(recursive: true);
  });

  testWidgets('到达底部后跟随卡片增高，向上滚动后保持阅读位置', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1600, 900));
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
    await tester.pump(const Duration(milliseconds: 500));

    final list = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.controller?.debugLabel == 'MCP 服务列表',
    );
    expect(list, findsOneWidget);

    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.fling(list, const Offset(0, -2400), 8000);
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));

    final previousMaxExtent = position.maxScrollExtent;
    await controller.checkServerHealth('server-4', preserveCurrentStatus: true);
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
    }
    await tester.pumpAndSettle();

    expect(position.maxScrollExtent, greaterThan(previousMaxExtent));
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));

    await tester.drag(list, const Offset(0, 400));
    await tester.pumpAndSettle();
    final readingOffset = position.pixels;
    expect(position.extentAfter, greaterThan(100));

    await controller.checkServerHealth('server-3', preserveCurrentStatus: true);
    await tester.pumpAndSettle();

    expect(position.pixels, closeTo(readingOffset, 0.5));
    expect(
      find.byKey(const ValueKey<String>('mcp-server-card-server-3')),
      findsOneWidget,
    );
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

class _FailingHealthDiscoveryService implements McpToolDiscoveryService {
  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    return const McpToolCatalog();
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    return const McpServerHealth(
      status: McpServerHealthStatus.unhealthy,
      errorMessage: '模拟健康检查失败，用于验证后台状态更新不会抢占用户滚动位置。',
    );
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
