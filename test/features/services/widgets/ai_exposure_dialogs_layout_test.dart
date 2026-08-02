import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';
import 'package:openhand/features/services/services_controller.dart';
import 'package:openhand/features/services/widgets/ai_exposure_monitoring_dialogs.dart';
import 'package:openhand/features/services/widgets/ai_exposure_proxy_dialog.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('代理池与节点详情适配宽窄视口', (tester) async {
    final controller = ServicesController(
      initialPreferences: _preferencesWithProxy(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.shutdown();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    await _pumpDialogHarness(
      tester,
      controller: controller,
      onOpen: showAiExposureProxyDialog,
    );

    expect(find.text('网络代理与代理池'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final detailsButton = find.byIcon(Icons.manage_search_rounded);
    await tester.scrollUntilVisible(
      detailsButton,
      360,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(detailsButton);
    await tester.pumpAndSettle();
    expect(find.text('代理节点详情'), findsOneWidget);
    expect(find.text('203.0.113.9'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(480, 760));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务运维弹窗适配宽窄视口', (tester) async {
    final controller = ServicesController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.shutdown();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    await _pumpDialogHarness(
      tester,
      controller: controller,
      onOpen: showAiExposureOperationsDialog,
    );

    expect(find.text('AI 基础设施扫描服务运维'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final tab in const <String>['任务管线', '数据源', '安全与依赖', '运维总览']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(const Size(480, 760));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('新增代理节点弹窗不会溢出协议选择框', (tester) async {
    final controller = ServicesController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.shutdown();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(560, 760));
    await _pumpDialogHarness(
      tester,
      controller: controller,
      onOpen: showAiExposureProxyDialog,
    );

    final addButton = find.byTooltip('添加代理');
    await tester.scrollUntilVisible(
      addButton,
      280,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(find.text('新增代理节点'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(380, 760));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDialogHarness(
  WidgetTester tester, {
  required ServicesController controller,
  required Future<void> Function(BuildContext context) onOpen,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<ServicesController>.value(
      value: controller,
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => onOpen(context),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

AiExposurePreferences _preferencesWithProxy() {
  final now = DateTime(2026, 8, 2, 12);
  final endpoint =
      AiExposureProxyEndpoint.parse(
        'http://user:password@proxy.example.com:8080',
      ).copyWith(
        name: '东京出口节点',
        samples: <AiExposureProxyProbeSample>[
          AiExposureProxyProbeSample(
            checkedAt: now,
            latencyMs: 86,
            statusCode: 204,
          ),
        ],
        statistics: AiExposureProxyUsageStatistics(
          requests: 128,
          successes: 118,
          failures: 7,
          timeouts: 3,
          totalResponseTimeMs: 14080,
          minResponseTimeMs: 42,
          maxResponseTimeMs: 860,
          status2xx: 110,
          status3xx: 8,
          status4xx: 5,
          status5xx: 2,
          consecutiveFailures: 1,
          lastUsedAt: now,
          lastSuccessAt: now,
          recentRequests: <AiExposureProxyRequestSample>[
            AiExposureProxyRequestSample(
              at: now,
              result: 'success',
              responseTimeMs: 92,
              statusCode: 200,
            ),
          ],
        ),
        identity: AiExposureProxyIdentity(
          exitIp: '203.0.113.9',
          ipType: 'IPv4',
          networkType: 'datacenter',
          cleanliness: 'medium',
          continent: 'Asia',
          country: 'Japan',
          countryCode: 'JP',
          region: 'Tokyo',
          city: 'Tokyo',
          district: 'Chiyoda',
          postalCode: '100-0001',
          timezone: 'Asia/Tokyo',
          currency: 'JPY',
          isp: 'Example ISP',
          organization: 'Example Network',
          asn: 'AS64500',
          asName: 'EXAMPLE-NET',
          mobile: false,
          proxy: true,
          hosting: true,
          latitude: 35.6812,
          longitude: 139.7671,
          observedAt: now,
        ),
      );
  final defaults = AiExposurePreferences.defaults();
  return AiExposurePreferences(
    enabledSources: defaults.enabledSources,
    defaultConcurrency: defaults.defaultConcurrency,
    defaultValidationMode: defaults.defaultValidationMode,
    defaultGptAssisted: defaults.defaultGptAssisted,
    useBundledEngine: defaults.useBundledEngine,
    externalAddress: defaults.externalAddress,
    proxyConfiguration: defaults.proxyConfiguration.copyWith(
      enabled: true,
      endpoints: <AiExposureProxyEndpoint>[endpoint],
    ),
  );
}
