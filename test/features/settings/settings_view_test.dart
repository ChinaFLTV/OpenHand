import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_info.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/memory/memory_controller.dart';
import 'package:openhand/features/settings/settings_view.dart';
import 'package:openhand/features/skills/skills_controller.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/data/database_service.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsView AI provider chips', () {
    late _SettingsViewTestHarness harness;

    setUp(() async {
      harness = await _SettingsViewTestHarness.create();
    });

    tearDown(() async {
      await harness.dispose();
    });

    testWidgets('active model chip keeps selected theme styling states', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await harness.seedAiModels();
      });
      await tester.pumpSettingsView(harness);

      final BuildContext context = tester.element(find.byType(SettingsView));
      final ThemeData theme = Theme.of(context);
      final ColorScheme colorScheme = theme.colorScheme;
      final bool isDark = theme.brightness == Brightness.dark;

      final InputChip activeChip = tester
          .widgetList<InputChip>(find.byType(InputChip))
          .firstWhere((chip) {
            final Text label = chip.label as Text;
            return label.data == 'zyb-fast';
          });

      expect(activeChip.color, isNotNull);
      final WidgetStateProperty<Color?> fillColor = activeChip.color!;
      expect(activeChip.selected, isTrue);
      expect((activeChip.label as Text).style?.fontWeight, FontWeight.w700);
      expect(
        activeChip.side?.color,
        colorScheme.primary.withValues(alpha: isDark ? 0.62 : 0.52),
      );
      expect(activeChip.side?.width, 1.15);

      final Color activeBaseColor = Color.alphaBlend(
        colorScheme.primary.withValues(alpha: isDark ? 0.10 : 0.03),
        Color.lerp(
              colorScheme.surfaceContainerLowest,
              colorScheme.primaryContainer,
              isDark ? 0.74 : 0.66,
            ) ??
            colorScheme.primaryContainer,
      );
      final Color activeHoverColor = Color.alphaBlend(
        colorScheme.primary.withValues(alpha: isDark ? 0.14 : 0.05),
        Color.lerp(activeBaseColor, colorScheme.primaryContainer, 0.36) ??
            activeBaseColor,
      );
      final Color activePressedColor = Color.alphaBlend(
        colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.08),
        Color.lerp(
              activeBaseColor,
              colorScheme.primary,
              isDark ? 0.14 : 0.10,
            ) ??
            activeBaseColor,
      );

      expect(
        fillColor.resolve(<WidgetState>{WidgetState.selected}),
        activeBaseColor,
      );
      expect(
        fillColor.resolve(<WidgetState>{
          WidgetState.selected,
          WidgetState.hovered,
        }),
        activeHoverColor,
      );
      expect(
        fillColor.resolve(<WidgetState>{
          WidgetState.selected,
          WidgetState.pressed,
        }),
        activePressedColor,
      );
    });

    testWidgets(
      'editing active model id keeps chips and saved provider in sync',
      (tester) async {
        await tester.runAsync(() async {
          await harness.seedAiModels();
        });
        await tester.pumpSettingsView(harness);

        await tester.tap(find.byIcon(Icons.edit_outlined));
        await tester.pump(const Duration(milliseconds: 260));

        final Finder dialogFinder = find.byType(Dialog);
        expect(dialogFinder, findsOneWidget);

        await tester.tap(
          find.descendant(of: dialogFinder, matching: find.text('zyb-high')),
        );
        await tester.pump(const Duration(milliseconds: 120));

        Finder activeModelFieldFinder = find.descendant(
          of: dialogFinder,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is TextFormField &&
                widget.controller?.text == 'zyb-high',
          ),
        );
        expect(activeModelFieldFinder, findsOneWidget);

        await tester.enterText(activeModelFieldFinder, 'custom-zyb-model');
        await tester.pump(const Duration(milliseconds: 120));

        activeModelFieldFinder = find.descendant(
          of: dialogFinder,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is TextFormField &&
                widget.controller?.text == 'custom-zyb-model',
          ),
        );
        expect(activeModelFieldFinder, findsOneWidget);
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is InputChip &&
                  widget.label is Text &&
                  (widget.label as Text).data == 'custom-zyb-model',
            ),
          ),
          findsOneWidget,
        );

        await tester.tap(
          find.descendant(of: dialogFinder, matching: find.text('保存')),
        );
        await tester.pump();
        await tester.flushRealAsyncWork();

        expect(find.byType(Dialog), findsNothing);
        expect(find.text('当前模型：custom-zyb-model'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is InputChip &&
                widget.label is Text &&
                (widget.label as Text).data == 'custom-zyb-model',
          ),
          findsOneWidget,
        );

        final AiModelConfig savedModel =
            harness.settingsController.aiModels.single;
        expect(savedModel.modelId, 'custom-zyb-model');
        expect(savedModel.availableModelIds, contains('custom-zyb-model'));
      },
    );
  });

  group('SettingsView editor LSP mappings', () {
    late _SettingsViewTestHarness harness;

    setUp(() async {
      harness = await _SettingsViewTestHarness.create();
    });

    tearDown(() async {
      await harness.dispose();
    });

    testWidgets('scrollbar shares its controller with the mapping list', (
      tester,
    ) async {
      await tester.pumpSettingsView(harness);
      await tester.ensureVisible(find.text('语言服务器映射'));
      await tester.pump();

      final Finder scrollbarFinder = find.byType(Scrollbar);
      expect(scrollbarFinder, findsOneWidget);

      final Finder listViewFinder = find.descendant(
        of: scrollbarFinder,
        matching: find.byType(ListView),
      );
      expect(listViewFinder, findsOneWidget);

      final Scrollbar scrollbar = tester.widget<Scrollbar>(scrollbarFinder);
      final ListView listView = tester.widget<ListView>(listViewFinder);

      expect(scrollbar.controller, isNotNull);
      expect(listView.controller, same(scrollbar.controller));
      expect(listView.primary, isFalse);

      await tester.drag(listViewFinder, const Offset(0, -320));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));

      expect(tester.takeException(), isNull);
    });
  });
}

