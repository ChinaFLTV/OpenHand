import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/features/instructions/data/instruction_market_catalog.dart';
import 'package:openhand/features/instructions/data/instructions_store.dart';
import 'package:openhand/features/instructions/instructions_controller.dart';
import 'package:openhand/features/instructions/model/user_instruction_entry.dart';
import 'package:openhand/features/instructions/widgets/instruction_market_dialog.dart';
import 'package:openhand/features/instructions/widgets/instruction_market_labels.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/openhand_safe_scrollbar.dart';
import 'package:openhand/shared/ui/openhand_table_pagination.dart';

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
    expect(instructionMarketCatalog.map((e) => e.category).toSet(), {
      kInstructionMarketCategoryAction,
      kInstructionMarketCategoryVitality,
      kInstructionMarketCategoryInsight,
      kInstructionMarketCategoryCompanion,
    });
    for (final entry in instructionMarketCatalog) {
      expect(entry.body.split('\n').length, 5);
      expect(entry.body, contains('\nrole: ${entry.role}\n'));
      expect(entry.body.length, lessThan(500));
      expect(entry.interpretation, isNotEmpty);
      expect(entry.matches(entry.id.toLowerCase()), isTrue);
      expect(kInstructionMarketCategoryOrder, contains(entry.category));
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

  test('跨语言关键词与分类名称都能命中角色', () {
    final yyds = instructionMarketCatalog.firstWhere((e) => e.id == 'YYDS');
    expect(instructionMarketMatches(yyds, 'Ace'), isTrue);
    expect(instructionMarketMatches(yyds, '神人'), isTrue);
    expect(instructionMarketMatches(yyds, '行动与决策'), isTrue);
    expect(instructionMarketMatches(yyds, 'Action & decisions'), isTrue);
    expect(instructionMarketMatches(yyds, 'soul preset'), isTrue);
    expect(instructionMarketMatches(yyds, '不存在的角色'), isFalse);
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
      expect(find.text('SkillHub'), findsNothing);
      expect(find.text('SOUL'), findsNothing);
      expect(find.text('灵魂设定'), findsWidgets);
      expect(find.text('角色库'), findsWidgets);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(ValueKey(instructionMarketCatalog.first.avatarUrl)),
        findsWidgets,
      );
      OpenHandTablePagination pager() => tester.widget<OpenHandTablePagination>(
        find.byType(OpenHandTablePagination),
      );
      expect(pager().total, 16);
      pager().onPageSizeChanged!(12);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(pager().page, 2);
      expect(
        find.byKey(ValueKey(instructionMarketCatalog[12].avatarUrl)),
        findsWidgets,
      );
      await tester.tap(find.byTooltip('刷新市场'));
      await tester.pumpAndSettle();
      expect(pager().page, 1);
      expect(pager().pageSize, 12);
      await tester.enterText(find.byType(TextField).first, '不存在的角色');
      await tester.pumpAndSettle();
      expect(pager().total, 0);
      expect(pager().page, 1);
      await tester.enterText(find.byType(TextField).first, 'Ace');
      await tester.pumpAndSettle();
      expect(pager().total, 1);
      await tester.enterText(find.byType(TextField).first, 'hhhh');
      await tester.pumpAndSettle();
      expect(pager().total, 1);
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
      expect(find.widgetWithText(FilledButton, '已添加'), findsOneWidget);
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
      expect(find.widgetWithText(FilledButton, '已添加'), findsOneWidget);
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

  testWidgets('英文界面展示本地化标签，不出现 SkillHub / SOUL', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _Store();
    final controller = InstructionsController.uninitialized(store: store);
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showInstructionMarketDialog(context, controller: controller),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Instruction Market'), findsOneWidget);
    expect(find.text('Add instruction'), findsOneWidget);
    expect(find.text('Soul preset'), findsWidgets);
    expect(find.text('Character library'), findsWidgets);
    expect(find.text('Action & decisions'), findsWidgets);
    expect(find.text('YYDS · Ace'), findsWidgets);
    expect(find.text('SkillHub'), findsNothing);
    expect(find.text('SOUL'), findsNothing);
    expect(find.text('指令市场'), findsNothing);
    expect(find.textContaining('YAML'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, 'Ace');
    await tester.pumpAndSettle();
    OpenHandTablePagination pager() => tester.widget<OpenHandTablePagination>(
      find.byType(OpenHandTablePagination),
    );
    expect(pager().total, 1);
    await tester.tap(find.text('Add instruction'));
    await tester.pumpAndSettle();
    expect(controller.entries.single.name, 'YYDS · Ace');
    expect(controller.entries.single.body, instructionMarketCatalog.first.body);
    expect(find.text('Added'), findsWidgets);
  });
}
