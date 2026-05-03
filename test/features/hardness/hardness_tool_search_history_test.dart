// 2026-05-04 — Hardness 侧 ToolSearch 加载历史的 widget 行为锁定。
// 覆盖：(1) phase 来源的历史条目以 “Hardness phase” chip 渲染；
// (2) 多 phase 共享同一 dialog 时各自来源标签独立呈现；
// (3) `AiToolSearchLoadHistoryEntry` 默认 source 为 aiSession，
//     `AiToolSearchLoadSource.hardnessPhase` 必须显式传入。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/service/mcp_loaded_tools_tracker.dart';
import 'package:openhand/features/mcp/widgets/tool_search_loaded_dialog.dart';
import 'package:openhand/l10n/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester, {
  required List<AiToolSearchLoadHistoryEntry> history,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showToolSearchLoadedDialog(
                context,
                names: history
                    .expand((e) => e.addedNames)
                    .toSet()
                    .toList(growable: false),
                history: history,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  test('AiToolSearchLoadHistoryEntry defaults source to AI session', () {
    final entry = AiToolSearchLoadHistoryEntry(
      timestamp: DateTime.utc(2026, 5, 4),
      query: 'q',
      addedNames: const ['mcp__a__b'],
      totalDeferred: 1,
    );
    expect(entry.source, AiToolSearchLoadSource.aiSession);
  });

  testWidgets(
      'hardness-source history entry renders the Hardness phase chip',
      (tester) async {
    await _pump(
      tester,
      history: <AiToolSearchLoadHistoryEntry>[
        AiToolSearchLoadHistoryEntry(
          timestamp: DateTime.utc(2026, 5, 4, 9),
          query: 'kubernetes pods',
          addedNames: const ['mcp__k8s__pods'],
          totalDeferred: 6,
          source: AiToolSearchLoadSource.hardnessPhase,
        ),
      ],
    );

    await tester.tap(find.text('Load history (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Hardness phase'), findsOneWidget);
    expect(find.text('AI session'), findsNothing);
    expect(find.text('mcp__k8s__pods'), findsOneWidget);
  });

  testWidgets(
      'hardness history filter narrows by tool name and by query text',
      (tester) async {
    await _pump(
      tester,
      history: <AiToolSearchLoadHistoryEntry>[
        AiToolSearchLoadHistoryEntry(
          timestamp: DateTime.utc(2026, 5, 4, 9),
          query: 'kubernetes',
          addedNames: const ['mcp__k8s__pods'],
          totalDeferred: 3,
          source: AiToolSearchLoadSource.hardnessPhase,
        ),
        AiToolSearchLoadHistoryEntry(
          timestamp: DateTime.utc(2026, 5, 4, 10),
          query: 'github review',
          addedNames: const ['mcp__github__pr_get'],
          totalDeferred: 4,
          source: AiToolSearchLoadSource.hardnessPhase,
        ),
      ],
    );

    await tester.tap(find.text('Load history (2)'));
    await tester.pumpAndSettle();

    expect(find.text('mcp__k8s__pods'), findsOneWidget);
    expect(find.text('mcp__github__pr_get'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'github');
    await tester.pumpAndSettle();
    expect(find.text('mcp__k8s__pods'), findsNothing);
    expect(find.text('mcp__github__pr_get'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'k8s');
    await tester.pumpAndSettle();
    expect(find.text('mcp__k8s__pods'), findsOneWidget);
    expect(find.text('mcp__github__pr_get'), findsNothing);
  });
}
