// 2026-05-09 — Phase 12 followup：锁定 Hardness 路径的 onReplayBatch 契约
// ——必须先 createSession 再在新 session 里 composer 出 `select:N1, select:N2`
// 并发送。单元层用 `replayToolSearchInFreshSession` 做编排校验；widget 层
// 直接驱动 ToolSearchLoadedDialog 的 history「重放」按钮，验证回调被传入了
// 正确的 names。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/service/mcp_loaded_tools_tracker.dart';
import 'package:openhand/features/mcp/service/tool_search_replay_dispatcher.dart';
import 'package:openhand/features/mcp/widgets/tool_search_loaded_dialog.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1200, 1600);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  group('replayToolSearchInFreshSession orchestration', () {
    test('createSession 一定先于 replay 调用，并把 names 透传过去', () async {
      final order = <String>[];
      List<String>? receivedNames;

      await replayToolSearchInFreshSession(
        names: const ['mcp__a__b', 'mcp__c__d'],
        createSession: () async {
          order.add('create');
          return true;
        },
        replayInCurrentSession: (n) async {
          order.add('replay');
          receivedNames = n;
        },
      );

      expect(order, ['create', 'replay']);
      expect(receivedNames, ['mcp__a__b', 'mcp__c__d']);
    });

    test('createSession 失败时 replay 不会触发', () async {
      var replayCalled = false;
      await replayToolSearchInFreshSession(
        names: const ['mcp__x__y'],
        createSession: () async => false,
        replayInCurrentSession: (_) async => replayCalled = true,
      );
      expect(replayCalled, isFalse);
    });

    test('空 names 直接返回，不调用 createSession', () async {
      var createCalled = false;
      var replayCalled = false;
      await replayToolSearchInFreshSession(
        names: const [],
        createSession: () async {
          createCalled = true;
          return true;
        },
        replayInCurrentSession: (_) async => replayCalled = true,
      );
      expect(createCalled, isFalse);
      expect(replayCalled, isFalse);
    });
  });

  testWidgets(
      'history「重放」按钮把 hardness phase 条目对应的 names 透传给 onReplayBatch',
      (tester) async {
    final history = <AiToolSearchLoadHistoryEntry>[
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 5, 9),
        query: 'select:N1, select:N2',
        addedNames: const ['mcp__alpha__N1', 'mcp__beta__N2'],
        totalDeferred: 2,
        source: AiToolSearchLoadSource.hardnessPhase,
      ),
    ];

    List<String>? capturedNames;

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
                  names: const ['mcp__alpha__N1', 'mcp__beta__N2'],
                  history: history,
                  onReplayBatch: (names) async {
                    capturedNames = List<String>.from(names);
                  },
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

    // 切到 history tab。
    await tester.tap(find.text('Load history (1)'));
    await tester.pumpAndSettle();

    // History 条目尾部的「重放」按钮（icon = copy_all_rounded）。
    final replayBtn = find.byIcon(Icons.copy_all_rounded);
    expect(replayBtn, findsWidgets);
    await tester.tap(replayBtn.first);
    await tester.pumpAndSettle();

    expect(capturedNames, ['mcp__alpha__N1', 'mcp__beta__N2']);
  });
}
