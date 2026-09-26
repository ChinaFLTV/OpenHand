import 'dart:io';

import 'support/flutter_widget_check.dart';

/// 直接验证页面内的私有工具预览，避免为测试扩展生产接口。
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final page = File('${root.path}/lib/features/mcp/widgets/mcp_view.dart');
  final libUri = Directory('${root.path}/lib/').uri;
  final source = (await page.readAsString()).replaceAllMapped(
    RegExp("import '([^']+)'"),
    (match) {
      if (match[1]!.contains(':')) return match[0]!;
      final relative = page.uri
          .resolve(match[1]!)
          .path
          .substring(libUri.path.length);
      return "import 'package:openhand/$relative'";
    },
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'mcp_preview',
    source:
        "import 'package:flutter_test/flutter_test.dart';\n"
        "import 'package:openhand/app/state/settings_store.dart';\n"
        "import 'package:openhand/app/model/app_settings_snapshot.dart';\n"
        // 授权面板使用固定高度占位，检查真实卡片布局且不读取本机凭证。
        "${source.replaceAll('McpOAuthPanel(', '_PreviewOAuthPanel(')}\n$_checks",
  );
}

const _checks = r'''
class _PreviewOAuthPanel extends StatelessWidget {
  const _PreviewOAuthPanel({required this.server, this.onAuthorized});
  final McpServer server;
  final VoidCallback? onAuthorized;
  @override
  Widget build(BuildContext context) => const SizedBox(height: 68, child: Text('授权状态'));
}

class _PreviewSettingsStore extends SettingsStore {
  _PreviewSettingsStore(this.animated);
  final bool animated;
  @override
  Future<SettingsLoadResult> load() async => SettingsLoadResult(
    snapshot: AppSettingsSnapshot.defaults().copyWith(
      chipAnimationSettings: animated
          ? OpenHandMotionDefaults.chip : OpenHandMotionDefaults.disabled,
    ),
    canPersist: false,
  );
}

const _cdnNames = [
  'cdn_domain_blocked_check', 'cdn_domain_config_query',
  'cdn_domain_meta_query', 'cdn_governance_scan',
  'cdn_ip_info_query', 'cdn_log_download', 'cdn_domain_query_tool',
];

McpTool _tool(String name) => McpTool(
  id: name, name: name, description: '用于布局回归的工具', inputSchema: const {},
);

class _PreviewProbe {
  _PreviewProbe(this.tester);
  final WidgetTester tester;
  late SettingsController settings;
  late StateSetter rebuild;
  String keyword = '';
  double width = 1560;
  double scale = 1;
  List<McpTool> tools = [
    ..._cdnNames.map(_tool),
    ...List.generate(64, (index) => _tool('cache_tool_$index')),
  ];
  _McpToolPreviewState get state => tester.state<_McpToolPreviewState>(find.byType(_McpToolPreview));

  Future<void> mount({bool animated = true}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = await SettingsController.create(store: _PreviewSettingsStore(animated));
    await tester.pumpWidget(ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: Card(child: Padding(
                padding: const EdgeInsets.all(18),
                child: _McpToolPreview(
                  server: const McpServer(name: '测试服务', type: McpServerType.streamableHttp,
                    enabled: true, url: 'https://example.com/mcp'),
                  toolCatalog: McpToolCatalog(status: McpToolCatalogStatus.ready, tools: tools),
                  searchKeyword: keyword,
                ),
              ))),
            )),
          );
        })),
      ),
    ));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      settings.dispose();
    });
    await settle();
  }

  Future<void> settle() async {
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);
  }

  Future<void> search(String value) async {
    rebuild(() => keyword = value);
    await settle();
  }

  Future<void> toggle() async {
    await tester.tap(find.text(state._expanded ? '收起' : '展开'));
    await settle();
  }
}

void main() {
  for (final animated in [false, true]) {
    testWidgets('筛选跨过八项阈值后，溢出工具仍可展开，动画=$animated', (tester) async {
      final probe = _PreviewProbe(tester);
      await probe.mount(animated: animated);
      await probe.search('c');
      expect(find.text('展开'), findsOneWidget);
      await probe.search('cd');
      expect(find.text('展开'), findsOneWidget, reason: '七个长名称仍会溢出，不能仅按数量隐藏按钮');
      await probe.search('cdn_log');
      expect(find.text('展开'), findsNothing);
      await probe.search('无匹配');
      expect(find.text('没有匹配的 Tool'), findsOneWidget);
      expect(find.text('展开'), findsNothing);
      await probe.search('cdn');
      expect(find.text('展开'), findsOneWidget);
      final button = tester.getRect(find.byType(TextButton));
      final strip = tester.getRect(find.byType(_McpHorizontalChipStrip));
      expect(strip.top - button.bottom, greaterThanOrEqualTo(12), reason: '操作胶囊和工具区保留清晰间距');
    });

    testWidgets('展开高度按内容收缩，筛选不残留滚动空白，动画=$animated', (tester) async {
      final probe = _PreviewProbe(tester);
      await probe.mount(animated: animated);
      await probe.toggle();
      expect(probe.state._expandedScrollController.position.viewportDimension,
        closeTo(_mcpToolPreviewExpandedMaxHeight, 1));
      expect(probe.state._expandedScrollController.position.maxScrollExtent, greaterThan(0));
      probe.state._expandedScrollController.jumpTo(probe.state._expandedScrollController.position.maxScrollExtent);
      await probe.settle();
      await probe.search('cdn');
      expect(find.text('收起'), findsOneWidget);
      final wrap = tester.getRect(find.byType(OpenHandAnimatedChipWrap));
      final preview = tester.getRect(find.byType(_McpToolPreview));
      expect(preview.bottom - wrap.bottom, closeTo(0, 1), reason: '展开内容底部不保留固定高度空白');
      expect(wrap.height, lessThan(_mcpToolPreviewExpandedMaxHeight));
      expect(probe.state._expandedScrollController.position.maxScrollExtent, closeTo(0, 1));
      expect(probe.state._expandedScrollController.offset, closeTo(0, 1));
      await probe.search('cdn_log');
      expect(tester.getSize(find.byType(OpenHandAnimatedChipWrap)).height, lessThan(wrap.height));
      await probe.search('无匹配');
      expect(find.text('没有匹配的 Tool'), findsOneWidget);
      expect(tester.getSize(find.byType(_McpToolPreview)).height, lessThan(preview.height));
      await probe.toggle();
      expect(find.text('收起'), findsNothing);
    });
  }

  testWidgets('窗口宽度、文字缩放和目录更新均重新判断实际溢出', (tester) async {
    final probe = _PreviewProbe(tester)..tools = [_tool('cdn_domain_blocked_check')];
    await probe.mount(animated: false);
    expect(find.text('展开'), findsNothing);
    probe.rebuild(() => probe.width = 260);
    await probe.settle();
    expect(find.text('展开'), findsOneWidget, reason: '单个长工具也可切换到换行预览');
    probe.rebuild(() { probe.width = 380; probe.scale = 2; probe.tools = [_tool('cdn_log_download')]; });
    await probe.settle();
    await probe.toggle();
    expect(find.text('收起'), findsOneWidget);
    final button = tester.getRect(find.byType(TextButton));
    final wrap = tester.getRect(find.byType(OpenHandAnimatedChipWrap));
    expect(wrap.top - button.bottom, greaterThanOrEqualTo(12));
    await probe.toggle();
    probe.rebuild(() { probe.width = 1000; probe.scale = 1; });
    await probe.settle();
    expect(find.text('展开'), findsNothing);
    probe.rebuild(() => probe.tools = List.generate(9, (index) => _tool('工具$index')));
    await probe.settle();
    expect(find.text('展开'), findsOneWidget, reason: '数量截断时即使单行够宽也能展开');
    probe.rebuild(() => probe.tools = [_tool('短工具')]);
    await probe.settle();
    expect(find.text('展开'), findsNothing);
  });

  testWidgets('连续切换平滑收敛，关闭动效及卸载不遗留回调', (tester) async {
    final probe = _PreviewProbe(tester);
    await probe.mount();
    final initialHeight = tester.getSize(find.byType(_McpToolPreview)).height;
    await tester.tap(find.text('展开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final intermediateHeight = tester.getSize(find.byType(_McpToolPreview)).height;
    await probe.settle();
    final expandedHeight = tester.getSize(find.byType(_McpToolPreview)).height;
    expect(intermediateHeight, greaterThan(initialHeight));
    expect(intermediateHeight, lessThan(expandedHeight), reason: '展开通过连续高度过渡完成');
    for (var index = 0; index < 6; index++) {
      await tester.tap(find.text(probe.state._expanded ? '收起' : '展开'));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await probe.settle();
    expect(tester.getSize(find.byType(_McpToolPreview)).height, closeTo(expandedHeight, 1));
    await probe.settings.updateChipAnimationSettings(OpenHandMotionDefaults.disabled);
    await probe.settle();
    await probe.toggle();
    expect(tester.getSize(find.byType(_McpToolPreview)).height, closeTo(initialHeight, 1));
    probe.rebuild(() => probe.keyword = 'cdn');
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await probe.settle();
  });

  testWidgets('四千工具按需构建，滚动到底及筛选切换不残留空白', (tester) async {
    final probe = _PreviewProbe(tester)
      ..tools = List.generate(kMcpMaxCatalogToolCount, (index) => _tool('工具_$index'));
    await probe.mount();
    await probe.toggle();
    expect(find.byType(ActionChip).evaluate().length, lessThan(80),
      reason: '构建量只随视口变化，不能随目录总量增长');
    final controller = probe.state._expandedScrollController;
    controller.jumpTo(controller.position.maxScrollExtent);
    await probe.settle();
    expect(find.text('工具_${kMcpMaxCatalogToolCount - 1}'), findsOneWidget);
    expect(find.byType(ActionChip).evaluate().length, lessThan(80));
    await probe.search('工具_4095');
    expect(controller.offset, closeTo(0, 1));
    expect(find.text('工具_4095'), findsOneWidget);
    await probe.search('');
    probe.rebuild(() { probe.width = 260; probe.scale = 2; });
    await probe.settle();
    expect(find.byType(ActionChip).evaluate().length, lessThan(30));
    await probe.toggle();
    await probe.toggle();
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('无关刷新复用筛选结果，替换目录后更新工具内容', (tester) async {
    final probe = _PreviewProbe(tester);
    await probe.mount(animated: false);
    await probe.search('cdn');
    final filtered = probe.state._filteredTools;
    probe.rebuild(() {});
    await probe.settle();
    expect(identical(filtered, probe.state._filteredTools), isTrue);
    probe.rebuild(() => probe.tools = [_tool('cdn_新工具')]);
    await probe.settle();
    expect(find.text('cdn_新工具'), findsOneWidget);
    expect(find.text('cdn_domain_blocked_check'), findsNothing);
  });

  testWidgets('底部吸附不劫持位置且每帧最多修正一次', (tester) async {
    final controller = _McpBottomAnchoredScrollController(
      shouldKeepBottomAnchored: () => true,
      onUserScrollDirection: (_) {},
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView.builder(
      controller: controller,
      itemCount: 100,
      itemExtent: 100,
      itemBuilder: (_, index) => Text('服务 $index'),
    ))));
    final position = controller.position as _McpBottomAnchoredScrollPosition;
    FixedScrollMetrics metrics(double maxExtent, double pixels) => FixedScrollMetrics(
      minScrollExtent: 0, maxScrollExtent: maxExtent, pixels: pixels,
      viewportDimension: 600, axisDirection: AxisDirection.down, devicePixelRatio: 1,
    );
    position.correctPixels(400);
    position.correctForNewDimensions(metrics(1000, 400), metrics(1200, 400));
    expect(position.pixels, 400, reason: '未贴底时保持阅读位置');
    position.correctForNewDimensions(metrics(400, 400), metrics(400, 400));
    expect(position.pixels, 400, reason: '尺寸未变时不强制校正');
    position.correctPixels(1000);
    expect(position.correctForNewDimensions(metrics(1000, 1000), metrics(1200, 1000)), isFalse);
    expect(position.pixels, 1200);
    position.correctForNewDimensions(metrics(1200, 1200), metrics(1400, 1200));
    expect(position.pixels, 1200, reason: '估算变化不能在同一帧反复追逐底部');
    await tester.pump();
    final gesture = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(position.isScrollingNotifier.value, isTrue);
    position.correctPixels(1000);
    position.correctForNewDimensions(metrics(1000, 1000), metrics(1200, 1000));
    expect(position.pixels, 1000, reason: '拖动优先于底部吸附');
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    expect(tester.takeException(), isNull);
  });


  testWidgets('两百张真实服务卡片快速往返滚动仍保持懒构建', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = await SettingsController.create(store: _PreviewSettingsStore(true));
    final directory = await tester.runAsync(() => Directory.systemTemp.createTemp('mcp_scroll_'));
    final mcp = (await tester.runAsync(() async =>
      McpController.uninitialized(initialFilePath: '${directory!.path}/mcp.json')))!;
    final catalog = McpToolCatalog(status: McpToolCatalogStatus.ready,
      tools: List.generate(41, (index) => _tool('工具_$index')));
    var builds = 0;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<McpController>.value(value: mcp),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: _AnimatedMcpServerList(
          servers: List.generate(200, (index) => McpServer(
            name: '服务_$index', type: McpServerType.streamableHttp,
            enabled: true, url: 'https://example.com/mcp',
            extraFields: index.isEven ? const {'oauth': {'enabled': true}} : const {},
          )),
          prefixChildren: const [], emptyChild: const Text('暂无服务'),
          itemBuilder: (context, server, health, tools) {
            builds++;
            return _McpServerCard(
              server: server, healthStatus: health, toolCatalog: catalog,
              onTap: () {}, onToggleEnabled: (_) {}, onCheckHealth: () {},
              onRefreshTools: () {}, onReconnect: () {}, onActionSelected: (_) {},
            );
          },
        )),
      ),
    ));
    final initialHeight = tester.getSize(find.byType(_McpServerCard).first).height;
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(_McpServerCard).first).height, initialHeight,
      reason: '授权卡片首次挂载直接恢复完整高度，不能随滚动重新展开');
    expect(builds, lessThan(20));
    final list = find.byType(ListView).first;
    for (final direction in [-1, -1, 1, 1]) {
      await tester.fling(list, Offset(0, direction * 1800), 5000);
      await tester.pumpAndSettle();
      expect(find.byType(_McpServerCard).evaluate().length, lessThan(20));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await mcp.shutdown();
      settings.dispose();
      await directory!.delete(recursive: true);
    });
  });

  testWidgets('进程日志通知不重建无变化的服务状态组件', (tester) async {
    var builds = 0;
    await tester.pumpWidget(MaterialApp(home: _McpProcessStateBuilder(
      serverName: '滚动回归测试服务',
      builder: (_, info, child) {
        builds++;
        return Text('进程状态：${info.state.name}');
      },
    )));
    expect(builds, 1);
    for (var index = 0; index < 30; index++) {
      McpStdioProcessManager.instance.notifyListeners();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(builds, 1, reason: '服务状态未变时，不随日志及其他服务通知重建');
    await tester.pumpWidget(const SizedBox.shrink());
    McpStdioProcessManager.instance.notifyListeners();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

}
''';
