import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';
import 'package:openhand/features/services/services_controller.dart';
import 'package:openhand/features/services/widgets/ai_exposure_monitoring_dialogs.dart';
import 'package:openhand/features/services/widgets/service_dialog_controls.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(_loadGoldenChineseFont);

  group('任务账本', () {
    final createdAt = DateTime.utc(2026, 8, 6, 8);
    final tasks = <AiExposureHistoryEntry>[
      _task(
        id: 'task-completed',
        name: '完成任务',
        stage: 'completed',
        mode: AiExposureScanMode.full,
        processed: 80,
        createdAt: createdAt,
      ),
      _task(
        id: 'task-running',
        name: '运行任务',
        stage: 'fingerprinting',
        mode: AiExposureScanMode.incremental,
        processed: 20,
        createdAt: createdAt.add(const Duration(minutes: 1)),
      ),
      _task(
        id: 'task-failed',
        name: '失败任务',
        stage: 'failed',
        mode: AiExposureScanMode.full,
        processed: 40,
        createdAt: createdAt.add(const Duration(minutes: 2)),
        errorMessage: '连接失败',
        sources: const [AiExposureSource.shodan],
      ),
    ];

    test('按状态、模式和错误摘要筛选', () {
      expect(
        filterAndSortAiExposureTasks(source: tasks, status: 'running'),
        hasLength(1),
      );
      expect(
        filterAndSortAiExposureTasks(source: tasks, mode: 'full'),
        hasLength(2),
      );
      expect(
        filterAndSortAiExposureTasks(source: tasks, query: '连接失败').single.id,
        'task-failed',
      );
    });

    test('按处理量降序排序', () {
      final sorted = filterAndSortAiExposureTasks(
        source: tasks,
        sort: AiExposureTaskLedgerSort.processed,
      );
      expect(sorted.map((task) => task.id), [
        'task-completed',
        'task-failed',
        'task-running',
      ]);
    });

    test('按来源和创建时间范围筛选', () {
      expect(
        filterAndSortAiExposureTasks(
          source: tasks,
          sources: const {AiExposureSource.shodan},
        ).single.id,
        'task-failed',
      );
      expect(
        filterAndSortAiExposureTasks(
          source: tasks,
          createdFrom: createdAt.add(const Duration(seconds: 90)),
          createdUntil: createdAt.add(const Duration(minutes: 3)),
        ).single.id,
        'task-failed',
      );
    });

    testWidgets('点击任务行交给任务详情入口', (tester) async {
      AiExposureHistoryEntry? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: SingleChildScrollView(
                child: AiExposureTaskLedger(
                  tasks: [tasks.first],
                  onOpenTask: (task) => opened = task,
                ),
              ),
            ),
          ),
        ),
      );

      final semantics = tester.ensureSemantics();
      try {
        final taskRow = find.byType(ServiceInteractiveSurface);
        final taskRowInkWell = find.descendant(
          of: taskRow,
          matching: find.byType(InkWell),
        );
        final taskRowSemantics = tester
            .getSemantics(taskRowInkWell)
            .getSemanticsData();
        expect(taskRowSemantics.label, startsWith('查看任务详情'));
        expect(taskRowSemantics.flagsCollection.isButton, isTrue);
        expect(taskRowSemantics.hasAction(SemanticsAction.tap), isTrue);
      } finally {
        semantics.dispose();
      }
      await tester.tap(find.text('完成任务').first);
      await tester.pump();
      expect(opened?.id, 'task-completed');
    });

    testWidgets('移动端使用 20 条分页且大字体无溢出', (tester) async {
      await _pumpTaskLedger(
        tester,
        size: const Size(390, 844),
        textScale: 1.3,
        tasks: _manyTasks(1000),
      );

      expect(find.byType(ServiceInteractiveSurface), findsNWidgets(20));
      expect(find.text('1/50'), findsOneWidget);
      _expectNoWidgetException(tester);
      if (_goldenChineseFontLoaded) {
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/task_ledger_mobile_large_text.png'),
        );
      }
    });

    testWidgets('桌面窄屏使用 50 条分页且显示生命周期列', (tester) async {
      await _pumpTaskLedger(
        tester,
        size: const Size(1024, 768),
        tasks: _manyTasks(1000),
        dark: true,
      );

      expect(find.byType(ServiceInteractiveSurface), findsNWidgets(50));
      expect(find.text('1/20'), findsOneWidget);
      expect(find.text('创建 / 结束 / 耗时'), findsOneWidget);
      _expectNoWidgetException(tester);
      if (_goldenChineseFontLoaded) {
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/task_ledger_desktop_dark.png'),
        );
      }
    });

    testWidgets('空账本显示明确空态', (tester) async {
      await _pumpTaskLedger(
        tester,
        size: const Size(1440, 900),
        tasks: const <AiExposureHistoryEntry>[],
      );

      expect(find.text('当前筛选范围内没有任务。'), findsOneWidget);
      expect(find.text('共 0 条'), findsOneWidget);
      _expectNoWidgetException(tester);
      if (_goldenChineseFontLoaded) {
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/task_ledger_desktop_empty.png'),
        );
      }
    });
  });

  group('运维显示规则', () {
    test('零值进度不绘制伪宽度', () {
      expect(
        serviceProgressRatio(value: 0, maximum: 0, minimumVisible: 0.16),
        0,
      );
      expect(
        serviceProgressRatio(value: 0, maximum: 100, minimumVisible: 0.16),
        0,
      );
      expect(
        serviceProgressRatio(value: 1, maximum: 100, minimumVisible: 0.04),
        0.04,
      );
      expect(serviceProgressRatio(value: 120, maximum: 100), 1);
    });

    testWidgets('零值进度组件保持空填充', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              child: ServiceAnimatedProgressBar(value: 0),
            ),
          ),
        ),
      );

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, 0);
    });

    test('凭证状态使用简体中文映射', () {
      expect(aiExposureCredentialStateName('valid'), '有效');
      expect(aiExposureCredentialStateName('rate_limited'), '受限');
      expect(aiExposureCredentialStateName('not_found'), '未发现');
      expect(aiExposureCredentialStateName(''), '状态未分类');
    });

    test('代理地址不泄露密码', () {
      final endpoint = AiExposureProxyEndpoint.parse(
        'http://audit-user:top-secret@proxy.example.com:8080',
      );
      expect(endpoint.maskedUrl, contains('audit-user:******@'));
      expect(endpoint.maskedUrl, isNot(contains('top-secret')));
    });

    test('列表截断时给出明确提示', () {
      expect(
        aiExposureListTruncationNotice(total: 31, visible: 30),
        '共 31 条，当前显示前 30 条（已截断）',
      );
      expect(aiExposureListTruncationNotice(total: 30, visible: 30), isNull);
    });

    testWidgets('无目标表面没有点击语义和详情图标', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServiceInteractiveSurface(onTap: null, child: Text('静态统计')),
          ),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.byType(Tooltip), findsNothing);
    });
  });

  group('增强数据契约', () {
    test('解析任务阶段时间且缺失字段保持空值', () {
      final task = AiExposureHistoryEntry.fromJson({
        'id': 'task-1',
        'name': '契约任务',
        'stage': 'completed',
        'sources': ['github'],
        'mode': 'full',
        'authorizedScope': ['example.com'],
        'progress': {
          'jobId': 'task-1',
          'stage': 'completed',
          'updatedAt': '2026-08-06T08:05:00Z',
        },
        'createdAt': '2026-08-06T08:00:00Z',
        'startedAt': '2026-08-06T08:00:01Z',
        'concurrency': 24,
        'validationMode': 'authorized_active',
        'stageTimings': [
          {
            'stage': 'discovering',
            'startedAt': '2026-08-06T08:00:01Z',
            'finishedAt': '2026-08-06T08:00:03Z',
            'durationMs': 2000,
          },
        ],
      });

      expect(task.startedAt, DateTime.utc(2026, 8, 6, 8, 0, 1));
      expect(task.concurrency, 24);
      expect(task.validationMode, AiExposureValidationMode.authorizedActive);
      expect(task.stageTimings.single.durationMs, 2000);
      expect(task.cancelReason, isNull);
      expect(task.retryCount, isNull);
    });

    test('解析日志和请求遥测字段', () {
      final log = AiExposureLogEntry.fromJson({
        'id': 'log-1',
        'level': 'error',
        'message': '请求失败',
        'at': '2026-08-06T08:00:00Z',
        'module': 'pipeline',
        'eventCode': 'scan_failed',
      });
      final request = AiExposureProxyRequestSample.fromJson({
        'atMs': DateTime.utc(2026, 8, 6, 8).millisecondsSinceEpoch,
        'result': 'failure',
        'responseTimeMs': 350,
        'id': 'request-1',
        'endpointId': 'endpoint-1',
        'targetHost': 'example.com',
        'method': 'GET',
        'errorType': 'transport',
      });

      expect(log.id, 'log-1');
      expect(log.module, 'pipeline');
      expect(log.eventCode, 'scan_failed');
      expect(request.id, 'request-1');
      expect(request.method, 'GET');
      expect(request.targetHost, 'example.com');
      expect(request.timeoutMs, isNull);

      final invalid = AiExposureProxyRequestSample.fromJson({
        'atMs': 0,
        'result': 'failure',
        'responseTimeMs': 0,
        'timeoutMs': -1,
      });
      expect(invalid.timeoutMs, isNull);
    });
  });

  group('代理遥测空态', () {
    for (final size in const <Size>[
      Size(390, 844),
      Size(720, 900),
      Size(1000, 900),
    ]) {
      testWidgets('${size.width.toInt()} 像素宽度结构清晰且无溢出', (tester) async {
        await _pumpOperationsNetwork(tester, size: size);

        await _openNetworkMetric(tester, '代理节点');
        expect(find.text('代理节点控制平面'), findsOneWidget);
        expect(find.text('代理池尚未配置节点。'), findsOneWidget);
        expect(find.text('节点请求负载排名'), findsNothing);
        _expectNoWidgetException(tester);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();

        await _openNetworkMetric(tester, '可连通节点');
        expect(find.text('已配置节点'), findsOneWidget);
        expect(find.text('网关可达'), findsOneWidget);
        expect(find.text('转发可用'), findsOneWidget);
        expect(find.text('等待巡检'), findsOneWidget);
        expect(find.text('最近巡检执行事件'), findsNothing);
        _expectNoWidgetException(tester);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();

        await _openNetworkMetric(tester, 'p95 响应');
        expect(find.text('长尾基线生成流程'), findsOneWidget);
        expect(find.text('代理业务请求'), findsOneWidget);
        expect(find.text('近期采样窗口'), findsOneWidget);
        expect(find.text('p95 基线'), findsOneWidget);
        expect(find.text('长尾响应与 p95 基线'), findsNothing);
        expect(find.text('节点长尾响应剖面'), findsNothing);
        _expectNoWidgetException(tester);
      });
    }
  });
}

