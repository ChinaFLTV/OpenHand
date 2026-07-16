import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/mcp/widgets/tool_search_loaded_dialog.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  Widget buildDialog(
    List<String> names, {
    List<AiToolSearchLoadHistoryEntry> history =
        const <AiToolSearchLoadHistoryEntry>[],
    VoidCallback? onClear,
    Locale? locale,
  }) {
    return MaterialApp(
      theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ToolSearchLoadedDialog(
          initialNames: names,
          initialHistory: history,
          onClear: onClear,
        ),
      ),
    );
  }

  testWidgets('工具分组折叠后可稳定重新展开', (tester) async {
    const names = <String>[
      'mcp__HowToCook__search_recipe',
      'mcp__HowToCook__get_recipe',
    ];
    await tester.pumpWidget(buildDialog(names));
    await tester.pump();

    final header = find.text('HowToCook');
    await tester.tap(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SelectableText), findsNWidgets(names.length));
  });

  testWidgets('普通工具组与同名服务器组使用不同标识', (tester) async {
    await tester.pumpWidget(
      buildDialog(const <String>['plain_tool', 'mcp___misc__server_tool']),
    );
    await tester.pump();

    final keys = tester
        .widgetList<ExpansionTile>(find.byType(ExpansionTile))
        .map((tile) => tile.key)
        .toSet();
    expect(keys, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('标题操作、标签指示器与分组按钮保持统一几何样式', (tester) async {
    final history = <AiToolSearchLoadHistoryEntry>[
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 7, 17),
        query: 'HowToCook',
        addedNames: const <String>['mcp__HowToCook__get_recipe'],
        totalDeferred: 2,
      ),
    ];
    await tester.pumpWidget(
      buildDialog(
        const <String>[
          'mcp__HowToCook__search_recipe',
          'mcp__HowToCook__get_recipe',
        ],
        history: history,
        onClear: () {},
        locale: const Locale('zh'),
      ),
    );
    await tester.pump();

    final clearButton = find.byKey(
      const ValueKey<String>('toolSearchClearAction'),
    );
    final closeButton = find.byTooltip('关闭');
    final clearRect = tester.getRect(clearButton);
    final closeRect = tester.getRect(closeButton);
    expect(closeRect.left - clearRect.right, greaterThanOrEqualTo(8));

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.indicator, isA<ShapeDecoration>());
    expect(tabBar.indicatorAnimation, TabIndicatorAnimation.linear);
    expect(tabBar.splashFactory, same(NoSplash.splashFactory));
    expect(tabBar.overlayColor?.resolve(<WidgetState>{}), Colors.transparent);

    final groupCopy = find.byKey(
      const ValueKey<String>('mcpToolGroupCopy:server:HowToCook'),
    );
    final groupExpand = find.byKey(
      const ValueKey<String>('mcpToolGroupExpand:server:HowToCook'),
    );
    final toolCopy = find.byKey(
      const ValueKey<String>('mcpToolCopy:mcp__HowToCook__get_recipe'),
    );
    final actionButtons = <Finder>[groupCopy, groupExpand, toolCopy];
    final loadedActionSize = tester.getSize(groupCopy);
    for (final finder in actionButtons) {
      expect(tester.getSize(finder), const Size.square(36));
      final button = tester.widget<IconButton>(finder);
      expect(
        button.style?.shape?.resolve(<WidgetState>{}),
        isA<CircleBorder>(),
      );
    }
    final groupCopyRect = tester.getRect(groupCopy);
    final groupExpandRect = tester.getRect(groupExpand);
    expect(groupExpandRect.left - groupCopyRect.right, 6);
    final actionColors = actionButtons
        .map(
          (finder) => tester
              .widget<IconButton>(finder)
              .style
              ?.backgroundColor
              ?.resolve(<WidgetState>{}),
        )
        .toSet();
    expect(actionColors, hasLength(1));
    expect(find.byTooltip('复制本组全部'), findsOneWidget);
    AnimatedRotation expansionRotation() => tester.widget<AnimatedRotation>(
      find.descendant(of: groupExpand, matching: find.byType(AnimatedRotation)),
    );
    expect(expansionRotation().turns, 0.5);
    await tester.tap(groupExpand);
    await tester.pumpAndSettle();
    expect(expansionRotation().turns, 0);

    final nameRect = tester.getRect(find.text('HowToCook'));
    final countRect = tester.getRect(
      find.byKey(const ValueKey<String>('mcpToolGroupCount:server:HowToCook')),
    );
    expect(countRect.left - nameRect.right, lessThanOrEqualTo(9));

    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pumpAndSettle();
    final historyReplay = find.byTooltip('把本次复制为 select:…');
    expect(tester.getSize(historyReplay), loadedActionSize);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗口可稳定展示长工具名与历史工具栏', (tester) async {
    tester.view.physicalSize = const Size(420, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const longName =
        'mcp__HowToCook__mcp_howtocook_getRecipesByCategoryWithExtendedMetadata';
    final history = <AiToolSearchLoadHistoryEntry>[
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 7, 16, 22, 35, 46),
        query: 'MCP AgentBay session create execute',
        addedNames: const <String>[longName],
        totalDeferred: 134,
      ),
    ];

    await tester.pumpWidget(
      buildDialog(const <String>[longName], history: history, onClear: () {}),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.textSpan?.toPlainText().contains(
                  'MCP AgentBay session create execute',
                ) ??
                false),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    expect(find.byIcon(Icons.file_open_rounded), findsOneWidget);
  });

  testWidgets('宽窗口历史筛选器与操作区不会相互挤压', (tester) async {
    tester.view.physicalSize = const Size(900, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final history = <AiToolSearchLoadHistoryEntry>[
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 7, 16, 22, 35, 46),
        query: 'select:mcp__Server__tool',
        addedNames: const <String>['mcp__Server__tool'],
        totalDeferred: 12,
      ),
    ];

    await tester.pumpWidget(
      buildDialog(
        const <String>['mcp__Server__tool'],
        history: history,
        onClear: () {},
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byType(SegmentedButton<AiToolSearchLoadSource?>),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.delete_sweep_rounded), findsNWidgets(2));
  });

  testWidgets('工具名会去空白、去重并忽略空项', (tester) async {
    await tester.pumpWidget(
      buildDialog(const <String>[
        ' mcp__Server__tool ',
        '',
        'mcp__Server__tool',
      ]),
    );
    await tester.pump();

    expect(find.text('Loaded · 1'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
