// 2026-05-04 — Widget tests for ToolSearchLoadedDialog: rendering,
// per-row copy-to-clipboard, and clear-list interaction.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/service/mcp_loaded_tools_tracker.dart';
import 'package:openhand/features/mcp/widgets/tool_search_loaded_dialog.dart';
import 'package:openhand/l10n/app_localizations.dart';

Future<void> _pumpDialog(
  WidgetTester tester, {
  required List<String> names,
  void Function()? onClear,
  List<AiToolSearchLoadHistoryEntry> history =
      const <AiToolSearchLoadHistoryEntry>[],
  Future<void> Function(List<String> names)? onReplayBatch,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showToolSearchLoadedDialog(
                  context,
                  names: names,
                  onClear: onClear,
                  history: history,
                  onReplayBatch: onReplayBatch,
                ),
                child: const Text('open'),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the loaded MCP tool names', (tester) async {
    await _pumpDialog(
      tester,
      names: const <String>['mcp__svr__alpha', 'mcp__svr__beta'],
    );

    expect(find.text('MCP tools loaded by ToolSearch'), findsOneWidget);
    expect(find.text('mcp__svr__alpha'), findsOneWidget);
    expect(find.text('mcp__svr__beta'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsNWidgets(2));
  });

  testWidgets('shows em-dash placeholder when name list is empty',
      (tester) async {
    await _pumpDialog(tester, names: const <String>[]);

    expect(find.text('—'), findsOneWidget);
    // Clear button must NOT appear when there is nothing to clear.
    expect(find.text('Clear loaded list'), findsNothing);
  });

  testWidgets('hides clear button when onClear is null', (tester) async {
    await _pumpDialog(
      tester,
      names: const <String>['mcp__a'],
    );

    expect(find.text('Clear loaded list'), findsNothing);
  });

  testWidgets('copy button writes select:NAME to clipboard and toasts',
      (tester) async {
    String? clipboardCapture;
    final binding = TestDefaultBinaryMessengerBinding.instance;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardCapture =
              (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpDialog(
      tester,
      names: const <String>['mcp__svr__alpha'],
    );

    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(clipboardCapture, 'select:mcp__svr__alpha');
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('clear button calls onClear, empties list and shows toast',
      (tester) async {
    var clearedCount = 0;
    await _pumpDialog(
      tester,
      names: const <String>['mcp__a', 'mcp__b'],
      onClear: () => clearedCount += 1,
    );

    expect(find.text('mcp__a'), findsOneWidget);
    expect(find.text('mcp__b'), findsOneWidget);
    expect(find.text('Clear loaded list'), findsOneWidget);

    await tester.tap(find.text('Clear loaded list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(clearedCount, 1);
    expect(find.text('mcp__a'), findsNothing);
    expect(find.text('mcp__b'), findsNothing);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Loaded list cleared'), findsOneWidget);
    // Once empty, the clear button itself should disappear.
    expect(find.text('Clear loaded list'), findsNothing);
  });

  testWidgets('close button dismisses the dialog', (tester) async {
    await _pumpDialog(
      tester,
      names: const <String>['mcp__a'],
    );
    expect(find.byType(ToolSearchLoadedDialog), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(ToolSearchLoadedDialog), findsNothing);
  });

  testWidgets('groups names by mcp__SERVER__ prefix and lists Other group',
      (tester) async {
    String? clipboardCapture;
    final binding = TestDefaultBinaryMessengerBinding.instance;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardCapture =
              (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    // Use a tall viewport so all three groups + their copy buttons fit
    // inside the 420 px dialog without ListView.builder dropping them.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDialog(
      tester,
      names: const <String>[
        'mcp__alpha__one',
        'mcp__alpha__two',
        'mcp__beta__only',
        'WebFetch',
      ],
    );

    // Group headers + counts.
    expect(find.text('alpha (2)'), findsOneWidget);
    expect(find.text('beta (1)'), findsOneWidget);
    expect(find.text('Other (no server prefix) (1)'), findsOneWidget);

    // Each individual full name still rendered (groups initially expanded).
    expect(find.text('mcp__alpha__one'), findsOneWidget);
    expect(find.text('mcp__alpha__two'), findsOneWidget);
    expect(find.text('mcp__beta__only'), findsOneWidget);
    expect(find.text('WebFetch'), findsOneWidget);

    // Group-level "copy all" button should write joined select: payload.
    final groupCopy = find.byIcon(Icons.copy_all_rounded);
    expect(groupCopy, findsNWidgets(3));
    await tester.tap(groupCopy.first); // alpha sorted first
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(clipboardCapture, 'select:mcp__alpha__one, select:mcp__alpha__two');
  });

  testWidgets('history tab shows empty placeholder when no history',
      (tester) async {
    await _pumpDialog(tester, names: const <String>['mcp__svr__alpha']);

    await tester.tap(find.text('Load history (0)'));
    await tester.pumpAndSettle();

    expect(
      find.text('No ToolSearch loads in this session yet'),
      findsOneWidget,
    );
  });

  testWidgets('history tab renders timeline entries with query and chips',
      (tester) async {
    final history = <AiToolSearchLoadHistoryEntry>[
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 5, 4, 10),
        query: 'k8s pod logs',
        addedNames: const ['mcp__k8s__pods', 'mcp__k8s__logs'],
        totalDeferred: 12,
      ),
    ];
    await _pumpDialog(
      tester,
      names: const <String>['mcp__k8s__pods', 'mcp__k8s__logs'],
      history: history,
    );

    await tester.tap(find.text('Load history (1)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('k8s pod logs'), findsOneWidget);
    expect(find.text('+2 / 12'), findsOneWidget);
    expect(find.text('mcp__k8s__pods'), findsOneWidget);
    expect(find.text('mcp__k8s__logs'), findsOneWidget);
  });

  testWidgets('loaded tab filter narrows visible groups by name', (tester) async {
    await _pumpDialog(tester, names: const <String>[
      'mcp__alpha__one',
      'mcp__alpha__two',
      'mcp__beta__three',
    ]);

    expect(find.text('mcp__alpha__one'), findsOneWidget);
    expect(find.text('mcp__beta__three'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pumpAndSettle();

    expect(find.text('mcp__alpha__one'), findsNothing);
    expect(find.text('mcp__beta__three'), findsOneWidget);
  });

  testWidgets('clear-history button empties history list and toasts',
      (tester) async {
    final history = <AiToolSearchLoadHistoryEntry>[
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 5, 4, 10),
        query: 'k8s',
        addedNames: const ['mcp__k8s__pods'],
        totalDeferred: 5,
      ),
    ];
    await _pumpDialog(
      tester,
      names: const <String>['mcp__k8s__pods'],
      history: history,
    );

    await tester.tap(find.text('Load history (1)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();

    expect(
      find.text('No ToolSearch loads in this session yet'),
      findsOneWidget,
    );
    expect(find.text('Load history cleared'), findsOneWidget);
  });

  testWidgets(
      'tapping a history entry copies select: payload for the whole batch',
      (tester) async {
    String? capture;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        capture = args['text']! as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final history = <AiToolSearchLoadHistoryEntry>[
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 5, 4, 10),
        query: 'k8s',
        addedNames: const ['mcp__k8s__pods', 'mcp__k8s__logs'],
        totalDeferred: 5,
      ),
    ];
    await _pumpDialog(
      tester,
      names: const <String>['mcp__k8s__pods', 'mcp__k8s__logs'],
      history: history,
    );

    await tester.tap(find.text('Load history (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+2 / 5'));
    await tester.pumpAndSettle();

    expect(capture, 'select:mcp__k8s__pods, select:mcp__k8s__logs');
  });

  testWidgets(
      'history filter narrows entries by name OR query (case-insensitive)',
      (tester) async {
    final history = <AiToolSearchLoadHistoryEntry>[
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 5, 4, 10),
        query: 'kubernetes pods',
        addedNames: const ['mcp__k8s__pods'],
        totalDeferred: 5,
      ),
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 5, 4, 11),
        query: 'github issues',
        addedNames: const ['mcp__github__issue_list'],
        totalDeferred: 8,
      ),
    ];
    await _pumpDialog(
      tester,
      names: const <String>['mcp__k8s__pods', 'mcp__github__issue_list'],
      history: history,
    );

    await tester.tap(find.text('Load history (2)'));
    await tester.pumpAndSettle();

    // Both visible initially.
    expect(find.text('mcp__k8s__pods'), findsOneWidget);
    expect(find.text('mcp__github__issue_list'), findsOneWidget);

    // Filter by query text — only the kubernetes entry stays.
    await tester.enterText(find.byType(TextField).last, 'KUBERN');
    await tester.pumpAndSettle();
    expect(find.text('mcp__k8s__pods'), findsOneWidget);
    expect(find.text('mcp__github__issue_list'), findsNothing);

    // Filter by tool name — only the github entry stays.
    await tester.enterText(find.byType(TextField).last, 'issue_list');
    await tester.pumpAndSettle();
    expect(find.text('mcp__k8s__pods'), findsNothing);
    expect(find.text('mcp__github__issue_list'), findsOneWidget);
  });

  testWidgets(
      'tapping history entry invokes onReplayBatch instead of clipboard',
      (tester) async {
    bool clipboardTouched = false;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardTouched = true;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final captured = <List<String>>[];
    final history = <AiToolSearchLoadHistoryEntry>[
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 5, 4, 10),
        query: 'k8s',
        addedNames: const ['mcp__k8s__pods', 'mcp__k8s__logs'],
        totalDeferred: 5,
      ),
    ];
    await _pumpDialog(
      tester,
      names: const <String>['mcp__k8s__pods', 'mcp__k8s__logs'],
      history: history,
      onReplayBatch: (names) async => captured.add(List<String>.from(names)),
    );

    await tester.tap(find.text('Load history (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.copy_all_rounded));
    await tester.pumpAndSettle();

    expect(captured, hasLength(1));
    expect(captured.single, ['mcp__k8s__pods', 'mcp__k8s__logs']);
    expect(clipboardTouched, isFalse);
    // Dialog should be dismissed by replay path.
    expect(find.text('Close'), findsNothing);
  });

  testWidgets(
      'history entries render distinct AI / Hardness source labels',
      (tester) async {
    final history = <AiToolSearchLoadHistoryEntry>[
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 5, 4, 10),
        query: 'a',
        addedNames: const ['mcp__x__y'],
        totalDeferred: 3,
      ),
      AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026, 5, 4, 11),
        query: 'b',
        addedNames: const ['mcp__p__q'],
        totalDeferred: 4,
        source: AiToolSearchLoadSource.hardnessPhase,
      ),
    ];
    await _pumpDialog(
      tester,
      names: const <String>['mcp__x__y', 'mcp__p__q'],
      history: history,
    );

    await tester.tap(find.text('Load history (2)'));
    await tester.pumpAndSettle();

    expect(find.text('AI session'), findsOneWidget);
    expect(find.text('Hardness phase'), findsOneWidget);
  });
}