AiExposureHistoryEntry _task({
  required String id,
  required String name,
  required String stage,
  required AiExposureScanMode mode,
  required int processed,
  required DateTime createdAt,
  String? errorMessage,
  List<AiExposureSource> sources = const [AiExposureSource.github],
}) => AiExposureHistoryEntry(
  id: id,
  name: name,
  stage: stage,
  sources: sources,
  mode: mode,
  authorizedScope: const ['example.com'],
  progress: AiExposureProgress(
    jobId: id,
    stage: stage,
    discovered: processed,
    candidates: processed,
    valid: processed ~/ 2,
    highValue: processed ~/ 4,
    processed: processed,
    total: 100,
    message: '',
    updatedAt: createdAt,
  ),
  createdAt: createdAt,
  finishedAt: stage == 'completed'
      ? createdAt.add(const Duration(minutes: 5))
      : null,
  errorMessage: errorMessage,
);

List<AiExposureHistoryEntry> _manyTasks(int count) {
  final createdAt = DateTime.utc(2026, 8, 6, 8);
  return List<AiExposureHistoryEntry>.generate(
    count,
    (index) => _task(
      id: 'task-$index',
      name: '超长任务名称-$index-用于验证响应式布局不会发生文字遮挡',
      stage: index.isEven ? 'completed' : 'failed',
      mode: index.isEven
          ? AiExposureScanMode.full
          : AiExposureScanMode.incremental,
      processed: index % 101,
      createdAt: createdAt.add(Duration(minutes: index)),
      errorMessage: index.isOdd ? '连接失败：用于验证超长错误消息能够正确换行并保持布局稳定' : null,
      sources: index.isEven
          ? const [AiExposureSource.github]
          : const [AiExposureSource.shodan, AiExposureSource.fofa],
    ),
    growable: false,
  );
}

