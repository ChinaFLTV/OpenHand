import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';
import 'package:openhand/features/services/services_controller.dart';
import 'package:openhand/features/services/widgets/ai_exposure_monitoring_dialogs.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('桌面尺寸可打开六个模块的全部指标与图表详情', (tester) async {
    await _pumpOperationsDialog(tester, const Size(1280, 900));

    for (final module in _modules) {
      await _selectModule(tester, module.name);
      for (final metric in module.metrics) {
        await _openAndCloseInsight(tester, metric);
      }
      for (final chart in module.charts) {
        await _openAndCloseInsight(tester, chart);
      }
    }
  });

  testWidgets('移动尺寸可打开全部图表详情且无布局异常', (tester) async {
    await _pumpOperationsDialog(tester, const Size(390, 844));

    for (final module in _modules) {
      await _selectModule(tester, module.name);
      for (final chart in module.charts) {
        await _openAndCloseInsight(tester, chart);
      }
    }
  });

  testWidgets('无需凭证来源状态一致并可打开详情', (tester) async {
    await _pumpOperationsDialog(tester, const Size(1280, 900));
    await _selectModule(tester, '数据源');

    final sourceTile = find.widgetWithText(ListTile, 'NodeSeek');
    expect(sourceTile, findsOneWidget);
    expect(
      find.descendant(of: sourceTile, matching: find.text('可用')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sourceTile, matching: find.text('无需访问凭证。')),
      findsOneWidget,
    );

    await tester.ensureVisible(sourceTile);
    await tester.tap(sourceTile);
    await tester.pumpAndSettle();
    expect(find.text('来源执行概览'), findsOneWidget);
    expect(find.text('无需 API 凭证'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _closeTopDialog(tester);
  });

  testWidgets('代理节点可打开实时请求与巡检详情', (tester) async {
    await _pumpOperationsDialog(
      tester,
      const Size(1280, 900),
      preferences: _preferencesWithProxy(),
    );
    await _selectModule(tester, '网络遥测');

    final endpointTile = find.widgetWithText(ListTile, '测试代理');
    expect(endpointTile, findsOneWidget);
    await tester.ensureVisible(endpointTile);
    await tester.tap(endpointTile);
    await tester.pumpAndSettle();
    expect(find.text('节点请求质量'), findsOneWidget);
    expect(find.text('节点请求时间线 · 2'), findsOneWidget);
    expect(find.text('节点巡检时间线 · 1'), findsOneWidget);
    expect(find.text('50.0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _closeTopDialog(tester);
  });
}

Future<void> _pumpOperationsDialog(
  WidgetTester tester,
  Size size, {
  AiExposurePreferences? preferences,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = ServicesController(initialPreferences: preferences);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ServicesController>.value(
      value: controller,
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showAiExposureOperationsDialog(context),
              child: const Text('打开运维弹窗'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开运维弹窗'));
  await tester.pumpAndSettle();
  expect(find.text('AI 基础设施扫描服务状态与运维'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _closeTopDialog(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.close_rounded).last);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _selectModule(WidgetTester tester, String name) async {
  final finder = find.text(name).first;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _openAndCloseInsight(WidgetTester tester, String title) async {
  final finder = find.text(title).first;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(find.text(title), findsWidgets);
  expect(tester.takeException(), isNull);
  await _closeTopDialog(tester);
}

AiExposurePreferences _preferencesWithProxy() {
  final defaults = AiExposurePreferences.defaults();
  final checkedAt = DateTime.utc(2026, 8, 4, 10);
  return AiExposurePreferences(
    enabledSources: defaults.enabledSources,
    defaultConcurrency: defaults.defaultConcurrency,
    defaultValidationMode: defaults.defaultValidationMode,
    forumFetchMode: defaults.forumFetchMode,
    defaultGptAssisted: defaults.defaultGptAssisted,
    useBundledEngine: defaults.useBundledEngine,
    externalAddress: defaults.externalAddress,
    proxyConfiguration: AiExposureProxyConfiguration(
      enabled: true,
      strategy: AiExposureProxyStrategy.roundRobin,
      rotationEvery: 1,
      bypassLocal: true,
      endpoints: [
        AiExposureProxyEndpoint(
          url: 'http://user:secret@127.0.0.1:8080',
          name: '测试代理',
          samples: [
            AiExposureProxyProbeSample(
              checkedAt: checkedAt,
              latencyMs: 35,
              statusCode: 204,
              gatewayReachable: true,
            ),
          ],
          statistics: AiExposureProxyUsageStatistics(
            requests: 2,
            successes: 1,
            failures: 1,
            totalResponseTimeMs: 180,
            minResponseTimeMs: 70,
            maxResponseTimeMs: 110,
            status2xx: 1,
            status5xx: 1,
            recentRequests: [
              AiExposureProxyRequestSample(
                at: checkedAt.subtract(const Duration(minutes: 2)),
                result: 'success',
                responseTimeMs: 70,
                statusCode: 204,
              ),
              AiExposureProxyRequestSample(
                at: checkedAt.subtract(const Duration(minutes: 1)),
                result: 'failure',
                responseTimeMs: 110,
                statusCode: 502,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _OperationsModule {
  const _OperationsModule(this.name, this.metrics, this.charts);

  final String name;
  final List<String> metrics;
  final List<String> charts;
}

const List<_OperationsModule> _modules = [
  _OperationsModule(
    '状态总览',
    [
      '任务总数',
      '结果总数',
      '高价值',
      '累计处理',
      '平均任务耗时',
      '已配置源',
      '启用规则',
      '代理选路',
      '代理平均响应',
      '警告日志',
      '错误日志',
      '已取消任务',
    ],
    ['任务处理趋势', '任务耗时趋势', '结果分类分布', '任务状态分布'],
  ),
  _OperationsModule(
    '任务管线',
    ['当前状态', '累计处理', '候选目标', '有效结果', '高价值结果', '任务并发', '全量扫描', '可恢复任务'],
    ['处理漏斗趋势', '扫描模式分布'],
  ),
  _OperationsModule(
    '数据源',
    ['已就绪来源', '配额可用源', '剩余配额', '启用发现源', '来源调用任务', '来源产出结果', '配额异常', '待配置来源'],
    ['结果来源分布', '任务来源覆盖'],
  ),
  _OperationsModule(
    '网络遥测',
    [
      '选路状态',
      '代理节点',
      '可连通节点',
      '累计请求',
      '成功请求',
      '失败请求',
      '超时请求',
      '平均响应',
      'p95 响应',
      'HTTP 2xx',
      '出口国家',
      '巡检计划',
    ],
    ['代理响应耗时趋势', '请求结果分布', 'HTTP 状态分布', '节点请求分布'],
  ),
  _OperationsModule(
    '存储与持久化',
    [
      'SQLite 数据库',
      '最后写入',
      '可见记录',
      '任务归档',
      '结果归档',
      '规则快照',
      '日志缓冲',
      '可恢复任务',
      'PostgreSQL 镜像',
      'Redis 协调',
      '凭证加密',
      '一致性审计',
    ],
    ['归档增长趋势', '任务写入负载', '记录类型分布', '任务归档状态', '凭证状态分布'],
  ),
  _OperationsModule(
    '安全与依赖',
    ['启用规则', '凭证模式', '模型端点', '编码识别', '代理请求', '代理成功', '代理异常', '依赖就绪'],
    ['代理可靠性分布', '启用规则供应商分布'],
  ),
];
