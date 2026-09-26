import 'dart:io';

import 'support/flutter_widget_check.dart';

/// 合并真实设置页验证滚动与状态保留；统计查询使用固定快照，避免读取本机数据。
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final page = File(
    '${root.path}/lib/features/settings/widgets/settings_view.dart',
  );
  final libUri = Directory('${root.path}/lib/').uri;
  var source = await page.readAsString();
  source = source.replaceAllMapped(RegExp("(import|export) '([^']+)'"), (
    match,
  ) {
    if (match[2]!.contains(':')) return match[0]!;
    final uri = page.uri.resolve(match[2]!);
    return "${match[1]} 'package:openhand/${uri.path.substring(libUri.path.length)}'";
  });
  source = source.replaceAllMapped(RegExp("part '([^']+)';"), (match) {
    return File.fromUri(page.uri.resolve(match[1]!))
        .readAsStringSync()
        .replaceFirst(RegExp('^part of [^;]+;', multiLine: true), '');
  });
  source = source.replaceAll(
    '_tracker.loadSnapshot(_filter)',
    '_testSnapshot(_filter)',
  );
  source = source.replaceAll(
    'AiUsageTracker.instance.loadRequestPage(',
    '_testRequestPage(',
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'settings_scroll',
    source:
        "import 'package:flutter_test/flutter_test.dart' hide isEmpty, isNotEmpty;\n"
        '$source\n$_checks',
  );
}

const _checks = '''
class _ScrollSettingsStore extends SettingsStore {
  @override
  Future<SettingsLoadResult> load() async => SettingsLoadResult(
    snapshot: AppSettingsSnapshot.defaults(), canPersist: false,
  );
}
int _requestCount = 0;
Future<AiUsageSnapshot> _testSnapshot(AiUsageFilter filter) async => AiUsageSnapshot(
  generatedAt: DateTime.now(), filter: filter,
  summary: AiUsageSummary(requestCount: _requestCount, successCount: _requestCount),
  trend: const [], heatmap: const [], providers: const [], models: const [],
  sources: const [], surfaces: const [], operations: const [], templates: const [],
  recentRequests: const [], providerFacets: const [], modelFacets: const [], sourceFacets: const [],
);
Future<(int, List<AiUsageRequestRecord>)> _testRequestPage(
  AiUsageFilter filter, {required int offset, required int limit}) async => (0, <AiUsageRequestRecord>[]);

Future<SettingsController> _mount(WidgetTester tester, {Widget child = const SettingsView(), Size size = const Size(1440, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = await SettingsController.create(store: _ScrollSettingsStore());
  await tester.pumpWidget(MultiProvider(providers: [
    ChangeNotifierProvider.value(value: settings),
    Provider.value(value: AppInfo.fallback()),
    ChangeNotifierProvider(create: (_) => MemoryController.uninitialized()),
    ChangeNotifierProvider(create: (_) => AiModelHealthController()),
  ], child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales, locale: const Locale('zh'),
    theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
    home: Scaffold(body: child),
  )));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    settings.dispose();
  });
  await tester.pumpAndSettle();
  return settings;
}

void main() {
  testWidgets('设置首页仅构建视口附近的动画分组，快速往返无异常', (tester) async {
    _requestCount = 0;
    await _mount(tester);
    expect(find.byType(_PageAnimationSettingsSection), findsNothing);
    expect(find.byType(_ListItemAnimationSettingsSection), findsNothing);
    final list = find.byType(ListView).first;
    final viewport = find.descendant(of: list, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byType(_ListItemAnimationSettingsSection), 600,
      scrollable: viewport, maxScrolls: 16);
    await tester.pumpAndSettle();
    expect(find.byType(_ListItemAnimationSettingsSection), findsOneWidget);
    for (final delta in [1600.0, -1200.0, 1600.0]) {
      await tester.fling(list, Offset(0, delta), 4500);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('窄窗口和减少动画模式下，分组控件保持可滚动且无溢出', (tester) async {
    _requestCount = 0;
    final settings = await _mount(tester, size: const Size(430, 850));
    await settings.updateReduceMotion(true);
    await tester.pumpAndSettle();
    final viewport = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byType(_ListItemAnimationSettingsSection), 500,
      scrollable: viewport, maxScrolls: 40);
    await tester.pumpAndSettle();
    expect(find.byType(_ListItemAnimationSettingsSection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 使用统计进入视口时不创建会话及模型配置控件', (tester) async {
    _requestCount = 0;
    await _mount(tester);
    final viewport = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byType(_AiUsageSettingsSection), 600,
      scrollable: viewport, maxScrolls: 30);
    await tester.pumpAndSettle();
    expect(find.byType(AiModelHealthSettingsPanel), findsNothing);
    expect(find.byKey(const ValueKey('settingsCompressionThresholdField')), findsNothing);
    expect(find.byKey(const ValueKey('settingsAiInputCacheEnabledSwitch')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('统计后台刷新复用图表状态，筛选切换仍有过渡且卸载停止计时', (tester) async {
    _requestCount = 10;
    await _mount(tester, child: const SingleChildScrollView(child: _AiUsageSettingsSection()));
    final section = tester.state<_AiUsageSettingsSectionState>(find.byType(_AiUsageSettingsSection));
    final chart = tester.state(find.byType(_AiUsageTrendChart).first);
    final breakdown = tester.state(find.byType(_AiUsageBreakdownPanel));
    _requestCount = 12;
    await section._load(quiet: true);
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.state(find.byType(_AiUsageTrendChart).first), same(chart));
    expect(tester.state(find.byType(_AiUsageBreakdownPanel)), same(breakdown));
    expect(find.byType(_AiUsageHero), findsOneWidget, reason: '后台刷新不能同时挂载两套统计');
    section._filter = const AiUsageFilter(range: AiUsageRange.sevenDays);
    await section._load();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(_AiUsageTrendChart).first), isNot(same(chart)));
    section._scheduleRefresh();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
''';
