import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/services_controller.dart';
import 'package:openhand/features/services/widgets/ai_exposure_dialogs.dart';
import 'package:openhand/l10n/app_localizations.dart';
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

  testWidgets('服务弹窗开关统一使用 Material 样式', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      for (final showDialog in <Future<void> Function(BuildContext)>[
        showAiExposureNewHuntDialog,
        showAiExposureToolsDialog,
        showAiExposureSettingsDialog,
      ]) {
        await _openDialog(tester, const Size(1280, 900), showDialog);
        expect(find.byType(Switch), findsWidgets);
        expect(find.byType(CupertinoSwitch), findsNothing);
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('数据源胶囊悬停时保持无阴影并对齐', (tester) async {
    await _openDialog(
      tester,
      const Size(1280, 900),
      showAiExposureNewHuntDialog,
    );
    final allChips = find.byType(FilterChip);
    expect(allChips, findsNWidgets(20));
    final chips = <Finder>[
      for (var index = 0; index < 5; index++) allChips.at(index),
    ];
    final firstRect = tester.getRect(chips.first);
    for (var index = 0; index < chips.length; index++) {
      final finder = chips[index];
      expect(finder, findsOneWidget);
      final chip = tester.widget<FilterChip>(finder);
      expect(chip.showCheckmark, isFalse);
      expect(chip.elevation, 0);
      expect(chip.pressElevation, 0);
      expect(chip.shadowColor, Colors.transparent);
      expect(chip.selectedShadowColor, Colors.transparent);
      expect(tester.getRect(finder).height, closeTo(firstRect.height, 0.01));
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(firstRect.center);
    await tester.pumpAndSettle();
    expect(tester.getRect(chips.first), firstRect);
    await mouse.removePointer();
  });

  testWidgets('扫描规则条目操作按钮保持间距', (tester) async {
    await _openDialog(tester, const Size(1280, 900), showAiExposureRulesDialog);
    await tester.tap(find.text('新增规则'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '测试厂商');
    await tester.enterText(fields.at(2), r'token_[a-z]+');
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();

    final editIcon = find.byIcon(Icons.edit_outlined);
    final deleteIcon = find.byIcon(Icons.delete_outline_rounded);
    expect(editIcon, findsOneWidget);
    expect(deleteIcon, findsOneWidget);
    final edit = find.ancestor(of: editIcon, matching: find.byType(IconButton));
    final delete = find.ancestor(
      of: deleteIcon,
      matching: find.byType(IconButton),
    );
    expect(
      tester.getRect(delete).left - tester.getRect(edit).right,
      closeTo(8, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('授权确认项悬停时不显示覆盖层', (tester) async {
    await _openDialog(
      tester,
      const Size(1280, 900),
      showAiExposureNewHuntDialog,
    );
    final confirmation = find.byKey(
      const ValueKey<String>('hunt-authorization-confirmation'),
    );
    await tester.ensureVisible(confirmation);
    await tester.pumpAndSettle();

    final tile = tester.widget<CheckboxListTile>(confirmation);
    expect(tile.hoverColor, Colors.transparent);
    expect(
      tile.overlayColor?.resolve(const <WidgetState>{WidgetState.hovered}),
      Colors.transparent,
    );
    final inkWell = find.descendant(
      of: confirmation,
      matching: find.byType(InkWell),
    );
    expect(
      Theme.of(tester.element(inkWell.first)).hoverColor,
      Colors.transparent,
    );
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
