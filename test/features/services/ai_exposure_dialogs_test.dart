import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/services_controller.dart';
import 'package:openhand/features/services/widgets/ai_exposure_dialogs.dart';
import 'package:openhand/shared/ui/openhand_form_fields.dart';
import 'package:provider/provider.dart';

void main() {
  final dialogs = <(String, Future<void> Function(BuildContext))>[
    ('服务状态', showAiExposureStatusDialog),
    ('新建狩猎', showAiExposureNewHuntDialog),
    ('自定义狩猎', (context) => showAiExposureNewHuntDialog(context, custom: true)),
    ('实时扫描', showAiExposureProgressDialog),
    ('结果中心', showAiExposureResultsDialog),
    ('扫描历史', showAiExposureHistoryDialog),
    ('扫描工具管理', showAiExposureToolsDialog),
    ('扫描规则管理', showAiExposureRulesDialog),
    ('服务设置', showAiExposureSettingsDialog),
  ];

  for (final (name, showDialog) in dialogs) {
    testWidgets('$name 弹窗适配桌面与移动尺寸', (tester) async {
      for (final size in const <Size>[Size(1280, 900), Size(390, 844)]) {
        await _openDialog(tester, size, showDialog);
        expect(find.byType(Dialog), findsOneWidget);
        final exception = tester.takeException();
        expect(exception, isNull);
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('服务设置弹窗在移动尺寸无布局溢出', (tester) async {
    await _openDialog(
      tester,
      const Size(390, 844),
      showAiExposureSettingsDialog,
    );
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    final postgresqlTile = find.widgetWithText(
      OpenHandAnimatedSwitchTile,
      'PostgreSQL',
    );
    await tester.ensureVisible(postgresqlTile);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: postgresqlTile, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    expect(find.text('PostgreSQL URL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openDialog(
  WidgetTester tester,
  Size size,
  Future<void> Function(BuildContext) showDialog,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = ServicesController();
  addTearDown(controller.shutdown);
  await tester.pumpWidget(
    ChangeNotifierProvider<ServicesController>.value(
      value: controller,
      child: MaterialApp(
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog(context),
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
