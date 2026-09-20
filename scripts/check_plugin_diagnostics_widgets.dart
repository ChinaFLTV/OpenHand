import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final view = File(
    '${root.path}/lib/features/plugin_service/widgets/plugin_service_view.dart',
  );
  final source = (await view.readAsString()).replaceAllMapped(
    RegExp("import '([^']+)'"),
    (match) {
      final uri = Uri.parse(match[1]!);
      return "import '${uri.hasScheme ? uri : view.uri.resolveUri(uri)}'";
    },
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'plugin_diagnostics',
    source:
        "import 'package:flutter_test/flutter_test.dart';\n$source\n$_checks",
  );
}

const _checks = r'''
class _DiagnosticController extends PluginServiceController {
  List<PluginInfo> items = [];
  @override
  List<PluginInfo> get plugins => items;
  @override
  PluginInfo? pluginById(String id) => items.where((item) => item.id == id).firstOrNull;
  @override
  bool get isLoading => false;
  @override
  bool get isBusy => false;
  void replace(PluginInfo? plugin) {
    items = [if (plugin != null) plugin];
    notifyListeners();
  }
}

const _plugin = PluginInfo(
  id: PluginCatalogIds.docker,
  name: 'Docker',
  description: '容器运行环境',
  status: PluginStatus.installed,
  supportsInstall: false,
  supportsUninstall: false,
);

Widget _app(_DiagnosticController controller, {double scale = 1, bool reduceMotion = false}) {
  return ChangeNotifierProvider<PluginServiceController>.value(
    value: controller,
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(
        child: Consumer<PluginServiceController>(builder: (context, value, _) => Column(
          children: [
            if (value.plugins.isNotEmpty) _PluginCard(plugin: value.plugins.first, controller: value),
            const SizedBox(key: ValueKey('后续卡片'), height: 40, width: 100),
          ],
        )),
      )),
    ),
  );
}

void main() {
  test('诊断过滤空白、合并重复消息并保留错误状态兜底', () {
    expect(_plugin.copyWith(errorMessage: '  ', metadata: {'update_check_error': '\n'}).diagnostics, isEmpty);
    final duplicate = _plugin.copyWith(errorMessage: ' 同一错误 ', metadata: {'update_check_error': '同一错误'});
    expect(duplicate.diagnostics, [(isError: true, message: '同一错误')]);
    expect(_plugin.copyWith(metadata: {'update_check_error': '更新检查失败'}).diagnostics.single.isError, isFalse);
    expect(_plugin.copyWith(status: PluginStatus.error).diagnostics.single.isError, isTrue);
  });

  testWidgets('消息增减和长正文不改变卡片高度或后续条目位置', (tester) async {
    final controller = _DiagnosticController();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 640.0, 1000.0]) {
      for (final scale in [1.0, 2.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        controller.replace(_plugin);
        await tester.pumpWidget(_app(controller, scale: scale));
        await tester.pumpAndSettle();
        final card = tester.getRect(find.byKey(const ValueKey('plugin-card-docker')));
        final following = tester.getRect(find.byKey(const ValueKey('后续卡片')));
        for (final plugin in [
          _plugin.copyWith(errorMessage: '错误正文' * 1000),
          _plugin.copyWith(metadata: {'update_check_error': '更新警告' * 1000}),
          _plugin.copyWith(errorMessage: '错误', metadata: {'update_check_error': '警告'}),
          _plugin,
        ]) {
          controller.replace(plugin);
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byKey(const ValueKey('plugin-card-docker'))), card);
          expect(tester.getRect(find.byKey(const ValueKey('后续卡片'))), following);
          expect(find.byType(SelectableText), findsNothing);
          expect(find.text('诊断 0'), findsNothing);
          expect(find.descendant(of: find.byType(_PluginDiagnosticsPill), matching: find.byType(TextButton)).hitTestable(),
            plugin.diagnostics.isEmpty ? findsNothing : findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('胶囊平滑显隐、快速反向且退场立即停止交互', (tester) async {
    final controller = _DiagnosticController();
    addTearDown(controller.dispose);
    controller.replace(_plugin);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    final pill = find.byType(_PluginDiagnosticsPill);
    final button = find.descendant(of: pill, matching: find.byType(TextButton));
    expect(button, findsNothing);
    final original = tester.getRect(pill);
    final error = _plugin.copyWith(errorMessage: '连接失败');
    controller.replace(error);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final fade = find.descendant(of: pill, matching: find.byType(FadeTransition));
    expect(fade, findsWidgets);
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, inExclusiveRange(0.0, 1.0));
    controller.replace(_plugin);
    await tester.pump();
    expect(button, findsOneWidget);
    expect(button.hitTestable(), findsNothing);
    expect(find.text('诊断 0'), findsNothing);
    await tester.pump(const Duration(milliseconds: 20));
    controller.replace(error);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    expect(tester.getRect(pill), original);
    controller.replace(_plugin);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(button, findsOneWidget);
    expect(button.hitTestable(), findsNothing);
    await tester.pumpAndSettle();
    expect(button, findsNothing);
    expect(tester.getRect(pill), original);
    controller.replace(error);
    await tester.pumpWidget(_app(controller, reduceMotion: true));
    await tester.pump();
    expect(button.hitTestable(), findsOneWidget);
    controller.replace(_plugin);
    await tester.pump();
    expect(button, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('弹窗显示完整当前消息、复制入口，刷新和移除插件后无旧消息残留', (tester) async {
    final controller = _DiagnosticController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final message = '很长的插件错误\n' * 150;
    controller.replace(_plugin.copyWith(errorMessage: message, metadata: {'update_check_error': '更新检查失败'}));
    await tester.pumpWidget(_app(controller, scale: 2));
    await tester.pumpAndSettle();
    final baselineBarriers = find.byType(ModalBarrier).evaluate().length;
    await tester.tap(find.byType(_PluginDiagnosticsPill));
    await tester.pumpAndSettle();
    expect(find.byType(_PluginDiagnosticsDialog), findsOneWidget);
    expect(find.text(message.trim()), findsOneWidget);
    expect(find.byType(OpenHandNoticeActionButtons), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    controller.replace(_plugin);
    await tester.pumpAndSettle();
    expect(find.text(message.trim()), findsNothing);
    expect(find.text('当前没有错误或警告'), findsOneWidget);
    controller.replace(null);
    await tester.pumpAndSettle();
    expect(find.text('插件已不在当前列表中'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(_PluginDiagnosticsDialog), findsNothing);
    expect(find.byType(ModalBarrier), findsNWidgets(baselineBarriers));
    expect(tester.takeException(), isNull);
  });
}
''';