Future<void> _pumpTaskLedger(
  WidgetTester tester, {
  required Size size,
  required List<AiExposureHistoryEntry> tasks,
  double textScale = 1,
  bool dark = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(fontFamily: _goldenFontFamily),
      darkTheme: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(
          fontFamily: _goldenFontFamily,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(child: AiExposureTaskLedger(tasks: tasks)),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpOperationsNetwork(
  WidgetTester tester, {
  required Size size,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = ServicesController(
    initialPreferences: AiExposurePreferences.defaults(),
    proxyInspectionFirstRunDelay: const Duration(days: 1),
  );
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
            builder: (context) => TextButton(
              onPressed: () => showAiExposureOperationsDialog(context),
              child: const Text('打开运维'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开运维'));
  await tester.pumpAndSettle();
  final networkTab = find.text('网络遥测');
  await tester.ensureVisible(networkTab);
  await tester.tap(networkTab);
  await tester.pumpAndSettle();
  _expectNoWidgetException(tester);
}

Future<void> _openNetworkMetric(WidgetTester tester, String label) async {
  final metric = find.text(label).first;
  await tester.ensureVisible(metric);
  await tester.tap(metric);
  await tester.pumpAndSettle();
}

void _expectNoWidgetException(WidgetTester tester) {
  final exception = tester.takeException();
  expect(exception, isNull, reason: '$exception');
}

const String _goldenFontFamily = 'OpenHandGoldenChinese';
const String _goldenFontPath = '/System/Library/Fonts/Hiragino Sans GB.ttc';
bool _goldenChineseFontLoaded = false;

Future<void> _loadGoldenChineseFont() async {
  final file = File(_goldenFontPath);
  if (!Platform.isMacOS || !file.existsSync()) return;
  final bytes = await file.readAsBytes();
  final loader = FontLoader(_goldenFontFamily)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
  _goldenChineseFontLoaded = true;
}
