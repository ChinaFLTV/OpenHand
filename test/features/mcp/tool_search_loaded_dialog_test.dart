// 2026-05-04 — Widget tests for ToolSearchLoadedDialog: rendering,
// per-row copy-to-clipboard, and clear-list interaction.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/mcp/widgets/tool_search_loaded_dialog.dart';
import 'package:openhand/l10n/app_localizations.dart';

Future<void> _pumpDialog(
  WidgetTester tester, {
  required List<String> names,
  void Function()? onClear,
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
}
