import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';
import 'package:openhand/features/services/services_controller.dart';
import 'package:openhand/features/services/widgets/ai_exposure_monitoring_dialogs.dart';
import 'package:openhand/features/services/widgets/ai_exposure_proxy_dialog.dart';
import 'package:openhand/features/services/widgets/service_dialog_controls.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('带图标服务胶囊不使用头像覆盖层', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ServiceFilterChip(
              selected: true,
              icon: const Icon(Icons.info_outline_rounded),
              label: const Text('INFO'),
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    final chip = tester.widget<FilterChip>(find.byType(FilterChip));
    expect(chip.avatar, isNull);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byType(FilterChip)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('代理弹窗在桌面与窄窗口完整呈现巡检控件', (tester) async {
    final defaults = AiExposurePreferences.defaults();
    final endpoint = AiExposureProxyEndpoint.parse('127.0.0.1:8080').withSample(
      AiExposureProxyProbeSample(
        checkedAt: DateTime.utc(2026, 8, 2),
        latencyMs: 86,
        statusCode: 204,
      ),
    );
    final controller = ServicesController(
      initialPreferences: AiExposurePreferences(
        enabledSources: defaults.enabledSources,
        defaultConcurrency: defaults.defaultConcurrency,
        defaultValidationMode: defaults.defaultValidationMode,
        defaultGptAssisted: defaults.defaultGptAssisted,
        useBundledEngine: defaults.useBundledEngine,
        externalAddress: defaults.externalAddress,
        proxyConfiguration: AiExposureProxyConfiguration(
          enabled: true,
          strategy: AiExposureProxyStrategy.roundRobin,
          rotationEvery: 1,
          bypassLocal: true,
          endpoints: <AiExposureProxyEndpoint>[endpoint],
        ),
      ),
    );
    addTearDown(controller.shutdown);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 920);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_DialogHarness(controller: controller));

    await tester.tap(find.text('Open proxy'));
    await tester.pumpAndSettle();
    expect(find.text('Network proxy pool'), findsOneWidget);
    expect(find.text('Scheduled inspection'), findsOneWidget);
    expect(find.text('Inspect all'), findsOneWidget);
    expect(find.text('86 ms'), findsOneWidget);
    expect(find.byIcon(Icons.speed_rounded), findsWidgets);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(760, 920);
    await tester.pumpAndSettle();
    expect(find.text('Network proxy pool'), findsOneWidget);
    expect(find.text('Apply proxy settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动跟随文字紧邻开关', (tester) async {
    final controller = ServicesController();
    addTearDown(controller.shutdown);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_DialogHarness(controller: controller));

    await tester.tap(find.text('Open logs'));
    await tester.pumpAndSettle();
    final label = find.text('Auto follow');
    final toggle = find.byType(Switch);
    expect(label, findsOneWidget);
    expect(toggle, findsOneWidget);
    final gap = tester.getTopLeft(toggle).dx - tester.getTopRight(label).dx;
    expect(gap, inInclusiveRange(0, 16));
    expect(tester.takeException(), isNull);
  });
}

class _DialogHarness extends StatelessWidget {
  const _DialogHarness({required this.controller});

  final ServicesController controller;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: controller,
    child: MaterialApp(
      theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
      home: Scaffold(
        body: Builder(
          builder: (context) => Row(
            children: [
              TextButton(
                onPressed: () => showAiExposureProxyDialog(context),
                child: const Text('Open proxy'),
              ),
              TextButton(
                onPressed: () => showAiExposureLogMonitorDialog(context),
                child: const Text('Open logs'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
