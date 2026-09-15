import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/features/instructions/data/instruction_market_catalog.dart';
import 'package:openhand/features/instructions/data/instructions_store.dart';
import 'package:openhand/features/instructions/instructions_controller.dart';
import 'package:openhand/features/instructions/model/user_instruction_entry.dart';
import 'package:openhand/features/instructions/widgets/instruction_market_dialog.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/openhand_safe_scrollbar.dart';

class _Store implements InstructionsStore {
  List<UserInstructionEntry> entries = [];
  bool failSave = false;
  @override
  Future<List<UserInstructionEntry>> loadAll() async => List.of(entries);
  @override
  Future<void> saveAll(List<UserInstructionEntry> next) async {
    if (failSave) throw StateError('模拟保存失败');
    entries = List.of(next);
  }
}

void main() {
  test('16 个角色完整、来源唯一，提示词清洗后与角色对应', () {
    expect(instructionMarketCatalog.length, 16);
    expect(instructionMarketCatalog.map((e) => e.id).toSet().length, 16);
    expect(instructionMarketCatalog.map((e) => e.sourceKey).toSet().length, 16);
    for (final entry in instructionMarketCatalog) {
      expect(entry.body.split('\n').length, 5);
      expect(entry.body, contains('\nrole: ${entry.role}\n'));
      expect(entry.body.length, lessThan(500));
      expect(entry.interpretation, isNotEmpty);
      expect(entry.matches(entry.id.toLowerCase()), isTrue);
    }
    expect(
      instructionMarketCatalog.firstWhere((e) => e.id == 'HHHH').role,
      'hhhh',
    );
    expect(
      instructionMarketCatalog.firstWhere((e) => e.id == 'WHY').role,
      'why',
    );
    expect(
      instructionMarketCatalog.firstWhere((e) => e.id == 'GOOD').role,
      'good',
    );
  });

  for (final (width, scale, dark) in [
    (1280.0, 1.0, false),
    (400.0, 1.0, false),
    (1280.0, 1.8, true),
  ]) {
    testWidgets('市场在 $width 宽度、$scale 倍字体下搜索、添加和关闭', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _Store();
      final controller = InstructionsController.uninitialized(store: store);
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark
              ? OpenHandTheme.dark(OpenHandThemePreset.tundraGreen)
              : OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showInstructionMarketDialog(
                  context,
                  controller: controller,
                ),
                child: const Text('打开市场'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开市场'));
      await tester.pumpAndSettle();
      expect(find.text('指令市场'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, '不存在的角色');
      await tester.pumpAndSettle();
      expect(find.text('共 0 条'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'hhhh');
      await tester.pumpAndSettle();
      expect(find.text('共 1 条'), findsOneWidget);
      if (width < 800) {
        for (final tab in ['指令详情', '浏览指令', '指令详情']) {
          await tester.tap(find.text(tab));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 40));
          for (final bar in tester.widgetList<OpenHandSafeScrollbar>(
            find.byType(OpenHandSafeScrollbar),
          )) {
            expect(bar.controller?.positions.length ?? 0, lessThanOrEqualTo(1));
          }
        }
        await tester.pumpAndSettle();
      }
      store.failSave = true;
      await tester.tap(find.text('添加指令'));
      await tester.pumpAndSettle();
      expect(controller.entries, isEmpty);
      expect(find.textContaining('模拟保存失败'), findsWidgets);
      store.failSave = false;
      await tester.tap(find.text('添加指令'));
      await tester.pumpAndSettle();
      expect(controller.entries.single.body, instructionMarketCatalog[1].body);
      expect(controller.entries.single.enabled, isFalse);
      expect(find.text('已添加'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '已添加'),
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开市场'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'hhhh');
      await tester.pumpAndSettle();
      expect(find.text('已添加'), findsOneWidget);
      expect(controller.entries.length, 1);
      await tester.enterText(find.byType(TextField).first, 'MUM');
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加指令'));
      await tester.pumpAndSettle();
      expect(controller.enabledEntries, isEmpty);
      expect(controller.entries.every((entry) => !entry.enabled), isTrue);
      expect(controller.entries.length, 2);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
