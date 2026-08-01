import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/plugin_service/model/plugin_info.dart';
import 'package:openhand/features/plugin_service/plugin_service_controller.dart';
import 'package:openhand/features/plugin_service/service/plugin_scanner_service.dart';
import 'package:openhand/features/plugin_service/widgets/plugin_service_view.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('插件卡空闲态操作按钮紧贴右侧内边距', (tester) async {
    final controller = PluginServiceController(scanner: _PluginScanner());
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.initialize();
    await tester.binding.setSurfaceSize(const Size(1280, 900));

    await tester.pumpWidget(
      ChangeNotifierProvider<PluginServiceController>.value(
        value: controller,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            cardTheme: const CardThemeData(margin: EdgeInsets.zero),
          ),
          home: const Scaffold(body: PluginServiceView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cardFinder = find.byKey(const ValueKey<String>('plugin-card-nodejs'));
    final lastAction = find
        .descendant(of: cardFinder, matching: find.byType(IconButton))
        .last;
    expect(cardFinder, findsOneWidget);
    expect(
      tester.getRect(cardFinder).right - tester.getRect(lastAction).right,
      closeTo(18, 0.01),
    );
    expect(tester.takeException(), isNull);
  });
}

class _PluginScanner extends PluginScannerService {
  @override
  Future<List<PluginInfo>> scanAll() async => const <PluginInfo>[
    PluginInfo(
      id: PluginCatalogIds.nodejs,
      name: 'Node.js',
      description: 'JavaScript 运行时环境',
      status: PluginStatus.installed,
      installedVersion: '26.1.0',
      installPath: '/usr/local/bin/node',
    ),
  ];
}