class _SettingsViewTestHarness {
  _SettingsViewTestHarness({
    required this.tempDirectory,
    required this.settingsController,
    required this.skillsController,
    required this.memoryController,
    required this.mcpController,
  });

  final Directory tempDirectory;
  final SettingsController settingsController;
  final SkillsController skillsController;
  final MemoryController memoryController;
  final McpController mcpController;

  static Future<_SettingsViewTestHarness> create() async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand-settings-view-test-',
    );
    await DatabaseService.initialize(
      databasePath: p.join(tempDirectory.path, 'openhand_test.db'),
      useNoIsolateFactory: true,
    );

    final settingsController = await SettingsController.create();
    final skillsPath = p.join(tempDirectory.path, 'skills');
    await Directory(skillsPath).create(recursive: true);
    final skillsController = await SkillsController.create(
      initialStoragePath: skillsPath,
    );
    final memoryController = await MemoryController.create();
    final mcpController = await McpController.create(
      initialFilePath: p.join(tempDirectory.path, 'mcp_servers.json'),
    );

    return _SettingsViewTestHarness(
      tempDirectory: tempDirectory,
      settingsController: settingsController,
      skillsController: skillsController,
      memoryController: memoryController,
      mcpController: mcpController,
    );
  }

  Future<void> seedAiModels() async {
    await settingsController.saveAiModel(
      const AiModelConfig(
        id: 'provider-1',
        name: '作业帮-架构',
        baseUrl: 'https://ccproxy.zuoyebang.cc/zp/anthropic/v1',
        authScheme: AiAuthScheme.bearer,
        token: 'secret-token-7072',
        modelId: 'zyb-fast',
        protocolType: AiProtocolType.claude,
        availableModelIds: <String>['zyb-fast', 'zyb-high'],
      ),
    );
  }

  Future<void> dispose() async {
    settingsController.dispose();
    skillsController.dispose();
    memoryController.dispose();
    mcpController.dispose();
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  }
}

extension on WidgetTester {
  Future<void> pumpSettingsView(_SettingsViewTestHarness harness) async {
    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(1600, 2600);
    addTearDown(view.reset);

    await pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(
            value: harness.settingsController,
          ),
          Provider<AppInfo>.value(value: AppInfo.fallback()),
          ChangeNotifierProvider<SkillsController>.value(
            value: harness.skillsController,
          ),
          ChangeNotifierProvider<MemoryController>.value(
            value: harness.memoryController,
          ),
          ChangeNotifierProvider<McpController>.value(
            value: harness.mcpController,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
          home: const Scaffold(body: SettingsView()),
        ),
      ),
    );
    await pump();
    await pump(const Duration(milliseconds: 120));
  }

  Future<void> flushRealAsyncWork({int cycles = 6}) async {
    for (var index = 0; index < cycles; index++) {
      await runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await pump(const Duration(milliseconds: 120));
    }
  }
}
